# shellcheck shell=bash
if [[ -n "$IO2_IDS" && -n "$IO2_MOUNT_POINTS" ]]; then
  n_ids=$(tr ',' '\n' <<<"$IO2_IDS" | wc -l | tr -d ' ')
  IO2_DEVICE_NAMES=$(make_array "$n_ids" "$IO2_DEVICE_NAMES")
  IO2_FSTYPES=$(make_array "$n_ids" "$IO2_FSTYPES")
  mapfile -t devices < <(csv_items "$IO2_DEVICE_NAMES")
  mapfile -t fstypes < <(csv_items "$IO2_FSTYPES")
  IFS=, read -r -a ids <<<"$IO2_IDS"
  IFS=, read -r -a mounts <<<"$IO2_MOUNT_POINTS"
  for i in "${!ids[@]}"; do
    # shellcheck disable=SC2016
    printf '[[ -n "\$instance_id" ]] || { echo "Could not determine the EC2 instance ID required to attach %q." >&2; exit 1; }; aws ec2 attach-volume --region "\$region" --volume-id %q --instance-id "\$instance_id" --device %q >/dev/null; aws ec2 wait volume-in-use --region "\$region" --volume-ids %q\n' \
      "${ids[i]}" "${ids[i]}" "${devices[i]}" "${ids[i]}"
    # shellcheck disable=SC2016
    printf 'io2_mount=%q; io2_type=%q; mkdir -p "\$io2_mount"; io2_path=""; for ((attempt=1; attempt<=mount_max_attempts; attempt++));do io2_path=\$(lsblk -nrpo PATH,SERIAL | awk -v serial=%q '\''\$2 == serial {print \$1; exit}'\''); [[ -n "\$io2_path" ]] && break; ((attempt == mount_max_attempts)) || sleep "\$mount_retry_interval"; done; [[ -n "\$io2_path" ]] || { echo "Attached volume %q did not appear as a block device." >&2; exit 1; }; io2_actual_type=\$(blkid -o value -s TYPE "\$io2_path" || true); [[ -n "\$io2_actual_type" ]] || { echo "Multi-Attach volume %q must be formatted before launch; automatic formatting is disabled." >&2; exit 1; }; [[ "\$io2_actual_type" == "\$io2_type" ]] || { echo "Multi-Attach volume %q has filesystem type \$io2_actual_type, expected \$io2_type." >&2; exit 1; }; uuid=\$(blkid -o value -s UUID "\$io2_path"); grep -qF " \$io2_mount " /etc/fstab || echo "UUID=\$uuid \$io2_mount \$io2_type defaults,nofail 0 2" >> /etc/fstab; required_mounts+=("\$io2_mount")\n' \
      "${mounts[i]}" "${fstypes[i]}" "${ids[i]//-/}" "${ids[i]}" "${ids[i]}" "${ids[i]}"
  done
fi
