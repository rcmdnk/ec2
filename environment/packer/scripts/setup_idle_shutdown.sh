#!/usr/bin/env bash
set -euo pipefail
[[ -z "${AMI_IDLE_SHUTDOWN_BACKEND:-}" ]] && exit 0
cat > /usr/local/sbin/shutdown_if_idle <<EOF
#!/usr/bin/env bash
set -eu

has_login_user() {
  who | grep -q .
}

has_keepalive_process() {
  if [[ -z "${AMI_IDLE_SHUTDOWN_KEEPALIVE_PROCESSES:-}" ]]; then
    return 1
  fi
  ps -eo uid=,comm= |
      awk '\$1 != 0 && \$2 ~ /^(${AMI_IDLE_SHUTDOWN_KEEPALIVE_PROCESSES:-sshd})\$/ { found = 1 } END { exit !found }'
}

is_idle() {
  ! has_login_user && ! has_keepalive_process
}

# First check
if ! is_idle; then
  exit 0
fi

# Wait briefly and check again to avoid shutting down during a transient idle state
sleep 60

# Second check
if is_idle; then
  logger -t shutdown-if-idle "No login users, SSH sessions, screen, or tmux sessions found. Powering off."
  /usr/bin/systemctl poweroff
fi
EOF
chmod 755 /usr/local/sbin/shutdown_if_idle
if [[ "$AMI_IDLE_SHUTDOWN_BACKEND" == systemd ]]; then
  cat > /etc/systemd/system/shutdown.service <<EOF
[Unit]
Description=Power off idle instance

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/shutdown_if_idle
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
EOF
  cat > /etc/systemd/system/shutdown.timer <<EOF
[Unit]
Description=Check for idle instance

[Timer]
OnCalendar=${AMI_IDLE_SHUTDOWN_SCHEDULE:-hourly}

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now shutdown.timer
  systemctl start shutdown.timer
elif [[ "$AMI_IDLE_SHUTDOWN_BACKEND" == cron ]]; then
  cron_duration=${AMI_IDLE_SHUTDOWN_SCHEDULE:-hourly}
  cat << EOF > "/etc/cron.$cron_duration/shutdown"
#!/usr/bin/env bash
/usr/local/sbin/shutdown_if_idle
EOF
  chmod 755 "/etc/cron.$cron_duration/shutdown"
fi
