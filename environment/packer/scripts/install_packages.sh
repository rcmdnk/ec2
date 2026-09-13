#!/usr/bin/env bash
set -euo pipefail

# AMI_PACKAGES, AMI_EXTRA_PACKAGES, and AMI_UPDATE_PACKAGES come from the Packer template's
# environment_vars, so an unset one means the template is out of sync.
# shellcheck disable=SC2153
read -r -a packages <<<"${AMI_PACKAGES} ${AMI_EXTRA_PACKAGES}"

remove_package() {
  local package=$1 remaining=()
  for candidate in "${packages[@]}"; do
    [[ "$candidate" != "$package" ]] && remaining+=("$candidate")
  done
  packages=("${remaining[@]}")
}

record_package_manifest() {
  rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\t%{ARCH}\n' | sort \
    > /var/log/ec2-environment-packages.tsv
}

if [[ -z "${packages[*]}" && -z "${AMI_FLATPAK_PACKAGES:-}" ]];then
  record_package_manifest
  exit 0
fi

if command -v dnf >/dev/null 2>&1; then
  # shellcheck disable=SC2153  # Supplied by the Packer environment_vars list.
  [[ "$AMI_UPDATE_PACKAGES" == 1 ]] && dnf update -y
  dnf install -y 'dnf-command(config-manager)'

  install_spal=0
  if printf '%s\n' "${packages[@]}" | grep -qx spal; then
    remove_package spal
    install_spal=1
  fi
  if printf '%s\n' "${packages[@]}" | grep -qx spal-release; then
    remove_package spal-release
    install_spal=1
  fi
  if [[ "${install_spal}" == "1" ]]; then
    dnf install -y spal-release
  fi
  if printf '%s\n' "${packages[@]}" | grep -qx gh; then
    dnf install -y dnf5-plugins 2>/dev/null || dnf install -y dnf-plugins-core
    if dnf --version | head -n 1 | grep -q '^5\.'; then
      dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
    else
      dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    fi
  fi
  if printf '%s\n' "${packages[@]}" | grep -qx lazygit; then
    dnf install -y dnf-plugins-core
    dnf copr enable -y dejan/lazygit amazonlinux-2023-x86_64
  fi
  if printf '%s\n' "${packages[@]}" | grep -qx terraform; then
    dnf install -y dnf5-plugins 2>/dev/null || dnf install -y dnf-plugins-core
    if dnf --version | head -n 1 | grep -q '^5\.'; then
      dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    else
      dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    fi
  fi
  if printf '%s\n' "${packages[@]}" | grep -qx google-chrome; then
    curl -fL -o /tmp/google-chrome.rpm https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
    dnf install -y /tmp/google-chrome.rpm
    rm -f /tmp/google-chrome.rpm
    remove_package google-chrome
  fi
  if [[ "${#packages[@]}" -gt 0 ]]; then
    dnf install -y "${packages[@]}"
  fi

  if [ "${AMI_FLATPAK_PACKAGES:-}" ]; then
    dnf install -y flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    # shellcheck disable=SC2086
    flatpak install -y flathub $AMI_FLATPAK_PACKAGES
  fi

elif command -v yum >/dev/null 2>&1; then
  # Plain install only. None of the special cases above apply here: the extra
  # repositories (gh, terraform, lazygit), the versioned kernel packages, the
  # google-chrome rpm and AMI_FLATPAK_PACKAGES are all dnf-only. Listing any of them
  # in AMI_PACKAGES on a yum image either fails or silently installs nothing.
  # shellcheck disable=SC2153  # Supplied by the Packer environment_vars list.
  [[ "$AMI_UPDATE_PACKAGES" == 1 ]] && yum update -y
  yum install -y "${packages[@]}"
else
  echo 'This template supports dnf or yum based images.' >&2
  exit 1
fi

record_package_manifest
