#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/bootstrap.sh" "${1:-}" "${2:-}" ec2

if [[ "$SUBNET_IDS" == *,* ]]; then
  echo "io2 requires exactly one subnet ID" >&2
  exit 1
fi

get_io2_id() {
  local name=$1
  aws "${AWS_ARGS[@]}" ec2 describe-volumes \
  --filters "Name=tag:Name,Values=$name" \
  --query 'Volumes[].VolumeId' --output text
}

prepare_io2_creation() {
  local n_names=$1
  if [[ -z "$SUBNET_IDS" ]];then
    echo "SUBNET_IDS must be set to create an io2 volume" >&2
    return 1
  fi
  IO2_VOLUME_SIZES_GIB=$(make_array "$n_names" "$IO2_VOLUME_SIZES_GIB") || return 1
  IO2_VOLUME_IOPS=$(make_array "$n_names" "$IO2_VOLUME_IOPS") || return 1
}

create_io2() {
  local i=$1 name=$2 id size iops availability_zone tags tag_specification
  size=$(csv_items "$IO2_VOLUME_SIZES_GIB" "$i")
  iops=$(csv_items "$IO2_VOLUME_IOPS" "$i")

  availability_zone=$(subnet_az "$SUBNET_IDS") || return 1
  tags=$(resource_tags_json "$name") || return 1
  tag_specification=$(printf '[{"ResourceType":"volume","Tags":%s}]' "$tags")
  id=$(aws "${AWS_ARGS[@]}" ec2 create-volume --availability-zone "$availability_zone" \
    --size "$size" --volume-type io2 --iops "$iops" --encrypted --multi-attach \
    --tag-specifications "$tag_specification" \
    --query VolumeId --output text) || return 1
  [[ -n "$id" && "$id" != None ]] || return 1
  record_resource io2 "$id" "$name" || return 1
  echo "Created io2 volume '$name': $id" >&2
  echo 'They are attached and formatted by user-data at the next launch.' >&2
  echo "$id"
}

validate_multi_attach_volumes() {
  local expected_az=$1 volume_id volume_type multi_attach availability_zone
  local -a volume_ids
  mapfile -t volume_ids < <(csv_items "$IO2_IDS")
  for volume_id in "${volume_ids[@]}"; do
    read -r volume_type multi_attach availability_zone < <(
      aws "${AWS_ARGS[@]}" ec2 describe-volumes --volume-ids "$volume_id" \
        --query 'Volumes[0].[VolumeType,MultiAttachEnabled,AvailabilityZone]' --output text
    )
    [[ "$volume_type" == io2 && "$multi_attach" == True ]] || {
      echo "io2 volume '$volume_id' must have Multi-Attach enabled." >&2
      return 1
    }
    [[ "$availability_zone" == "$expected_az" ]] || {
      echo "io2 volume '$volume_id' is in '$availability_zone', expected '$expected_az'." >&2
      return 1
    }
  done
}

setup_filesystem_ids io2 create_io2 prepare_io2_creation
if [[ -n "$IO2_IDS" ]]; then
  expected_az=$(subnet_az "$SUBNET_IDS") || exit 1
  validate_multi_attach_volumes "$expected_az"
fi
echo "$IO2_IDS"
