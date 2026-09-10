#!/usr/bin/env bash
set -euo pipefail
if [[ "${MULTI_PROCESSING:-}" = 1 ]];then
  chmod 1777 /dev/shm
fi
