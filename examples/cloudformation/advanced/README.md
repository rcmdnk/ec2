# Advanced CloudFormation example

This profile creates a separate network for a work/job workflow:

- public subnets for the AMI build path
- private work subnets in two Availability Zones
- private job subnets in two Availability Zones
- a NAT Gateway for package installation and SSM
- FSx for OpenZFS with a Multi-AZ deployment
- SSM and IAM instance profile access

The NAT Gateway and FSx filesystem are intentionally included to demonstrate
the production-like layout. They are more expensive than the Quickstart
resources.

## Run

Choose two Availability Zones in the target region and use a narrow CIDR for
the AMI build machine:

```sh
./bootstrap.sh \
  --region ap-northeast-1 \
  --availability-zones ap-northeast-1a,ap-northeast-1c \
  --ssh-cidr 203.0.113.10/32
```

The script writes state to `~/.config/ec2/advanced/` and generates the work
environment:

```sh
state=$HOME/.config/ec2/advanced
ec2 make_ami --environment-config "$state/environment" --setup
ec2 launch -t t3.medium
ec2 ssh
```

The generated work environment mounts FSx at `/mnt/fsx`. A second
`environment-job` file is generated with the private job subnets. Set up both
configurations when you want `ec2 submit` to launch jobs separately from work
instances:

```sh
ec2 setup --environment-config "$state/environment" \
  --workdir "$state/work"
ec2 setup --environment-config "$state/environment-job" \
  --workdir "$state/job"
ec2 --config "$state/job/ec2/config" submit -t c8i.large ./run.sh
```

Both environments mount FSx at `/mnt/fsx`; the work environment uses SSM for
interactive access and the job environment uses the private job subnets.

## Cleanup

Terminate work and job instances before deleting the stack. This removes the
custom VPC, NAT Gateway, FSx filesystem, IAM resources, and security groups.

```sh
./cleanup.sh --region ap-northeast-1
rm -rf "$HOME/.config/ec2/advanced"
```

The cleanup script asks for confirmation unless `--yes` is supplied.
