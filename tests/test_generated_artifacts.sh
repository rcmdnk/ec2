#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-environment-artifacts.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
config="$runtime_dir/config"
mkdir -p "$mock_bin"

cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" ec2 describe-images "* ]];then echo ami-generated-artifact-test;fi
EOF
chmod 755 "$mock_bin/aws"
cat > "$config" <<'EOF'
AWS_REGION=ap-northeast-1
CPU_OUTPUT_AMI_NAME=generated-artifact-test
AWS_SUBNET_IDS=subnet-generated-artifact-test
EC2_SUBNET_LABELS=ci
EC2_KEY_NAME=generated-artifact-test
EC2_SSH_PRIVATE_KEY=/tmp/generated-artifact-test.pem
USER_ENV_ENABLE_USR_SYMLINK=0
USER_ENV_DOTFILES_FILE=
USER_ENV_DOTFILES_DIR=
EOF

work=${runtime_dir#"$root/"}/work
PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$work" \
  --environment-config "$config" --install-config 0 >/dev/null
artifact_dir="$runtime_dir/work/ec2"

python3 -m json.tool "$artifact_dir/cli_input_json/generated-artifact-test-ci.json" >/dev/null
bash -n "$artifact_dir/user_data.sh"
gzip -cd "$artifact_dir/user_data.sh.gz" | bash -n

echo 'Generated artifact tests passed.'
