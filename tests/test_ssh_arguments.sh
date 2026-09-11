#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/ec2-ssh-arguments.XXXXXX")
trap 'command rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
export ARG_LOG="$runtime_dir/arguments.log"
mkdir -p "$mock_bin"

for command_name in ssh mosh et scp rsync;do
  cat > "$mock_bin/$command_name" <<'EOF'
#!/usr/bin/env bash
{
  printf '[%s]\n' "${0##*/}"
  printf '<%s>\n' "$@"
} >> "$ARG_LOG"
EOF
  chmod 755 "$mock_bin/$command_name"
done
PATH="$mock_bin:$PATH"

# Load function definitions without running src/ec2's main entry point.
# shellcheck disable=SC1090
source <(awk '/^# Main$/{exit} {print}' src/ec2)

config="$runtime_dir/config"
cat > "$config" <<'EOF'
ssh_option="-o StrictHostKeyChecking=no"
EOF
__config="$config"
__ssh_option=()
_read_config
[[ ${#__ssh_option[@]} == 2 ]]
[[ ${__ssh_option[0]} == -o ]]
[[ ${__ssh_option[1]} == StrictHostKeyChecking=no ]]

cat > "$config" <<'EOF'
ssh_option=(-o StrictHostKeyChecking=no -o 'ProxyCommand=ssh -W %h:%p bastion')
et_option=(--keepalive 30)
scp_option=(-r -p)
rsync_option=(-a '--exclude=cache dir')
EOF
__ssh_option=()
__et_option=()
__scp_option=()
__rsync_option=()
_read_config
[[ ${#__ssh_option[@]} == 4 ]]
[[ ${__ssh_option[0]} == -o ]]
[[ ${__ssh_option[1]} == StrictHostKeyChecking=no ]]
[[ ${__ssh_option[2]} == -o ]]
[[ ${__ssh_option[3]} == 'ProxyCommand=ssh -W %h:%p bastion' ]]
[[ ${#__et_option[@]} == 2 ]]
[[ ${__et_option[0]} == --keepalive ]]
[[ ${__et_option[1]} == 30 ]]
[[ ${#__scp_option[@]} == 2 ]]
[[ ${__scp_option[0]} == -r ]]
[[ ${__scp_option[1]} == -p ]]
[[ ${#__rsync_option[@]} == 2 ]]
[[ ${__rsync_option[0]} == -a ]]
[[ ${__rsync_option[1]} == '--exclude=cache dir' ]]

eval "$(_generate_read_args)"
_read_args mosh --ssh-option -J --ssh-option 'jump host' \
  --et-option --terminal-path --et-option 'et terminal' \
  --scp-option -C --rsync-option --delete
[[ ${#__ssh_option[@]} == 6 ]]
[[ ${__ssh_option[4]} == -J ]]
[[ ${__ssh_option[5]} == 'jump host' ]]
[[ ${#__et_option[@]} == 4 ]]
[[ ${__et_option[2]} == --terminal-path ]]
[[ ${__et_option[3]} == 'et terminal' ]]
[[ ${#__scp_option[@]} == 3 ]]
[[ ${__scp_option[2]} == -C ]]
[[ ${#__rsync_option[@]} == 3 ]]
[[ ${__rsync_option[2]} == --delete ]]

__ssh_user=tester
__execute_command=''
_instance_check() {
  __instance_ip=203.0.113.10
}

read_command_args() {
  local name=$1 occurrence=$2
  awk -v marker="[$name]" -v occurrence="$occurrence" '
    $0 == marker { seen++; capture = (seen == occurrence); next }
    /^\[[^]]+\]$/ { capture = 0 }
    capture { sub(/^</, ""); sub(/>$/, ""); print }
  ' "$ARG_LOG"
}

: > "$ARG_LOG"
__ssh_option=()
__ssh_key=''
__mosh_server=''
mosh
mapfile -t default_mosh_args < <(read_command_args mosh 1)
[[ ${#default_mosh_args[@]} == 1 ]]
[[ ${default_mosh_args[0]} == tester@203.0.113.10 ]]

: > "$ARG_LOG"
__et_option=()
et
mapfile -t default_et_args < <(read_command_args et 1)
[[ ${#default_et_args[@]} == 1 ]]
[[ ${default_et_args[0]} == tester@203.0.113.10 ]]

: > "$ARG_LOG"
__ssh_option=(-o StrictHostKeyChecking=no -o 'ProxyCommand=ssh -W %h:%p bastion')
__ssh_key="$runtime_dir/key with spaces.pem"
__mosh_server="$runtime_dir/mosh server"
mosh
mapfile -t ready_args < <(read_command_args ssh 1)
[[ ${#ready_args[@]} == 8 ]]
[[ ${ready_args[4]} == -i ]]
[[ ${ready_args[5]} == "$__ssh_key" ]]
[[ ${ready_args[6]} == tester@203.0.113.10 ]]

mapfile -t mosh_args < <(read_command_args mosh 1)
printf -v expected_mosh_ssh '%q ' ssh "${__ssh_option[@]}" -i "$__ssh_key"
expected_mosh_ssh=${expected_mosh_ssh% }
[[ ${#mosh_args[@]} == 3 ]]
[[ ${mosh_args[0]} == "--ssh=$expected_mosh_ssh" ]]
[[ ${mosh_args[1]} == "--server=$__mosh_server" ]]
[[ ${mosh_args[2]} == tester@203.0.113.10 ]]

: > "$ARG_LOG"
__et_option=(--keepalive 30 --terminal-path "$runtime_dir/et terminal")
__execute_command='tmux new-session'
et
mapfile -t et_args < <(read_command_args et 1)
[[ ${#et_args[@]} == 13 ]]
[[ ${et_args[0]} == --keepalive ]]
[[ ${et_args[1]} == 30 ]]
[[ ${et_args[2]} == --terminal-path ]]
[[ ${et_args[3]} == "$runtime_dir/et terminal" ]]
[[ ${et_args[4]} == --ssh-option ]]
[[ ${et_args[5]} == StrictHostKeyChecking=no ]]
[[ ${et_args[6]} == --ssh-option ]]
[[ ${et_args[7]} == 'ProxyCommand=ssh -W %h:%p bastion' ]]
[[ ${et_args[8]} == --ssh-option ]]
[[ ${et_args[9]} == "IdentityFile=$__ssh_key" ]]
[[ ${et_args[10]} == --command ]]
[[ ${et_args[11]} == "$__execute_command" ]]
[[ ${et_args[12]} == tester@203.0.113.10 ]]

: > "$ARG_LOG"
__execute_command="printf '%s\\n' 'hello world'"
ssh
mapfile -t command_args < <(read_command_args ssh 2)
[[ ${#command_args[@]} == 8 ]]
[[ ${command_args[7]} == "$__execute_command" ]]

: > "$ARG_LOG"
__file="$runtime_dir/input file"
: > "$__file"
__transfer_operands=()
__scp_option=(-r)
scp
mapfile -t scp_args < <(read_command_args scp 1)
[[ ${#scp_args[@]} == 9 ]]
[[ ${scp_args[5]} == "$__ssh_key" ]]
[[ ${scp_args[6]} == -r ]]
[[ ${scp_args[7]} == "$__file" ]]
[[ ${scp_args[8]} == tester@203.0.113.10: ]]

: > "$ARG_LOG"
source_dir="$runtime_dir/source directory"
mkdir -p "$source_dir"
__transfer_operands=("$source_dir" ':/tmp/remote directory/')
__ssh_option=(-p 2222 -o StrictHostKeyChecking=no)
__ssh_key="$runtime_dir/key with spaces.pem"
__scp_option=(-r -p)
scp
mapfile -t upload_args < <(read_command_args scp 1)
[[ ${#upload_args[@]} == 10 ]]
[[ ${upload_args[0]} == -P ]]
[[ ${upload_args[1]} == 2222 ]]
[[ ${upload_args[2]} == -o ]]
[[ ${upload_args[3]} == StrictHostKeyChecking=no ]]
[[ ${upload_args[4]} == -i ]]
[[ ${upload_args[5]} == "$__ssh_key" ]]
[[ ${upload_args[6]} == -r ]]
[[ ${upload_args[7]} == -p ]]
[[ ${upload_args[8]} == "$source_dir" ]]
[[ ${upload_args[9]} == 'tester@203.0.113.10:/tmp/remote directory/' ]]

: > "$ARG_LOG"
download_dir="$runtime_dir/download directory"
__transfer_operands=(':/tmp/remote file' "$download_dir")
__ssh_option=()
__ssh_key=''
__scp_option=()
scp
mapfile -t download_args < <(read_command_args scp 1)
[[ ${#download_args[@]} == 2 ]]
[[ ${download_args[0]} == 'tester@203.0.113.10:/tmp/remote file' ]]
[[ ${download_args[1]} == "$download_dir" ]]

: > "$ARG_LOG"
__transfer_operands=("$source_dir" 'remote directory')
__rsync_option=(-a --delete)
__ssh_option=(-o 'ProxyCommand=ssh -W %h:%p bastion')
__ssh_key="$runtime_dir/key with spaces.pem"
rsync
mapfile -t rsync_args < <(read_command_args rsync 1)
printf -v expected_rsync_ssh '%q ' ssh "${__ssh_option[@]}" -i "$__ssh_key"
expected_rsync_ssh=${expected_rsync_ssh% }
[[ ${#rsync_args[@]} == 6 ]]
[[ ${rsync_args[0]} == -a ]]
[[ ${rsync_args[1]} == --delete ]]
[[ ${rsync_args[2]} == -e ]]
[[ ${rsync_args[3]} == "$expected_rsync_ssh" ]]
[[ ${rsync_args[4]} == "$source_dir" ]]
[[ ${rsync_args[5]} == 'tester@203.0.113.10:remote directory' ]]

__transfer_operands=(':/tmp/source' ':/tmp/destination')
if rsync >/dev/null 2>&1;then
  echo 'rsync must reject remote-to-remote transfers.' >&2
  exit 1
fi

echo 'SSH argument tests passed.'
