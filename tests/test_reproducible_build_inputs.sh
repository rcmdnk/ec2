#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-environment-build-inputs.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
aws_log="$runtime_dir/aws.log"
packer_log="$runtime_dir/packer.log"
mkdir -p "$mock_bin"

cat > "$mock_bin/aws" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$aws_log'
if [[ " \$* " == *" ec2 describe-images "* ]];then echo ami-resolved-source;fi
EOF
cat > "$mock_bin/packer" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$packer_log'
if [[ "\${1:-}" == version ]];then echo 'Packer v-test';fi
if [[ " \$* " == *" build "* ]];then echo 'mock build';fi
EOF
chmod 755 "$mock_bin"/*

write_config() {
  local path=$1 source_id=${2-}
  cat > "$path" <<EOF
AWS_REGION=ap-northeast-1
CPU_ENABLED=1
GPU_ENABLED=0
CPU_OUTPUT_AMI_NAME=reproducible-build-test
CPU_SOURCE_AMI_NAME_FILTER=source-name-*
CPU_SOURCE_AMI_OWNER=123456789012
CPU_SOURCE_AMI_ID=$source_id
AWS_SUBNET_IDS=subnet-build-input-test
AWS_VPC_ID=vpc-build-input-test
AMI_PACKAGES=git
AMI_UPDATE_PACKAGES=0
EOF
}

config="$runtime_dir/config"
write_config "$config"
work=${runtime_dir#"$root/"}/work
PATH="$mock_bin:$PATH" bin/ec2 make_ami --workdir "$work" \
  --environment-config "$config" >/dev/null
generated="$runtime_dir/work/packer"

python3 -m json.tool "$generated/main.json" >/dev/null
python3 -m json.tool "$generated/variables_cpu.json" >/dev/null
python3 -m json.tool "$generated/build-inputs-cpu.json" >/dev/null
grep -q '"source_ami": "ami-resolved-source"' "$generated/variables_cpu.json" || {
  echo 'The newest source AMI was not resolved to an exact ID before Packer.' >&2
  exit 1
}
grep -q '"source_ami_id": "ami-resolved-source"' "$generated/build-inputs-cpu.json" || {
  echo 'The resolved source AMI was not recorded in the build manifest.' >&2
  exit 1
}
grep -q '^init \.$' "$packer_log" || {
  echo 'make_ami did not initialize the constrained Packer plugin.' >&2
  exit 1
}

# The build must request cleanup for resources created before a failure.
grep -q '^build -on-error=cleanup ' "$packer_log" || {
  echo 'make_ami did not request Packer cleanup on build failure.' >&2
  exit 1
}

# An explicitly pinned source ID must bypass the mutable name lookup.
: > "$aws_log"
write_config "$config" ami-explicit-source
pinned_work=${runtime_dir#"$root/"}/work-pinned
PATH="$mock_bin:$PATH" bin/ec2 make_ami --workdir "$pinned_work" \
  --environment-config "$config" >/dev/null
grep -q '"source_ami": "ami-explicit-source"' "$runtime_dir/work-pinned/packer/variables_cpu.json" || {
  echo 'An explicit source AMI did not take precedence over the name filter.' >&2
  exit 1
}
if grep -q 'describe-images' "$aws_log";then
  echo 'An explicit source AMI must not perform a mutable image lookup.' >&2
  exit 1
fi

cat >> "$config" <<'EOF'
AMI_EXISTING_IMAGE_ACTION=reuse
EOF
reuse_work=${runtime_dir#"$root/"}/work-reuse
: > "$packer_log"
PATH="$mock_bin:$PATH" bin/ec2 make_ami --workdir "$reuse_work" \
  --environment-config "$config" >/dev/null
grep -q $'^0\tami-resolved-source' "$reuse_work/packer/.build-cpu.result" || {
  echo 'AMI reuse did not record the existing AMI.' >&2
  exit 1
}
if grep -q '^build ' "$packer_log"; then
  echo 'AMI reuse must not start a Packer build.' >&2
  exit 1
fi

echo 'Reproducible build input tests passed.'
