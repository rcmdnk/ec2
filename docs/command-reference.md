# Command reference

Run ec2 help for the exact help text bundled with the installed version. The
following is the stable command map:

| Area                       | Commands                                                          |
| -------------------------- | ----------------------------------------------------------------- |
| Instance lifecycle         | launch, start, stop, terminate, rm, instances, list, ls, describe |
| Connections and transfer   | ssh, mosh, et, scp, rsync                                         |
| Jobs                       | submit, jobs, delete_job                                          |
| Images and templates       | images, new_image, rm_image, templates, new_template              |
| Instance types and pricing | types, update_types, pricing, price                               |
| Environment and cleanup    | init_environment, setup, make_ami, new_image, cleanup_resources   |
| Help and configuration     | commands, help, version, list_json_groups                         |

Global options include configuration and environment paths, AMI selection,
instance/image/template filters, connection and transfer options, dry-run and
verbosity controls, spot/retry controls, job limits, and -- to separate ec2
options from a submitted command.

For automation, pass explicit IDs and avoid interactive selection. Review the
generated launch JSON and user-data before launching.
