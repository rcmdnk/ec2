#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${AMI_SWAP_BLOCK_SIZE:-}" ]] && [[ -n "${AMI_SWAP_BLOCK_COUNT:-}" ]] && [[ ! -f /swapfile ]]; then
  dd if=/dev/zero of=/swapfile bs="$AMI_SWAP_BLOCK_SIZE" count="$AMI_SWAP_BLOCK_COUNT"
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
fi
