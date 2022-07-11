# ec2
AWS CLI Wrapper for EC2 management.

## Installation

Use homebrew:

    $ brew install rcmdnk/rcmdnkpac/ec2

or put `bin/ec2` in anywhere in the PATH.

## Usage

    $ ec2 <subcommand> [-i <instance_id>] [-f <name_filter>] [-t <type_filter>] [-g <gpu_filter>] [-k <ssh_key>] [-u <ssh_user>] [-r <running_only>] [-h] [arg0 [arg1...]]

Subcommands:

* help: Show help.
* list: List up instances.
* ls: Alias of list
* mosh: Connect to an instance with mosh.
* ssh: Connect to an instance with mosh.
* start: Start instances.
* stop: Stop instances.
* terminate: Terminate instances.
* types: Show instance types.


[peco](https://github.com/peco/peco), [fzy](https://github.com/jhawthorn/fzy), [fzf](https://github.com/junegunn/fzf), [sentaku](https://github.com/rcmdnk/sentaku/)




## Configuration

Use **~/.config/ec2/config**.

Parameters can be set like:

    ec2_name_filter=my-instance

`#` can be used to comment out.

Available parameters are:

* instance_id: Assign instance id to be managed.
* name_filter: Only instances which includes this value is listed.
* type_filter: Filter to pick up instance type.
* gpu_filter: Filter to pick up instance type with gpu. 0: CPU only, 1: with GPU, other strings: instances which have GPUs named <gpu_filter>.
* ssh_key: Key for ssh.
* ssh_user: User for ssh.
* running_only: Show only running instances at ssh/mosh
* selection_tool: Selection tool list, separated by `,`. Default value is `sentaku,peco,fzy,fzf`.
    * The first one found is used. If nothing, bash's `select` is used.

These parameters can be set by arguments, too.

    [-i <instance_id>] [-f <name_filter>] [-t <instance_type>] [-g <gpu_filter>] [-k <ssh_key>] [-u <ssh_user>] [-r <running_only>] [-s <selection_tool>] [-h] [arg0 [arg1...]]
