# User guide

This page contains the detailed operational guide. For the shorter explanation
of the control, work, and job instance model, see
[Use cases and architecture](use-cases.md).

## Configuration

ec2 normally reads ~/.config/ec2/config. Environment commands use
~/.config/ec2/environment as input and generate the normal configuration.

```text
~/.config/ec2/environment  input for make_ami and setup
~/.config/ec2/config       generated launch and instance configuration
~/.config/ec2/work         generated working files by default
```

Start with ec2 init_environment, edit the generated file, and run ec2 setup.
Use --environment-config, --workdir, --install-config 0, and
--replace-config 1 when the defaults or replacement behavior are not
appropriate. See [Environment setup](environment-setup.md) for AWS settings
and permissions.

## AMI and launch configuration

ec2 make_ami builds configured AMI families with Packer. ec2 make_ami --setup
runs setup only after all enabled AMI builds succeed. ec2 setup resolves or
creates configured filesystems when enabled, writes launch JSON and user-data,
and can install the resulting configuration.

Review generated user-data before launching. It can contain copied file
contents and root-run commands. Prefer instance profiles for AWS credentials.

## Interactive instances

```sh
ec2 launch -t t3.medium
ec2 launch -t select
ec2 ssh
ec2 mosh
ec2 et
```

Use --private-ip 1 when the control path can reach the VPC privately. Keys,
users, connection methods, and additional SSH options come from the generated
configuration or command-line options.

## Selecting instances for operations

Instance operations such as `start`, `stop`, `rm`, `terminate`, `ssh`, and
`describe` use the following target-selection rules:

- When `--instance-id` (or `-i`) is set to an EC2 instance ID, the command
  operates on that instance directly and does not open a selection prompt.
- When `--instance-id` is omitted, empty, or set to `select`, ec2 lists
  candidate instances and opens the configured selection tool.
- `--name-filter` (or `-f`) narrows the candidate list to instance names that
  contain the specified value. It does not select an instance by itself, so a
  selection prompt is still shown.
- When no name filter is configured, all instances in the relevant state are
  candidates. The relevant state depends on the operation: `start` lists
  stopped instances, `stop` lists running instances, and `rm`/`terminate`
  lists instances that can be terminated.

The selection tool is chosen from `--selection-tool` (or `-s`), a comma-separated
preference list. The first installed tool is used. The default preference is
`sentaku,peco,fzy,fzf`; if none is installed, Bash's built-in `select` is used.

For example:

```sh
ec2 -i i-0123456789abcdef0 stop       # Operate directly; no prompt
ec2 -f dev-nohara-02 start            # Filter candidates, then prompt
ec2 -s fzf,sentaku stop               # Prefer fzf for this prompt
```

## File transfer

Prefix an instance-side path with :.

```sh
ec2 scp ./build/ :/tmp/build/
ec2 scp :/var/log/app.log ./logs/
ec2 rsync ./src/ :/srv/app/src/
ec2 rsync :/srv/app/output/ ./output/
```

rsync must be installed both locally and on the instance. Use the shared
filesystem instead of repeated transfers for durable job inputs and outputs.

## Shared filesystems

Configure EFS, FSx, S3-backed filesystems, or io2 according to the environment
settings. EFS and FSx are the normal choices for files shared by work and job
instances. S3-backed filesystems do not provide ordinary POSIX semantics. io2
Multi-Attach requires coordinated access and is not a general replacement for
shared storage.

Keep source, inputs, outputs, and persistent user software on shared storage.
Instance-local temporary data is acceptable when it can be recreated.

## Submit a job

```sh
cd /mnt/fsx/jobs/my-job
ec2 submit -t r8i.4xlarge --submit-current-dir 1 ./run.sh
ec2 --submit-command 1 submit -- python /mnt/efs/jobs/train.py --epochs 10
```

Use --submit-max-jobs for concurrency, retry options for transient launch or
SSH failures, --submit-measure-time 1 for timing, and
--submit-remain-instance 1 only when the instance should remain after the job.
The default lifecycle is launch, run, and terminate.

## Image and template lifecycle

```sh
ec2 new_image
ec2 new_template
ec2 rm_image
```

Confirm image targets before removal. For resources left by a failed
environment command, inspect the cleanup plan with ec2 cleanup_resources and
use --execute 1 only when the targets are verified.
