#!/usr/bin/env bash
set -euo pipefail

execute=0
manifest_override=''
workdir=${WORKDIR:-my_work}
config=${CONFIG:-./config}
while (($# > 0));do
  case $1 in
    --execute) execute=1 ;;
    --manifest) manifest_override=${2:?--manifest requires a path}; shift ;;
    --workdir) workdir=${2:?--workdir requires a path}; shift ;;
    --config) config=${2:?--config requires a path}; shift ;;
    --help)
      echo 'Usage: scripts/cleanup_resources.sh [--manifest PATH] [--workdir DIR] [--config FILE] [--execute]'
      echo 'Without --execute, only the exact-ID deletion plan is printed.'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/bootstrap.sh" "$workdir" "$config"
manifest=${manifest_override:-$RESOURCE_MANIFEST}
[[ -f "$manifest" ]] || { echo "Resource manifest not found: $manifest" >&2; exit 1; }

aws_error_is_retryable() {
  [[ "$1" =~ RequestLimitExceeded|Throttl|TooManyRequests|ServiceUnavailable|Internal(Error|Failure)|RequestTimeout|PriorRequestNotComplete|SlowDown|temporar|timed[[:space:]]out|connection[[:space:]](reset|closed) ]]
}

aws_retry() {
  local attempt=1 status error_file error
  while :; do
    error_file=$(mktemp "${TMPDIR:-/tmp}/ec2-aws-error.XXXXXX")
    status=0
    aws "$@" 2>"$error_file" || status=$?
    if ((status == 0)); then
      cat "$error_file" >&2
      rm -f "$error_file"
      return 0
    fi
    error=$(<"$error_file")
    rm -f "$error_file"
    if ((attempt >= AWS_MAX_ATTEMPTS)) || ! aws_error_is_retryable "$error"; then
      printf '%s\n' "$error" >&2
      return "$status"
    fi
    sleep "$AWS_POLL_DELAY_SECONDS"
    ((attempt++))
  done
}

managed_tag() {
  local type=$1 id=$2
  case $type in
    ami)
      aws_retry "${AWS_ARGS[@]}" ec2 describe-images --image-ids "$id" \
        --query "Images[0].Tags[?Key=='ManagedBy'].Value | [0]" --output text
      ;;
    instance)
      aws_retry "${AWS_ARGS[@]}" ec2 describe-instances --instance-ids "$id" \
        --query "Reservations[0].Instances[0].Tags[?Key=='ManagedBy'].Value | [0]" --output text
      ;;
    snapshot)
      aws_retry "${AWS_ARGS[@]}" ec2 describe-snapshots --snapshot-ids "$id" \
        --query "Snapshots[0].Tags[?Key=='ManagedBy'].Value | [0]" --output text
      ;;
    efs)
      aws_retry "${AWS_ARGS[@]}" efs describe-file-systems --file-system-id "$id" \
        --query "FileSystems[0].Tags[?Key=='ManagedBy'].Value | [0]" --output text
      ;;
    fsx)
      aws_retry "${AWS_ARGS[@]}" fsx describe-file-systems --file-system-ids "$id" \
        --query "FileSystems[0].Tags[?Key=='ManagedBy'].Value | [0]" --output text
      ;;
    io2)
      aws_retry "${AWS_ARGS[@]}" ec2 describe-volumes --volume-ids "$id" \
        --query "Volumes[0].Tags[?Key=='ManagedBy'].Value | [0]" --output text
      ;;
    *) return 2 ;;
  esac
}

verify_managed_resource() {
  local type=$1 id=$2 actual
  if ! actual=$(managed_tag "$type" "$id" 2>&1); then
    if [[ "$actual" =~ NotFound|not[[:space:]]exist|does[[:space:]]not[[:space:]]exist|InvalidInstanceID\.NotFound ]]; then
      return 2
    fi
    echo "Could not inspect $type $id: $actual" >&2
    return 1
  fi
  [[ "$actual" == "$RESOURCE_MANAGED_BY" ]] || {
    echo "Refusing to delete $type $id: ManagedBy is '$actual', expected '$RESOURCE_MANAGED_BY'." >&2
    return 1
  }
}

delete_efs() {
  local id=$1 target remaining attempt
  local -a targets
  mapfile -t targets < <(aws_retry "${AWS_ARGS[@]}" efs describe-mount-targets --file-system-id "$id" \
    --query 'MountTargets[].MountTargetId' --output text | tr '\t' '\n' | awk 'NF && $0 != "None"')
  for target in "${targets[@]}";do
    aws_retry "${AWS_ARGS[@]}" efs delete-mount-target --mount-target-id "$target"
  done
  for ((attempt=1; attempt<=AWS_MAX_ATTEMPTS; attempt++));do
    remaining=$(aws_retry "${AWS_ARGS[@]}" efs describe-mount-targets --file-system-id "$id" \
      --query 'length(MountTargets)' --output text)
    [[ "$remaining" == 0 ]] && break
    ((attempt == AWS_MAX_ATTEMPTS)) || sleep "$AWS_POLL_DELAY_SECONDS"
  done
  [[ "$remaining" == 0 ]] || { echo "Timed out deleting mount targets for $id." >&2; return 1; }
  aws_retry "${AWS_ARGS[@]}" efs delete-file-system --file-system-id "$id"
}

delete_ami() {
  local id=$1 snapshot_ids snapshot verify_status failed=0
  mapfile -t snapshot_ids < <(aws_retry "${AWS_ARGS[@]}" ec2 describe-images --image-ids "$id" \
    --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text 2>/dev/null | \
    tr '\t' '\n' | awk 'NF && $0 != "None"')
  aws_retry "${AWS_ARGS[@]}" ec2 deregister-image --image-id "$id"
  for snapshot in "${snapshot_ids[@]}"; do
    if verify_managed_resource snapshot "$snapshot"; then
      verify_status=0
    else
      verify_status=$?
    fi
    case $verify_status in
      0)
      aws_retry "${AWS_ARGS[@]}" ec2 delete-snapshot --snapshot-id "$snapshot" || failed=1
        ;;
      2)
        echo "Snapshot $snapshot is already absent."
        ;;
      *)
      echo "Leaving snapshot $snapshot because its ManagedBy tag could not be verified." >&2
      failed=1
        ;;
    esac
  done
  return "$failed"
}

delete_resource() {
  local type=$1 id=$2 verify_status
  if verify_managed_resource "$type" "$id"; then
    verify_status=0
  else
    verify_status=$?
  fi
  case $verify_status in
    2) echo "$type $id is already absent."; return 0 ;;
    0) ;;
    *) return 1 ;;
  esac
  case $type in
    ami) delete_ami "$id" ;;
    instance) aws_retry "${AWS_ARGS[@]}" ec2 terminate-instances --instance-ids "$id" ;;
    snapshot) aws_retry "${AWS_ARGS[@]}" ec2 delete-snapshot --snapshot-id "$id" ;;
    efs) delete_efs "$id" ;;
    fsx) aws_retry "${AWS_ARGS[@]}" fsx delete-file-system --file-system-id "$id" --open-zfs-configuration SkipFinalBackup=true ;;
    io2) aws_retry "${AWS_ARGS[@]}" ec2 delete-volume --volume-id "$id" ;;
    *) echo "Unsupported manifest resource type: $type" >&2; return 1 ;;
  esac
}

echo "Resource cleanup plan from $manifest:"
while IFS=$'\t' read -r type id name created_at;do
  [[ "$type" == type || -z "$type" ]] && continue
  printf '  delete %-4s id=%s name=%s created=%s\n' "$type" "$id" "$name" "$created_at"
done < "$manifest"
if [[ "$execute" != 1 ]];then
  echo 'Dry run only. Re-run with --execute to verify ManagedBy tags and delete these exact IDs.'
  exit 0
fi

remaining_manifest=$(mktemp "${manifest}.remaining.XXXXXX")
trap 'rm -f "$remaining_manifest"' EXIT
printf 'type\tid\tname\tcreated_at\n' > "$remaining_manifest"
failed=0
while IFS=$'\t' read -r type id name created_at;do
  [[ "$type" == type || -z "$type" ]] && continue
  if delete_resource "$type" "$id";then
    echo "Deleted $type $id."
  else
    printf '%s\t%s\t%s\t%s\n' "$type" "$id" "$name" "$created_at" >> "$remaining_manifest"
    failed=1
  fi
done < "$manifest"
mv "$remaining_manifest" "$manifest"
trap - EXIT
exit "$failed"
