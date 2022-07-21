# ec2
AWS CLI Wrapper for EC2 management.

## Installation

Use homebrew:

    $ brew install rcmdnk/rcmdnkpac/ec2

or put `bin/ec2` in anywhere in the PATH.

## Usage

    $ ec2 [-i <instance_id>] [-f <name_filter>] [-g <gpu_filter>] [-p <cpu_filter>] [-P <private_ip>] [-T <template_id>] [-t <instance_type>] [-I <image_name>] [-k <ssh_key>] [-u <ssh_user>] [-r <running_only>] [-s <selection_tool>] [-a <aws_profile>] [-d <dry_run>] [-h] <subcommand>

Subcommands:

* Instance management:
  * list: List up instances.
  * ls: Alias of list
  * start: Start instances.
  * stop: Stop instances.
  * launch: Launch a new instance.
  * terminate: Terminate instances.
  * rm: Alias of terminate.
* Connection helper:
  * ssh: Connect to an instance with mosh.
  * mosh: Connect to an instance with mosh.
* Image (AMI) managemen:t
  * images: List up images (AMI).
  * new_image: Create new image from an instance.
  * rm_image: Deregister AMI and delete the associated snapshot.
* Template management:
  * templates: List up launch templates.
  * new_template: Create new template version from an existing template with new AMI.
* Others:
  * types: Show instance types.
  * help: Show help.

## AWS CLI Profile

If you want to use a profile other than default,
set:

    export AWS_PROFILE=xxx

before using ec2.

## Configuration

Use **~/.config/ec2/config**.

Parameters can be set like:

    name_filter=my-instance

`#` can be used to comment out the line.

Available parameters are:

* instance_id: Assign instance id to be managed.
* name_filter: Only instances which includes this value is listed.
* gpu_filter: Filter to pick up instance type by gpu.
* cpu_filter: Filter to pick up instance type by cpu.
* private_ip: Set 1 to use private IP addresses instead of public IP addresses.
* template_id: Launch template id.
* instance_type: Instance type for launch command.
    * If `select` is passed, you can choose the type from the list.
* image_name: Image name for new_image/rm_image command.
* ssh_key: Key for ssh.
* ssh_user: User for ssh.
* running_only: Show only running instances at ssh/mosh
* selection_tool: Selection tool list, separated by `,`. Default value is `sentaku,peco,fzy,fzf`.
    * The first one found is used. If nothing, bash's `select` is used.
    * Tools ref:
        * [sentaku](https://github.com/rcmdnk/sentaku/)
        * [peco](https://github.com/peco/peco)
        * [fzy](https://github.com/jhawthorn/fzy)
        * [fzf](https://github.com/junegunn/fzf)
* aws_profile: Profile name for aws cli (if not specified, default profile is used.)
* dry_run: Set 1 to run as dry run mode (modification commands are not executed.)

These parameters can be set by arguments, too.

## Examples

### Manage my instances with prefix "my-insatances"

Make ~/.config/ec2/config file as follows:

    name_filter=my-instances
    ssh_key=~/.ssh/my_ssh.pem
    ssh_user=ec2-user

This will show only instances which include `my-instances` in the Name.

It uses the key **~/.ssh/my_ssh.pem** at `ec2 ssh` or `ec2 mosh`, with the user name `ec2-user`.

### Launch new instance

    $ ec2 -t r3.large launch

Then select the template with the selection too.

If you give `-t select`, you can choose the instance type from the list.

You can pass template name by `-T <your template>`, too.

### Create new template version

First, make a new AMI from an existing instance:

    $ ec2 new_image

Then, make new template version:

    $ ec2 new_template

During the command, select the template name what you want to update
and select new AMI created above.

If old AMI is not necessary, remove it:

    $ ec2 rm_image

This command also remove the associated snapshot, too.

Note: `new_image` create a new version of the template. If you do not have any templates,
make it with the Web interface or aws cli command directly.
