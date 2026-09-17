# Use cases and architecture

ec2 is intended for a development environment in which the machine used to
manage AWS, the machine used for interactive work, and the machine used for a
heavy job have different roles.

## Three machine roles

### Control machine

The control machine is the user's own computer, commonly macOS. It is the main
origin for ec2 launch, ec2 ssh, ec2 submit, and other management commands. It
does not need to run the workload itself.

### Work instance

The work instance is a small, usually persistent EC2 instance such as a
t3.medium. It is used for editing, interactive development, small tests, and
optionally Claude, Codex, or other development tools. It should remain
responsive; a heavy job does not need to run there merely because it started
there.

### Job instance

The job instance is selected for one workload and is normally temporary. It
may be a large instance such as r8i.4xlarge or g4dn.4xlarge, but it may also
be a smaller type such as c8i.large when the goal is to isolate a job from the
work instance.

Select it according to the bottleneck:

- vCPU and CPU generation for CPU-heavy or highly parallel work
- Memory for large in-memory datasets and memory-heavy processes
- GPU type and GPU memory for CUDA, tensor, or GPU-only workloads
- A combination when the workload has more than one hard requirement

Do not choose by vCPU count alone, and do not silently run a GPU-required job
on a CPU instance.

## Shared environment model

The work and job instances can be effectively interchangeable when they use the
same AMI configuration and mount the same shared filesystem:

~~~mermaid
flowchart TB
    AMI["Configured AMI<br/>software and runtime"]
    Setup["ec2 setup<br/>launch JSON + user-data"]
    FS["Shared filesystem<br/>source / input / output / user environment"]
    Work["Work instance"]
    Job["Job instance"]

    AMI --> Setup
    Setup --> Work
    Setup --> Job
    FS <--> Work
    FS <--> Job
~~~

Files on an instance's root EBS volume are not copied automatically. Anything
needed by a later job must be on a configured shared filesystem or be copied
explicitly.

## Two ways to run a job

A job can be submitted from either machine:

~~~mermaid
flowchart LR
    Control["Control machine"]
    Work["Work instance"]
    Job["Job instance"]
    FS["Shared filesystem"]

    Control -->|"ec2 submit"| Job
    Work -->|"ec2 submit"| Job
    Work <--> FS
    Job <--> FS
~~~

Submitting from the work instance is convenient when the work directory and
its environment are already available there. Submitting from the control
machine is useful when the job is already prepared on a shared path.

## When to use ec2 submit

Prefer ec2 submit when a task is expected to take several minutes, is CPU- or
memory-heavy, needs a GPU, uses substantial parallelism, or would make the
work instance unresponsive. Examples include large test suites, builds,
benchmarks, static analysis, data conversion, model training, and large-file
processing.

Run locally or on the work instance when the task is small, interactive, or
requires files and software that have not been made available through the AMI
and shared filesystem.

~~~mermaid
sequenceDiagram
    participant Source as Control or work instance
    participant CLI as ec2 submit
    participant Job as Job instance
    participant FS as Shared filesystem

    Source->>CLI: Submit script or command
    CLI->>Job: Launch selected instance
    Job->>FS: Mount configured filesystem
    CLI->>Job: Wait for connection and run job
    Job->>FS: Write outputs
    CLI->>Job: Terminate by default
    CLI-->>Source: Return status and output paths
~~~

Use --submit-current-dir 1 only when the same absolute path exists on the job
instance through the shared filesystem. ec2 submit does not make an arbitrary
local directory or dataset available.

## Initial dotfiles migration and verification

When a new work instance is created, do not assume that its dotfiles and user
configuration are already correct. Migrate them explicitly from an existing
work instance such as dev-nohara-02, then verify them on a separate new
instance.

1. Launch and log in to the new instance.
2. Confirm that the shared filesystem configured by USER_ENV_ROOT_DIR is
   mounted, for example /mnt/fsx/fs1.
3. Copy the dotfiles from the existing work instance using scp, rsync, or
   another deliberate transfer method.
4. Place files intended for ~/ directly under:

   ~~~text
   <USER_ENV_ROOT_DIR>/dotfiles/
   ~~~

5. Place files intended for ~/.config/ under:

   ~~~text
   <USER_ENV_ROOT_DIR>/dotfiles/.config/
   ~~~

   For example, with USER_ENV_ROOT_DIR=/mnt/fsx/fs1, use
   /mnt/fsx/fs1/dotfiles/.config/ for persistent .config contents.
6. Configure the relevant USER_ENV_DOTFILES_* and
   USER_ENV_CONFIG_DOTFILES_* settings.
7. Run ec2 setup so the dotfile links are included in generated user-data.
8. Launch a second, fresh instance and verify that the expected files and
   directories are symlinked into ~/ and ~/.config/, and that applications can
   read them.

The second-instance check matters because the links are created during
instance setup. A successful copy on one instance does not prove that a fresh
instance will recreate the intended links.

Do not overwrite the source instance's dotfiles during migration. Compare the
files first and keep a recoverable backup when replacing an existing
configuration.
