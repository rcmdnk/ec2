#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
snapshot=$(mktemp "${TMPDIR:-/tmp}/ec2-generated-bin.XXXXXX")
trap 'rm -f "$snapshot"' EXIT
cp bin/ec2 "$snapshot"
scripts/build
cmp -s "$snapshot" bin/ec2 || {
  echo 'bin/ec2 is not reproducible from src/ and environment/.' >&2
  exit 1
}

echo 'Generated bin/ec2 test passed.'
