#!/usr/bin/env bash
# shellcheck disable=SC2034  # Values are consumed by the generated resource helpers.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-environment-resource-lifecycle.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT

# shellcheck disable=SC1091
source environment/scripts/common.sh
RESOURCE_MANAGED_BY=ec2-environment
RESOURCE_PROJECT='project with spaces'
RESOURCE_OWNER=owner@example.com
RESOURCE_EXPIRES_AT=2026-12-31T00:00:00Z
RESOURCE_MANIFEST="$runtime_dir/resources.tsv"

tags=$(resource_tags_json 'name with spaces')
python3 -c 'import json,sys; tags=json.loads(sys.argv[1]); assert {t["Key"] for t in tags} == {"Name","ManagedBy","Project","Owner","ExpiresAt"}' "$tags"
record_resource io2 vol-recorded 'volume name'
record_resource io2 vol-recorded 'volume name'
[[ $(wc -l < "$RESOURCE_MANIFEST" | tr -d ' ') == 2 ]] || {
  echo 'The resource manifest must not duplicate an already-recorded exact ID.' >&2
  exit 1
}

# Dry-run creation prints every missing resource but never invokes its callback.
TEST_IDS=''
# shellcheck disable=SC2034  # Read indirectly by setup_filesystem_ids.
TEST_NAMES='one,two'
# shellcheck disable=SC2034  # Read indirectly by setup_filesystem_ids.
TEST_MOUNT_POINTS='/mnt/one,/mnt/two'
CREATE_FILE_SYSTEMS=1
RESOURCE_DRY_RUN=1
create_marker="$runtime_dir/create-called"
get_test_id() { echo None; }
create_test() { touch "$create_marker"; echo "id-$2"; }
plan=$(setup_filesystem_ids test create_test 2>&1)
[[ -z "$TEST_IDS" && ! -e "$create_marker" ]] || {
  echo 'RESOURCE_DRY_RUN must not call a resource creation callback.' >&2
  exit 1
}
grep -q 'create test name=one' <<<"$plan"
grep -q 'create test name=two' <<<"$plan"

mock_bin="$runtime_dir/bin"
aws_log="$runtime_dir/aws.log"
mount_target_deleted="$runtime_dir/mount-target-deleted"
transient_error="$runtime_dir/transient-error"
hook_dir="$runtime_dir/cleanup-hooks"
hook_log="$runtime_dir/hook.log"
mkdir -p "$mock_bin"
mkdir -p "$hook_dir"
cat > "$hook_dir/custom.sh" <<EOF
#!/usr/bin/env bash
printf '%s:%s\n' "\$1" "\$2" >> '$hook_log'
EOF
chmod 755 "$hook_dir/custom.sh"
cat > "$mock_bin/aws" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$aws_log'
if [[ "\$*" == *"vol-missing"* ]];then
  echo 'An error occurred (InvalidVolume.NotFound) when calling the DescribeVolumes operation: volume does not exist' >&2
  exit 255
elif [[ "\$*" == *"vol-transient"* && ! -e '$transient_error' ]];then
  touch '$transient_error'
  echo 'An error occurred (ThrottlingException) while describing volume' >&2
  exit 255
elif [[ "\$*" == *ManagedBy* ]];then
  [[ " \$* " == *" vol-unmanaged "* ]] && echo somebody-else || echo ec2-environment
elif [[ " \$* " == *" efs describe-mount-targets "* ]];then
  if [[ " \$* " == *" length(MountTargets) "* ]];then
    echo 0
  elif [[ ! -e '$mount_target_deleted' ]];then
    echo mt-exact
  fi
elif [[ " \$* " == *" efs delete-mount-target "* ]];then
  touch '$mount_target_deleted'
fi
EOF
chmod 755 "$mock_bin/aws"
config="$runtime_dir/config"
cat > "$config" <<'EOF'
AWS_REGION=ap-northeast-1
CPU_ENABLED=0
GPU_ENABLED=0
RESOURCE_MANAGED_BY=ec2-environment
AWS_POLL_DELAY_SECONDS=1
AWS_MAX_ATTEMPTS=2
EOF
printf 'EC2_FILESYSTEM_CLEANUP_HOOK_DIR=%s\n' "$hook_dir" >> "$config"

cleanup_manifest="$runtime_dir/cleanup.tsv"
cat > "$cleanup_manifest" <<'EOF'
type	id	name	created_at
ami	ami-exact	image	2026-09-10T00:00:00Z
efs	fs-exact	efs	2026-09-10T00:00:00Z
fsx	fsx-exact	fsx	2026-09-10T00:00:00Z
io2	vol-exact	io2	2026-09-10T00:00:00Z
EOF

PATH="$mock_bin:$PATH" bin/ec2 cleanup_resources --workdir "$runtime_dir/work" \
  --environment-config "$config" --manifest "$cleanup_manifest" >/dev/null
if grep -qE 'delete-(file-system|volume)|deregister-image' "$aws_log";then
  echo 'Cleanup without --execute must not make deletion API calls.' >&2
  exit 1
fi

: > "$aws_log"
PATH="$mock_bin:$PATH" bin/ec2 cleanup_resources --workdir "$runtime_dir/work" \
  --environment-config "$config" --manifest "$cleanup_manifest" --execute 1 >/dev/null
grep -q 'ec2 deregister-image --image-id ami-exact' "$aws_log"
grep -q 'efs delete-file-system --file-system-id fs-exact' "$aws_log"
grep -q 'fsx delete-file-system --file-system-id fsx-exact' "$aws_log"
grep -q 'ec2 delete-volume --volume-id vol-exact' "$aws_log"
[[ $(wc -l < "$cleanup_manifest" | tr -d ' ') == 1 ]] || {
  echo 'Successfully deleted resources must be removed from the manifest.' >&2
  exit 1
}

cat > "$cleanup_manifest" <<'EOF'
type	id	name	created_at
io2	vol-unmanaged	foreign	2026-09-10T00:00:00Z
EOF
if PATH="$mock_bin:$PATH" bin/ec2 cleanup_resources --workdir "$runtime_dir/work" \
  --environment-config "$config" --manifest "$cleanup_manifest" --execute 1 >/dev/null 2>&1;then
  echo 'Cleanup must refuse resources whose ManagedBy tag does not match.' >&2
  exit 1
fi
grep -q 'vol-unmanaged' "$cleanup_manifest" || {
  echo 'A refused resource must remain in the manifest.' >&2
  exit 1
}

cat > "$cleanup_manifest" <<'EOF'
type	id	name	created_at
io2	vol-missing	missing	2026-09-10T00:00:00Z
EOF
PATH="$mock_bin:$PATH" bin/ec2 cleanup_resources --workdir "$runtime_dir/work" \
  --environment-config "$config" --manifest "$cleanup_manifest" --execute 1 >/dev/null
[[ $(wc -l < "$cleanup_manifest" | tr -d ' ') == 1 ]] || {
  echo 'Already absent resources must be removed from the manifest.' >&2
  exit 1
}

cat > "$cleanup_manifest" <<'EOF'
type	id	name	created_at
io2	vol-transient	transient	2026-09-10T00:00:00Z
EOF
PATH="$mock_bin:$PATH" bin/ec2 cleanup_resources --workdir "$runtime_dir/work" \
  --environment-config "$config" --manifest "$cleanup_manifest" --execute 1 >/dev/null
[[ -e "$transient_error" && $(wc -l < "$cleanup_manifest" | tr -d ' ') == 1 ]] || {
  echo 'Transient AWS errors must be retried before cleanup continues.' >&2
  exit 1
}

cat > "$cleanup_manifest" <<'EOF'
type	id	name	created_at
custom	custom-id	custom-name	2026-09-10T00:00:00Z
EOF
PATH="$mock_bin:$PATH" bin/ec2 cleanup_resources --workdir "$runtime_dir/work" \
  --environment-config "$config" --manifest "$cleanup_manifest" --execute 1 >/dev/null
grep -q '^custom-id:custom-name$' "$hook_log" || {
  echo 'Configured filesystem cleanup hooks were not invoked.' >&2
  exit 1
}
[[ $(wc -l < "$cleanup_manifest" | tr -d ' ') == 1 ]] || {
  echo 'A successful filesystem cleanup hook must remove its manifest row.' >&2
  exit 1
}

echo 'Resource lifecycle tests passed.'
