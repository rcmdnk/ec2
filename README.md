# ec2
AWS CLI Wrapper for EC2 management.

## Requirement

* [AWS CLI](https://aws.amazon.com/cli/)

## Installation

Use Homebrew:

    $ brew install rcmdnk/rcmdnkpac/ec2

If you have not installed `awscli` by Homebrew, it is also installed.

Or put `bin/ec2` anywhere in the PATH.
(In this case, you need to install `awscli` by yourself.)

## Usage

    $ ec2 [-i <instance_id>] [-f <name_filter>] [-g <gpu_filter>] [-p <cpu_filter>] [-P <private_ip>] [-T <template_id>] [-t <instance_type>] [-S <spot_instance>] [-I <image_name>] [-k <ssh_key>] [-u <ssh_user>] [-r <running_only>] [-s <selection_tool>] [-a <aws_profile>] [-d <dry_run>] [-h] <subcommand>

Subcommands:

images
instances
launch
list
* Instance management:
  * instances: List up instances.
  * list: Alias of instances.
  * ls: Alias of instances.
  * start: Start instances.
  * stop: Stop instances.
  * launch: Launch a new instance.
      * If `spot_isntance` is 1, a persistent type spot instance is launched to allow start/stop it.
  * terminate: Terminate instances.
      * If the instance's lifecycle is `spot`, the spot instance request is also canceled.
  * rm: Alias of terminate.
* Connection helper:
  * ssh: Connect to an instance with mosh.
  * mosh: Connect to an instance with mosh.
* Image (AMI) managemen:t
  * images: List up images (AMI).
  * new_image: Create a new image from an instance.
  * rm_image: Deregister AMI and delete the associated snapshot.
* Template management:
  * templates: List up launch templates.
  * new_template: Create a new template version from an existing template with a new AMI.
* Others:
  * types: Show instance types.
  * help: Show help.

## AWS CLI Profile

If you want to use a profile other than the default,
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
* name_filter: Only instances which include this value is listed.
* gpu_filter: Filter to pick up instance type by GPU.
* cpu_filter: Filter to pick up instance type by CPU.
* private_ip: Set 1 to use private IP addresses instead of public IP addresses.
* template_id: Launch template id.
* instance_type: Instance type for launch command.
    * If `select` is passed, you can choose the type from the list.
* spot_instance: Set 1 to launch a spot instance.
* image_name: Image name for new_image/rm_image command.
* image_name_filter: Filter to pick up images (AMI).
* ssh_key: Key for ssh.
* ssh_user: User for ssh.
* running_only: Show only running instances at ssh/mosh
* selection_tool: Selection tool list, separated by `,`. The default value is `sentaku,peco,fzy,fzf`.
    * The first one found is used. If nothing, bash's `select` is used.
    * Tools ref:
        * [sentaku](https://github.com/rcmdnk/sentaku/)
        * [peco](https://github.com/peco/peco)
        * [fzy](https://github.com/jhawthorn/fzy)
        * [fzf](https://github.com/junegunn/fzf)
* aws_profile: Profile name for aws cli (if not specified, the default profile is used.)
* dry_run: Set 1 to run as dry run mode (modification commands are not executed.)

These parameters can be set by arguments, too.

## Examples

### Manage my instances with the prefix "my-instances"

Make ~/.config/ec2/config file as follows:

    name_filter=my-instances
    ssh_key=~/.ssh/my_ssh.pem
    ssh_user=ec2-user
    aws_profile=my-profile

This will show only instances which include `my-instances` in the Name.

It uses the key **~/.ssh/my_ssh.pem** at `ec2 ssh` or `ec2 mosh`, with the user name `ec2-user`.

Set `aws_profile` if you want to use other than the default profile.

### Launch new instance

    $ ec2 -t r3.large launch

Then select the template with the selection too.

If you give `-t select`, you can choose the instance type from the list.

You can pass the template name by `-T <your template>`, too.

### Create a new template version

First, make a new AMI from an existing instance:

    $ ec2 new_image

Then, make new template version:

    $ ec2 new_template

During the command, select the template name that you want to update
and select a new AMI created above.

If old AMI is not necessary, remove it:

    $ ec2 rm_image

This command also removes the associated snapshot.

Note: `new_image` create a new version of the template. If you do not have any templates,
make it with the Web interface or aws cli command directly.
