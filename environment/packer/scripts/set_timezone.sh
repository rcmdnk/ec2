#!/usr/bin/env bash
set -euo pipefail
[[ -n "${AMI_TIMEZONE:-}" ]] && timedatectl set-timezone "$AMI_TIMEZONE"
