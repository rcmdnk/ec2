#!/usr/bin/env bash
set -euo pipefail

if ! type packer >/dev/null 2>&1; then
  echo "Packer is not installed. Please install Packer to continue." >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$(dirname "$0")/bootstrap.sh" "${1:-}" "${2:-}"
repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
repository_revision=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unknown)

rm -rf "$WORKDIR/packer"
mkdir -p "$WORKDIR/packer"
cp -R "$(dirname "$0")/../packer/." "$WORKDIR/packer/"
cd "$WORKDIR/packer"

make_main() {
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
      "SWAP_BS={{user \`swap_bs\`}}",
      "SWAP_COUNT={{user \`swap_count\`}}",
      "PACKAGES={{user \`packages\`}}",
      "FLATPAK_PACKAGES={{user \`flatpak_packages\`}}",
      "UPDATE_PACKAGES={{user \`update_packages\`}}",
      "ADDITIONAL_PACKAGES={{user \`additional_packages\`}}",
      "TIME_ZONE={{user \`time_zone\`}}",
      "SHUTDOWN={{user \`shutdown\`}}",
      "SHUTDOWN_DURATION={{user \`shutdown_duration\`}}",
      "SHUTDOWN_CHECK_PROCESS={{user \`shutdown_check_process\`}}",
      "MULTI_PROCESSING={{user \`multi_processing\`}}"
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
      printf '%s' "${!fallback}"
    fi
  }
  source_ami=$(family_value "$family" SOURCE_AMI_ID)
  if [[ -z "$source_ami" ]];then
    source_ami=$(aws "${AWS_ARGS[@]}" ec2 describe-images \
      --owners "$(family_value "$family" AMI_OWNER)" \
      --filters "Name=name,Values=$(family_value "$family" AMI_FILTER)" 'Name=state,Values=available' \
      --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' --output text)
  fi
  [[ -n "$source_ami" && "$source_ami" != None ]] || {
    echo "No available source AMI matched the $family family configuration." >&2
    return 1
  }
  cat > "variables_${family,,}.json" <<EOF
{
  "ami_name": $(json_quote "$(family_value "$family" AMI_NAME)"),
  "source_ami": $(json_quote "$source_ami"),
  "resource_managed_by": $(json_quote "$RESOURCE_MANAGED_BY"),
  "resource_project": $(json_quote "$RESOURCE_PROJECT"),
  "resource_owner": $(json_quote "$RESOURCE_OWNER"),
  "resource_expires_at": $(json_quote "$RESOURCE_EXPIRES_AT"),
  "ami_filter": $(json_quote "$(family_value "$family" AMI_FILTER)"),
  "ami_owner": $(json_quote "$(family_value "$family" AMI_OWNER)"),
  "instance_type": $(json_quote "$(family_value "$family" INSTANCE_TYPE)"),
  "additional_packages": $(json_quote "$(family_value "$family" ADDITIONAL_PACKAGES)"),
  "profile": $(json_quote "$(family_value "$family" PROFILE)"),
  "region": $(json_quote "$(family_value "$family" REGION)"),
  "ssh_interface": $(json_quote "$(family_value "$family" SSH_INTERFACE)"),
  "ssh_username": $(json_quote "$(family_value "$family" SSH_USERNAME)"),
  "security_group_ids": $(json_quote "$(family_value "$family" SECURITY_GROUP_IDS)"),
  "subnet_id": $(json_quote "$(family_value "$family" SUBNET_ID)"),
  "vpc_id": $(json_quote "$(family_value "$family" VPC_ID)"),
  "iam_instance_profile": $(json_quote "$(family_value "$family" IAM_INSTANCE_PROFILE)"),
  "device_name": $(json_quote "$(family_value "$family" DEVICE_NAME)"),
  "delete_on_termination": $(json_quote "$(family_value "$family" DELETE_ON_TERMINATION)"),
  "volume_size": $(json_quote "$(family_value "$family" VOLUME_SIZE)"),
  "volume_type": $(json_quote "$(family_value "$family" VOLUME_TYPE)"),
  "encrypted": $(json_quote "$(family_value "$family" ENCRYPTED)"),
  "scripts": $(json_quote "$(family_value "$family" SCRIPTS)"),
  "swap_bs": $(json_quote "$(family_value "$family" SWAP_BS)"),
  "swap_count": $(json_quote "$(family_value "$family" SWAP_COUNT)"),
  "packages": $(json_quote "$(family_value "$family" PACKAGES)"),
  "flatpak_packages": $(json_quote "$(family_value "$family" FLATPAK_PACKAGES)"),
  "update_packages": $(json_quote "$(family_value "$family" UPDATE_PACKAGES)"),
  "time_zone": $(json_quote "$(family_value "$family" TIME_ZONE)"),
  "shutdown": $(json_quote "$(family_value "$family" SHUTDOWN)"),
  "shutdown_duration": $(json_quote "$(family_value "$family" SHUTDOWN_DURATION)"),
  "shutdown_check_process": $(json_quote "$(family_value "$family" SHUTDOWN_CHECK_PROCESS)"),
  "multi_processing": $(json_quote "$(family_value "$family" MULTI_PROCESSING)")
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
  "source_ami_filter": $(json_quote "$(family_value "$family" AMI_FILTER)"),
  "source_ami_owner": $(json_quote "$(family_value "$family" AMI_OWNER)"),
  "variables_sha256": $(json_quote "$(sha256_file "$variables_file")"),
  "packer_version": $(json_quote "$(packer version | head -n 1)"),
  "amazon_plugin_constraint": "= 1.3.4",
  "repository_revision": $(json_quote "$repository_revision")
}
EOF
}

export AWS_POLL_DELAY_SECONDS
export AWS_MAX_ATTEMPTS

monitor_ami_progress() {
  local family=$1 build_output=$2 packer_pid=$3 ami_id='' snapshot_id='' state='' progress=''

  while kill -0 "$packer_pid" 2>/dev/null; do
    ami_id=$(sed -n 's/.*AMI: \(ami-[[:alnum:]]*\).*/\1/p' "$build_output" | tail -n 1)
    if [[ -n "$ami_id" ]]; then
      snapshot_id=$(aws "${AWS_ARGS[@]}" ec2 describe-images --image-ids "$ami_id" \
        --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text 2>/dev/null || true)
      if [[ -n "$snapshot_id" && "$snapshot_id" != None ]]; then
        state=$(aws "${AWS_ARGS[@]}" ec2 describe-snapshots --snapshot-ids "$snapshot_id" \
          --query 'Snapshots[0].State' --output text 2>/dev/null || true)
        progress=$(aws "${AWS_ARGS[@]}" ec2 describe-snapshots --snapshot-ids "$snapshot_id" \
          --query 'Snapshots[0].Progress' --output text 2>/dev/null || true)
        printf '%s: AMI %s snapshot %s (%s)\n' "$family" "$ami_id" "${progress:-unknown}" "${state:-unknown}"
      fi
    else
      printf '%s: Packer build in progress...\n' "$family"
    fi
    sleep 15
  done
}

sso_watch() {
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
      printf 'AWS SSO session is unavailable; attempting login for active Packer builds...\n' >&2
      if ! aws sso login --profile "$PROFILE"; then
        printf 'AWS SSO login failed; active Packer builds may fail authentication.\n' >&2
      fi
    fi
    sleep 60
  done
}

run_family() {
  local family=$1 variables_file="variables_${1,,}.json" build_output=".build-${1,,}.log" result_file=".build-${1,,}.result" packer_pid monitor_pid build_status ami_id ami_name

  : > "$build_output"
  : > "$result_file"
  if [[ "$PACKER_VALIDATE_ONLY" == 1 ]]; then
    if packer validate -syntax-only main.json >"$build_output" 2>&1; then
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

  if packer validate -var-file="$variables_file" main.json >"$build_output" 2>&1; then
    :
  else
    build_status=$?
    printf '%s\t\n' "$build_status" > "$result_file"
    cat "$build_output" >&2
    return "$build_status"
  fi

  packer build -var-file="$variables_file" main.json >>"$build_output" 2>&1 &
  packer_pid=$!
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
  ami_name=$(family_value "$family" AMI_NAME)
  if [[ -z "$ami_id" && -z "$(family_value "$family" SOURCE_AMI_ID)" ]]; then
    ami_id=$(aws "${AWS_ARGS[@]}" ec2 describe-images --owners self \
      --filters "Name=name,Values=$ami_name" \
      --query 'Images | sort_by(@,&CreationDate)[-1].ImageId' --output text 2>/dev/null || true)
  fi
  printf '%s\t%s\n' "$build_status" "$ami_id" > "$result_file"
  return "$build_status"
}

make_main
packer init .

enabled_families=()
for family in CPU GPU; do
  instance_var=${family}_INSTANCE
  if [[ "${!instance_var:-0}" == 1 ]]; then
    make_vars "$family"
    [[ -f "variables_${family,,}.json" ]] || { echo "Packer variables not generated: $PWD/variables_${family,,}.json" >&2; exit 1; }
    write_build_manifest "$family" "variables_${family,,}.json"
    enabled_families+=("$family")
  fi
done

if ((${#enabled_families[@]} == 0)); then
  exit 0
fi

declare -a family_pids=()
for family in "${enabled_families[@]}"; do
  run_family "$family" &
  family_pids+=("$!")
done
sso_watch "${family_pids[@]}" &
sso_pid=$!

build_status=0
for pid in "${family_pids[@]}"; do
  if ! wait "$pid"; then
    build_status=1
  fi
done
kill "$sso_pid" 2>/dev/null || true
wait "$sso_pid" 2>/dev/null || true

for family in "${enabled_families[@]}"; do
  result_file=".build-${family,,}.result"
  IFS=$'\t' read -r family_status ami_id < "$result_file"
  ami_name=$(family_value "$family" AMI_NAME)
  if [[ "$family_status" == 0 && -n "$ami_id" ]]; then
    record_resource ami "$ami_id" "$ami_name"
  elif [[ "$family_status" == 0 && "$PACKER_VALIDATE_ONLY" != 1 ]]; then
    echo "Could not determine the built AMI ID for '$ami_name'; skipping manifest recording." >&2
  fi
done
exit "$build_status"
