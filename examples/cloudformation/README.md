# CloudFormation examples

These examples create the AWS resources around `ec2` and then render an
environment file for the normal `ec2 make_ami`, `ec2 setup`, `ec2 launch`, and
`ec2 submit` workflow. They are deliberately separate because the two profiles
have different cost, networking, and cleanup characteristics.

## Choose a profile

| Profile                            | Use when                      | Main resources                                                  |
| ---------------------------------- | ----------------------------- | --------------------------------------------------------------- |
| [Quickstart](quickstart/README.md) | You want to try `ec2` quickly | Default VPC, public subnet, EFS, SSM, small CPU work instance   |
| [Advanced](advanced/README.md)     | You want a work/job layout    | Custom VPC, private subnets, NAT, FSx for OpenZFS, multiple AZs |

Both examples create an SSH key locally and import its public key into EC2.
The generated environment uses SSM for interactive sessions, but the key is
also required by the current `ec2 setup` launch configuration.

Every example creates billable AWS resources. Run its cleanup script when done.
