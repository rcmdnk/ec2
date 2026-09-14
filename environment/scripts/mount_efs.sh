# shellcheck shell=bash
if [[ -n "$EFS_IDS" && -n "$EFS_MOUNT_POINTS" ]]; then
  IFS=, read -r -a ids <<<"$EFS_IDS"
  IFS=, read -r -a mounts <<<"$EFS_MOUNT_POINTS"
  for i in "${!ids[@]}"; do
    printf 'mount_entry %q %q efs %q\n' "${ids[i]}:/" "${mounts[i]}" '_netdev,tls,noresvport,nofail'
  done
fi
