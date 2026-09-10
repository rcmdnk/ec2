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
REGION=ap-northeast-1
CPU_AMI_NAME=generated-artifact-test
SUBNET_IDS=subnet-generated-artifact-test
SUBNET_LABELS=ci
KEY_NAME=generated-artifact-test
EC2_SSH_KEY=/tmp/generated-artifact-test.pem
FS_USR=0
FS_DOTFILES_FILE=
FS_DOTFILES_DIR=
EOF

work=${runtime_dir#"$root/"}/work
PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$work" \
  --environment-config "$config" --install-config 0 >/dev/null
artifact_dir="$runtime_dir/work/ec2"

python3 -m json.tool "$artifact_dir/cli_input_json/generated-artifact-test-ci.json" >/dev/null
bash -n "$artifact_dir/user_data.sh"
gzip -cd "$artifact_dir/user_data.sh.gz" | bash -n

echo 'Generated artifact tests passed.'
