#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/bootstrap.sh"

get_efs_id() {
  local name=$1
  aws "${AWS_ARGS[@]}" efs describe-file-systems \
  --query "FileSystems[?Name=='$name'].FileSystemId" --output text
}

prepare_efs_creation() {
  local n_names=$1
  if [[ -z "$SUBNET_IDS" ]];then
    echo "SUBNET_IDS must be set to create an EFS" >&2
    return 1
  fi
  if [[ -z "$EFS_SECURITY_GROUP_IDS" ]]; then
    echo "EFS_SECURITY_GROUP_IDS is required when EFSs are created from EFS_NAMES" >&2
    return 1
  fi
  EFS_SECURITY_GROUP_IDS=$(make_array "$n_names" "$EFS_SECURITY_GROUP_IDS") || return 1
  EFS_PERFORMANCE_MODES=$(make_array "$n_names" "$EFS_PERFORMANCE_MODES" "generalPurpose") || return 1
  EFS_THROUGHPUT_MODES=$(make_array "$n_names" "$EFS_THROUGHPUT_MODES" "bursting") || return 1
}

create_efs() {
  local i=$1 name=$2 id tags creation_token
  local security_group_id performance_mode throughput_mode subnet_id
  local -a subnet_ids
  security_group_id=$(csv_items "$EFS_SECURITY_GROUP_IDS" "$i")
  performance_mode=$(csv_items "$EFS_PERFORMANCE_MODES" "$i")
  throughput_mode=$(csv_items "$EFS_THROUGHPUT_MODES" "$i")

  tags=$(resource_tags_json "$name") || return 1
  creation_token=$(efs_creation_token "$name") || return 1
  id=$(aws "${AWS_ARGS[@]}" efs create-file-system --creation-token "$creation_token" \
    --backup --encrypted --performance-mode "$performance_mode" \
    --throughput-mode "$throughput_mode" --tags "$tags" \
    --query FileSystemId --output text) || return 1
  [[ -n "$id" && "$id" != None ]] || return 1
  record_resource efs "$id" "$name" || return 1
  mapfile -t subnet_ids < <(csv_items "$SUBNET_IDS")
  for subnet_id in "${subnet_ids[@]}"; do
    aws "${AWS_ARGS[@]}" efs create-mount-target --file-system-id "$id" \
      --subnet-id "$subnet_id" --security-groups "$security_group_id" >/dev/null || return 1
  done
  echo "Created EFS '$name': $id" >&2
  echo 'Mount targets take a few minutes to become available. Until then the' >&2
  echo 'mounts fail silently on the instance (they are added with nofail).' >&2
  echo "$id"
}

setup_filesystem_ids efs create_efs prepare_efs_creation
echo "$EFS_IDS"
