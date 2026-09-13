#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2154  # Source and enum values are supplied by src/ec2.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/ec2-connection-method.XXXXXX")
trap 'command rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
mkdir -p "$mock_bin"
export ARG_LOG="$runtime_dir/aws.log"
cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ARG_LOG"
EOF
chmod 755 "$mock_bin/aws"
PATH="$mock_bin:$PATH"

source <(awk '/^# Main$/{exit} {print}' src/ec2)
__verbose=0
__exit_at_fail=1
__aws_profile=''
__connection_method=ssm
__execute_command=''
_instance_check() {
  __ids[__enum_instance]=i-0123456789abcdef0
  __instance_ip=''
}
ssh
grep -q 'ssm start-session --target i-0123456789abcdef0' "$ARG_LOG"
echo 'EC2 connection method tests passed.'
