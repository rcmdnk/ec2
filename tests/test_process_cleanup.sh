#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-environment-process-cleanup.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
child_pid_file="$runtime_dir/child.pid"
child_stopped_file="$runtime_dir/child.stopped"
mkdir -p "$mock_bin"

cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" sts get-caller-identity "* ]]; then
  exit 0
fi
EOF
cat > "$mock_bin/packer" <<EOF
#!/usr/bin/env bash
case \${1:-} in
  version) echo 'Packer v-test' ;;
  init|validate) ;;
  build)
    (
      trap 'printf stopped > "$child_stopped_file"; exit 0' TERM INT HUP
      printf '%s\n' "\$BASHPID" > "$child_pid_file"
      while :; do sleep 1; done
    ) &
    wait \$!
    ;;
esac
EOF
chmod 755 "$mock_bin"/*

config="$runtime_dir/config"
cat > "$config" <<'EOF'
AWS_REGION=ap-northeast-1
CPU_ENABLED=1
GPU_ENABLED=0
CPU_OUTPUT_AMI_NAME=process-cleanup-test
CPU_SOURCE_AMI_ID=ami-source
AWS_SUBNET_IDS=subnet-process-cleanup-test
AMI_PROGRESS_POLL_DELAY_SECONDS=1
EOF
work=${runtime_dir#"$root/"}/work

PATH="$mock_bin:$PATH" bash environment/scripts/make_ami.sh "$work" "$config" \
  >"$runtime_dir/output" 2>&1 &
make_ami_pid=$!
for _ in {1..50}; do
  [[ -s "$child_pid_file" ]] && break
  sleep 0.1
done
[[ -s "$child_pid_file" ]] || {
  echo 'The mock Packer child process did not start.' >&2
  cat "$runtime_dir/output" >&2
  kill "$make_ami_pid" 2>/dev/null || true
  wait "$make_ami_pid" 2>/dev/null || true
  exit 1
}
child_pid=$(<"$child_pid_file")

kill -TERM "$make_ami_pid"
set +e
wait "$make_ami_pid"
make_ami_status=$?
set -e

[[ "$make_ami_status" == 130 ]] || {
  echo "SIGTERM did not produce the expected make_ami status: $make_ami_status" >&2
  cat "$runtime_dir/output" >&2
  exit 1
}
if kill -0 "$child_pid" 2>/dev/null; then
  echo 'The Packer child process survived make_ami termination.' >&2
  exit 1
fi

echo 'Process cleanup tests passed.'
