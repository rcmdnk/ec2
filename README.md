# aw
AWS CLI Wrapper

## Installation

Use homebrew:

    $ brew install rcmdnk/rcmdnkpac/aw

or put `bin/aw` in anywhere in the PATH.

## Configuration

Use **~/.config/aw/config**.

Parameters can be set like:

    ec2_name_filter=my-instance

`#` can be used to comment out.

Available parameters are:

* ec2_name_filter: Only instances which includes this value is listed.
* ssh_key: Key for ssh.
* ssh_user: User for ssh.

These parameters can be set by arguments, too.

    [-f <ec_name_filter>] [-k <ssh_key>] [-u <ssh_user>]
