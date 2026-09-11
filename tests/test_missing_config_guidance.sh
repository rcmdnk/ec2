#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/ec2-missing-config.XXXXXX")
trap 'command rm -rf "$runtime_dir"' EXIT
export HOME="$runtime_dir/home"
export XDG_CONFIG_HOME="$runtime_dir/config"

if output=$(bin/ec2 setup 2>&1);then
  echo 'setup must fail when its environment configuration is missing.' >&2
  exit 1
fi
grep -Fq "Environment configuration file not found: $XDG_CONFIG_HOME/ec2/environment" <<< "$output"
grep -Fq 'ec2 init_environment' <<< "$output"
grep -Fq "${EDITOR:-vi} $XDG_CONFIG_HOME/ec2/environment" <<< "$output"
if grep -Fq 'copy config.example' <<< "$output";then
  echo 'setup must not refer to an unavailable config.example file.' >&2
  exit 1
fi

if output=$(bin/ec2 ssh 2>&1);then
  echo 'ssh must fail when its EC2 configuration is missing.' >&2
  exit 1
fi
grep -Fq "EC2 configuration file not found: $XDG_CONFIG_HOME/ec2/config" <<< "$output"
grep -Fq 'name_filter=my-instances' <<< "$output"
grep -Fq 'image_name_filter=my-images' <<< "$output"
grep -Fq 'ssh_user=ec2-user' <<< "$output"
grep -Fq 'ec2 init_environment' <<< "$output"
grep -Fq 'ec2 setup' <<< "$output"

bin/ec2 help >/dev/null
bin/ec2 init_environment >/dev/null
[[ -f "$XDG_CONFIG_HOME/ec2/environment" ]]

echo 'Missing configuration guidance tests passed.'
