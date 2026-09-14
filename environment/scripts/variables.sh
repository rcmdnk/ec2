#!/usr/bin/env bash
# shellcheck disable=SC2034  # Values are consumed by the other environment scripts.
set -euo pipefail

# Settings with no sensible default. environment.example ships them uncommented and
# empty, so that a fresh copy names all of them at once instead of failing on
# whichever one happens to be read first.
#   REQUIRED_SETTINGS      needed by every entry point
#   REQUIRED_SETTINGS_EC2  needed on top of those by scripts/setup_ec2.sh, which
#                          writes the launch JSON and the `ec2` configuration.
#                          Building an AMI or a file system does not need them.
REQUIRED_SETTINGS=(AWS_REGION)
REQUIRED_SETTINGS_EC2=(EC2_KEY_NAME)
required_settings=("${REQUIRED_SETTINGS[@]}")
[[ "${REQUIRE_EC2_SETTINGS:-0}" == 1 ]] && required_settings+=("${REQUIRED_SETTINGS_EC2[@]}")
missing=()
for required in "${required_settings[@]}"; do
  [[ -n "${!required-}" ]] && continue
  # A required <X>_IDS can instead be given as <X>_NAMES, which bootstrap.sh
  # resolves once the credentials are known to work.
  alternative=''
  [[ "$required" == *_IDS ]] && alternative="${required%_IDS}_NAMES"
  [[ -n "$alternative" && -n "${!alternative-}" ]] && continue
  missing+=("${required}${alternative:+ (or $alternative)}")
done
if ((${#missing[@]} > 0)); then
  printf 'Required setting(s) not set in %s:\n' "${CONFIG:-config}" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo 'See environment.example for what each one means.' >&2
  exit 1
fi
unset missing required required_settings alternative

validate_choice() {
  local name=$1 value=$2 allowed
  shift 2
  for allowed in "$@"; do
    [[ "$value" == "$allowed" ]] && return 0
  done
  echo "$name must be one of: $* (got '$value')." >&2
  exit 1
}

validate_bool() {
  local name=$1 value=$2
  [[ "$value" == 0 || "$value" == 1 || "$value" == true || "$value" == false ]] && return 0
  echo "$name must be 0, 1, true, or false (got '$value')." >&2
  exit 1
}

validate_positive_integer() {
  local name=$1 value=$2
  [[ "$value" =~ ^[1-9][0-9]*$ ]] && return 0
  echo "$name must be a positive integer (got '$value')." >&2
  exit 1
}

AWS_PROFILE="${AWS_PROFILE-default}"
AWS_REGION="${AWS_REGION-}"
AWS_AUTH_COMMAND="${AWS_AUTH_COMMAND-}"
AWS_VPC_ID="${AWS_VPC_ID-}"
AWS_VPC_NAME="${AWS_VPC_NAME-}"
AWS_SUBNET_IDS="${AWS_SUBNET_IDS-}"
AWS_SUBNET_NAMES="${AWS_SUBNET_NAMES-}"
AWS_SECURITY_GROUP_IDS="${AWS_SECURITY_GROUP_IDS-}"
AWS_SECURITY_GROUP_NAMES="${AWS_SECURITY_GROUP_NAMES-}"
AWS_IAM_INSTANCE_PROFILE="${AWS_IAM_INSTANCE_PROFILE-}"
EC2_DEFAULT_USERNAME="${EC2_DEFAULT_USERNAME-ec2-user}"
EC2_CONNECTION_METHOD="${EC2_CONNECTION_METHOD-ssh}"
validate_choice EC2_CONNECTION_METHOD "$EC2_CONNECTION_METHOD" ssh ssm ec2_instance_connect

# Operation-specific settings override the common AWS settings. The normalized
# names below are internal implementation details; config files should use the
# AWS_*, AMI_BUILD_* and EC2_* names.
AMI_BUILD_PROFILE="${AMI_BUILD_PROFILE-${AWS_PROFILE}}"
AMI_BUILD_REGION="${AMI_BUILD_REGION-${AWS_REGION}}"
AMI_BUILD_VPC_ID="${AMI_BUILD_VPC_ID-${AWS_VPC_ID-}}"
AMI_BUILD_VPC_NAME="${AMI_BUILD_VPC_NAME-${AWS_VPC_NAME-}}"
AMI_BUILD_SUBNET_IDS="${AMI_BUILD_SUBNET_IDS-${AWS_SUBNET_IDS-}}"
AMI_BUILD_SUBNET_NAMES="${AMI_BUILD_SUBNET_NAMES-${AWS_SUBNET_NAMES-}}"
AMI_BUILD_SECURITY_GROUP_IDS="${AMI_BUILD_SECURITY_GROUP_IDS-${AWS_SECURITY_GROUP_IDS-}}"
AMI_BUILD_SECURITY_GROUP_NAMES="${AMI_BUILD_SECURITY_GROUP_NAMES-${AWS_SECURITY_GROUP_NAMES-}}"
AMI_BUILD_IAM_INSTANCE_PROFILE="${AMI_BUILD_IAM_INSTANCE_PROFILE-${AWS_IAM_INSTANCE_PROFILE-}}"
EC2_PROFILE="${EC2_PROFILE-${AWS_PROFILE}}"
EC2_REGION="${EC2_REGION-${AWS_REGION}}"
EC2_VPC_ID="${EC2_VPC_ID-${AWS_VPC_ID-}}"
EC2_VPC_NAME="${EC2_VPC_NAME-${AWS_VPC_NAME-}}"
EC2_SUBNET_IDS="${EC2_SUBNET_IDS-${AWS_SUBNET_IDS-}}"
EC2_SUBNET_NAMES="${EC2_SUBNET_NAMES-${AWS_SUBNET_NAMES-}}"
EC2_SECURITY_GROUP_IDS="${EC2_SECURITY_GROUP_IDS-${AWS_SECURITY_GROUP_IDS-}}"
EC2_SECURITY_GROUP_NAMES="${EC2_SECURITY_GROUP_NAMES-${AWS_SECURITY_GROUP_NAMES-}}"
EC2_IAM_INSTANCE_PROFILE="${EC2_IAM_INSTANCE_PROFILE-${AWS_IAM_INSTANCE_PROFILE-}}"

if [[ "${REQUIRE_EC2_SETTINGS:-0}" == 1 && -z "${EC2_SUBNET_IDS}${EC2_SUBNET_NAMES}" ]]; then
  echo "EC2_SUBNET_IDS or EC2_SUBNET_NAMES must be set in ${CONFIG:-config}." >&2
  exit 1
fi

if [[ "${ENVIRONMENT_OPERATION:-common}" == ami ]]; then
  PROFILE="$AMI_BUILD_PROFILE"; REGION="$AMI_BUILD_REGION"
  VPC_ID="$AMI_BUILD_VPC_ID"; VPC_NAME="$AMI_BUILD_VPC_NAME"
  SUBNET_IDS="$AMI_BUILD_SUBNET_IDS"; SUBNET_NAMES="$AMI_BUILD_SUBNET_NAMES"
  SECURITY_GROUP_IDS="$AMI_BUILD_SECURITY_GROUP_IDS"
  SECURITY_GROUP_NAMES="$AMI_BUILD_SECURITY_GROUP_NAMES"
  IAM_INSTANCE_PROFILE="$AMI_BUILD_IAM_INSTANCE_PROFILE"
else
  PROFILE="$EC2_PROFILE"; REGION="$EC2_REGION"
  VPC_ID="$EC2_VPC_ID"; VPC_NAME="$EC2_VPC_NAME"
  SUBNET_IDS="$EC2_SUBNET_IDS"; SUBNET_NAMES="$EC2_SUBNET_NAMES"
  SECURITY_GROUP_IDS="$EC2_SECURITY_GROUP_IDS"
  SECURITY_GROUP_NAMES="$EC2_SECURITY_GROUP_NAMES"
  IAM_INSTANCE_PROFILE="$EC2_IAM_INSTANCE_PROFILE"
fi
PROFILE="${PROFILE-}"
REGION="${REGION-}"
AWS_ARGS=(--profile "$PROFILE" --region "$REGION")
export AWS_PROFILE AWS_REGION
EC2_USER="$EC2_DEFAULT_USERNAME"

AWS_POLL_DELAY_SECONDS=${AWS_POLL_DELAY_SECONDS-10}
AWS_MAX_ATTEMPTS=${AWS_MAX_ATTEMPTS-400}
MOUNT_READY_MAX_ATTEMPTS=${MOUNT_READY_MAX_ATTEMPTS-60}
MOUNT_READY_RETRY_INTERVAL_SECONDS=${MOUNT_READY_RETRY_INTERVAL_SECONDS-2}
AMI_VALIDATE_ONLY=${AMI_VALIDATE_ONLY-0}
AMI_PROGRESS_POLL_DELAY_SECONDS=${AMI_PROGRESS_POLL_DELAY_SECONDS-15}
AMI_PROGRESS_MAX_ATTEMPTS=${AMI_PROGRESS_MAX_ATTEMPTS-400}
validate_positive_integer AWS_POLL_DELAY_SECONDS "$AWS_POLL_DELAY_SECONDS"
validate_positive_integer AWS_MAX_ATTEMPTS "$AWS_MAX_ATTEMPTS"
validate_positive_integer MOUNT_READY_MAX_ATTEMPTS "$MOUNT_READY_MAX_ATTEMPTS"
validate_positive_integer MOUNT_READY_RETRY_INTERVAL_SECONDS "$MOUNT_READY_RETRY_INTERVAL_SECONDS"
validate_positive_integer AMI_PROGRESS_POLL_DELAY_SECONDS "$AMI_PROGRESS_POLL_DELAY_SECONDS"
validate_positive_integer AMI_PROGRESS_MAX_ATTEMPTS "$AMI_PROGRESS_MAX_ATTEMPTS"
validate_bool AMI_VALIDATE_ONLY "$AMI_VALIDATE_ONLY"
AMI_PACKER_ON_ERROR=${AMI_PACKER_ON_ERROR-cleanup}
AMI_PACKER_TEMPLATE_FILE=${AMI_PACKER_TEMPLATE_FILE-}
validate_choice AMI_PACKER_ON_ERROR "$AMI_PACKER_ON_ERROR" cleanup abort ask
AMI_EXISTING_IMAGE_ACTION=${AMI_EXISTING_IMAGE_ACTION-build}
validate_choice AMI_EXISTING_IMAGE_ACTION "$AMI_EXISTING_IMAGE_ACTION" build reuse fail

AMI_BUILD_SSH_INTERFACE=${AMI_BUILD_SSH_INTERFACE-private_ip}
AMI_BUILD_SSH_USERNAME=${AMI_BUILD_SSH_USERNAME-${EC2_USER}}
validate_choice AMI_BUILD_SSH_INTERFACE "$AMI_BUILD_SSH_INTERFACE" private_ip public_ip private_dns public_dns session_manager
# Optional: Packer builds a temporary security group when this is empty, and the
# generated launch JSON leaves "Groups" out so EC2 applies the VPC default.
SECURITY_GROUP_IDS=${SECURITY_GROUP_IDS-}
SECURITY_GROUP_NAMES=${SECURITY_GROUP_NAMES-}
# Optional for make_ami, which lets Packer pick a subnet. Required by setup_ec2
# through REQUIRED_SETTINGS_EC2, and by the file system scripts when they create
# something.
SUBNET_IDS=${SUBNET_IDS-}
SUBNET_NAMES=${SUBNET_NAMES-}
EC2_SUBNET_LABELS=${EC2_SUBNET_LABELS-}
VPC_ID=${VPC_ID-}
VPC_NAME=${VPC_NAME-}
# Optional: Packer resolves the VPC from SUBNET_ID when this is empty, and only
# ever needs it to build a temporary security group, which SECURITY_GROUP_IDS
# already makes unnecessary.
IAM_INSTANCE_PROFILE=${IAM_INSTANCE_PROFILE-}
AMI_ROOT_DEVICE_NAME=${AMI_ROOT_DEVICE_NAME-/dev/xvda}
AMI_ROOT_VOLUME_DELETE_ON_TERMINATION=${AMI_ROOT_VOLUME_DELETE_ON_TERMINATION-true}
AMI_ROOT_VOLUME_SIZE_GIB=${AMI_ROOT_VOLUME_SIZE_GIB-60}
AMI_ROOT_VOLUME_TYPE=${AMI_ROOT_VOLUME_TYPE-gp3}
AMI_ROOT_VOLUME_ENCRYPTED=${AMI_ROOT_VOLUME_ENCRYPTED-true}
AMI_PROVISION_SCRIPTS=${AMI_PROVISION_SCRIPTS-./scripts/setup_swap.sh,./scripts/setup_shared_memory.sh,./scripts/install_packages.sh,./scripts/set_timezone.sh,./scripts/setup_idle_shutdown.sh}
AMI_SWAP_BLOCK_SIZE=${AMI_SWAP_BLOCK_SIZE-128M}
AMI_SWAP_BLOCK_COUNT=${AMI_SWAP_BLOCK_COUNT-64}
AMI_TIMEZONE=${AMI_TIMEZONE-UTC}
AMI_IDLE_SHUTDOWN_BACKEND=${AMI_IDLE_SHUTDOWN_BACKEND-systemd}
AMI_IDLE_SHUTDOWN_SCHEDULE=${AMI_IDLE_SHUTDOWN_SCHEDULE-hourly}
AMI_IDLE_SHUTDOWN_KEEPALIVE_PROCESSES=${AMI_IDLE_SHUTDOWN_KEEPALIVE_PROCESSES-sshd|screen|tmux|mosh-server}
AMI_PACKAGES=${AMI_PACKAGES-}
AMI_FLATPAK_PACKAGES=${AMI_FLATPAK_PACKAGES-}
AMI_UPDATE_PACKAGES=${AMI_UPDATE_PACKAGES-1}
AMI_PACKAGE_MANAGER=${AMI_PACKAGE_MANAGER-auto}
AMI_ENABLE_SHARED_MEMORY=${AMI_ENABLE_SHARED_MEMORY-1}
validate_choice AMI_PACKAGE_MANAGER "$AMI_PACKAGE_MANAGER" auto dnf yum apt
validate_bool AMI_UPDATE_PACKAGES "$AMI_UPDATE_PACKAGES"
validate_bool AMI_ENABLE_SHARED_MEMORY "$AMI_ENABLE_SHARED_MEMORY"

# CPU instance configuration.
AMI_FAMILIES=${AMI_FAMILIES-CPU,GPU}
CPU_ENABLED=${CPU_ENABLED-1}
CPU_OUTPUT_AMI_NAME=${CPU_OUTPUT_AMI_NAME-}
CPU_SOURCE_AMI_NAME_FILTER=${CPU_SOURCE_AMI_NAME_FILTER-al2023-ami-*-x86_64} # Amazon Linux 2023
CPU_SOURCE_AMI_OWNER=${CPU_SOURCE_AMI_OWNER-amazon}
CPU_SOURCE_AMI_ID=${CPU_SOURCE_AMI_ID-}
CPU_BUILD_INSTANCE_TYPE=${CPU_BUILD_INSTANCE_TYPE-c8i.2xlarge}
CPU_AMI_EXTRA_PACKAGES=${CPU_AMI_EXTRA_PACKAGES-}

# GPU instance configuration.
GPU_ENABLED=${GPU_ENABLED-0}
GPU_OUTPUT_AMI_NAME=${GPU_OUTPUT_AMI_NAME-}
GPU_SOURCE_AMI_NAME_FILTER="${GPU_SOURCE_AMI_NAME_FILTER-Deep Learning OSS Nvidia Driver AMI GPU PyTorch * (Amazon Linux 2023)*}" # suffix contains release date
GPU_SOURCE_AMI_OWNER=${GPU_SOURCE_AMI_OWNER-amazon}
GPU_SOURCE_AMI_ID=${GPU_SOURCE_AMI_ID-}
GPU_BUILD_INSTANCE_TYPE=${GPU_BUILD_INSTANCE_TYPE-"g4dn.xlarge"}
GPU_AMI_EXTRA_PACKAGES=${GPU_AMI_EXTRA_PACKAGES-}

# An enabled family needs a name: Packer builds under it and setup_ec2 looks the
# image up by it.
[[ -n "$AMI_FAMILIES" ]] || { echo 'AMI_FAMILIES must not be empty.' >&2; exit 1; }
declare -A seen_ami_families=()
# shellcheck disable=SC2153  # The uppercase setting is loaded from the environment config.
IFS=, read -r -a ami_families <<<"$AMI_FAMILIES"
for family in "${ami_families[@]}"; do
  [[ "$family" =~ ^[A-Z][A-Z0-9_]*$ ]] || {
    echo "AMI_FAMILIES contains an invalid family name: '$family'." >&2
    exit 1
  }
  [[ -z "${seen_ami_families[$family]+x}" ]] || {
    echo "AMI_FAMILIES contains a duplicate family: '$family'." >&2
    exit 1
  }
  seen_ami_families[$family]=1
  enabled_var="${family}_ENABLED" name_var="${family}_OUTPUT_AMI_NAME"
  validate_bool "$enabled_var" "${!enabled_var-0}"
  if [[ "${!enabled_var-0}" == 1 && -z "${!name_var-}" ]]; then
    echo "${name_var} must be set in ${CONFIG:-config} while ${enabled_var} is 1" >&2
    exit 1
  fi
done
unset family enabled_var name_var ami_families seen_ami_families

# File system configuration.
CREATE_FILE_SYSTEMS=${CREATE_FILE_SYSTEMS-0}
EC2_FILESYSTEM_PROVIDERS=${EC2_FILESYSTEM_PROVIDERS-s3files,efs,fsx,io2}
EC2_FILESYSTEM_CLEANUP_HOOK_DIR=${EC2_FILESYSTEM_CLEANUP_HOOK_DIR-}
validate_bool CREATE_FILE_SYSTEMS "$CREATE_FILE_SYSTEMS"
RESOURCE_DRY_RUN=${RESOURCE_DRY_RUN-0}
RESOURCE_MANAGED_BY=${RESOURCE_MANAGED_BY-ec2-environment}
RESOURCE_PROJECT=${RESOURCE_PROJECT-}
RESOURCE_OWNER=${RESOURCE_OWNER-}
RESOURCE_EXPIRES_AT=${RESOURCE_EXPIRES_AT-}
if [[ "$WORKDIR" == /* ]];then
  resource_manifest_default="$WORKDIR/resources.tsv"
else
  resource_manifest_default="$PWD/$WORKDIR/resources.tsv"
fi
RESOURCE_MANIFEST=${RESOURCE_MANIFEST-$resource_manifest_default}
unset resource_manifest_default
S3FILES_IDS=${S3FILES_IDS-}
S3FILES_NAMES=${S3FILES_NAMES-}
S3FILES_MOUNT_POINTS=${S3FILES_MOUNT_POINTS-/mnt/s3files}
EFS_IDS=${EFS_IDS-}
EFS_NAMES=${EFS_NAMES-}
EFS_MOUNT_POINTS=${EFS_MOUNT_POINTS-/mnt/efs}
EFS_SECURITY_GROUP_IDS="${EFS_SECURITY_GROUP_IDS-}"
EFS_SECURITY_GROUP_NAMES=${EFS_SECURITY_GROUP_NAMES-}
EFS_PERFORMANCE_MODES=${EFS_PERFORMANCE_MODES-generalPurpose}
EFS_THROUGHPUT_MODES=${EFS_THROUGHPUT_MODES-bursting}
FSX_NAMES=${FSX_NAMES-}
FSX_IDS=${FSX_IDS-}
FSX_MOUNT_POINTS=${FSX_MOUNT_POINTS-/mnt/fsx}
FSX_SECURITY_GROUP_IDS=${FSX_SECURITY_GROUP_IDS-}
FSX_SECURITY_GROUP_NAMES=${FSX_SECURITY_GROUP_NAMES-}
FSX_STORAGE_TYPES=${FSX_STORAGE_TYPES-SSD}
FSX_STORAGE_CAPACITIES_GIB=${FSX_STORAGE_CAPACITIES_GIB-100}
FSX_THROUGHPUT_CAPACITIES_MIBPS=${FSX_THROUGHPUT_CAPACITIES_MIBPS-160}
FSX_AUTOMATIC_BACKUP_RETENTION_DAYS=${FSX_AUTOMATIC_BACKUP_RETENTION_DAYS-30}
FSX_ROUTE_TABLE_IDS=${FSX_ROUTE_TABLE_IDS-}
FSX_ROUTE_TABLE_NAMES=${FSX_ROUTE_TABLE_NAMES-}
FSX_DEPLOYMENT_TYPE=${FSX_DEPLOYMENT_TYPE-SINGLE_AZ_1}
IO2_NAMES=${IO2_NAMES-}
IO2_IDS=${IO2_IDS-}
IO2_MOUNT_POINTS=${IO2_MOUNT_POINTS-/mnt/io2}
IO2_FSTYPES=${IO2_FSTYPES-xfs}
IO2_VOLUME_SIZES_GIB=${IO2_VOLUME_SIZES_GIB-100}
IO2_VOLUME_IOPS=${IO2_VOLUME_IOPS-3000}
IO2_DEVICE_NAMES=${IO2_DEVICE_NAMES-/dev/sdf}

EC2_NAME_FILTER=${EC2_NAME_FILTER-}
EC2_IMAGE_NAME_FILTER=${EC2_IMAGE_NAME_FILTER-}
EC2_SSH_PRIVATE_KEY=${EC2_SSH_PRIVATE_KEY-}
if ! declare -p EC2_SSH_OPTIONS &>/dev/null; then
  EC2_SSH_OPTIONS=()
fi
if ! declare -p EC2_ET_OPTIONS &>/dev/null; then
  EC2_ET_OPTIONS=()
fi
if ! declare -p EC2_SCP_OPTIONS &>/dev/null; then
  EC2_SCP_OPTIONS=(-r)
fi
if ! declare -p EC2_RSYNC_OPTIONS &>/dev/null; then
  EC2_RSYNC_OPTIONS=(-a)
fi
EC2_SSH_USERNAME=${EC2_SSH_USERNAME-${EC2_USER}}
EC2_ASSOCIATE_PUBLIC_IP=${EC2_ASSOCIATE_PUBLIC_IP-false}
EC2_USE_PRIVATE_IP=${EC2_USE_PRIVATE_IP-1}
EC2_DEFAULT_INSTANCE_TYPE=${EC2_DEFAULT_INSTANCE_TYPE-t3.medium}
EC2_USE_SPOT_INSTANCE=${EC2_USE_SPOT_INSTANCE-0}
EC2_SUBMIT_COMMAND=${EC2_SUBMIT_COMMAND-1}
validate_bool EC2_ASSOCIATE_PUBLIC_IP "$EC2_ASSOCIATE_PUBLIC_IP"
validate_bool EC2_USE_PRIVATE_IP "$EC2_USE_PRIVATE_IP"
validate_bool EC2_USE_SPOT_INSTANCE "$EC2_USE_SPOT_INSTANCE"
EC2_SUBMIT_N_RETRY_LAUNCH=${EC2_SUBMIT_N_RETRY_LAUNCH-120}
EC2_SUBMIT_N_RETRY_SSH=${EC2_SUBMIT_N_RETRY_SSH-10}
EC2_SUBMIT_RETRY_LAUNCH_INTERVAL=${EC2_SUBMIT_RETRY_LAUNCH_INTERVAL-60}
EC2_SUBMIT_RETRY_SSH_INTERVAL=${EC2_SUBMIT_RETRY_SSH_INTERVAL-10}
EC2_CLI_INPUT_JSON_GROUP=${EC2_CLI_INPUT_JSON_GROUP-cpu}
if [[ "$WORKDIR" == /* ]];then
  ec2_user_data_default="fileb://$WORKDIR/ec2/user_data.sh.gz"
else
  ec2_user_data_default="fileb://$PWD/$WORKDIR/ec2/user_data.sh.gz"
fi
EC2_USER_DATA_URI=${EC2_USER_DATA_URI-$ec2_user_data_default}
EC2_USER_DATA_FORMAT=${EC2_USER_DATA_FORMAT-auto}
EC2_USER_DATA_MAX_BYTES=${EC2_USER_DATA_MAX_BYTES-16384}
validate_choice EC2_USER_DATA_FORMAT "$EC2_USER_DATA_FORMAT" auto plain gzip
validate_positive_integer EC2_USER_DATA_MAX_BYTES "$EC2_USER_DATA_MAX_BYTES"
EC2_CLOUD_INIT_INSTANCE_DIR=${EC2_CLOUD_INIT_INSTANCE_DIR-/var/lib/cloud/instances}
EC2_READY_FILENAME=${EC2_READY_FILENAME-ready}
unset ec2_user_data_default
EC2_MOSH_SERVER_PATH=${EC2_MOSH_SERVER_PATH-/usr/bin/mosh-server}

USER_ENV_ROOT_DIR=${USER_ENV_ROOT_DIR-}
USER_ENV_ENABLE_USR_SYMLINK=${USER_ENV_ENABLE_USR_SYMLINK-1}
USER_ENV_INSTALLER_SCRIPTS=${USER_ENV_INSTALLER_SCRIPTS-}
USER_ENV_DOTFILES_FILE=${USER_ENV_DOTFILES_FILE-}
USER_ENV_DOTFILES_DIR=${USER_ENV_DOTFILES_DIR-}
USER_ENV_CONFIG_DOTFILES_FILE=${USER_ENV_CONFIG_DOTFILES_FILE-}
USER_ENV_CONFIG_DOTFILES_DIR=${USER_ENV_CONFIG_DOTFILES_DIR-}

INSTANCE_ENABLE_DOCKER=${INSTANCE_ENABLE_DOCKER-0}
INSTANCE_AWS_CONFIG=${INSTANCE_AWS_CONFIG-}
INSTANCE_SSH_KNOWN_HOSTS=${INSTANCE_SSH_KNOWN_HOSTS-}
INSTANCE_SSH_CONFIG=${INSTANCE_SSH_CONFIG-}
INSTANCE_SSH_RC=${INSTANCE_SSH_RC-}
INSTANCE_USER_DATA_EXTRA_SCRIPT=${INSTANCE_USER_DATA_EXTRA_SCRIPT-}
