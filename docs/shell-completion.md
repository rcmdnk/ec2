# Shell completion

The repository includes command completion for Bash and zsh:

- etc/bash_completion.d/ec2 is the completion implementation. It supports Bash
  and detects zsh when sourced from zsh.
- share/zsh/site-functions/\_ec2 is the zsh site-function entry point. It is a
  symlink to the completion implementation in etc.

## Bash

Source the completion file from a shell startup file, or install it under the
system's bash_completion.d directory:

```sh
source /path/to/ec2/etc/bash_completion.d/ec2
```

## zsh

Add the repository's site-functions directory to fpath before initializing
completion:

```zsh
fpath=(/path/to/ec2/share/zsh/site-functions $fpath)
autoload -Uz compinit
compinit
```

The completion list is generated dynamically from ec2 commands, so it follows
the installed command's available subcommands.
