# AI tools and the ec2-operator skill

This repository includes the ec2-operator skill under
skills/ec2-operator/. The skill teaches an AI coding tool how to use this
repository's ec2 command, especially when a substantial task should be
submitted to a CPU-, memory-, or GPU-appropriate job instance.

The skill is intentionally separate from the command itself. Install or link
it into the AI tool you use, while keeping this repository as the source of
truth for updates.

## Codex

Install the skill from the GitHub repository using the Codex skill installer:

~~~text
Repository: rcmdnk/ec2
Path: skills/ec2-operator
~~~

The installer places it in the Codex skills directory, normally
~/.codex/skills/ec2-operator. If CODEX_HOME is configured, use its skills
directory instead.

For local development, install the checked-out directory into the same skills
directory or update the installed copy after changing
skills/ec2-operator/. Start a new Codex session after installation or an
update so the skill is discovered.

Ask Codex naturally:

~~~text
Run the full test suite. Decide whether this should use ec2 submit.
~~~

Or invoke the skill explicitly when supported:

~~~text
$ec2-operator
Run the memory-heavy analysis in this repository.
~~~

Codex should inspect the configured shared filesystem and AMI assumptions
before submitting a job. It should select an instance type based on the
workload bottleneck, report the command and output location, and not claim
success without checking the remote exit status.

## Claude Code

Claude Code loads project skills from
.claude/skills/<skill-name>/SKILL.md and personal skills from
~/.claude/skills/<skill-name>/SKILL.md. For a checkout of this repository,
make the skill available to Claude Code with a symlink:

~~~sh
mkdir -p .claude/skills
ln -s ../../skills/ec2-operator .claude/skills/ec2-operator
~~~

The relative path above is from .claude/skills/ to the repository's
skills/ec2-operator/ directory. Use an absolute path if the project layout or
symlink policy requires it. A personal installation can be created with:

~~~sh
mkdir -p ~/.claude/skills
ln -s /path/to/ec2/skills/ec2-operator ~/.claude/skills/ec2-operator
~~~

Start Claude Code from the repository and invoke the skill explicitly:

~~~sh
claude
~~~

~~~text
/ec2-operator
Run the expensive test in the current project using an appropriate job instance.
~~~

Claude Code may also load the skill automatically when a request matches its
description. Explicit invocation is useful when the choice to use ec2 submit
is important.

For non-interactive Claude Code runs, use a prompt that states the workload and
the expected execution policy:

~~~sh
claude -p "Run the full analysis. Use ec2 submit if the shared filesystem and AMI make the job reproducible. Choose CPU, memory, or GPU capacity from the workload."
~~~

Review permissions before allowing commands that launch or terminate AWS
instances. Keep --dangerously-skip-permissions out of normal workflows.

See the [Claude Code skills documentation](https://code.claude.com/docs/en/skills)
for current skill locations, invocation, and sharing behavior.

## Prompting examples

These requests provide enough context for the skill to make a useful choice:

~~~text
Run the full test suite. The repository is on the configured shared filesystem.
Use ec2 submit if it is likely to take more than a few minutes, and choose an
instance type appropriate for the test's CPU and memory needs.
~~~

~~~text
Run this GPU analysis. Confirm that the configured AMI and instance type
provide the required GPU runtime, and keep the outputs on the shared filesystem.
~~~

~~~text
Do a quick syntax check locally. Do not launch an EC2 instance for this small task.
~~~
