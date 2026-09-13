#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
marker=$(mktemp "${TMPDIR:-/tmp}/ec2-authentication.XXXXXX")
trap 'rm -f "$marker"' EXIT
export marker

source environment/scripts/common.sh
# shellcheck disable=SC2016  # The marker is intentionally expanded by the child shell.
AWS_AUTH_COMMAND='printf refreshed > "$marker"'
run_aws_auth_command
[[ $(<"$marker") == refreshed ]]

AWS_AUTH_COMMAND=''
if run_aws_auth_command; then
  echo 'An empty AWS_AUTH_COMMAND must not run an authentication command.' >&2
  exit 1
fi
echo 'AWS authentication tests passed.'
