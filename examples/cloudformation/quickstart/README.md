# Quickstart CloudFormation example

This profile is the shortest path to a working `ec2` environment. It uses the
default VPC and a public subnet, creates an encrypted EFS filesystem, and gives
instances an SSM instance profile. The AMI build and the launched work instance
use a small CPU instance type by default.

## Run

Use a narrow CIDR for the machine that runs the AMI build. Do not use
`0.0.0.0/0` unless this is an isolated test account.

```sh
./bootstrap.sh \
  --region ap-northeast-1 \
  --ssh-cidr 203.0.113.10/32
```

The script writes state to `~/.config/ec2/quickstart/` and generates an
environment file. Build the AMI and launch the work instance:

```sh
state=$HOME/.config/ec2/quickstart
ec2 make_ami --environment-config "$state/environment" --setup
ec2 launch -t t3.medium
ec2 ssh
```

The generated environment mounts EFS at `/mnt/efs` and uses
`/mnt/efs/ec2` as the persistent environment root.

## Cleanup

Terminate any instances first, then delete the stack. The script keeps the
local key and environment until you remove them deliberately.

```sh
./cleanup.sh --region ap-northeast-1
rm -rf "$HOME/.config/ec2/quickstart"
```

The default VPC is never deleted by this example.
