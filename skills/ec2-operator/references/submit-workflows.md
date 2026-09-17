# Submit workflows

## Preconditions

The normal flow is:

```text
ec2 setup -> generated launch JSON and user-data -> ec2 submit -> SSH -> job -> terminate
```

The AMI and shared filesystem mounts must already be usable. Check that the current directory is a shared mount and that the job's inputs and outputs are there. `--submit-current-dir 1` changes to the same path on the remote instance.

## Patterns

Script file:

```sh
ec2 submit -t <instance-type> --submit-current-dir 1 ./run.sh
```

Inline command (put `--` before command arguments):

```sh
ec2 -t <instance-type> --submit-command 1 submit -- python /mnt/efs/jobs/analyze.py --input input/data
```

Useful controls:

- `--submit-max-jobs N`: cap concurrent submitted jobs.
- `--submit-n-retry-launch N` and `--submit-retry-launch-interval SEC`: recover from capacity/launch failures.
- `--submit-n-retry-ssh N` and `--submit-retry-ssh-interval SEC`: recover from transient SSH failures.
- `--submit-measure-time 1`: measure command time.
- `--submit-remain-instance 1`: retain the instance for inspection; otherwise it is terminated after completion.

If the current directory is not shared, do not use `--submit-current-dir 1`; explain the portability problem and either use a shared path or stay local.
