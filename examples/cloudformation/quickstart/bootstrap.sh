#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
region="${AWS_REGION-}"
stack_name=ec2-quickstart
ssh_cidr=''
state_dir="${EC2_QUICKSTART_STATE_DIR:-$HOME/.config/ec2/quickstart}"

usage() {
  cat <<'EOF'
Usage: bootstrap.sh --region REGION --ssh-cidr CIDR [--stack-name NAME]
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) region=$2; shift 2;;
    --stack-name) stack_name=$2; shift 2;;
    --ssh-cidr) ssh_cidr=$2; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2;;
  esac
done
[[ -n "$region" && -n "$ssh_cidr" ]] || { usage >&2; exit 2; }

aws_cmd=(aws --region "$region")
vpc_id=$("${aws_cmd[@]}" ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
[[ "$vpc_id" != None && -n "$vpc_id" ]] || {
  echo 'No default VPC was found. Create one or use the advanced example.' >&2
  exit 1
}
subnet_id=$("${aws_cmd[@]}" ec2 describe-subnets \
  --filters Name=vpc-id,Values="$vpc_id" Name=map-public-ip-on-launch,Values=true \
  --query 'Subnets[0].SubnetId' --output text)
[[ "$subnet_id" != None && -n "$subnet_id" ]] || {
  echo "No public subnet was found in default VPC $vpc_id." >&2
  exit 1
}

mkdir -p "$state_dir"
key_name="${stack_name}-key"
key_file="$state_dir/id_ed25519"
if [[ ! -f "$key_file" ]]; then
  ssh-keygen -q -t ed25519 -N '' -f "$key_file" -C "$key_name"
fi
if ! "${aws_cmd[@]}" ec2 describe-key-pairs --key-names "$key_name" >/dev/null 2>&1; then
  "${aws_cmd[@]}" ec2 import-key-pair --key-name "$key_name" \
    --public-key-material "fileb://$key_file.pub" >/dev/null
fi

"${aws_cmd[@]}" cloudformation deploy \
  --stack-name "$stack_name" \
  --template-file "$script_dir/template.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    VpcId="$vpc_id" \
    SubnetId="$subnet_id" \
    KeyName="$key_name" \
    AllowedSshCidr="$ssh_cidr" \
  >/dev/null

"$repo_root/examples/cloudformation/render-environment.sh" \
  --profile quickstart --region "$region" --stack-name "$stack_name" --state-dir "$state_dir"
cat <<EOF

Next:
  ec2 make_ami --environment-config "$state_dir/environment" --setup
  ec2 launch -t t3.medium
  ec2 ssh
EOF
