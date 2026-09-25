#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-existing-ami.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
config="$runtime_dir/config"
mkdir -p "$mock_bin"

cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" sts get-caller-identity "* ]]; then
  echo 123456789012
elif [[ " $* " == *" ec2 describe-images "* ]]; then
  if [[ " $* " == *" --image-ids "* ]]; then
    echo ami-existing-test
  else
    echo ami-named-test
  fi
fi
EOF
chmod 755 "$mock_bin/aws"

cat > "$config" <<'EOF'
AWS_REGION=ap-northeast-1
CPU_ENABLED=1
CPU_AMI_ID=ami-existing-test
GPU_ENABLED=0
AWS_SUBNET_IDS=subnet-existing-test
EC2_KEY_NAME=existing-test
EC2_FILESYSTEM_PROVIDERS=
EOF

work=${runtime_dir#"$root/"}/work
PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$work" \
  --environment-config "$config" --install-config 0 >/dev/null

json=$(find "$runtime_dir/work/ec2/cli_input_json" -name '*.json' -print -quit)
[[ -n "$json" ]] || { echo 'No launch JSON was generated for an existing AMI.' >&2; exit 1; }
grep -q '"ImageId": "ami-existing-test"' "$json" || {
  echo 'The exact existing AMI ID was not written to launch JSON.' >&2
  exit 1
}

echo 'Existing AMI setup tests passed.'
