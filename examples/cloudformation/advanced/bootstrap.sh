#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
region="${AWS_REGION-}"
stack_name=ec2-advanced
ssh_cidr=''
az_a=''
az_b=''
state_dir="${EC2_ADVANCED_STATE_DIR:-$HOME/.config/ec2/advanced}"

usage() {
  cat <<'EOF'
Usage: bootstrap.sh --region REGION --availability-zones AZ-A,AZ-B \
  --ssh-cidr CIDR [--stack-name NAME]
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) region=$2; shift 2;;
    --availability-zones)
      IFS=, read -r az_a az_b <<< "$2"; shift 2;;
    --stack-name) stack_name=$2; shift 2;;
    --ssh-cidr) ssh_cidr=$2; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2;;
  esac
done
[[ -n "$region" && -n "$az_a" && -n "$az_b" && -n "$ssh_cidr" ]] || {
  usage >&2; exit 2;
}
[[ "$az_a" != "$az_b" ]] || { echo 'Availability zones must differ.' >&2; exit 2; }

mkdir -p "$state_dir"
key_name="${stack_name}-key"
key_file="$state_dir/id_ed25519"
if [[ ! -f "$key_file" ]]; then
  ssh-keygen -q -t ed25519 -N '' -f "$key_file" -C "$key_name"
fi
if ! aws --region "$region" ec2 describe-key-pairs --key-names "$key_name" >/dev/null 2>&1; then
  aws --region "$region" ec2 import-key-pair --key-name "$key_name" \
    --public-key-material "fileb://$key_file.pub" >/dev/null
fi

aws --region "$region" cloudformation deploy \
  --stack-name "$stack_name" \
  --template-file "$script_dir/template.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    AvailabilityZoneA="$az_a" \
    AvailabilityZoneB="$az_b" \
    AllowedSshCidr="$ssh_cidr" \
    KeyName="$key_name" \
  >/dev/null

"$repo_root/examples/cloudformation/render-environment.sh" \
  --profile advanced --region "$region" --stack-name "$stack_name" --state-dir "$state_dir"
cat <<EOF

Next:
  ec2 make_ami --environment-config "$state_dir/environment" --setup
  ec2 launch -t t3.medium
  ec2 ssh

The generated job subnet IDs are in:
  $state_dir/job-subnets.env
Use a separate job environment or launch JSON when submitting work to those subnets.
EOF
