# EC2 environment setup

The `ec2` command can build Amazon EC2 AMIs with Packer, prepare optional shared
file systems, generate launch JSON and user-data, and install the resulting
configuration for its normal instance-management commands.

## Prerequisites

### On your machine

Install [the AWS CLI](https://aws.amazon.com/cli/). Install
[Packer](https://developer.hashicorp.com/packer) when you use `ec2 make_ami`.
[ShellCheck](https://github.com/koalaman/shellcheck) is needed only to run the
repository checks.

Configure an AWS CLI profile and set it as `AWS_PROFILE`. Authentication goes
through the normal credential chain; optionally set `AWS_AUTH_COMMAND` to a
local refresh command when credentials expire.
These local AWS credentials are not automatically written into user-data.
However, `INSTANCE_COPY_ENTRIES` and `INSTANCE_USER_DATA_EXTRA_SCRIPT` can
explicitly embed sensitive contents, so review generated user-data before launch.

### In AWS

This toolkit creates AMIs, EFS, FSx and io2 volumes, but it never creates the
network or identity resources around them - it only references them by ID. Set
these up once in the region you use as `AWS_REGION`, then put the IDs in
`~/.config/ec2/environment`.

| Prepare                           | Setting                    | Required          |
| --------------------------------- | -------------------------- | ----------------- |
| Subnet(s)                         | `AWS_SUBNET_IDS`           | for `ec2 setup`   |
| EC2 key pair                      | `EC2_KEY_NAME`             | for `ec2 setup`   |
| Private key path override         | `EC2_SSH_PRIVATE_KEY`      | no, see below     |
| Security group(s) in the same VPC | `AWS_SECURITY_GROUP_IDS`   | no, but see below |
| VPC                               | `AWS_VPC_ID`               | no                |
| IAM instance profile              | `AWS_IAM_INSTANCE_PROFILE` | no, but see below |

Every one of these can be given by name instead of by ID - `AWS_SUBNET_NAMES`,
`AWS_SECURITY_GROUP_NAMES`, `AWS_VPC_NAME` - and the environment commands resolve them before
anything else runs. The `*_IDS` form wins when both are set, and a name that
matches nothing or more than one resource is an error rather than a guess,
because Name tags are not unique in AWS. Security groups are matched on their
real `GroupName`, not on a Name tag; since group names are only unique within a
VPC, set `AWS_VPC_ID` too when the same name exists in several VPCs.

`AWS_REGION` is the only setting every environment command needs. `ec2 make_ami`
can build an AMI with nothing else: Packer picks a subnet in the default VPC, creates a
throwaway security group, and uses a temporary key pair of its own. Read the
security group note below before relying on that.

**VPC.** Every instance runs in one, but you do not have to name it. The subnet
determines the VPC, and Packer resolves it from `AWS_SUBNET_IDS` when `AWS_VPC_ID` is
empty - the only thing Packer wants the VPC for is a temporary security group,
which it never creates here because `AWS_SECURITY_GROUP_IDS` is always passed.
`ec2 setup` does not read `AWS_VPC_ID` at all. The account's default VPC is
therefore enough: pick a subnet in it and leave `AWS_VPC_ID` commented out. Set it
when you want Packer to fail early if the subnet and the security groups do not
belong to the VPC you expect.

**Subnets.** Needed by `ec2 setup`, which writes one launch JSON per subnet, and
by the file system scripts when they create something. One is enough; listing
several gives you a launch JSON per availability zone. Two file system kinds
constrain the count, and both checks run even when that kind is unused: io2
requires exactly one subnet, and FSx requires one for `SINGLE_AZ_*` and at
least two for `MULTI_AZ_*`. The subnet also needs outbound internet
access, because the Packer build installs packages from the distribution
mirrors and from `cli.github.com`, `rpm.releases.hashicorp.com`,
`dl.google.com` and `flathub.org`. Use a NAT gateway for a private subnet, or a
public subnet with auto-assign public IP.

**Security groups.** Optional, but leaving `AWS_SECURITY_GROUP_IDS` empty is a real
downgrade rather than a neutral default: Packer then builds a throwaway
security group authorised from `temporary_security_group_source_cidrs`, which
defaults to `0.0.0.0/0`, so inbound SSH is open to the internet for the length
of the build - and the launch JSON omits `Groups`, leaving instances on the VPC
default security group.

When you do set it, the same groups are attached to both the Packer build
instance and the launched instances, so they have to cover both. Inbound TCP 22
from wherever you run Packer and from wherever you SSH in; add UDP 60000-61000
if you use mosh, or TCP 2022 (by default) if you use Eternal Terminal. Outbound
HTTPS for the package installs, and outbound TCP 2049 when you mount EFS or FSx.
Note that `AMI_BUILD_SSH_INTERFACE` defaults to `private_ip`,
so the machine running Packer must reach the VPC privately - over a VPN, Direct
Connect, or from inside the VPC. Otherwise set it to `public_ip` with a public
subnet, or to `session_manager`.

**Key pair.** Create it in EC2 and put its name in `EC2_KEY_NAME`; `ec2 setup` puts
that name into the launch JSON. `EC2_SSH_PRIVATE_KEY` is optional. Set it to a local
private-key path only when you want the generated `ec2` configuration to pass
that key explicitly with `-i`, or as Eternal Terminal's `IdentityFile` SSH
option. Otherwise OpenSSH selects an identity from its defaults, `ssh-agent`, or
`~/.ssh/config`. Because `ec2` normally connects by IP address, any `Host` rule
must match that address or pattern. The private key never leaves your machine.
Packer creates and discards a temporary key pair of its own, so `make_ami` works
without either setting.

**Instance profile.** Optional, but the instance cannot use the AWS credential
chain without one. Required if you use io2 (`ec2:AttachVolume` from user-data),
an instance-side AWS configuration with `credential_source = Ec2InstanceMetadata`
(`sts:AssumeRole` on the target role, whose trust policy must allow this one),
IAM-authenticated EFS mounts, or `EC2_CONNECTION_METHOD=ssm`.

**Permissions for the identity running the commands.** Packer's own EC2 build
permissions, plus `ec2:DescribeImages` and `ec2:DescribeSubnets`, plus whatever
you enable. Looking a resource up by name costs a `Describe`/`List` call even
when you never create anything:

| Feature         | Look up by `*_NAMES`                    | Create with `CREATE_FILE_SYSTEMS=1`                                                                                                               |
| --------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| EFS             | `elasticfilesystem:DescribeFileSystems` | `elasticfilesystem:CreateFileSystem`, `elasticfilesystem:CreateMountTarget`, `elasticfilesystem:TagResource`, `elasticfilesystem:PutBackupPolicy` |
| FSx             | `fsx:DescribeFileSystems`               | `fsx:CreateFileSystem`, `fsx:TagResource`                                                                                                         |
| io2             | `ec2:DescribeVolumes`                   | `ec2:CreateVolume`, `ec2:CreateTags`                                                                                                              |
| S3-backed       | `s3files:ListFileSystems`               | not supported - they must already exist                                                                                                           |
| Subnets         | `ec2:DescribeSubnets`                   | -                                                                                                                                                 |
| Security groups | `ec2:DescribeSecurityGroups`            | -                                                                                                                                                 |
| VPC             | `ec2:DescribeVpcs`                      | -                                                                                                                                                 |
| Route tables    | `ec2:DescribeRouteTables`               | -                                                                                                                                                 |

When `AWS_IAM_INSTANCE_PROFILE` is set you also need `iam:PassRole` for that role -
both Packer and `run-instances` fail without it.

**Depending on what you enable.** Creating EFS or FSx needs its own security
group allowing inbound TCP 2049 from `AWS_SECURITY_GROUP_IDS`
(`EFS_SECURITY_GROUP_IDS`, `FSX_SECURITY_GROUP_IDS`). A `MULTI_AZ_*` FSx
deployment needs route tables (`FSX_ROUTE_TABLE_IDS`). S3-backed file systems
(`S3FILES_*`) are never created here and must already exist. GPU instance types
need a non-zero "Running On-Demand G and VT instances" service quota, which is
0 on new accounts.

## Getting started

```sh
ec2 init_environment
$EDITOR ~/.config/ec2/environment
```

The generated environment file documents every setting and is the reference
for what each one does. Almost everything in it is commented out and shows the
default value; the uncommented lines are the ones you have to inspect. Settings
marked `# REQUIRED` have no default, and the command refuses to run until all of
them are set, listing every missing one at once. The repository copy is
available at [`environment/environment.example`](../environment/environment.example).

## Workflow

Build one or both AMI families selected in the environment file:

```sh
ec2 make_ami
```

To generate the launch JSON and install the resulting `ec2` configuration after
all enabled AMI builds complete, add `--setup`:

```sh
ec2 make_ami --setup
```

The setup phase runs only when every AMI build succeeds. Setup options such as
`--install-config 0` can be supplied on the same command line.

Packer is invoked with `AMI_PACKER_ON_ERROR=cleanup` by default. If a failed
build still leaves an AMI or build instance identifiable in the Packer log, its
ID is recorded in the resource manifest. Review and remove such resources with:

```sh
ec2 cleanup_resources
ec2 cleanup_resources --execute 1
```

AMI cleanup also attempts to remove its associated snapshots, but only after
verifying their `ManagedBy` tag.

Prepare shared filesystems and generate one launch JSON per enabled AMI and
subnet:

```sh
ec2 setup
```

By default, build and generated files are placed under `~/.config/ec2/work`.
`ec2 setup` then installs the generated command configuration as
`~/.config/ec2/config`, where normal `ec2` commands read it. Use
`--install-config 0` to generate files without installing that configuration.
Override the paths when needed:

```sh
ec2 setup --workdir /path/to/work --environment-config /path/to/environment
```

Existing resource IDs can be provided in the environment file; otherwise named
resources are looked up, and created when
`CREATE_FILE_SYSTEMS=1` and enough settings are present. A newly created EFS or
FSx file system is not usable immediately - the scripts say so when they create
one, and the generated mounts use `nofail` so a launch during that window still
boots.

`AWS_SUBNET_IDS` accepts several subnets, which produces one launch JSON per subnet
per enabled AMI family. Two of the file system kinds constrain the count, and
both checks run even when that kind is unused: io2 requires exactly one subnet,
and FSx requires one for `SINGLE_AZ_*` and at least two for `MULTI_AZ_*`. io2
and FSx therefore cannot be combined with a `MULTI_AZ_*` deployment.

io2 volumes created or accepted by this toolkit must have Multi-Attach enabled.
AWS Multi-Attach allows an `io1` or `io2` volume to be attached to multiple
Nitro instances in the same Availability Zone, but XFS and ext4 are not
cluster-aware filesystems. Do not mount them read-write from multiple instances
at the same time; use a clustered filesystem with the required locking, or use
EFS/FSx for ordinary shared files. Blank Multi-Attach volumes are not formatted
automatically by user-data, so initialize them deliberately before use.

The generated user-data must fit EC2's 16 KB limit before API Base64 encoding.
When gzip is selected, the compressed payload is measured; with plain text, the
uncompressed script is measured. `ec2 setup` warns past 80% and fails past the
limit. Compression does not encrypt user-data. Move long setup into the AMI,
`AMI_PROVISION_SCRIPTS`, or `USER_ENV_INSTALLER_SCRIPTS` if you hit the limit.

### Use an existing AMI

You can skip `ec2 make_ami` when the configured AMI already exists in your AWS
account. Set `CPU_OUTPUT_AMI_NAME` and, when enabled, `GPU_OUTPUT_AMI_NAME` to the existing
AMI names, then run `ec2 setup`. The setup command resolves the newest matching
self-owned AMI and writes its ID into the generated launch JSON.

For an AMI that is not owned by your account, create the normal
`~/.config/ec2/config` and launch JSON manually as described in the
[main README](../README.md#manage-configuration-manually).

## Generated files

With the default paths, environment commands produce:

```text
~/.config/ec2/
├── environment                  # input edited by the user
├── config                       # installed output read by normal ec2 commands
└── work/
    ├── packer/                  # Packer templates, variables, manifests, logs
    ├── ec2/
    │   ├── config               # setup output before installation
    │   ├── cli_input_json/      # one launch JSON per family and subnet
    │   ├── user_data.sh
    │   └── user_data.sh.gz
    └── resources.tsv            # resources created by environment commands
```

Before it calls AWS, `ec2 setup` checks the destination
`~/.config/ec2/config`. It updates a configuration previously generated by
`ec2 setup`, but refuses to replace a hand-written file or symbolic link. Use
`--replace-config 1` to replace one intentionally; the existing entry is first
preserved as a timestamped backup. Use `--install-config 0` when you only want
the files under the work directory.

## Hooks and security

Set `INSTANCE_USER_DATA_EXTRA_SCRIPT` to a local shell script for site-specific
setup. The hook is copied into generated user-data, so review it before launching. Do not
put access keys, API keys, private keys, or other secrets in the hook or
configuration. The hook runs as root. `INSTANCE_COPY_ENTRIES` can also copy
local files into the instance, but their contents are embedded in user-data.
Use an instance profile and the AWS CLI credential chain where possible.

`EC2_USER_DATA_URI` is both the URI handed to the `ec2` command and the source of
the local output path: `ec2 setup` strips the scheme to decide where to write
the script, and a `.gz` suffix additionally makes it gzip the result. Use
`fileb://` for the compressed form and `file://` for plain text.

The generated user-data and its `.gz` are written with restrictive permissions
but this protects only the local files before launch. Anything embedded in
them is readable from inside the launched instance through the instance
metadata service. Base64 and gzip provide encoding and compression, not
confidentiality.

## Validation

Install `shellcheck`.

Run the repository checks with:

```sh
bash tests/test_shell.sh
```

The test script runs `bash -n` and `shellcheck` over every script, checks that
an untouched `environment/environment.example` is rejected for its unset required settings, that
a filled-in copy loads cleanly, and that no script reads a variable that nothing
defines. It never contacts AWS.

## Resource cleanup

Created AMIs, EFS file systems, FSx file systems, and io2 volumes are tagged
with `ManagedBy=ec2-environment` and recorded by exact ID in
`RESOURCE_MANIFEST` (default: `<WORKDIR>/resources.tsv`). Set the optional
project, owner, and expiry settings in the environment file to make cost
ownership visible.

Review the deletion plan without changing AWS:

```sh
ec2 cleanup_resources
```

Apply that exact-ID plan explicitly:

```sh
ec2 cleanup_resources --execute 1
```

Before each deletion the command reads the resource from AWS and refuses it
unless its `ManagedBy` tag matches `RESOURCE_MANAGED_BY`. Successfully deleted
entries are removed from the manifest; failures remain for a later retry.
