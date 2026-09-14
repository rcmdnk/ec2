# shellcheck shell=bash
if [[ -n "$S3FILES_IDS" && -n "$S3FILES_MOUNT_POINTS" ]]; then
  IFS=, read -r -a ids <<<"$S3FILES_IDS"
  IFS=, read -r -a mounts <<<"$S3FILES_MOUNT_POINTS"
  for i in "${!ids[@]}"; do
    printf 'mount_entry %q %q s3files %q\n' "${ids[i]}:/" "${mounts[i]}" '_netdev,nofail'
  done
fi
