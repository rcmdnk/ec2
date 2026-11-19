#!/usr/bin/env bash
# delete_job must never act on a job it was not asked for, and submit must
# never wait forever for an instance which does not come back.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-job-safety.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
mock_state="$runtime_dir/state"
xdg_config="$runtime_dir/xdg"
config="$runtime_dir/config"
aws_log="$runtime_dir/aws.log"
ssh_log="$runtime_dir/ssh.log"
job_list="$xdg_config/ec2/job_list"
output="$runtime_dir/output"
mkdir -p "$mock_bin" "$mock_state" "$xdg_config/ec2" "$runtime_dir/home"

instance_id=i-0aaaaaaaaaaaaaaa1

cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AWS_LOG"
state_file="$MOCK_STATE/instance_state"
mode=$(cat "$MOCK_STATE/aws_mode" 2>/dev/null || true)
case " $* " in
  *" ec2 run-instances "*)
    cat "$MOCK_STATE/initial_state" > "$state_file"
    printf 'job-1\ti-0aaaaaaaaaaaaaaa1\t10.0.0.5\tt3.micro\n'
    ;;
  *" ec2 describe-instances "*SpotInstanceRequestId*) ;;
  *" ec2 describe-instances "*StateTransitionReason*)
    printf '%s\t\n' "$(cat "$state_file" 2>/dev/null)"
    ;;
  *" ec2 describe-instances "*)
    [ -f "$state_file" ] || exit 0
    if [ "$mode" = "list_fails" ];then
      echo 'An error occurred (InternalError) when calling the DescribeInstances operation' >&2
      exit 254
    fi
    state=$(cat "$state_file")
    [ "$state" = "terminated" ] && exit 0
    printf 'job-1\ti-0aaaaaaaaaaaaaaa1\t10.0.0.5\t%s\tt3.micro\tspot\tus-east-1a\n' "$state"
    ;;
  *" ec2 start-instances "*)
    echo 'An error occurred (IncorrectSpotRequestState) when calling the StartInstances operation' >&2
    exit 254
    ;;
  *" ec2 terminate-instances "*)
    if [ "$mode" = "terminate_fails" ];then
      echo 'An error occurred (UnauthorizedOperation) when calling the TerminateInstances operation' >&2
      exit 254
    fi
    echo terminated > "$state_file"
    ;;
esac
EOF

cat > "$mock_bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SSH_LOG"
if [[ " $* " == *" -G "* ]];then
  printf 'serveraliveinterval 0\nconnecttimeout none\n'
  exit 0
fi
case "$(cat "$MOCK_STATE/ssh_mode")" in
  ok) ;;
  hang) sleep 300 ;;
  *) exit 255 ;;
esac
EOF
chmod 755 "$mock_bin"/*

# The configured instance name filter equals a job name on purpose: it must
# never be taken as a job selector.
cat > "$config" <<'EOF'
name_filter=job
ssh_user=tester
EOF
printf '{}\n' > "$runtime_dir/launch.json"

# setsid detaches the controlling terminal so that the non-interactive paths
# are exercised even when the tests are started from a terminal.
detach=()
if type setsid >/dev/null 2>&1;then
  detach=(setsid -w)
fi

run_ec2 () {
  HOME="$runtime_dir/home" XDG_CONFIG_HOME="$xdg_config" AWS_LOG="$aws_log" \
    SSH_LOG="$ssh_log" MOCK_STATE="$mock_state" PATH="$mock_bin:$PATH" \
    "${detach[@]}" timeout 120 bin/ec2 --config "$config" "$@" < /dev/null
}

fail () {
  echo "$1" >&2
  [ ! -f "$output" ] || cat "$output" >&2
  exit 1
}

# PIDs beyond any real pid_max, so that no process is ever signalled.
jobs_fixture=$(cat <<EOF
99900123 2026-11-18 14:00:00 model_resp i-0bbbbbbbbbbbbbbb1 10.0.0.1 running
99900124 2026-11-18 14:00:01 model_resp_long i-0bbbbbbbbbbbbbbb2 10.0.0.2 running
999001230 2026-11-18 14:00:02 other-99900123 i-0bbbbbbbbbbbbbbb3 10.0.0.3 running
99900125 2026-11-18 14:00:03 job - - waiting
EOF
)

reset_jobs () {
  printf '%s\n' "$jobs_fixture" > "$job_list"
  : > "$aws_log"
}

expect_untouched () {
  [ "$(cat "$job_list")" = "$jobs_fixture" ] || fail "$1: the job list was modified."
  ! grep -q 'terminate-instances' "$aws_log" || fail "$1: an instance was terminated."
}

# A name which matches no job is an error, not a reason to pick another job.
reset_jobs
if run_ec2 delete_job -f od-v0.19.22-not-submitted-yet > "$output" 2>&1;then
  fail 'delete_job -f with no matching job must fail.'
fi
grep -q 'No job matches the name' "$output" || fail 'delete_job -f must report the unmatched name.'
expect_untouched 'delete_job -f <no match>'

# Without a target and without a terminal nothing may be selected.
reset_jobs
if run_ec2 delete_job > "$output" 2>&1;then
  fail 'delete_job without a target must fail when there is no terminal.'
fi
expect_untouched 'delete_job without a terminal'

# An ambiguous name is refused without a terminal.
reset_jobs
if run_ec2 delete_job -f model_res > "$output" 2>&1;then
  fail 'delete_job -f with several matching jobs must fail without a terminal.'
fi
grep -q 'matches several jobs' "$output" || fail 'delete_job -f must report an ambiguous name.'
expect_untouched 'delete_job -f <ambiguous>'

# Unknown and malformed PIDs delete nothing.
reset_jobs
if run_ec2 delete_job 999 > "$output" 2>&1;then
  fail 'delete_job with an unknown PID must fail.'
fi
expect_untouched 'delete_job <unknown PID>'
if run_ec2 delete_job model_resp > "$output" 2>&1;then
  fail 'delete_job with a non-numeric PID must fail.'
fi
expect_untouched 'delete_job <non-numeric PID>'

# --dry-run only shows the target.
reset_jobs
run_ec2 --dry-run 1 delete_job -f model_resp_long > "$output" 2>&1 || fail 'delete_job --dry-run failed.'
grep -q 'Dry run: Deleting job: 99900124 ' "$output" || fail 'delete_job --dry-run must show the target.'
expect_untouched 'delete_job --dry-run'

# An exact name deletes exactly that job, even when it is a prefix of another.
reset_jobs
run_ec2 delete_job -f model_resp > "$output" 2>&1 || fail 'delete_job -f <exact name> failed.'
expected=$(printf '%s\n' "$jobs_fixture" | grep -v '^99900123 ')
[ "$(cat "$job_list")" = "$expected" ] || fail 'delete_job -f <exact name> must remove only that job.'
[ "$(grep -c 'terminate-instances' "$aws_log")" = 1 ] || fail 'delete_job -f must terminate exactly one instance.'
grep -q 'terminate-instances --instance-ids i-0bbbbbbbbbbbbbbb1' "$aws_log" ||
  fail 'delete_job -f terminated the wrong instance.'

# A PID is matched as a whole field: 99900123 must not touch 999001230 or a
# job whose name contains the number.
reset_jobs
run_ec2 delete_job 99900123 > "$output" 2>&1 || fail 'delete_job <PID> failed.'
[ "$(cat "$job_list")" = "$expected" ] || fail 'delete_job <PID> must remove only that job.'
[ "$(grep -c 'terminate-instances' "$aws_log")" = 1 ] || fail 'delete_job <PID> must terminate exactly one instance.'

# A job without an instance is removed without any instance operation.
reset_jobs
run_ec2 delete_job 99900125 > "$output" 2>&1 || fail 'delete_job for a waiting job failed.'
! grep -q '^99900125 ' "$job_list" || fail 'delete_job must remove a waiting job.'
[ ! -s "$aws_log" ] || fail 'delete_job for a waiting job must not call AWS.'

# --- submit ------------------------------------------------------------------

submit_job () {
  : > "$job_list"
  : > "$aws_log"
  : > "$ssh_log"
  command rm -f "$mock_state/instance_state"
  run_ec2 --submit-command 1 --cli-input-json "$runtime_dir/launch.json" \
    --submit-name job-1 --submit-ready-timeout 1 "$@" submit -- true > "$output" 2>&1
}

expect_cleared () {
  [ ! -s "$job_list" ] || fail "$1: the job was left in the job list."
  grep -q "terminate-instances --instance-ids $instance_id" "$aws_log" ||
    fail "$1: the instance was not terminated."
}

# A normal job runs with keep-alive probing so that a vanished instance ends
# the ssh session instead of blocking it forever.
echo running > "$mock_state/initial_state"
echo ok > "$mock_state/ssh_mode"
: > "$mock_state/aws_mode"
submit_job || fail 'submit failed for a healthy instance.'
grep 'RUN STARTED' "$ssh_log" | grep -q 'ServerAliveInterval=30' ||
  fail 'submit must run the job with ServerAliveInterval.'
grep -q 'finishing job: .* return code: 0' "$output" || fail 'submit did not finish the job.'
expect_cleared 'submit'

# An instance which never becomes reachable ends the attempt.
echo fail > "$mock_state/ssh_mode"
submit_job || true
grep -q 'was not ready within 1 seconds' "$output" || fail 'submit must give up on an unreachable instance.'
! grep -q 'RUN STARTED' "$ssh_log" || fail 'submit must not run the job on an unreachable instance.'
expect_cleared 'submit with an unreachable instance'

# A probe which connects but never returns is cut off by the same limit.
if type timeout >/dev/null 2>&1;then
  echo hang > "$mock_state/ssh_mode"
  submit_job || true
  grep -q 'was not ready within 1 seconds' "$output" || fail 'submit must give up on a hanging readiness probe.'
  expect_cleared 'submit with a hanging readiness probe'
fi

# A spot instance stopped by an interruption which cannot be started again
# must not be waited for forever.
echo stopped > "$mock_state/initial_state"
echo ok > "$mock_state/ssh_mode"
submit_job || true
grep -q "Instance $instance_id state: stopped" "$output" || fail 'submit must report the stopped instance.'
grep -q 'was not ready within 1 seconds' "$output" || fail 'submit must give up on a stopped spot instance.'
expect_cleared 'submit with a stopped spot instance'

# With retries the failed attempt is replaced by a new launch.
submit_job --submit-n-retry-ssh 2 --submit-retry-ssh-interval 0 || true
[ "$(grep -c 'ec2 run-instances' "$aws_log")" = 2 ] || fail 'submit must relaunch after a failed attempt.'
expect_cleared 'submit with retries'

# An error exit from a helper still clears the job and its instance.
echo running > "$mock_state/initial_state"
echo list_fails > "$mock_state/aws_mode"
if submit_job;then
  fail 'submit must fail when AWS calls fail.'
fi
expect_cleared 'submit with an AWS failure'

# When the instance cannot be terminated the job stays traceable, and no
# replacement is launched while the previous instance may still be alive.
echo running > "$mock_state/initial_state"
echo fail > "$mock_state/ssh_mode"
echo terminate_fails > "$mock_state/aws_mode"
if submit_job --submit-n-retry-ssh 3 --submit-retry-ssh-interval 0;then
  fail 'submit must fail when its instance cannot be terminated.'
fi
grep -q " job-1 $instance_id 10.0.0.5 terminate_failed\$" "$job_list" ||
  fail 'submit must keep the job with its instance when termination fails.'
[ "$(grep -c 'ec2 run-instances' "$aws_log")" = 1 ] ||
  fail 'submit must not relaunch while the previous instance cannot be terminated.'

# delete_job keeps such a job too, and removes it once termination works.
if run_ec2 delete_job -f job-1 > "$output" 2>&1;then
  fail 'delete_job must fail when the instance cannot be terminated.'
fi
grep -q " job-1 $instance_id 10.0.0.5 delete_failed\$" "$job_list" ||
  fail 'delete_job must keep the job when termination fails.'
: > "$mock_state/aws_mode"
run_ec2 delete_job -f job-1 > "$output" 2>&1 || fail 'delete_job failed after termination recovered.'
[ ! -s "$job_list" ] || fail 'delete_job must remove the job once its instance is terminated.'

echo 'Job safety tests passed.'
