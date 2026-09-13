#!/usr/bin/env bash
set -euo pipefail
if [[ "${AMI_ENABLE_SHARED_MEMORY:-}" = 1 ]];then
  chmod 1777 /dev/shm
fi
