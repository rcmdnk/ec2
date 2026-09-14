#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
config=$(mktemp "${TMPDIR:-/tmp}/ec2-variable-precedence.XXXXXX")
trap 'rm -f "$config"' EXIT
cat > "$config" <<'EOF'
AWS_REGION=common-region
AWS_SUBNET_IDS=common-subnet
EC2_KEY_NAME=test-key
EC2_REGION=ec2-region
EC2_SUBNET_IDS=ec2-subnet
AMI_BUILD_REGION=ami-region
AMI_BUILD_SUBNET_IDS=ami-subnet
CPU_ENABLED=0
GPU_ENABLED=0
EOF

common=$(CONFIG="$config" WORKDIR=tmp bash -c 'source "$CONFIG"; source environment/scripts/variables.sh; printf "%s %s\n" "$REGION" "$SUBNET_IDS"')
ami=$(CONFIG="$config" WORKDIR=tmp ENVIRONMENT_OPERATION=ami bash -c 'source "$CONFIG"; source environment/scripts/variables.sh; printf "%s %s\n" "$REGION" "$SUBNET_IDS"')
[[ "$common" == 'ec2-region ec2-subnet' ]]
[[ "$ami" == 'ami-region ami-subnet' ]]

if EC2_CONNECTION_METHOD=telnet CONFIG="$config" WORKDIR=tmp bash -c 'source "$CONFIG"; source environment/scripts/variables.sh' >/dev/null 2>&1; then
  echo 'Invalid EC2_CONNECTION_METHOD must be rejected.' >&2
  exit 1
fi
if AMI_FAMILIES=CPU,CPU CONFIG="$config" WORKDIR=tmp bash -c 'source "$CONFIG"; source environment/scripts/variables.sh' >/dev/null 2>&1; then
  echo 'Duplicate AMI families must be rejected.' >&2
  exit 1
fi
echo 'Variable precedence tests passed.'
