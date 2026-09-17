---
name: ec2-operator
description: Help operate this repository's ec2 command for AWS EC2 instance launch, connection, file transfer, AMI setup, and temporary job submission. Use when a task requires running a substantial test, build, analysis, or other workload that may benefit from a remote CPU-, memory-, or GPU-appropriate instance.
---

# ec2 operator

Use this skill to decide whether work should run through the repository's `ec2` command and to construct a command that preserves the user's working files and results.

## Default execution policy

When asked to run a test, build, benchmark, data analysis, training job, or other task, estimate its resource needs before executing it.

- Run small, quick, interactive checks locally.
- Prefer `ec2 submit` for work that is CPU-heavy, memory-heavy, GPU-dependent, expected to take several minutes, or likely to interfere with the local machine.
- This preference applies even when the user does not explicitly ask for EC2, provided the configured shared filesystem makes the working directory and outputs visible to the submitted instance.
- Do not submit blindly: confirm that the current directory, inputs, scripts, dependencies, and output location exist on a configured shared filesystem. `submit` does not copy an arbitrary local directory or dataset.
- Prefer `--submit-current-dir 1` when the current path is shared and the command relies on relative paths.
- Use `--submit-command 1` for an inline command; otherwise submit an existing script file.
- Remember that submitted instances terminate after completion by default. Use `--submit-remain-instance 1` only when the user needs to inspect or reuse the instance.

Before a remote execution, explain briefly which resources are being requested, why, where the results will be written, and any uncertainty in the estimate. Use `--dry-run 1` or inspect configuration when launch behavior is unclear. Do not claim a job succeeded until the remote command exits successfully and its outputs are checked.

## Selecting an instance type

Choose the smallest sensible type that satisfies the workload, then add headroom for the dominant constraint. Use an explicitly requested type or a known project configuration over a guess.

- CPU-heavy, parallel compilation, or numerical work: prioritize vCPU count and sustained CPU performance.
- Memory-heavy work, large test suites, dataframes, or in-memory models: prioritize RAM; avoid selecting by vCPU alone.
- CUDA, tensor, or explicitly GPU-dependent work: select a GPU-backed type and verify the AMI has the required drivers/runtime. A GPU request must never silently fall back to CPU.
- Mixed workloads: satisfy the hard requirement first (GPU or memory), then optimize vCPU and cost.
- If the workload size is unknown, start conservatively, use the repository's configured launch JSON/type selection, and suggest a larger or smaller type based on observed resource usage rather than inventing precise capacity.
- Check the account's GPU quota and the configured AMI/filesystem compatibility when using GPU types.

Do not infer that a high vCPU count implies enough memory, or that a GPU type provides unlimited CPU/RAM. Treat `--instance-type`, `-t`, launch JSON groups, and the configured AMI family as the sources of truth.

## Shared filesystem and environment

`ec2 submit` assumes `ec2 setup` has generated usable launch configuration and mounts. Inspect the relevant configuration when needed. Shared paths are configured through matching `*_NAMES`/`*_IDS` and `*_MOUNT_POINTS` settings, commonly EFS or FSx; persistent user software may live under `USER_ENV_ROOT_DIR`.

If the task depends on files outside the shared filesystem, either move/copy them through an intentional user-approved workflow or run locally. Do not assume the submitted instance has uncommitted local changes, local virtual environments, credentials, or instance-local temporary data. Keep durable inputs and outputs on the shared filesystem.

Read [references/submit-workflows.md](references/submit-workflows.md) for the remote execution decision and command patterns. Read [references/instance-selection.md](references/instance-selection.md) when estimating CPU, memory, or GPU requirements. Read [references/command-matrix.md](references/command-matrix.md) when choosing another `ec2` subcommand.

## Safety and reporting

- Preserve the repository's existing uncommitted changes; do not reset or overwrite them.
- Avoid `--submit-remain-instance 1` unless persistence is intentional.
- For cleanup or image deletion, show the target and prefer a plan/dry run before execution.
- Report the exact command, selected instance type, shared path, retry/termination behavior, exit status, and relevant output paths.
