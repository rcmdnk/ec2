#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/bootstrap.sh"

get_s3files_id() {
  local name=$1
  aws "${AWS_ARGS[@]}" s3files list-file-systems \
  --query "fileSystems[?name=='$name'].fileSystemId" --output text
}

setup_filesystem_ids s3files
echo "$S3FILES_IDS"
