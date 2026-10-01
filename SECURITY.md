# Security policy

## Reporting a vulnerability

Please report security issues privately through the repository's GitHub security
advisory workflow rather than opening a public issue. Include the affected version,
the smallest reproduction, and the expected versus observed behavior.

## Trust boundaries

The environment and normal configuration files are executable shell-style input.
Treat them as trusted local code: do not run a configuration copied from an
untrusted repository without reviewing it.

ec2 setup can place commands, copied files, and credentials-sensitive content in
root-run EC2 user-data. Review generated user-data and launch JSON before launching
an instance. Prefer instance profiles over embedding AWS credentials.

Use least-privilege IAM policies, restrict SSH/SSM security-group access, and keep
resource cleanup manifests protected. Downloaded release binaries should be
verified against the published checksum before installation.
