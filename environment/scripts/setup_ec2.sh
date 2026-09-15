#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2088
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Read by scripts/variables.sh: this entry point also needs EC2_KEY_NAME, which
# building an AMI or a file system does not.
# shellcheck disable=SC2034
REQUIRE_EC2_SETTINGS=1
source "$script_dir/bootstrap.sh" "${1:-}" "${2:-}" ec2
IFS=, read -r -a filesystem_providers <<<"$EC2_FILESYSTEM_PROVIDERS"
for filesystem_provider in "${filesystem_providers[@]}"; do
  [[ -z "$filesystem_provider" ]] && continue
  [[ "$filesystem_provider" =~ ^[a-z][a-z0-9_]*$ ]] || {
    echo "Invalid EC2_FILESYSTEM_PROVIDERS entry: $filesystem_provider" >&2
    exit 1
  }
  provider_script="$script_dir/setup_${filesystem_provider}.sh"
  [[ -x "$provider_script" ]] || {
    echo "Filesystem provider script not found: $provider_script" >&2
    exit 1
  }
  provider_var="${filesystem_provider^^}_IDS"
  printf -v "$provider_var" '%s' "$("$provider_script")"
done

systemd_services=()
IFS=, read -r -a configured_systemd_services <<<"$INSTANCE_SYSTEMD_SERVICES"
for systemd_service in "${configured_systemd_services[@]}"; do
  [[ -z "$systemd_service" ]] && continue
  [[ "$systemd_service" =~ ^[a-zA-Z0-9_.@:-]+$ ]] || {
    echo "Invalid INSTANCE_SYSTEMD_SERVICES entry: $systemd_service" >&2
    exit 1
  }
  systemd_services+=("$systemd_service")
done

for setting in MOUNT_READY_MAX_ATTEMPTS MOUNT_READY_RETRY_INTERVAL_SECONDS;do
  [[ "${!setting}" =~ ^[1-9][0-9]*$ ]] || {
    echo "$setting must be a positive integer." >&2
    exit 1
  }
done

# Omitted rather than sent empty, so that EC2 applies the VPC default security
# group instead of being handed a list with nothing in it.
groups_json=''
if [[ -n "$SECURITY_GROUP_IDS" ]];then
  groups_json=$(printf '\n            "Groups":%s,' "$(json_array_from_csv "$SECURITY_GROUP_IDS")")
fi
iam_json=''
if [[ -n "$IAM_INSTANCE_PROFILE" ]];then
  iam_json=$(printf '{"Name":%s}' "$(json_quote "$IAM_INSTANCE_PROFILE")")
fi

get_image_id() {
  local enabled=$1 name=$2 image
  [[ "$enabled" == 1 && -n "$name" ]] || return 0
  image=$(aws "${AWS_ARGS[@]}" ec2 describe-images --owners self --filters "Name=name,Values=$name" --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' --output text)
  [[ "$image" != None && -n "$image" ]] || return 0
  echo "$image"
}

json_dir="$WORKDIR/ec2/cli_input_json"
mkdir -p "$json_dir"
mkdir -p "$WORKDIR/ec2/mounts"

copy_entries=("${INSTANCE_COPY_ENTRIES[@]}")
for copy_entry in "${copy_entries[@]}"; do
  IFS='|' read -r copy_source copy_destination copy_permission copy_extra <<<"$copy_entry"
  [[ -n "$copy_source" && -z "${copy_extra:-}" ]] || {
    echo "INSTANCE_COPY_ENTRIES must use source|destination|permission: $copy_entry" >&2
    exit 1
  }
  [[ -z "${copy_permission:-}" || "$copy_permission" =~ ^[0-7]{3,4}$ ]] || {
    echo "Invalid permission in INSTANCE_COPY_ENTRIES entry: $copy_permission" >&2
    exit 1
  }
done
# The `ec2` command is run from anywhere, so it needs an absolute path.
json_dir_abs=$(cd "$json_dir" && pwd)
cpu_group=''
gpu_group=''
mapfile -t ids < <(csv_items "$SUBNET_IDS")
mapfile -t labels < <(csv_items "$EC2_SUBNET_LABELS")
jsons=()
json_contents=()
used_labels=()
# shellcheck disable=SC2153  # The uppercase setting is loaded from the environment config.
IFS=, read -r -a ami_families <<<"$AMI_FAMILIES"
for family in "${ami_families[@]}"; do
  printf -v "${family,,}_group" '%s' ''
done

for i in "${!ids[@]}";do
  if [ -z "${ids[i]}" ];then
    echo "SUBNET_IDS[$i] is empty" >&2
    exit 1
  fi
  subnet_id="${ids[i]}"
  if [[ -n "${labels[i]:-}" ]];then
    label="${labels[i]}"
  else
    label="${ids[i]#*-}"
  fi
  if [[ " ${used_labels[*]-} " == *" $label "* ]];then
    echo "EC2_SUBNET_LABELS[$i] is '$label', which is already used by another subnet." >&2
    echo 'Labels name the generated launch JSON files, so they must be unique.' >&2
    exit 1
  fi
  used_labels+=("$label")
  for family in "${ami_families[@]}";do
    enabled_var="${family}_ENABLED"; name_var="${family}_OUTPUT_AMI_NAME"; type_var="${family}_BUILD_INSTANCE_TYPE"
    image_id=$(get_image_id "${!enabled_var-0}" "${!name_var-}")
    [[ -n "$image_id" ]] || continue
    json_name="${!name_var}-${label}.json"
    output="$json_dir/$json_name"
    jsons+=("$json_name")
    public_ip=$EC2_ASSOCIATE_PUBLIC_IP
    [[ "$public_ip" == true || "$public_ip" == false ]] || { echo 'EC2_ASSOCIATE_PUBLIC_IP must be true or false' >&2; exit 1; }
    json_content=$({
      printf '{
    "ImageId": %s,
    "InstanceType": %s,
    "KeyName": %s,
    "EbsOptimized": true,' "$(json_quote "$image_id")" "$(json_quote "${!type_var}")" "$(json_quote "$EC2_KEY_NAME")"
      [[ -n "$iam_json" ]] && printf '
    "IamInstanceProfile": %s,' "$iam_json"
      printf '
    "NetworkInterfaces":[
        {
            "DeleteOnTermination":true,
            "Description":"",
            "DeviceIndex":0,%s
            "SubnetId":%s,
            "NetworkCardIndex":0,
            "AssociatePublicIpAddress":%s
        }
    ]
}' "$groups_json" "$(json_quote "$subnet_id")" "$public_ip"
      printf '\n'
    })
    echo "$json_content" > "$output"
    json_contents+=("$json_content")
    group_var="${family,,}_group"
    printf -v "$group_var" '%s' "${!group_var:+${!group_var},}$(basename "$output")"
  done
done

{
  echo '# Generated by ec2 setup.'
  echo '# Edit the environment configuration and run `ec2 setup` again.'
  shell_assignment name_filter "$EC2_NAME_FILTER"
  shell_assignment image_name_filter "$EC2_IMAGE_NAME_FILTER"
  shell_assignment ssh_key "$EC2_SSH_PRIVATE_KEY"
  shell_array_assignment ssh_option "${EC2_SSH_OPTIONS[@]}"
  shell_array_assignment et_option "${EC2_ET_OPTIONS[@]}"
  shell_array_assignment scp_option "${EC2_SCP_OPTIONS[@]}"
  shell_array_assignment rsync_option "${EC2_RSYNC_OPTIONS[@]}"
  shell_assignment ssh_user "$EC2_SSH_USERNAME"
  shell_assignment connection_method "$EC2_CONNECTION_METHOD"
  shell_assignment mosh_server "$EC2_MOSH_SERVER_PATH"
  shell_assignment private_ip "$EC2_USE_PRIVATE_IP"
  shell_assignment instance_type "$EC2_DEFAULT_INSTANCE_TYPE"
  shell_assignment spot_instance "$EC2_USE_SPOT_INSTANCE"
  shell_assignment submit_command "$EC2_SUBMIT_COMMAND"
  shell_assignment submit_n_retry_launch "$EC2_SUBMIT_N_RETRY_LAUNCH"
  shell_assignment submit_n_retry_ssh "$EC2_SUBMIT_N_RETRY_SSH"
  shell_assignment submit_retry_launch_interval "$EC2_SUBMIT_RETRY_LAUNCH_INTERVAL"
  shell_assignment submit_retry_ssh_interval "$EC2_SUBMIT_RETRY_SSH_INTERVAL"
  shell_assignment user_data "$EC2_USER_DATA_URI"
  shell_assignment auth_command "$AWS_AUTH_COMMAND"
  shell_assignment cli_input_json_directory "$json_dir_abs"
  shell_assignment cli_input_json_group "$EC2_CLI_INPUT_JSON_GROUP"
  for family in "${ami_families[@]}"; do
    group_var="${family,,}_group"
    shell_assignment "cli_input_json_group_${family,,}" "${!group_var}"
  done
} > "$WORKDIR/ec2/config"
unset ami_families group_var family
chmod 600 "$WORKDIR/ec2/config"

user_data_name=$(basename "$EC2_USER_DATA_URI")
user_data_sh="${EC2_USER_DATA_URI#*:}"
while [[ $user_data_sh == //* ]];do
  user_data_sh="${user_data_sh#/}"
done
user_data_sh="${user_data_sh%.gz}"
mkdir -p "$(dirname "$user_data_sh")"
{
  cat <<'EEOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== Starting user script set by ec2 command ==="
EEOF
  shell_assignment user "$EC2_SSH_USERNAME"
  shell_assignment ready_filename "$EC2_READY_FILENAME"
  shell_assignment region "$REGION"
  shell_assignment mount_max_attempts "$MOUNT_READY_MAX_ATTEMPTS"
  shell_assignment mount_retry_interval "$MOUNT_READY_RETRY_INTERVAL_SECONDS"
  cat <<'EEOF'
instance_id=""
token=$(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' || true)
[[ -n "$token" ]] && instance_id=$(curl -fsS -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/instance-id || true)
[[ -n "$instance_id" ]] || instance_id=$(curl -fsS http://169.254.169.254/latest/meta-data/instance-id || true)

echo "Setting s3 files..."
required_mounts=()
mount_entry() { local source=$1 target=$2 fstype=$3 options=$4; mkdir -p "$target"; grep -qF " $target " /etc/fstab || echo "$source $target $fstype $options 0 0" >> /etc/fstab; required_mounts+=("$target"); }
mount_required() {
  local target=$1 attempt
  for ((attempt=1; attempt<=mount_max_attempts; attempt++));do
    mountpoint -q "$target" && return 0
    if mount "$target" && mountpoint -q "$target";then return 0;fi
    ((attempt == mount_max_attempts)) || sleep "$mount_retry_interval"
  done
  echo "Failed to mount required file system at $target after $mount_max_attempts attempts." >&2
  return 1
}
EEOF
  for filesystem_provider in "${filesystem_providers[@]}"; do
    mount_script="$WORKDIR/ec2/mounts/$filesystem_provider.sh"
    if [[ -f "$mount_script" ]]; then
      # Custom providers can supply a generated user-data fragment here.
      source "$mount_script"
    elif [[ -f "$script_dir/mount_$filesystem_provider.sh" ]]; then
      # Built-in providers use the same provider hook contract.
      source "$script_dir/mount_$filesystem_provider.sh"
    fi
  done
  cat <<'EEOF'
for required_mount in "${required_mounts[@]}";do
  mount_required "$required_mount"
done

EEOF

  if ((${#systemd_services[@]} > 0)); then
    echo 'echo "Enabling systemd services..."'
    for systemd_service in "${systemd_services[@]}"; do
      printf 'systemctl enable --now %q 2>/dev/null || true\n' "$systemd_service"
    done
  fi

  ignored_fs_settings=()
  [[ "$USER_ENV_ENABLE_USR_SYMLINK" == 1 ]] && ignored_fs_settings+=(USER_ENV_ENABLE_USR_SYMLINK)
  [[ -n "$USER_ENV_INSTALLER_SCRIPTS" ]] && ignored_fs_settings+=(USER_ENV_INSTALLER_SCRIPTS)
  [[ -n "$USER_ENV_DOTFILES_FILE" ]] && ignored_fs_settings+=(USER_ENV_DOTFILES_FILE)
  [[ -n "$USER_ENV_DOTFILES_DIR" ]] && ignored_fs_settings+=(USER_ENV_DOTFILES_DIR)
  [[ -n "$USER_ENV_CONFIG_DOTFILES_FILE" ]] && ignored_fs_settings+=(USER_ENV_CONFIG_DOTFILES_FILE)
  [[ -n "$USER_ENV_CONFIG_DOTFILES_DIR" ]] && ignored_fs_settings+=(USER_ENV_CONFIG_DOTFILES_DIR)
  if [[ -z "$USER_ENV_ROOT_DIR" && ${#ignored_fs_settings[@]} -gt 0 ]];then
    printf 'Warning: USER_ENV_ROOT_DIR is empty; ignoring user environment settings: %s\n' "${ignored_fs_settings[*]}" >&2
  fi

  if [[ -n "$USER_ENV_ROOT_DIR" ]];then
    cat <<'EEOF'
echo "Setting fs dir..."

EEOF
    shell_assignment fs_dir "$USER_ENV_ROOT_DIR"
    if [[ "$USER_ENV_ENABLE_USR_SYMLINK" = 1 ]];then
      cat <<'EEOF'
sudo -u "$user" mkdir -p "$fs_dir/usr/bin"
sudo -u "$user" ln -s "$fs_dir/usr" "/home/$user/usr"
EEOF
    fi

    mapfile -t scripts < <(csv_items "$USER_ENV_INSTALLER_SCRIPTS")
    for f in "${scripts[@]}";do
      if [ -z "$f" ];then continue; fi
      if [ ! -f "$f" ];then
        echo "USER_ENV_INSTALLER_SCRIPT: $f not found" >&2
        exit 1
      fi
      fname=$(basename "$f")
      exe=${fname#install_}
      arg=${exe^^}_OPT
      shell_assignment installer_name "$fname"
      shell_assignment installer_exe "$exe"
      shell_assignment installer_option "${!arg}"
      shell_assignment installer_payload "$(base64_file "$f")"
      cat <<'EEOF'
printf 'Installing %s...\n' "$installer_name"
sudo -u "$user" mkdir -p "$fs_dir/opt/bin"
printf '%s' "$installer_payload" | base64 -d | sudo -u "$user" tee "$fs_dir/opt/bin/$installer_name" >/dev/null
chown "$user:$user" "$fs_dir/opt/bin/$installer_name"
chmod 755 "$fs_dir/opt/bin/$installer_name"
printf 'Installing %s...\n' "$installer_exe"
installer_args=()
[[ -n "$installer_option" ]] && installer_args+=("$installer_option")
sudo -u "$user" "$fs_dir/opt/bin/$installer_name" "$fs_dir/opt" "$fs_dir/usr" "${installer_args[@]}"

EEOF
    done
  fi

  if [[ -n "$USER_ENV_ROOT_DIR" && (
    -n "$USER_ENV_DOTFILES_FILE" ||
    -n "$USER_ENV_DOTFILES_DIR" ||
    -n "$USER_ENV_CONFIG_DOTFILES_FILE" ||
    -n "$USER_ENV_CONFIG_DOTFILES_DIR"
  ) ]];then
    cat <<'EEOF'
echo "Setting dotfiles..."

sudo -u "$user" mkdir -p "$fs_dir/dotfiles"

EEOF
    shell_assignment dotfiles_file_values "$(csv_items "$USER_ENV_DOTFILES_FILE")"
    shell_assignment dotfiles_dir_values "$(csv_items "$USER_ENV_DOTFILES_DIR")"
    shell_assignment dotfiles_config_file_values "$(csv_items "$USER_ENV_CONFIG_DOTFILES_FILE")"
    shell_assignment dotfiles_config_dir_values "$(csv_items "$USER_ENV_CONFIG_DOTFILES_DIR")"
    cat <<'EEOF'

mapfile -t files <<<"$dotfiles_file_values"
for f in "${files[@]}";do
  [[ -n "$f" ]] || continue
  sudo -u "$user" touch "$fs_dir/dotfiles/$f"
done
mapfile -t dirs <<<"$dotfiles_dir_values"
for d in "${dirs[@]}";do
  [[ -n "$d" ]] || continue
  sudo -u "$user" mkdir -p "$fs_dir/dotfiles/$d"
done
for f in "${files[@]}" "${dirs[@]}";do
  [[ -n "$f" ]] || continue
  if [ ! -L "/home/$user/$f" ];then
    sudo -u "$user" rm -rf "/home/$user/$f"
    sudo -u "$user" ln -s "$fs_dir/dotfiles/$f" "/home/$user/$f"
  fi
done

sudo -u "$user" mkdir -p "$fs_dir/dotfiles/.config"
sudo -u "$user" mkdir -p "/home/$user/.config"

mapfile -t config_files <<<"$dotfiles_config_file_values"
for f in "${config_files[@]}";do
  [[ -n "$f" ]] || continue
  sudo -u "$user" touch "$fs_dir/dotfiles/.config/$f"
done
mapfile -t config_dirs <<<"$dotfiles_config_dir_values"
for d in "${config_dirs[@]}";do
  [[ -n "$d" ]] || continue
  sudo -u "$user" mkdir -p "$fs_dir/dotfiles/.config/$d"
done
for f in "${config_files[@]}" "${config_dirs[@]}";do
  [[ -n "$f" ]] || continue
  if [ ! -L "/home/$user/.config/$f" ];then
    sudo -u "$user" rm -rf "/home/$user/.config/$f"
    sudo -u "$user" ln -s "$fs_dir/dotfiles/.config/$f" "/home/$user/.config/$f"
  fi
done

EEOF
  fi

  cat <<'EEOF'
echo "Setting ec2 command configuration..."
sudo -u "$user" mkdir -p "/home/$user/.config/ec2/cli_input_json"
EEOF
  ec2_config_payload=$({
    shell_assignment name_filter "$EC2_NAME_FILTER"
    shell_assignment image_name_filter "$EC2_IMAGE_NAME_FILTER"
    shell_assignment ssh_user "$EC2_SSH_USERNAME"
    shell_assignment connection_method "$EC2_CONNECTION_METHOD"
    shell_assignment mosh_server "$EC2_MOSH_SERVER_PATH"
    shell_assignment private_ip "$EC2_USE_PRIVATE_IP"
    shell_assignment instance_type "$EC2_DEFAULT_INSTANCE_TYPE"
    shell_assignment spot_instance "$EC2_USE_SPOT_INSTANCE"
    shell_assignment submit_command "$EC2_SUBMIT_COMMAND"
    shell_assignment submit_n_retry_launch "$EC2_SUBMIT_N_RETRY_LAUNCH"
    shell_assignment submit_n_retry_ssh "$EC2_SUBMIT_N_RETRY_SSH"
    shell_assignment submit_retry_launch_interval "$EC2_SUBMIT_RETRY_LAUNCH_INTERVAL"
    shell_assignment submit_retry_ssh_interval "$EC2_SUBMIT_RETRY_SSH_INTERVAL"
    shell_assignment user_data "fileb:///home/$EC2_SSH_USERNAME/.config/ec2/$user_data_name"
    shell_assignment cli_input_json_directory "/home/$EC2_SSH_USERNAME/.config/ec2/cli_input_json"
    shell_assignment cli_input_json_group "$EC2_CLI_INPUT_JSON_GROUP"
    shell_assignment cli_input_json_group_cpu "$cpu_group"
    shell_assignment cli_input_json_group_gpu "$gpu_group"
    shell_assignment submit_current_dir 1
    shell_assignment submit_measure_time 1
  })
  printf 'printf %%s %q | base64 -d | sudo -u "$user" tee "/home/$user/.config/ec2/config" >/dev/null\n' "$(base64_string "$ec2_config_payload")"

  for i in "${!jsons[@]}";do
    shell_assignment json_name "${jsons[i]}"
    printf 'printf %%s %q | base64 -d | sudo -u "$user" tee "/home/$user/.config/ec2/cli_input_json/$json_name" >/dev/null\n' "$(base64_string "${json_contents[i]}")"
  done

  shell_assignment user_data_name "$user_data_name"
  printf 'cp %q/$instance_id/user-data.txt "/home/$user/.config/ec2/$user_data_name"\n' "$EC2_CLOUD_INIT_INSTANCE_DIR"
  cat <<'EEOF'
chown -R "$user:$user" "/home/$user/.config/ec2/$user_data_name"

EEOF

  for copy_entry in "${copy_entries[@]}"; do
    IFS='|' read -r copy_source copy_destination copy_permission copy_extra <<<"$copy_entry"
    [[ -n "$copy_destination" ]] || copy_destination=$copy_source
    case "$copy_source" in
      '~') copy_source="$HOME" ;;
      '~/'*) copy_source="$HOME/${copy_source:2}" ;;
      '${HOME}') copy_source="$HOME" ;;
      '${HOME}/'*) copy_source="$HOME/${copy_source#'${HOME}/'}" ;;
    esac
    [[ -f "$copy_source" ]] || continue
    case "$copy_destination" in
      '~') printf 'copy_destination=/home/"$user"\n' ;;
      '~/'*) printf 'copy_destination=/home/"$user"/%q\n' "${copy_destination:2}" ;;
      /*) printf 'copy_destination=%q\n' "$copy_destination" ;;
      *) printf 'copy_destination=/home/"$user"/%q\n' "$copy_destination" ;;
    esac
    if [[ -z "$copy_permission" ]]; then
      copy_permission=$(stat -f '%Lp' "$copy_source" 2>/dev/null || stat -c '%a' "$copy_source")
    fi
    printf 'echo Copying %q to "$copy_destination"...\n' "$copy_source"
    printf 'sudo -u "$user" mkdir -p "$(dirname -- "$copy_destination")"\n'
    printf 'printf %%s %q | base64 -d | sudo -u "$user" tee "$copy_destination" >/dev/null\n' "$(base64_file "$copy_source")"
    printf 'sudo -u "$user" chmod %q "$copy_destination"\n' "${copy_permission:-600}"
  done

  if [[ -n "$INSTANCE_USER_DATA_EXTRA_SCRIPT" && -f "$INSTANCE_USER_DATA_EXTRA_SCRIPT" ]];then cat "$INSTANCE_USER_DATA_EXTRA_SCRIPT";fi
  cat <<'EEOF'

echo "=== End user script set by ec2 command ==="

cp /var/log/cloud-init-output.log "/home/$user/$ready_filename"
chown "$user:$user" "/home/$user/$ready_filename"

EEOF
} > "$user_data_sh"
chmod 700 "$user_data_sh"
case "$EC2_USER_DATA_FORMAT" in
auto) [[ "$EC2_USER_DATA_URI" == *gz ]] && EC2_USER_DATA_FORMAT=gzip || EC2_USER_DATA_FORMAT=plain ;;
plain|gzip) ;;
*) echo 'EC2_USER_DATA_FORMAT must be auto, plain, or gzip.' >&2; exit 1 ;;
esac
if [[ "$EC2_USER_DATA_FORMAT" == gzip ]];then
  gzip -c "$user_data_sh" > "$user_data_sh.gz"
  chmod 600 "$user_data_sh.gz"
  user_data_sent="$user_data_sh.gz"
else
  user_data_sent="$user_data_sh"
fi

# EC2 caps user-data at 16 KB of payload before API Base64 encoding. When gzip
# is selected this is the compressed payload; with plain it is the script.
# Reject the launch locally when the configured limit is exceeded.
user_data_size=$(wc -c < "$user_data_sent" | tr -d ' ')
if ((user_data_size > EC2_USER_DATA_MAX_BYTES));then
  echo "user-data payload is $user_data_size bytes, over the $EC2_USER_DATA_MAX_BYTES byte limit." >&2
  echo 'Shorten INSTANCE_USER_DATA_EXTRA_SCRIPT, or move the work into the AMI or USER_ENV_INSTALLER_SCRIPTS.' >&2
  exit 1
fi
if ((user_data_size > EC2_USER_DATA_MAX_BYTES * 80 / 100));then
  echo "Warning: user-data is $user_data_size of the $EC2_USER_DATA_MAX_BYTES bytes allowed." >&2
fi
echo "Generated $WORKDIR/ec2/config and $user_data_sh"
