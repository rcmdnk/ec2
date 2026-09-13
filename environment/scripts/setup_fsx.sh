#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/bootstrap.sh"

if [[ "$FSX_DEPLOYMENT_TYPE" == MULTI_AZ_* && "$SUBNET_IDS" != *,* ]]; then
  echo "FSX MULTI_AZ deployment requires at least two subnet IDs" >&2
  exit 1
fi
if [[ "$FSX_DEPLOYMENT_TYPE" == SINGLE_AZ_* && "$SUBNET_IDS" == *,* ]]; then
  echo "FSX SINGLE_AZ deployment accepts only one subnet ID" >&2
  exit 1
fi

get_fsx_id() {
  local name=$1
  aws "${AWS_ARGS[@]}" fsx describe-file-systems \
  --query "FileSystems[?Tags[?Key=='Name' && Value=='$name']].FileSystemId" --output text
}

prepare_fsx_creation() {
  local n_names=$1
  if [[ -z "$SUBNET_IDS" ]];then
    echo "SUBNET_IDS must be set to create an FSx file system" >&2
    return 1
  fi
  if [ -z "$FSX_SECURITY_GROUP_IDS" ]; then
    echo "FSX_SECURITY_GROUP_IDS is required when FSXs are created from FSX_NAMES" >&2
    return 1
  fi
  FSX_SECURITY_GROUP_IDS=$(make_array "$n_names" "$FSX_SECURITY_GROUP_IDS") || return 1
  FSX_STORAGE_TYPES=$(make_array "$n_names" "$FSX_STORAGE_TYPES" "SSD") || return 1
  FSX_STORAGE_CAPACITIES=$(make_array "$n_names" "$FSX_STORAGE_CAPACITIES" "100") || return 1
  FSX_THROUGHPUT_CAPACITIES=$(make_array "$n_names" "$FSX_THROUGHPUT_CAPACITIES" "160") || return 1
  FSX_AUTOMATIC_BACKUP_RETENTION_DAYS=$(make_array "$n_names" "$FSX_AUTOMATIC_BACKUP_RETENTION_DAYS" "30") || return 1
  FSX_ROUTE_TABLE_IDS=$(make_array "$n_names" "$FSX_ROUTE_TABLE_IDS") || return 1
}

create_fsx() {
  local i=$1 name=$2 id openzfs tags
  local security_group_id storage_type storage_capacity throughput_capacity
  local automatic_backup_retention_days route_table_id
  local -a args
  security_group_id=$(csv_items "$FSX_SECURITY_GROUP_IDS" "$i")
  storage_type=$(csv_items "$FSX_STORAGE_TYPES" "$i")
  storage_capacity=$(csv_items "$FSX_STORAGE_CAPACITIES" "$i")
  throughput_capacity=$(csv_items "$FSX_THROUGHPUT_CAPACITIES" "$i")
  automatic_backup_retention_days=$(csv_items "$FSX_AUTOMATIC_BACKUP_RETENTION_DAYS" "$i")
  route_table_id=$(csv_items "$FSX_ROUTE_TABLE_IDS" "$i")
  [[ "$throughput_capacity" =~ ^[0-9]+$ && "$automatic_backup_retention_days" =~ ^[0-9]+$ ]] || {
    echo 'FSX throughput and backup retention must be integers' >&2
    return 1
  }
  openzfs=$(printf '{"DeploymentType":%s,"ThroughputCapacity":%s,"AutomaticBackupRetentionDays":%s,"PreferredSubnetId":%s}' \
    "$(json_quote "$FSX_DEPLOYMENT_TYPE")" "$throughput_capacity" "$automatic_backup_retention_days" "$(json_quote "${SUBNET_IDS%%,*}")")
  tags=$(resource_tags_json "$name") || return 1

  args=("${AWS_ARGS[@]}" fsx create-file-system --file-system-type OPENZFS \
    --storage-type "$storage_type" --subnet-ids "${SUBNET_IDS//,/ }" \
    --security-group-ids "$security_group_id" \
    --tags "$tags" --query FileSystem.FileSystemId --output text)
  if [[ "$storage_type" == SSD ]]; then
    args+=(--storage-capacity "$storage_capacity")
  fi
  if [[ "$FSX_DEPLOYMENT_TYPE" == MULTI_AZ_* && -n "$route_table_id" ]]; then
    openzfs=${openzfs%\}}
    openzfs+=$(printf ',"RouteTableIds":[%s]}' "$(json_quote "$route_table_id")")
  fi
  args+=(--open-zfs-configuration "$openzfs")
  id=$(aws "${args[@]}") || return 1
  [[ -n "$id" && "$id" != None ]] || return 1
  record_resource fsx "$id" "$name" || return 1
  echo "Created FSx for OpenZFS '$name': $id" >&2
  echo 'Creation typically takes around 20 minutes. Until it reports AVAILABLE' >&2
  echo 'the mounts fail silently on the instance (they are added with nofail).' >&2
  echo "Check with: aws fsx describe-file-systems --file-system-ids $id --query 'FileSystems[].Lifecycle'" >&2
  echo "$id"
}

setup_filesystem_ids fsx create_fsx prepare_fsx_creation
echo "$FSX_IDS"
