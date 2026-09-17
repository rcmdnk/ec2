# Instance selection

Use the workload's bottleneck, not a generic “largest available” choice.

| Workload signal                                           | Selection priority                              | Validation                                  |
| --------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------- |
| Parallel compile, CPU benchmark, numerical CPU job        | vCPU and CPU generation                         | Confirm the job can use parallelism         |
| Large in-memory data, memory errors, JVM/R/Python workers | memory first, then vCPU                         | Estimate peak working set plus headroom     |
| CUDA, tensor, deep learning, GPU-only package             | GPU type and GPU memory                         | Confirm GPU AMI, driver, runtime, and quota |
| Mixed or unknown                                          | satisfy hard constraint, then moderate vCPU/RAM | Observe usage and resize on the next run    |

Prefer a configured launch JSON group or an explicit `-t/--instance-type`. If no type is specified, inspect available project configuration and use the repository's selection facilities; do not fabricate exact AWS capacity or pricing. State the estimate and uncertainty.

For GPU jobs, selecting a CPU instance is a failure, not an acceptable fallback. For memory-heavy jobs, selecting solely from vCPU count is unsafe.
