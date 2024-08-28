# ec2

AWS CLI Wrapper for EC2 management.

## Requirement

- [AWS CLI](https://aws.amazon.com/cli/)

## Installation

Use Homebrew:

```
$ brew install rcmdnk/rcmdnkpac/ec2
```

If you have not installed `awscli` by Homebrew, it is also installed.

Or put `bin/ec2` and `bin/ec2_submit` anywhere in the PATH.
(In this case, you need to install `awscli` by yourself.)

## ec2

### Usage

Usage: ec2 <subcommand> \[options\]

```
Subcommands:
  commands                           List commands.
  delete_job                         Delete jobs.
  help                               Show help.
  images                             List images.
  instances                          List instances.
  jobs                               List jobs.
  launch                             Launch a new instance.
  list                               Alias for instances.
  ls                                 Alias for instances.
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
  ssh                                SSH to an instance.
                                     Use `ssh [commands] [options]`.
  start                              Start stopped instances.
  stop                               Stop running instances.
  submit                             Make a new instance and submit a job.
                                     Use `submit <file or commands> [options].
  templates                          List templates.
  terminate                          Terminate instances.
  types                              List instance types.
  version                            Show version.

Options:
  --all, -A                          Set 1 to ignore preset filters.
  --aws-profile, -a                  Profile name for aws cli (if not specified, the default profile is used.)
  --cli-input-json, -c               A json file which has parameters to launch an instance.
  --cli-input-json-directory, -C     A directory which has json files.
                                     If cli_input_json is not assigned and cli_input_json_directory is set,
                                     files are searched and it enters the selection mode.
  --cpu-filter, -p                   Filter to pick up instance type by CPU.
  --current-dir, -D                  Set 1 to use the current directory as the working directory.
  --dry-run, -d                      Set 1 to run as dry run mode (modification commands are not executed.)
  --gpu-filter, -g                   Filter to pick up instance type by GPU.
  --help, -h                         Show help.
  --image-name, -I                   Image name for new_image/rm_image command.
  --image-name-filter, -j            Filter to pick up images (AMI).
  --instance-id, -i                  Assign instance id to be managed.
                                     If '' or 'select' is passed, it is selected interactively.
  --instance-type, -t                Instance type for launch command.
                                     If '' or 'select' is passed, it is selected interactively.
  --max-jobs, -M                     Maximum number of submitted jobs running in parallel.
  --mosh-server, -m                  Mosh server path.
  --n-cpu-core, -n                   Set number of CPU core of instance to set other than default number.
  --n-thread, -H                     Set 1 to disable hyper-threading.
  --name-filter, -f                  Only instances which include this value is listed.
  --private-ip, -P                   Set 1 to use private IP addresses instead of public IP addresses.
  --retry-non-spot, -R               Set 0 to disable retry to launch a non-spot instance
                                     when launching a spot instance failed.
  --selection-tool, -s               Selection tool list, separated by ','.
                                     The default value is 'sentaku,peco,fzy,fzf'.
                                     The first one found is used. If nothing, bash's 'select' is used.
                                     Tools ref:
                                       - [sentaku](https://github.com/rcmdnk/sentaku/)
                                       - [peco](https://github.com/peco/peco)
                                       - [fzy](https://github.com/jhawthorn/fzy)
                                       - [fzf](https://github.com/junegunn/fzf)
  --spot-instance, -S                Set 1 to launch a spot instance.
  --ssh-key, -k                      Key for ssh.
  --ssh-user, -u                     User for ssh.
  --template-id, -T                  Assign template id. If '' or 'select' is passed, it is selected interactively.
  --user-data, -U                    user data file for luanch (run-instances),
                                     e.g: file:///path/to/your/user/data/script
  --verbose, -v                      Set 1 to run as verbose mode (show executing commands.)
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

Use **~/.config/ec2/config**.

Options can be set like:

```
name_filter=my-instance
```

`#` can be used to comment out the line.

Available options are same as the command line options starting with `--`, but without `--` and `-` is replaced by `_`,
i.e., `aws_profile` for `--aws-profile`.

### Examples

#### Manage my instances with the prefix "my-instances"

Make ~/.config/ec2/config file as follows:

```
name_filter=my-instances
ssh_key=~/.ssh/my_ssh.pem
ssh_user=ec2-user
aws_profile=my-profile
```

This will show only instances which include `my-instances` in the Name.

It uses the key **~/.ssh/my_ssh.pem** at `ec2 ssh` or `ec2 mosh`, with the user name `ec2-user`.

Set `aws_profile` if you want to use other than the default profile.

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

#### pre-commit

Install pre-commit by pip:

```
$ pip3 install pre-commit
```

or by Homebrew

```
$ brew install pre-commit
```

Install pre-commit environment:

```
$ pre-commit install
```

Then, automatically checked at `git commit` or run checks manually:

```
$ pre-commit run -a
```
