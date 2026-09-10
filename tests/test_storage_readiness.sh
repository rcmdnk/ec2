#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
runtime_dir=$(mktemp -d "$root/tmp/ec2-environment-storage-readiness.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
mkdir -p "$mock_bin"

cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" ec2 describe-images "* ]];then echo ami-storage-readiness-test;fi
EOF
cat > "$mock_bin/mount" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat > "$mock_bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat > "$mock_bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod 755 "$mock_bin"/*

config="$runtime_dir/config"
cat > "$config" <<EOF
REGION=ap-northeast-1
CPU_AMI_NAME=storage-readiness-test
SUBNET_IDS=subnet-storage-readiness-test
KEY_NAME=storage-readiness-test
EC2_SSH_KEY=/tmp/storage-readiness-test.pem
S3FILES_IDS=fs-storage-readiness-test
S3FILES_MOUNT_POINTS=$runtime_dir/mnt
FS_MOUNT_MAX_ATTEMPTS=2
FS_MOUNT_RETRY_INTERVAL=1
EOF

work=${runtime_dir#"$root/"}/work
PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$work" \
  --environment-config "$config" --install-config 0 >/dev/null
generated="$runtime_dir/work/ec2/user_data.sh"
offline="$runtime_dir/user_data_mounts.sh"

# Execute the generated mount section with local substitutes. This catches
# runtime failures that syntax-only validation cannot observe without touching
# the host's fstab or continuing into package/user configuration.
awk -v fstab="$runtime_dir/fstab" '
  { gsub("/etc/fstab", fstab); print }
  /for required_mount in / { in_mount_loop=1 }
  in_mount_loop && /^done$/ { exit }
' "$generated" > "$offline"

if output=$(PATH="$mock_bin:$PATH" bash "$offline" 2>&1);then
  echo 'Generated user-data must fail when a required mount never becomes ready.' >&2
  exit 1
fi
grep -q 'Failed to mount required file system' <<<"$output" || {
  echo 'Generated user-data did not report the failed required mount.' >&2
  exit 1
}
[[ ! -e "$runtime_dir/ready" ]] || {
  echo 'A failed required mount must not produce the ready marker.' >&2
  exit 1
}

echo 'Storage readiness tests passed.'
