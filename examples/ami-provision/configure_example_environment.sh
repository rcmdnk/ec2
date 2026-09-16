#!/usr/bin/env bash
set -euo pipefail

# AMI_PROVISION_SCRIPTS are run as root after the built-in AMI provisioning
# steps. This example makes a value available to every interactive shell.
install -d -m 0755 /etc/profile.d
install -m 0644 /dev/null /etc/profile.d/ec2-environment-example.sh
cat >/etc/profile.d/ec2-environment-example.sh <<'EOF'
export EC2_ENVIRONMENT_EXAMPLE=1
EOF
