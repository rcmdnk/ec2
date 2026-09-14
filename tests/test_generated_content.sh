#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-environment-generated-content.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
marker="$runtime_dir/unexpected-command"
ssh_input="$runtime_dir/ssh-config"
aws_input="$runtime_dir/aws-config"
local_home="$runtime_dir/local-home"
config="$runtime_dir/config"
mkdir -p "$mock_bin" "$local_home"

cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" ec2 describe-images "* ]];then echo ami-generated-content-test;fi
EOF
chmod 755 "$mock_bin/aws"
cat > "$ssh_input" <<EOF
Host test
  LocalCommand touch $marker
EOF
cat > "$aws_input" <<EOF
[profile test]
value=\$(touch $marker)
EOF
printf 'local rc\n' > "$local_home/.localrc"
cat > "$config" <<EOF
AWS_REGION=ap-northeast-1
CPU_OUTPUT_AMI_NAME=generated-content-test
AWS_SUBNET_IDS=subnet-generated-content-test
EC2_KEY_NAME=generated-content-test
EC2_SSH_PRIVATE_KEY='/tmp/key with spaces.pem'
EC2_SSH_USERNAME='test-user; touch $marker'
EC2_SUBMIT_COMMAND='echo \$(touch $marker)'
S3FILES_IDS=fs-generated-content-test
S3FILES_MOUNT_POINTS='$runtime_dir/mount point; touch $marker'
USER_ENV_ROOT_DIR='$runtime_dir/fs dir; touch $marker'
USER_ENV_ENABLE_USR_SYMLINK=0
USER_ENV_DOTFILES_FILE=
USER_ENV_DOTFILES_DIR=
INSTANCE_SYSTEMD_SERVICES=chronyd,amazon-ssm-agent
INSTANCE_COPY_FILES='$ssh_input,$aws_input,~/.localrc'
INSTANCE_COPY_DESTINATIONS='~/.ssh/config,~/.aws/config,'
INSTANCE_COPY_PERMISSIONS='600,640,644'
EOF

work=${runtime_dir#"$root/"}/work
HOME="$local_home" PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$work" \
  --environment-config "$config" --install-config 0 >/dev/null
generated_config="$runtime_dir/work/ec2/config"
generated_user_data="$runtime_dir/work/ec2/user_data.sh"

[[ ! -e "$marker" ]] || {
  echo 'Configuration values executed while generated content was written.' >&2
  exit 1
}
bash -n "$generated_user_data"
grep -q 'systemctl enable --now chronyd' "$generated_user_data"
grep -q 'systemctl enable --now amazon-ssm-agent' "$generated_user_data"
grep -q 'copy_destination=/home/"\$user"/.ssh/config' "$generated_user_data"
grep -q 'copy_destination=/home/"\$user"/.aws/config' "$generated_user_data"
grep -q 'copy_destination=/home/"\$user"/.localrc' "$generated_user_data"
grep -q 'chmod 600 "\$copy_destination"' "$generated_user_data"
grep -q 'chmod 640 "\$copy_destination"' "$generated_user_data"
grep -q 'chmod 644 "\$copy_destination"' "$generated_user_data"

# Sourcing the generated client config must restore values, not interpret them
# as additional shell syntax.
unset submit_command ssh_user
# shellcheck disable=SC1090
source "$generated_config"
# shellcheck disable=SC2154  # Assigned by the generated config sourced above.
[[ "$submit_command" == "echo \$(touch $marker)" ]] || {
  echo 'The generated client config did not preserve a metacharacter value.' >&2
  exit 1
}
# shellcheck disable=SC2154  # Assigned by the generated config sourced above.
[[ "$ssh_user" == "test-user; touch $marker" ]] || {
  echo 'The generated client config did not preserve the SSH user value.' >&2
  exit 1
}
[[ ! -e "$marker" ]] || {
  echo 'Sourcing the generated client config executed embedded syntax.' >&2
  exit 1
}

# Execute the generated prologue through the serialized assignments. An unsafe
# user assignment would run the marker command before instance metadata starts.
awk '/^instance_id=/{exit} {print}' "$generated_user_data" > "$runtime_dir/prologue.sh"
bash "$runtime_dir/prologue.sh" >/dev/null
[[ ! -e "$marker" ]] || {
  echo 'The generated user-data prologue executed an embedded user value.' >&2
  exit 1
}

if grep -qF "LocalCommand touch $marker" "$generated_user_data" ||
  grep -qF "value=\$(touch $marker)" "$generated_user_data";then
  echo 'Multiline configuration payloads must be encoded in generated user-data.' >&2
  exit 1
fi

echo 'Generated content serialization tests passed.'
