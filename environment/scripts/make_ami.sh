#!/usr/bin/env bash
set -euo pipefail

if ! type packer >/dev/null 2>&1; then
  echo "Packer is not installed. Please install Packer to continue." >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$(dirname "$0")/bootstrap.sh" "${1:-}" "${2:-}" ami
AMI_BUILD_SUBNET_ID="${AMI_BUILD_SUBNET_ID-${SUBNET_ID-}}"
repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
repository_revision=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unknown)

rm -rf "$WORKDIR/packer"
mkdir -p "$WORKDIR/packer"
cp -R "$(dirname "$0")/../packer/." "$WORKDIR/packer/"
cd "$WORKDIR/packer"

make_main() {
  if [[ -n "$AMI_PACKER_TEMPLATE_FILE" ]]; then
    [[ -f "$AMI_PACKER_TEMPLATE_FILE" ]] || {
      echo "Packer template file not found: $AMI_PACKER_TEMPLATE_FILE" >&2
      return 1
    }
    cp "$AMI_PACKER_TEMPLATE_FILE" main.json
    return 0
  fi
  cat > "main.json" <<EOF
{
  "variables": {
  },
  "builders": [{
    "type": "amazon-ebs",
    "ami_name": "{{user \`ami_name\`}}",
    "source_ami": "{{user \`source_ami\`}}",
    "tags": {"Name": "{{user \`ami_name\`}}", "ManagedBy": "{{user \`resource_managed_by\`}}", "Project": "{{user \`resource_project\`}}", "Owner": "{{user \`resource_owner\`}}", "ExpiresAt": "{{user \`resource_expires_at\`}}"},
    "run_tags": {"Name": "{{user \`ami_name\`}}", "ManagedBy": "{{user \`resource_managed_by\`}}", "Project": "{{user \`resource_project\`}}", "Owner": "{{user \`resource_owner\`}}", "ExpiresAt": "{{user \`resource_expires_at\`}}"},
    "instance_type": "{{user \`instance_type\`}}",
    "profile": "{{user \`profile\`}}",
    "region": "{{user \`region\`}}",
    "ssh_interface": "{{user \`ssh_interface\`}}",
    "ssh_username": "{{user \`ssh_username\`}}",
    "vpc_id": "{{user \`vpc_id\`}}",
    "security_group_ids": "{{user \`security_group_ids\`}}",
    "subnet_id": "{{user \`subnet_id\`}}",
    "iam_instance_profile": "{{user \`iam_instance_profile\`}}",
    "launch_block_device_mappings": [{
      "delete_on_termination": "{{user \`delete_on_termination\`}}",
      "device_name": "{{user \`device_name\`}}",
      "volume_size": "{{user \`volume_size\`}}",
      "volume_type": "{{user \`volume_type\`}}",
      "encrypted": "{{user \`encrypted\`}}"
    }]
  }],
  "provisioners": [{
    "type": "shell",
    "execute_command": "echo 'packer' | {{.Vars}} sudo -S -E sh -eux '{{.Path}}'",
    "environment_vars": [
      "SSH_USERNAME={{user \`ssh_username\`}}",
      "AMI_SWAP_BLOCK_SIZE={{user \`swap_block_size\`}}",
      "AMI_SWAP_BLOCK_COUNT={{user \`swap_block_count\`}}",
      "AMI_PACKAGES={{user \`packages\`}}",
      "AMI_FLATPAK_PACKAGES={{user \`flatpak_packages\`}}",
      "AMI_UPDATE_PACKAGES={{user \`update_packages\`}}",
      "AMI_PACKAGE_MANAGER={{user \`package_manager\`}}",
      "AMI_EXTRA_PACKAGES={{user \`extra_packages\`}}",
      "AMI_TIMEZONE={{user \`timezone\`}}",
      "AMI_IDLE_SHUTDOWN_BACKEND={{user \`idle_shutdown_backend\`}}",
      "AMI_IDLE_SHUTDOWN_SCHEDULE={{user \`idle_shutdown_schedule\`}}",
      "AMI_IDLE_SHUTDOWN_KEEPALIVE_PROCESSES={{user \`idle_shutdown_keepalive_processes\`}}",
      "AMI_ENABLE_SHARED_MEMORY={{user \`enable_shared_memory\`}}"
    ],
    "scripts": "{{user \`scripts\`}}"
  }]
}
EOF
}

make_vars() {
  local family=$1 source_ami
  family_value() {
    local variable="${1}_${2}"
    local fallback=${2}
    if declare -p "$variable" >/dev/null 2>&1; then
      printf '%s' "${!variable}"
    else
      printf '%s' "${!fallback-}"
    fi
  }
  provision_scripts() {
    local provision_family=$1 script_list=() extra_script
    [[ "$(family_value "$provision_family" AMI_ENABLE_SWAP)" == 1 ]] && script_list+=(./scripts/setup_swap.sh)
    [[ "$(family_value "$provision_family" AMI_ENABLE_SHARED_MEMORY)" == 1 ]] && script_list+=(./scripts/setup_shared_memory.sh)
    [[ "$(family_value "$provision_family" AMI_ENABLE_PACKAGES)" == 1 ]] && script_list+=(./scripts/install_packages.sh)
    [[ "$(family_value "$provision_family" AMI_ENABLE_TIMEZONE)" == 1 ]] && script_list+=(./scripts/set_timezone.sh)
    [[ "$(family_value "$provision_family" AMI_ENABLE_IDLE_SHUTDOWN)" == 1 ]] && script_list+=(./scripts/setup_idle_shutdown.sh)
    IFS=, read -r -a extra_scripts <<<"$(family_value "$provision_family" AMI_PROVISION_SCRIPTS)"
    for extra_script in "${extra_scripts[@]}"; do
      [[ -n "$extra_script" ]] && script_list+=("$extra_script")
    done
    local IFS=,
    printf '%s' "${script_list[*]}"
  }
  source_ami=$(family_value "$family" SOURCE_AMI_ID)
  if [[ -z "$source_ami" ]];then
    source_ami=$(aws "${AWS_ARGS[@]}" ec2 describe-images \
      --owners "$(family_value "$family" SOURCE_AMI_OWNER)" \
      --filters "Name=name,Values=$(family_value "$family" SOURCE_AMI_NAME_FILTER)" 'Name=state,Values=available' \
      --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' --output text)
  fi
  [[ -n "$source_ami" && "$source_ami" != None ]] || {
    echo "No available source AMI matched the $family family configuration." >&2
    return 1
  }
  cat > "variables_${family,,}.json" <<EOF
{
  "ami_name": $(json_quote "$(family_value "$family" OUTPUT_AMI_NAME)"),
  "source_ami": $(json_quote "$source_ami"),
  "resource_managed_by": $(json_quote "$RESOURCE_MANAGED_BY"),
  "resource_project": $(json_quote "$RESOURCE_PROJECT"),
  "resource_owner": $(json_quote "$RESOURCE_OWNER"),
  "resource_expires_at": $(json_quote "$RESOURCE_EXPIRES_AT"),
  "ami_filter": $(json_quote "$(family_value "$family" SOURCE_AMI_NAME_FILTER)"),
  "ami_owner": $(json_quote "$(family_value "$family" SOURCE_AMI_OWNER)"),
  "instance_type": $(json_quote "$(family_value "$family" BUILD_INSTANCE_TYPE)"),
  "additional_packages": $(json_quote "$(family_value "$family" AMI_EXTRA_PACKAGES)"),
  "profile": $(json_quote "$(family_value "$family" AMI_BUILD_PROFILE)"),
  "region": $(json_quote "$(family_value "$family" AMI_BUILD_REGION)"),
  "ssh_interface": $(json_quote "$(family_value "$family" AMI_BUILD_SSH_INTERFACE)"),
  "ssh_username": $(json_quote "$(family_value "$family" AMI_BUILD_SSH_USERNAME)"),
  "security_group_ids": $(json_quote "$(family_value "$family" SECURITY_GROUP_IDS)"),
  "subnet_id": $(json_quote "$(family_value "$family" AMI_BUILD_SUBNET_ID)"),
  "vpc_id": $(json_quote "$(family_value "$family" AMI_BUILD_VPC_ID)"),
  "iam_instance_profile": $(json_quote "$(family_value "$family" AMI_BUILD_IAM_INSTANCE_PROFILE)"),
  "device_name": $(json_quote "$(family_value "$family" AMI_ROOT_DEVICE_NAME)"),
  "delete_on_termination": $(json_quote "$(family_value "$family" AMI_ROOT_VOLUME_DELETE_ON_TERMINATION)"),
  "volume_size": $(json_quote "$(family_value "$family" AMI_ROOT_VOLUME_SIZE_GIB)"),
  "volume_type": $(json_quote "$(family_value "$family" AMI_ROOT_VOLUME_TYPE)"),
  "encrypted": $(json_quote "$(family_value "$family" AMI_ROOT_VOLUME_ENCRYPTED)"),
  "scripts": $(json_quote "$(provision_scripts "$family")"),
  "swap_block_size": $(json_quote "$(family_value "$family" AMI_SWAP_BLOCK_SIZE)"),
  "swap_block_count": $(json_quote "$(family_value "$family" AMI_SWAP_BLOCK_COUNT)"),
  "packages": $(json_quote "$(family_value "$family" AMI_PACKAGES)"),
  "flatpak_packages": $(json_quote "$(family_value "$family" AMI_FLATPAK_PACKAGES)"),
  "update_packages": $(json_quote "$(family_value "$family" AMI_UPDATE_PACKAGES)"),
  "package_manager": $(json_quote "$(family_value "$family" AMI_PACKAGE_MANAGER)"),
  "timezone": $(json_quote "$(family_value "$family" AMI_TIMEZONE)"),
  "idle_shutdown_backend": $(json_quote "$(family_value "$family" AMI_IDLE_SHUTDOWN_BACKEND)"),
  "idle_shutdown_schedule": $(json_quote "$(family_value "$family" AMI_IDLE_SHUTDOWN_SCHEDULE)"),
  "idle_shutdown_keepalive_processes": $(json_quote "$(family_value "$family" AMI_IDLE_SHUTDOWN_KEEPALIVE_PROCESSES)"),
  "enable_shared_memory": $(json_quote "$(family_value "$family" AMI_ENABLE_SHARED_MEMORY)")
}
EOF
}

write_build_manifest() {
  local family=$1 variables_file=$2 source_ami
  source_ami=$(awk -F'"' '/"source_ami"/{print $4; exit}' "$variables_file")
  cat > "build-inputs-${family,,}.json" <<EOF
{
  "family": $(json_quote "$family"),
  "source_ami_id": $(json_quote "$source_ami"),
  "source_ami_filter": $(json_quote "$(family_value "$family" SOURCE_AMI_NAME_FILTER)"),
  "source_ami_owner": $(json_quote "$(family_value "$family" SOURCE_AMI_OWNER)"),
  "variables_sha256": $(json_quote "$(sha256_file "$variables_file")"),
  "packer_version": $(json_quote "$(packer version | head -n 1)"),
  "amazon_plugin_constraint": "= 1.3.4",
  "repository_revision": $(json_quote "$repository_revision")
}
EOF
}

export AWS_POLL_DELAY_SECONDS
export AWS_MAX_ATTEMPTS

terminal_state=''
family_pids=()
sso_pid=''
if [[ -t 0 && -r /dev/tty ]]; then
  terminal_state=$(stty -g </dev/tty 2>/dev/null || true)
fi
# shellcheck disable=SC2317  # Called indirectly by the EXIT trap.
restore_terminal() {
  if [[ -n "$terminal_state" ]]; then
    stty "$terminal_state" </dev/tty 2>/dev/null || true
  fi
}
# shellcheck disable=SC2317  # Called indirectly by the EXIT trap.
terminate_process_group() {
  local pid=$1
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
}

# shellcheck disable=SC2317  # Called indirectly by EXIT/INT/TERM/HUP traps.
cleanup_family_processes() {
  local status=$?
  trap - EXIT INT TERM HUP
  [[ -z "${monitor_pid:-}" ]] || kill "$monitor_pid" 2>/dev/null || true
  [[ -z "${packer_pid:-}" ]] || terminate_process_group "$packer_pid"
  [[ -z "${monitor_pid:-}" ]] || wait "$monitor_pid" 2>/dev/null || true
  [[ -z "${packer_pid:-}" ]] || wait "$packer_pid" 2>/dev/null || true
  return "$status"
}

# shellcheck disable=SC2317  # Called indirectly by the EXIT trap.
cleanup_all_builds() {
  local status=$?
  trap - EXIT INT TERM HUP
  [[ -z "${sso_pid:-}" ]] || kill "$sso_pid" 2>/dev/null || true
  for pid in "${family_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${family_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  restore_terminal
  exit "$status"
}

trap cleanup_all_builds EXIT
trap 'exit 130' INT TERM HUP

monitor_ami_progress() {
  local family=$1 build_output=$2 packer_pid=$3 ami_id='' snapshot_id='' state='' progress='' stage elapsed snapshot_status attempts=0
  local start_seconds=$SECONDS
  local -a snapshot_ids snapshot_statuses

  while kill -0 "$packer_pid" 2>/dev/null; do
    attempts=$((attempts + 1))
    if ((attempts > AMI_PROGRESS_MAX_ATTEMPTS)); then
      printf '%s: AMI progress timed out after %ss (%s attempts); Packer is still running.\n' \
        "$family" "$((attempts * AMI_PROGRESS_POLL_DELAY_SECONDS))" "$AMI_PROGRESS_MAX_ATTEMPTS" >&2
      return 124
    fi
    elapsed=$((SECONDS - start_seconds))
    stage=$(sed -n 's/^==> amazon-ebs: //p' "$build_output" | tail -n 1)
    stage=${stage:-Packer build in progress}
    ami_id=$(sed -n 's/.*AMI: \(ami-[[:alnum:]]*\).*/\1/p' "$build_output" | tail -n 1)
    if [[ -n "$ami_id" ]]; then
      mapfile -t snapshot_ids < <(aws "${AWS_ARGS[@]}" ec2 describe-images --image-ids "$ami_id" \
        --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text 2>/dev/null | \
        tr '\t' '\n' | awk 'NF && $0 != "None"')
      if ((${#snapshot_ids[@]} > 0)); then
        mapfile -t snapshot_statuses < <(aws "${AWS_ARGS[@]}" ec2 describe-snapshots \
          --snapshot-ids "${snapshot_ids[@]}" \
          --query 'Snapshots[].[SnapshotId,State,Progress]' --output text)
        for snapshot_status in "${snapshot_statuses[@]}"; do
          read -r snapshot_id state progress <<<"$snapshot_status"
          printf '%s: AMI %s snapshot=%s progress=%s state=%s elapsed=%ss\n' \
            "$family" "$ami_id" "$snapshot_id" "${progress:-unknown}" "${state:-unknown}" "$elapsed"
        done
      else
        printf '%s: AMI %s elapsed=%ss stage=%s\n' "$family" "$ami_id" "$elapsed" "$stage"
      fi
    else
      printf '%s: elapsed=%ss stage=%s\n' "$family" "$elapsed" "$stage"
    fi
    sleep "$AMI_PROGRESS_POLL_DELAY_SECONDS"
  done
}

aws_auth_watch() {
  local -a pids=("$@")
  local alive pid

  while :; do
    alive=0
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        alive=1
        break
      fi
    done
    ((alive)) || return 0

    if ! aws "${AWS_ARGS[@]}" sts get-caller-identity >/dev/null 2>&1; then
      if [[ -z "$AWS_AUTH_COMMAND" ]]; then
        printf 'AWS credentials are unavailable; no authentication refresh command is configured.\n' >&2
      elif ! run_aws_auth_command; then
        printf 'AWS authentication refresh failed; active Packer builds may fail authentication.\n' >&2
      fi
    fi
    sleep 60
  done
}

run_family() {
  local family=$1 variables_file="variables_${1,,}.json" build_output=".build-${1,,}.log" result_file=".build-${1,,}.result" packer_pid monitor_pid build_status ami_id ami_name build_instance_id

  : > "$build_output"
  : > "$result_file"
  if [[ "$AMI_VALIDATE_ONLY" == 1 ]]; then
    if packer validate -syntax-only main.json </dev/null >"$build_output" 2>&1; then
      printf '0\t\n' > "$result_file"
      cat "$build_output"
      return 0
    else
      build_status=$?
    fi
    printf '%s\t\n' "$build_status" > "$result_file"
    cat "$build_output" >&2
    return "$build_status"
  fi

  if packer validate -var-file="$variables_file" main.json </dev/null >"$build_output" 2>&1; then
    :
  else
    build_status=$?
    printf '%s\t\n' "$build_status" > "$result_file"
    cat "$build_output" >&2
    return "$build_status"
  fi

  trap cleanup_family_processes EXIT INT TERM HUP
  set -m
  packer build -on-error="$AMI_PACKER_ON_ERROR" -var-file="$variables_file" main.json \
    </dev/null >>"$build_output" 2>&1 &
  packer_pid=$!
  set +m
  monitor_ami_progress "$family" "$build_output" "$packer_pid" &
  monitor_pid=$!

  if wait "$packer_pid"; then
    build_status=0
  else
    build_status=$?
  fi
  kill "$monitor_pid" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true
  sed "s/^/$family: /" "$build_output"

  ami_id=$(grep -Eo 'AMI: ami-[[:alnum:]]+' "$build_output" | grep -Eo 'ami-[[:alnum:]]+' | tail -n 1 || true)
  ami_name=$(family_value "$family" OUTPUT_AMI_NAME)
  if [[ -z "$ami_id" && -z "$(family_value "$family" SOURCE_AMI_ID)" ]]; then
    ami_id=$(aws "${AWS_ARGS[@]}" ec2 describe-images --owners self \
      --filters "Name=name,Values=$ami_name" \
      --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' --output text 2>/dev/null || true)
  fi
  build_instance_id=$(grep -Eo 'instance i-[[:alnum:]]+' "$build_output" | grep -Eo 'i-[[:alnum:]]+' | tail -n 1 || true)
  printf '%s\t%s\t%s\n' "$build_status" "$ami_id" "$build_instance_id" > "$result_file"
  return "$build_status"
}

make_main
packer init .

enabled_families=()
reused_families=()
declare -A existing_ami_ids=()
# shellcheck disable=SC2153  # The uppercase setting is loaded from the environment config.
IFS=, read -r -a ami_families <<<"$AMI_FAMILIES"
for family in "${ami_families[@]}"; do
  instance_var=${family}_ENABLED
  if [[ "${!instance_var:-0}" == 1 ]]; then
    make_vars "$family"
    [[ -f "variables_${family,,}.json" ]] || { echo "Packer variables not generated: $PWD/variables_${family,,}.json" >&2; exit 1; }
    write_build_manifest "$family" "variables_${family,,}.json"
    if [[ "$AMI_EXISTING_IMAGE_ACTION" != build ]]; then
      existing_ami_ids[$family]=$(aws "${AWS_ARGS[@]}" ec2 describe-images --owners self \
        --filters "Name=name,Values=$(family_value "$family" OUTPUT_AMI_NAME)" \
        --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' --output text 2>/dev/null || true)
      [[ "${existing_ami_ids[$family]}" == None ]] && existing_ami_ids[$family]=''
    fi
    enabled_families+=("$family")
  fi
done
unset ami_families

if [[ "$AMI_EXISTING_IMAGE_ACTION" == fail ]]; then
  for family in "${enabled_families[@]}"; do
    if [[ -n "${existing_ami_ids[$family]-}" ]]; then
      echo "An AMI named '$(family_value "$family" OUTPUT_AMI_NAME)' already exists: ${existing_ami_ids[$family]}" >&2
      echo 'Set AMI_EXISTING_IMAGE_ACTION=reuse to use it, or build to retain the current behavior.' >&2
      exit 1
    fi
  done
fi

if [[ "$AMI_EXISTING_IMAGE_ACTION" == reuse ]]; then
  build_families=()
  for family in "${enabled_families[@]}"; do
    if [[ -n "${existing_ami_ids[$family]-}" ]]; then
      printf '0\t%s\t\n' "${existing_ami_ids[$family]}" > ".build-${family,,}.result"
      reused_families+=("$family")
      echo "$family: reusing existing AMI ${existing_ami_ids[$family]}"
    else
      build_families+=("$family")
    fi
  done
  enabled_families=("${build_families[@]}")
  unset build_families
fi

if ((${#enabled_families[@]} == 0 && ${#reused_families[@]} == 0)); then
  exit 0
fi

for family in "${enabled_families[@]}"; do
  run_family "$family" &
  family_pids+=("$!")
done
if ((${#family_pids[@]} > 0)); then
  aws_auth_watch "${family_pids[@]}" &
  sso_pid=$!
fi

build_status=0
for pid in "${family_pids[@]}"; do
  if ! wait "$pid"; then
    build_status=1
  fi
done
if [[ -n "$sso_pid" ]]; then
  kill "$sso_pid" 2>/dev/null || true
  wait "$sso_pid" 2>/dev/null || true
fi

families_to_record=("${enabled_families[@]}" "${reused_families[@]}")
for family in "${families_to_record[@]}"; do
  result_file=".build-${family,,}.result"
  IFS=$'\t' read -r family_status ami_id build_instance_id < "$result_file"
  ami_name=$(family_value "$family" OUTPUT_AMI_NAME)
  if [[ -n "$ami_id" && ( "$family_status" == 0 || "$AMI_VALIDATE_ONLY" != 1 ) ]]; then
    record_resource ami "$ami_id" "$ami_name"
    if [[ "$family_status" != 0 ]]; then
      echo "Recorded failed-build AMI $ami_id in $RESOURCE_MANIFEST for cleanup." >&2
    fi
  elif [[ "$family_status" == 0 && "$AMI_VALIDATE_ONLY" != 1 ]]; then
    echo "Could not determine the built AMI ID for '$ami_name'; skipping manifest recording." >&2
  fi
  if [[ "$family_status" != 0 && -n "$build_instance_id" ]]; then
    record_resource instance "$build_instance_id" "$ami_name"
    echo "Recorded failed-build instance $build_instance_id in $RESOURCE_MANIFEST for cleanup." >&2
  fi
done
exit "$build_status"
