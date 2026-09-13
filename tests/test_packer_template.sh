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
cat > "$config" <<'EOF'
AWS_REGION=ap-northeast-1
CPU_ENABLED=1
GPU_ENABLED=0
CPU_OUTPUT_AMI_NAME=packer-template-test
AWS_SUBNET_IDS=subnet-packer-template-test
AWS_VPC_ID=vpc-packer-template-test
EOF

work=${runtime_dir#"$root/"}/work
PATH="$mock_bin:$PATH" AMI_VALIDATE_ONLY=1 bin/ec2 make_ami --workdir "$work" \
  --environment-config "$config" >/dev/null
generated="$runtime_dir/work/packer"
python3 -m json.tool "$generated/main.json" >/dev/null
python3 -m json.tool "$generated/variables_cpu.json" >/dev/null
while read -r mode relative;do
  [[ "$relative" == packer/* ]] || continue
  extracted="$generated/${relative#packer/}"
  cmp -s "environment/$relative" "$extracted" || {
    echo "Extracted Packer asset differs from its source: $relative" >&2
    exit 1
  }
  [[ $(stat -f '%Lp' "$extracted" 2>/dev/null || stat -c '%a' "$extracted") == "$mode" ]] || {
    echo "Extracted Packer asset has the wrong mode: $relative" >&2
    exit 1
  }
done < environment/assets.manifest

echo 'Packer template tests passed.'
