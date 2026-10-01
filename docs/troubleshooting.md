# Troubleshooting

## Wrong account or region

Check the active AWS identity and region before inspecting resources:

```
aws sts get-caller-identity
aws configure get region
ec2 version
```

Use the configured AWS profile and region consistently. If a command shows no
instances, verify the profile, region, VPC, subnet, and Name filters first.

## Authentication and SSO

Credential refresh commands run locally. Run the refresh command manually, then
retry the ec2 command. Avoid putting credentials in environment files or user-data.

## Launch and AMI failures

Inspect generated files under ~/.config/ec2/work, especially launch JSON, Packer
output, and generated user-data. Confirm the AMI architecture matches the instance
type and that subnet security groups allow the chosen connection method.

## SSH/SSM readiness

Confirm the instance is running, has the expected public/private address, and has
the correct key or SSM permissions. A successful AWS launch does not imply that
cloud-init, the SSH daemon, or SSM is ready.

## Jobs and stale records

Use ec2 jobs to inspect the persistent job list. A machine crash can leave a
record behind; verify the PID and instance ID before deleting anything. Do not
kill a reused local PID.

## Shared filesystem mounts

Check /etc/fstab, mount, and generated user-data. Confirm mount-target security
groups allow the required NFS traffic and that the instance is in a subnet/AZ
covered by the filesystem.

## Cleanup

cleanup_resources is dry-run by default. Review its plan and manifest before using
--execute. Resources are deleted only when ownership metadata or a configured
cleanup hook verifies that they belong to this environment.
