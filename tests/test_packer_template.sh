#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-environment-packer-template.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
config="$runtime_dir/config"
mkdir -p "$mock_bin"

cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" ec2 describe-images "* ]];then echo ami-packer-template-test;fi
exit 0
EOF
chmod 755 "$mock_bin/aws"
template="$runtime_dir/custom-template.json"
cat > "$template" <<'EOF'
{"builders":[],"provisioners":[]}
EOF
cat > "$config" <<'EOF'
AWS_REGION=ap-northeast-1
CPU_ENABLED=1
GPU_ENABLED=0
CPU_OUTPUT_AMI_NAME=packer-template-test
AWS_SUBNET_IDS=subnet-packer-template-test
AWS_VPC_ID=vpc-packer-template-test
EC2_KEY_NAME=packer-template-test
EC2_FILESYSTEM_PROVIDERS=
EOF

work=${runtime_dir#"$root/"}/work
PATH="$mock_bin:$PATH" AMI_VALIDATE_ONLY=1 bin/ec2 make_ami --workdir "$work" \
  --environment-config "$config" --setup --install-config 0 >/dev/null
generated="$runtime_dir/work/packer"
python3 -m json.tool "$generated/main.json" >/dev/null
python3 -m json.tool "$generated/variables_cpu.json" >/dev/null
[[ -s "$runtime_dir/work/ec2/config" ]] || {
  echo 'make_ami --setup did not run the setup phase.' >&2
  exit 1
}
while read -r mode relative;do
  [[ "$relative" == packer/* ]] || continue
  extracted="$generated/${relative#packer/}"
  cmp -s "environment/$relative" "$extracted" || {
    echo "Extracted Packer asset differs from its source: $relative" >&2
    exit 1
  }
  if stat_mode=$(stat -c '%a' "$extracted" 2>/dev/null);then :; else stat_mode=$(stat -f '%Lp' "$extracted"); fi
  [[ "$stat_mode" == "$mode" ]] || {
    echo "Extracted Packer asset has the wrong mode: $relative" >&2
    exit 1
  }
done < environment/assets.manifest

cat >> "$config" <<'EOF'
AMI_ENABLE_SWAP=0
AMI_ENABLE_SHARED_MEMORY=0
AMI_ENABLE_IDLE_SHUTDOWN=0
AMI_PACKAGES=
AMI_FLATPAK_PACKAGES=
AMI_UPDATE_PACKAGES=0
AMI_TIMEZONE=
AMI_PROVISION_SCRIPTS=./scripts/custom-provision.sh
EOF
feature_work=${runtime_dir#"$root/"}/work-features
PATH="$mock_bin:$PATH" AMI_VALIDATE_ONLY=1 bin/ec2 make_ami --workdir "$feature_work" \
  --environment-config "$config" --install-config 0 >/dev/null
grep -q '"scripts": "\./scripts/custom-provision.sh"' \
  "$feature_work/packer/variables_cpu.json" || {
  echo 'AMI feature flags and additional provisioning scripts were not composed correctly.' >&2
  exit 1
}

cat >> "$config" <<'EOF'
AMI_PACKAGES=git
AMI_TIMEZONE=Asia/Tokyo
EOF
automatic_work=${runtime_dir#"$root/"}/work-automatic
PATH="$mock_bin:$PATH" AMI_VALIDATE_ONLY=1 bin/ec2 make_ami --workdir "$automatic_work" \
  --environment-config "$config" --install-config 0 >/dev/null
grep -q './scripts/install_packages.sh' \
  "$automatic_work/packer/variables_cpu.json" || {
  echo 'AMI_PACKAGES did not enable package provisioning.' >&2
  exit 1
}
grep -q './scripts/set_timezone.sh' \
  "$automatic_work/packer/variables_cpu.json" || {
  echo 'AMI_TIMEZONE did not enable timezone provisioning.' >&2
  exit 1
}

printf 'AMI_PACKER_TEMPLATE_FILE=%s\n' "$template" >> "$config"
external_work=${runtime_dir#"$root/"}/work-external
PATH="$mock_bin:$PATH" AMI_VALIDATE_ONLY=1 bin/ec2 make_ami --workdir "$external_work" \
  --environment-config "$config" --install-config 0 >/dev/null
cmp -s "$template" "$external_work/packer/main.json" || {
  echo 'AMI_PACKER_TEMPLATE_FILE was not used as the Packer template.' >&2
  exit 1
}

echo 'Packer template tests passed.'
