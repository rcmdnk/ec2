# shellcheck shell=bash
if [[ -n "$FSX_IDS" && -n "$FSX_MOUNT_POINTS" ]]; then
  IFS=, read -r -a ids <<<"$FSX_IDS"
  IFS=, read -r -a mounts <<<"$FSX_MOUNT_POINTS"
  for i in "${!ids[@]}"; do
    printf 'mount_entry %q %q nfs4 %q\n' \
      "${ids[i]}.fsx.${REGION}.amazonaws.com:/fsx/" "${mounts[i]}" \
      'noatime,nfsvers=4.2,nconnect=16,_netdev,nofail'
  done
fi
