# ec2 command matrix

| Goal                           | Subcommand                  | Important considerations                                      |
| ------------------------------ | --------------------------- | ------------------------------------------------------------- |
| List or inspect instances      | `instances`, `instance`     | Use filters or an explicit instance ID                        |
| Launch an interactive instance | `launch`                    | Select AMI/template/type; use `--dry-run` when uncertain      |
| Connect                        | `ssh`, `mosh`, `et`         | Choose public/private IP and configured key/user              |
| Copy files                     | `scp`, `rsync`              | Verify source/destination and shared storage assumptions      |
| Build an AMI                   | `make_ami`                  | Requires Packer and environment configuration                 |
| Generate launch configuration  | `setup`                     | Prepares mounts, launch JSON, user-data, and installed config |
| Run a temporary workload       | `submit`                    | Requires usable AMI and shared filesystem                     |
| Create image/template          | `new_image`, `new_template` | Confirm target before mutating resources                      |
| Review/execute cleanup         | `cleanup_resources`         | Use plan mode first; `--execute 1` performs cleanup           |

Use `ec2 help` and the repository README for options not covered here.
