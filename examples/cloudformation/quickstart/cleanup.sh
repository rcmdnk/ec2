#!/usr/bin/env bash
set -euo pipefail

region="${AWS_REGION-}"
stack_name=ec2-quickstart
state_dir="${EC2_QUICKSTART_STATE_DIR:-$HOME/.config/ec2/quickstart}"
yes=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) region=$2; shift 2;;
    --stack-name) stack_name=$2; shift 2;;
    --yes) yes=1; shift;;
    *) echo "Unknown argument: $1" >&2; exit 2;;
  esac
done
[[ -n "$region" ]] || { echo '--region is required.' >&2; exit 2; }
if (( ! yes )); then
  read -r -p "Delete stack $stack_name and its EFS? [y/N] " answer
  [[ "$answer" == y || "$answer" == Y ]] || exit 0
fi
key_name="${stack_name}-key"
aws --region "$region" cloudformation delete-stack --stack-name "$stack_name"
aws --region "$region" cloudformation wait stack-delete-complete --stack-name "$stack_name"
aws --region "$region" ec2 delete-key-pair --key-name "$key_name" || true
echo "Deleted $stack_name. Local state remains at $state_dir; remove it after checking the key is no longer needed."
