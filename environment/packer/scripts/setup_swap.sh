#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${SWAP_BS:-}" ]] && [[ -n "${SWAP_COUNT:-}" ]] && [[ ! -f /swapfile ]]; then
  dd if=/dev/zero of=/swapfile bs="$SWAP_BS" count="$SWAP_COUNT"
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
fi
