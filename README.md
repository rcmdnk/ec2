# ec2

AWS CLI wrapper for EC2 management.

## Requirement

- [AWS CLI](https://aws.amazon.com/cli/)
- [Packer](https://developer.hashicorp.com/packer) (`make_ami` only)

## Installation

Use Homebrew:

```
$ brew install rcmdnk/rcmdnkpac/ec2
```

If you have not installed `awscli` by Homebrew, it is also installed.

Or put `bin/ec2` anywhere in the PATH.
(In this case, you need to install `awscli` by yourself.)

## Getting started

The basic workflow is to build an AMI with the software you need, launch and
manage instances from that AMI, and connect to them with familiar tools such as
SSH, [Mosh](https://mosh.org/), or [Eternal Terminal](https://eternalterminal.dev/).
For batch work, use `ec2 submit` to start an instance only for the duration of a
job. Put the code, inputs, outputs, and persistent user environment on a shared
file system so a newly launched instance can use the same files immediately.

First create and edit the environment configuration. Set the AWS, AMI, and
network settings you need; configure EFS, FSx, or another shared file system if
you want jobs to share files between instances:

```sh
$ ec2 init_environment
$ $EDITOR ~/.config/ec2/environment
```

Build the AMI and generate the launch configuration:

```sh
$ ec2 make_ami --setup
```

Use a small instance for everyday work. It can be launched, inspected, and
managed with the normal commands:

```sh
$ ec2 launch -t t3.medium
$ ec2 ssh
```

You can use `ec2 mosh` or `ec2 et` instead when those clients and services are
configured.

When a larger machine is needed, keep the job directory on the shared file
system and submit the job from there. `ec2 submit` launches a fresh instance,
runs the job, and terminates it when the job finishes by default:

```sh
$ cd /mnt/fsx/jobs/my-job
$ ec2 submit -t c8i.4xlarge --submit-current-dir 1 ./run.sh
```

This makes the instance size and lifetime match the job instead of the
interactive work. You can keep a small instance running for normal tasks and
start larger, short-lived instances only when required, while the shared file
system preserves the working environment, inputs, and outputs. See [Shared file
systems](#shared-file-systems) and [Submit jobs with temporary
instances](#submit-jobs-with-temporary-instances) for configuration details.

## AWS CLI Profile

If you want to use a profile other than the default,
use `--aws-profile`, set `aws_profile` in the configuration file or
set:

```
export AWS_PROFILE=xxx
```

before using ec2.

## Configuration

Use **~/.config/ec2/config** by default. A different configuration file can be
selected with `--config`:

```
ec2 --config ~/.config/ec2/work-config instances
```

Options can be set like:

```
name_filter=my-instance
```

`#` can be used to comment out the line.

Available options are same as the command line options starting with `--`, but without `--` and `-` is replaced by `_`,
i.e., `aws_profile` for `--aws-profile`.

## Manage configuration manually

If you already have an AMI and the required AWS resources, create
`~/.config/ec2/config` directly. For example:

```
name_filter=my-instances
image_name_filter=my-ami
ssh_user=ec2-user
aws_profile=my-profile
cli_input_json=~/.config/ec2/cli_input_json/my-instance.json
```

This limits instance listings to names containing `my-instances`, uses the
configured user for `ec2 ssh`, `ec2 mosh`, and `ec2 et`, and selects the AWS CLI profile.
Omit `aws_profile` to use the default AWS credential chain. OpenSSH normally
selects the identity from its defaults, `ssh-agent`, or `~/.ssh/config`. Add
`ssh_key=~/.ssh/my_ssh.pem` only when you want `ec2` to pass that key explicitly
with `-i`. Because `ec2` normally connects by IP address, any `Host` rule must
match that address or pattern.

Write multiple SSH arguments as a one-line Bash array in the configuration.
Each element is passed without another round of word splitting. `ec2 rsync`
uses the array to construct its SSH transport, and `ec2 scp` converts SSH's
lowercase `-p PORT` to scp's uppercase `-P PORT`. `ec2 et` forwards `-o VALUE`
and `-i KEY` through Eternal Terminal's `--ssh-option` interface:

```
ssh_option=(-o StrictHostKeyChecking=no -o 'ProxyCommand=ssh -W %h:%p bastion')
```

On the command line, repeat the option once per SSH argument:

```
$ ec2 mosh --ssh-option -o --ssh-option 'ProxyCommand=ssh -W %h:%p bastion'
```

Eternal Terminal-specific arguments use `et_option` in the configuration or a
repeated `--et-option` on the command line:

```
et_option=(--keepalive 30)
$ ec2 et
```

The local `et` client must be installed, the Eternal Terminal service must be
running on the instance, and its TCP port must be reachable (2022 by default).
ET also uses SSH for its initial handshake, so normal SSH access must work.

scp- and rsync-specific arguments use arrays of their own. `scp` defaults to
recursive copies (`-r`), and `rsync` defaults to archive mode (`-a`). Set the
corresponding option array to `()` to disable its default. Do not put `-e`/`--rsh`
in `rsync_option`, because `ec2` constructs the remote shell from `ssh_option`
and `ssh_key`:

```
scp_option=(-r -p)
rsync_option=(-a --delete)
```

To launch your prepared AMI without `ec2 setup`, create the referenced launch
JSON yourself:

```
{
  "ImageId": "ami-0123456789abcdef0",
  "InstanceType": "t3.medium",
  "KeyName": "my-key",
  "SecurityGroupIds": ["sg-0123456789abcdef0"],
  "SubnetId": "subnet-0123456789abcdef0"
}
```

The launch JSON is unnecessary when you only want to manage existing
instances. After creating the configuration, normal commands can be used
immediately:

```
$ ec2 instances
$ ec2 launch
$ ec2 ssh
```

## AMI builds and environment setup

Environment commands use a separate Bash configuration file so that their
upper-case provisioning settings do not conflict with the generated `ec2`
configuration:

```
~/.config/ec2/environment  # input for make_ami and setup
~/.config/ec2/config       # generated by setup and read by other commands
```

Create the documented environment template, edit its required settings, and
run the environment commands:

```
$ ec2 init_environment
$ $EDITOR ~/.config/ec2/environment
$ ec2 make_ami --setup
```

AWS prerequisites, IAM permissions, network requirements, file-system setup,
security notes, and resource cleanup are documented in the
[environment setup guide](docs/environment-setup.md).

The default working directory is `~/.config/ec2/work`, independent of the
directory where the command is run. Override the defaults when needed:

```
$ ec2 make_ami --workdir /path/to/work --environment-config /path/to/environment
$ ec2 setup --workdir /path/to/work --environment-config /path/to/environment
```

`setup` generates launch JSON and user-data under the working directory, then
atomically installs the generated configuration as `~/.config/ec2/config`.
It replaces configurations previously generated by `ec2 setup`, but refuses to
replace a hand-written file or symbolic link. To replace one intentionally,
use `--replace-config 1`; the previous file is retained as a timestamped backup.
Use `--install-config 0` to generate artifacts without changing the default
configuration.

Review generated user-data before launching. `INSTANCE_COPY_ENTRIES` and
`INSTANCE_USER_DATA_EXTRA_SCRIPT` can embed local file contents or root-run
commands in user-data, which is readable from inside the instance through the
instance metadata service. Prefer an instance profile for AWS credentials.

The Packer scripts and the environment template are embedded in `bin/ec2`.
They are extracted to a temporary directory when an environment command runs,
so a copied `bin/ec2` has no runtime dependency on this source tree.

## Launch new instance

```
$ ec2 -t r3.large launch
```

If you give `-t select`, you can choose the instance type from the list.

You can pass the template name by `-T <your template>`, too.

## Connect to an instance

Use `ec2 ssh` for a normal interactive SSH session. `ec2 mosh` provides a more
resilient interactive connection when the network changes using
[Mosh](https://mosh.org/), and `ec2 et` uses
[Eternal Terminal](https://eternalterminal.dev/) when `et` is installed locally
and its service is running on the instance. All three commands use the instance
and SSH settings from the generated configuration; they require the instance
to be reachable and SSH access to be configured.

```sh
$ ec2 ssh
$ ec2 mosh
$ ec2 et
```

## Transfer files

Prefix an instance-side path with `:`. This supports uploads and downloads while
the instance host and SSH user continue to come from the normal selection and
configuration:

```
$ ec2 scp ./build/ :/tmp/build/
$ ec2 scp :/var/log/app.log ./logs/
$ ec2 rsync ./src/ :/srv/app/src/
$ ec2 rsync :/srv/app/output/ ./output/
```

For compatibility, `ec2 scp FILE` uploads to the remote home directory. If no
path has a `:` prefix, the final path is treated as the remote destination, so
`ec2 rsync SOURCE DESTINATION` is an upload. Use `--` before paths beginning
with a dash.

`rsync` must be installed both locally and on the instance. Repeat
`--scp-option` or `--rsync-option` to pass command-specific arguments, or place
the corresponding arrays in `~/.config/ec2/config`.

## Shared file systems

Configure shared storage in the environment file with the provider's `*_IDS`
or `*_NAMES` setting and its corresponding `*_MOUNT_POINTS`. `ec2 setup`
resolves (or, when explicitly enabled, creates) the configured S3-backed file
systems, EFS, and FSx file systems, then writes their mounts into the generated
user-data. The AMI build and `ec2 setup` therefore form one environment: an
instance launched with `ec2 launch` and a temporary instance launched by
`ec2 submit` receive the same configured mounts.

Set these filesystem settings before running `ec2 setup`; they are carried into
the generated launch JSON and user-data. After the AMI and configuration have
been created, both ordinary instances and submitted job instances use the same
mount points automatically.

This is deliberately different from an EBS volume. The configured io2 volume
is attached to one instance at a time by this toolkit and is not a replacement
for shared storage. AWS supports [EBS Multi-Attach for io1/io2](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volumes-multi.html)
in the same Availability Zone, but ordinary XFS and ext4 file systems must not
be mounted read-write by multiple instances; a clustered file system and
coordinated locking are required. This project does not configure Multi-Attach,
so use EFS, FSx, or S3-backed storage when multiple instances need the same
files.

As a practical rule of thumb:

| Storage | Good default use | Important trade-off |
| --- | --- | --- |
| EFS | Large shared datasets and files, including access from multiple AZs | Network filesystem metadata operations can make trees with many small files slow; throughput is shared by clients |
| FSx for OpenZFS | Active workspaces with many small files, source trees, `venv` directories, and build trees | Requires suitable network placement and is a provisioned service with its own cost/performance settings |
| S3-backed file system | Large object-like datasets where S3 semantics are acceptable | It is not a general POSIX filesystem; applications may observe different metadata, rename, and consistency behavior |
| io2 | High-performance storage for one instance | EBS volume; this project does not enable Multi-Attach, and same-AZ attachment plus instance-profile permissions are required |

In particular, EFS is often the better choice for storing large files and
datasets, while FSx is often better for an active workspace containing many
small files. Python virtual environments and similar dependency trees can take
a long time to create or remove on EFS because of metadata traffic. Benchmark
the actual workload and keep only persistent data on the shared filesystem;
instance-local storage can be preferable for disposable intermediate files.

Files on an instance's root EBS volume are not copied to another instance
automatically. Keep anything needed by a later `launch` or `submit` run on one
of the configured shared filesystems, or copy it explicitly with `scp`/`rsync`.

## Submit jobs with temporary instances

With the launch configuration generated by `ec2 setup`, `ec2 submit` can launch
a new instance just for a job and use that shared storage. It waits for SSH,
runs the script or command, and terminates the instance after completion by
default. A new instance can therefore be started for each job without copying
a large dataset to a new EBS volume or keeping a worker running between jobs.

Submit a local Bash script:

```sh
$ ec2 submit ./jobs/train.sh
```

Or submit a command directly. Put `--` before arguments that belong to the
command:

```sh
$ ec2 --submit-command 1 submit -- python /mnt/efs/jobs/train.py --epochs 10
```

Use `--submit-current-dir 1` when the command must run from the current working
directory, and `--submit-remain-instance 1` when the instance should be kept
after the job finishes. `--submit-max-jobs` limits concurrent submitted jobs.
The AMI and shared-file-system mounts must be ready before submitting; `submit`
does not make a local working directory or a dataset available by itself.

For example, suppose `FSX_MOUNT_POINTS` is configured as `/mnt/fsx`. Keep the
job directory, its input, and its output on that file system:

```sh
$ cd /mnt/fsx/jobs/image-classification
$ ls
input/  output/  run.sh  train.py
$ ec2 submit --submit-current-dir 1 ./run.sh
```

`run.sh` can use paths such as `input/train` and `output/checkpoints`. Because
`--submit-current-dir 1` changes to the same path on the new instance, the job
sees the files already on the shared file system and writes its results there.
The source files, inputs, outputs, and any persistent environment configured
under `USER_ENV_ROOT_DIR` remain available when the temporary instance is
terminated; only software installed in the AMI and instance-local temporary
data need to be recreated.

## Create a new template version

First, make a new AMI from an existing instance:

```
$ ec2 new_image
```

Then, make new template version:

```
$ ec2 new_template
```

During the command, select the template name that you want to update
and select a new AMI created above.

If old AMI is not necessary, remove it:

```
$ ec2 rm_image
```

This command also removes the associated snapshot.

Note: `new_image` create a new version of the template. If you do not have any templates,
make it with the Web interface or aws cli command directly.

## Help

This is the help output generated by the installed `ec2` command. It is kept
collapsed because the list of subcommands and options is long and can be viewed
directly whenever needed:

<details>
<summary>Show help output</summary>

```sh
Usage: ec2 <subcommand> [options]

Subcommands:
  cleanup_resources                  Show or execute cleanup for resources recorded by environment commands.
  commands                           List commands.
  delete_job                         Delete jobs.
  describe                           Show detailed information about instances
  et                                 Connect to an instance with Eternal Terminal.
                                     Use `et [command] [options]`.
  help                               Show help.
  images                             List images.
  init_environment                   Install an example environment configuration without overwriting one.
  instances                          List instances.
  jobs                               List jobs.
  launch                             Launch a new instance.
  list                               Alias for instances.
  list_json_groups                   List available JSON groups
  ls                                 Alias for instances.
  make_ami                           Build the configured EC2 AMIs with Packer.
  mosh                               Mosh to an instance.
                                     Use `mosh [commands] [options]`.
  new_image                          Create a new image from an instance.
  new_template                       Create a new template from an image.
  price                              Alias for pricing.
  pricing                            Show pricing of instance types.
  rm                                 Alias for terminate.
  rm_image                           Delete images.
  rsync                              Synchronize files with an instance.
                                     Prefix an instance path with `:`, for example `rsync ./src/ :/srv/src/`.
  scp                                Copy files to or from an instance.
                                     Prefix an instance path with `:`, for example `scp file :/tmp/`.
  setup                              Generate EC2 launch inputs and install the default ec2 configuration.
  setup_efs                          Resolve or create configured EFS file systems.
  setup_fsx                          Resolve or create configured FSx file systems.
  setup_io2                          Resolve or create configured io2 volumes.
  setup_s3files                      Resolve configured S3 file-system identifiers.
  ssh                                SSH to an instance.
                                     Use `ssh [commands] [options]`.
  start                              Start stopped instances.
  stop                               Stop running instances.
  submit                             Make a new instance and submit a job.
                                     Use `submit <file or commands> [options].
                                     If __submit_command is not set, need one
                                     bash file.
                                     If __submit_command is set, given options
                                     are recognized as command. Use `--` to
                                     separate options for ec2 and options for
                                     the command.
                                     If `__curent_dir` is set, the command is
                                     executed in the current directory.
                                     (Need same directory structure in the
                                     instance.)
  templates                          List templates.
  terminate                          Terminate instances.
  types                              List instance types.
  update_types                       Force update instance type list cache
  version                            Show version.

Options:
  --all, -a                          Set 1 to ignore preset filters.
  --config                           Configuration file to read instead of the default config file.
  --environment-config, -E           Configuration file for make_ami/setup.
  --workdir, -W                      Working directory for environment commands.
  --install-config                   Set 1 to install setup output as the default ec2 config.
  --setup                            Run setup automatically after make_ami completes successfully.
  --replace-config                   Set 1 to back up and replace an unmanaged ec2 config.
  --manifest                         Resource manifest used by cleanup_resources.
  --execute                          Set 1 to execute cleanup_resources instead of showing its plan.
  --aws-profile                      Profile name for aws cli (if not
                                     specified, the default profile is used.)
  --cli-input-json, -c               A json file which has parameters to launch
                                     an instance. Multiple files can be
                                     assigned by comma separated list.
                                     If multiple files are given, secondary
                                     files are used if the first one failed by
                                     the capacity problem.
  --cli-input-json-group, -G         JSON group name for launch
                                     an instance. Multiple groups can be
                                     assigned by comma separated list.
                                     If multiple groups are given, secondary
                                     groups are used if the first one failed by
                                     the capacity problem.
  --cli-input-json-directory, -C     A directory which has json files. If
                                     cli_input_json is not assigned and
                                     cli_input_json_directory is set, files are
                                     searched and it enters the selection mode.
  --cpu-filter                       Filter to pick up instance type by CPU.
  --dry-run, -d                      Set 1 to run as dry run mode (modification
                                     commands are not executed.)
  --et-option                        Additional Eternal Terminal argument. Repeat for more.
  --gpu-filter                       Filter to pick up instance type by GPU.
  --image-id                         Image name for new_image/rm_image command.
  --image-name, -I                   Image name for new_image/rm_image command.
  --image-name-filter                Filter to pick up images (AMI).
  --instance-id, -i                  Assign instance id to be managed. If '' or
                                     'select' is passed, it is selected
                                     interactively.
  --instance-type, -t                 Instance type for launch command. If ''
                                     or 'select' is passed, it is selected
                                     interactively.
  --mosh-server, -m                  Mosh server path.
  --n-cpu-core, -n                   Set number of CPU core of instance to set
                                     other than default number.
  --n-thread                         Set 1 to disable hyper-threading.
  --name-filter, -f                  Only instances which include this value
                                     is listed.
  --private-ip, -P                   Set 1 to use private IP addresses instead
                                     of public IP addresses.
  --retry-non-spot                   Set 0 to disable retry to launch a
                                     non-spot instance when launching a spot
                                     instance failed.
  --rsync-option                     Additional rsync argument. Repeat for more.
  --scp-option                       Additional scp argument. Repeat for more.
  --selection-tool, -s               Selection tool list, separated by ','. The
                                     default value is 'sentaku,peco,fzy,fzf'.
                                     The first one found is used. If nothing,
                                     bash's 'select' is used. Tools ref:
                                       - [sentaku](https://github.com/rcmdnk/sentaku/)
                                       - [peco](https://github.com/peco/peco)
                                       - [fzy](https://github.com/jhawthorn/fzy)
                                       - [fzf](https://github.com/junegunn/fzf)
  --spot-instance, -S                Set 1 to launch a spot instance.
  --ssh-key, -k                      Key for ssh.
  --ssh-option                       Additional SSH argument. Repeat for more.
  --ssh-user, -u                     User for ssh.
  --submit-command                   Set 1 to submit command instead of
                                     submitting script file.
  --submit-current-dir               Set 1 to use the current directory as the
                                     working directory by submit.
  --submit-n-retry-launch            Number of retries to launch an instance by
                                     submit. Default is 0.
  --submit-retry-launch-interval     Interval of retry to launch an instance by
                                     submit (sec) when all combinations of
                                     cli_input_json failed. Default is 60.
  --submit-n-retry-ssh               Number of retries after ssh connection
                                     failed. Default is 0.
  --submit-retry-ssh-interval        Interval of retry after ssh connection
                                     failed (sec). Default is 10.
  --submit-name                      Name of submitted job. If not given, the
                                     command name is used.
  --submit-max-jobs                  Maximum number of submitted jobs running
                                     in parallel.
  --submit-measure-time              Set 1 to measure time of the command.
  --submit-remain-instance           Set 1 to keep instances after finishing
                                     submitted jobs.
  --template-id, -T                  Assign template id. If not given, not
                                     templated is used. If 'select' is passed,
                                     it is selected interactively.
  --user-data, -U                    user data file for launch (run-instances),
                                     e.g: file:///path/to/your/user/data/script or fileb:///path/to/your/user/data/script.gz
  --verbose, -v                      Set 1 to run as verbose mode (show
                                     executing commands.)
  --help, -h                         Show help.
```

</details>

## Development

Install either [prek](https://prek.j178.dev/) or
[pre-commit](https://pre-commit.com/) before making changes. The configured
hooks install and run ShellCheck, so a separate system installation is not
required.

```
$ pip3 install prek
# or
$ brew install prek
```

Install the Git hook:

```
$ prek install
```

Run all checks after making changes:

```
$ prek run -a
```

If you use `pre-commit`, replace `prek` in the commands above with
`pre-commit`.

`bin/ec2` is generated from `src/ec2`, `environment/commands.sh`, and the files
listed in `environment/assets.manifest`. Regenerate it before running the
checks when any of those sources change:

```
$ scripts/build
$ prek run -a
$ bash scripts/verify.sh
```
