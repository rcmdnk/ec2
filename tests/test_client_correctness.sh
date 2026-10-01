#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/ec2-client-correctness.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
config="$runtime_dir/config"
aws_log="$runtime_dir/aws.log"
xdg_config="$runtime_dir/xdg"
mkdir -p "$mock_bin" "$xdg_config"

cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_LOG"
if [[ " $* " == *" sts get-caller-identity "* ]]; then
  printf '123456789012\n'
elif [[ " $* " == *" ec2 describe-instances "* ]]; then
  printf 'Name with spaces\ti-0123456789abcdef0\t203.0.113.10\trunning\tt3.micro\ton-demand\tus-east-1a\n'
elif [[ " $* " == *" ec2 describe-images "* ]]; then
  printf 'Image name with spaces\tami-0123456789abcdef0\tsnap-0123456789abcdef0\n'
fi
EOF
chmod 755 "$mock_bin/aws"

cat > "$config" <<'EOF'
AWS_REGION=us-east-1
AWS_PROFILE=base-profile
EC2_PROFILE=ec2-profile
EC2_REGION=eu-west-1
CPU_OUTPUT_AMI_NAME=client-correctness-test
AWS_SUBNET_IDS=subnet-client-correctness-test
EC2_KEY_NAME=client-correctness-test
EC2_FILESYSTEM_PROVIDERS=
EC2_SSH_OPTIONS=()
EC2_ET_OPTIONS=()
EC2_SCP_OPTIONS=(-r)
EC2_RSYNC_OPTIONS=(-a)
EOF

HOME="$runtime_dir/home" XDG_CONFIG_HOME="$xdg_config" AWS_LOG="$aws_log" \
  PATH="$mock_bin:$PATH" bin/ec2 setup --environment-config "$config" \
  --workdir "$runtime_dir/work" --install-config 0 >/dev/null
generated_config="$runtime_dir/work/ec2/config"
grep -q '^aws_profile=ec2-profile$' "$generated_config"
grep -q '^aws_region=eu-west-1$' "$generated_config"

: > "$aws_log"
instance_output=$(HOME="$runtime_dir/home" XDG_CONFIG_HOME="$xdg_config" AWS_LOG="$aws_log" \
  PATH="$mock_bin:$PATH" bin/ec2 --config "$generated_config" \
  --aws-profile cli-profile --aws-region cli-region instances)
instance_line=$(printf '%s\n' "$instance_output" | grep 'i-0123456789abcdef0')
[[ "$instance_line" == *'Name with spaces'* ]]
[[ "$instance_line" == *'i-0123456789abcdef0'* ]]
[[ "$instance_line" == *'203.0.113.10'* ]]
if grep -Fq '\\t' <<< "$instance_output"; then
  echo 'Instance listings must render tab-separated fields as aligned columns.' >&2
  exit 1
fi
grep -q -- '--profile cli-profile' "$aws_log"
grep -q -- '--region cli-region' "$aws_log"

function_source="$runtime_dir/functions.sh"
sed '/^# Main$/,$d' src/ec2 > "$function_source"
job_list="$runtime_dir/job-list"
printf '%s\n' '123 2026-09-30 12:00:00 job - - running' > "$job_list"
boundary=$(bash -c 'source "$1"; __job_list="$2"; __submit_sedi_lock="$2.lock"; __submit_max_jobs=1; _check_job_instances' _ "$function_source" "$job_list")
[[ "$boundary" == 1 ]]
below_boundary=$(bash -c 'source "$1"; __job_list="$2"; __submit_sedi_lock="$2.lock"; __submit_max_jobs=2; _check_job_instances' _ "$function_source" "$job_list")
[[ "$below_boundary" == 0 ]]

echo 'Client correctness tests passed.'
