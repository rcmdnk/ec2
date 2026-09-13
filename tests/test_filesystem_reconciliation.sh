#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
# shellcheck disable=SC1091
source environment/scripts/common.sh

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/ec2-environment-filesystems.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
lookup_file="$test_dir/lookups"
lookup_log="$test_dir/lookup.log"
create_log="$test_dir/create.log"
prepare_log="$test_dir/prepare.log"
error_log="$test_dir/error.log"
fail_marker="$test_dir/fail-once"

fail() {
  echo "$1" >&2
  exit 1
}

assert_equal() {
  local expected=$1 actual=$2 message=$3
  [[ "$actual" == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_empty_file() {
  local file=$1 message=$2
  [[ ! -s "$file" ]] || fail "$message: $(<"$file")"
}

reset_fixture() {
  : > "$lookup_file"
  : > "$lookup_log"
  : > "$create_log"
  : > "$prepare_log"
  : > "$error_log"
  rm -f "$fail_marker"
  lookup_failure_name=
  fail_once_name=
  create_prefix=
  MOCK_IDS=
  MOCK_NAMES=
  MOCK_MOUNT_POINTS=
  CREATE_FILE_SYSTEMS=0
}

get_mock_id() {
  local name=$1
  echo "$name" >> "$lookup_log"
  [[ "$name" != "$lookup_failure_name" ]] || return 9
  awk -F= -v name="$name" '$1 == name { print $2 }' "$lookup_file"
}

prepare_mock_creation() {
  local count=$1
  create_prefix="id-created"
  echo "$count" >> "$prepare_log"
}

create_mock() {
  local i=$1 name=$2 id="${create_prefix:-unprepared}-$2"
  echo "$i:$name" >> "$create_log"
  if [[ "$name" == "$fail_once_name" && ! -e "$fail_marker" ]];then
    : > "$fail_marker"
    return 1
  fi
  echo "$name=$id" >> "$lookup_file"
  echo "$id"
}

test_explicit_ids_skip_lookup() {
  reset_fixture
  MOCK_IDS="id-a,id-b"
  MOCK_NAMES="ignored-a,ignored-b"
  MOCK_MOUNT_POINTS=/mnt/a,/mnt/b
  setup_filesystem_ids mock create_mock prepare_mock_creation
  assert_equal id-a,id-b "$MOCK_IDS" 'Explicit IDs must be preserved'
  assert_empty_file "$lookup_log" 'Explicit IDs must skip name lookup'
}

test_all_existing_preserve_order() {
  reset_fixture
  cat > "$lookup_file" <<'EOF'
beta=id-b
alpha=id-a
EOF
  MOCK_NAMES=alpha,beta
  MOCK_MOUNT_POINTS=/mnt/a,/mnt/b
  CREATE_FILE_SYSTEMS=1
  setup_filesystem_ids mock create_mock prepare_mock_creation
  assert_equal id-a,id-b "$MOCK_IDS" 'Resolved IDs must follow input name order'
  assert_empty_file "$create_log" 'Existing resources must not be created again'
  assert_empty_file "$prepare_log" 'Creation options must not be prepared when everything exists'
}

test_mixed_existing_and_missing() {
  reset_fixture
  echo 'existing=id-existing' > "$lookup_file"
  MOCK_NAMES=existing,missing
  MOCK_MOUNT_POINTS=/mnt/existing,/mnt/missing
  CREATE_FILE_SYSTEMS=1
  setup_filesystem_ids mock create_mock prepare_mock_creation
  assert_equal id-existing,id-created-missing "$MOCK_IDS" 'Missing resources must be created in place'
  assert_equal 2 "$(<"$prepare_log")" 'Creation options must be prepared for the complete request'
  assert_equal 1:missing "$(<"$create_log")" 'Only the missing resource must be created'
}

test_missing_with_creation_disabled() {
  reset_fixture
  echo 'existing=id-existing' > "$lookup_file"
  MOCK_NAMES=existing,missing
  MOCK_MOUNT_POINTS=/mnt/existing,/mnt/missing
  if setup_filesystem_ids mock create_mock prepare_mock_creation 2> "$error_log";then
    fail 'Missing resources must fail when creation is disabled'
  fi
  grep -q '^  missing$' "$error_log" || fail 'The missing resource name must be reported'
  assert_empty_file "$create_log" 'Creation-disabled reconciliation must not create resources'
}

test_ambiguity_stops_before_creation() {
  reset_fixture
  cat > "$lookup_file" <<'EOF'
ambiguous=id-one
ambiguous=id-two
EOF
  MOCK_NAMES=missing,ambiguous
  MOCK_MOUNT_POINTS=/mnt/missing,/mnt/ambiguous
  CREATE_FILE_SYSTEMS=1
  if setup_filesystem_ids mock create_mock prepare_mock_creation 2> "$error_log";then
    fail 'Ambiguous names must fail reconciliation'
  fi
  grep -q "'ambiguous' matches 2" "$error_log" || fail 'The ambiguous resource name must be reported'
  assert_empty_file "$create_log" 'All names must be checked before anything is created'
  assert_empty_file "$prepare_log" 'Ambiguity must fail before creation is prepared'
}

test_lookup_failure_is_not_missing() {
  reset_fixture
  lookup_failure_name=unavailable
  MOCK_NAMES=unavailable
  MOCK_MOUNT_POINTS=/mnt/unavailable
  CREATE_FILE_SYSTEMS=1
  if setup_filesystem_ids mock create_mock prepare_mock_creation 2> "$error_log";then
    fail 'Lookup errors must fail reconciliation'
  fi
  grep -q "lookup failed for 'unavailable'" "$error_log" || fail 'Lookup failures must be identified'
  assert_empty_file "$create_log" 'A lookup error must not be treated as a missing resource'
}

test_retry_after_partial_creation() {
  reset_fixture
  fail_once_name=second
  MOCK_NAMES=first,second
  MOCK_MOUNT_POINTS=/mnt/first,/mnt/second
  CREATE_FILE_SYSTEMS=1
  if setup_filesystem_ids mock create_mock prepare_mock_creation 2> "$error_log";then
    fail 'The first run must expose the simulated creation failure'
  fi
  grep -q '^first=id-created-first$' "$lookup_file" || fail 'The first resource must remain discoverable after partial creation'

  : > "$error_log"
  setup_filesystem_ids mock create_mock prepare_mock_creation
  assert_equal id-created-first,id-created-second "$MOCK_IDS" 'A retry must reuse created resources and create the remainder'
  assert_equal 2 "$(grep -c '^1:second$' "$create_log")" 'Only the failed resource must be retried'
}

test_name_mount_count_checked_before_lookup() {
  reset_fixture
  # shellcheck disable=SC2034  # setup_filesystem_ids reads this fixture indirectly.
  MOCK_NAMES=first,second
  # shellcheck disable=SC2034  # setup_filesystem_ids reads this fixture indirectly.
  MOCK_MOUNT_POINTS=/mnt/only-one
  CREATE_FILE_SYSTEMS=1
  if setup_filesystem_ids mock create_mock prepare_mock_creation 2> "$error_log";then
    fail 'Name and mount-point count mismatches must fail'
  fi
  assert_empty_file "$lookup_log" 'Length validation must happen before AWS lookup'
}

test_explicit_ids_skip_lookup
test_all_existing_preserve_order
test_mixed_existing_and_missing
test_missing_with_creation_disabled
test_ambiguity_stops_before_creation
test_lookup_failure_is_not_missing
test_retry_after_partial_creation
test_name_mount_count_checked_before_lookup

echo 'All filesystem reconciliation checks passed.'
