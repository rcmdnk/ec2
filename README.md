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

## ec2

### Usage

```
Usage: ec2 <subcommand> [options]

Subcommands:
  cleanup_resources                  Show or execute cleanup for resources recorded by environment commands.
  commands                           List commands.
  delete_job                         Delete jobs.
  describe                           Show detailed information about instances
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
  scp                                SCP to an instance.
                                     Use `scp <file> [options]`.
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
                                     separate options for ec2 and options  for
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
  --config                           Configuration file to read instead of the
                                     default config file.
  --environment-config, -E           Configuration file for make_ami/setup.
  --workdir, -W                      Working directory for environment commands.
  --install-config                   Set 1 to install setup output as the default
                                     ec2 config.
  --replace-config                   Set 1 to back up and replace an unmanaged
                                     ec2 config.
  --manifest                         Resource manifest used by cleanup_resources.
  --execute                          Set 1 to execute cleanup_resources instead
                                     of showing its plan.
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
  --user-data, -U                    user data file for luanch (run-instances),
                                     e.g: file:///path/to/your/user/data/script
  --verbose, -v                      Set 1 to run as verbose mode (show
                                     executing commands.)
  --help, -h                         Show help.
```

### AWS CLI Profile

If you want to use a profile other than the default,
use `--aws-profile`, set `aws_profile` in the configuration file or
set:

```
export AWS_PROFILE=xxx
```

before using ec2.

### Configuration

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

### Manage configuration manually

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
configured user for `ec2 ssh` and `ec2 mosh`, and selects the AWS CLI profile.
Omit `aws_profile` to use the default AWS credential chain. OpenSSH normally
selects the identity from its defaults, `ssh-agent`, or `~/.ssh/config`. Add
`ssh_key=~/.ssh/my_ssh.pem` only when you want `ec2` to pass that key explicitly
with `-i`. Because `ec2` normally connects by IP address, any `Host` rule must
match that address or pattern.

Write multiple SSH arguments as a one-line Bash array in the configuration.
Each element is passed to `ssh`, `mosh`, and `scp` without another round of word
splitting:

```
ssh_option=(-o StrictHostKeyChecking=no -o 'ProxyCommand=ssh -W %h:%p bastion')
```

On the command line, repeat the option once per SSH argument:

```
$ ec2 mosh --ssh-option -o --ssh-option 'ProxyCommand=ssh -W %h:%p bastion'
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

### AMI builds and environment setup

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
$ ec2 make_ami
$ ec2 setup
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

The Packer scripts and the environment template are embedded in `bin/ec2`.
They are extracted to a temporary directory when an environment command runs,
so a copied `bin/ec2` has no runtime dependency on this source tree.

### Examples

#### Launch new instance

```
$ ec2 -t r3.large launch
```

If you give `-t select`, you can choose the instance type from the list.

You can pass the template name by `-T <your template>`, too.

#### Create a new template version

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

### Development

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
```
