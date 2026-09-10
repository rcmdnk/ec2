#!/usr/bin/env bash
set -euo pipefail
[[ -n "${TIME_ZONE:-}" ]] && timedatectl set-timezone "$TIME_ZONE"
