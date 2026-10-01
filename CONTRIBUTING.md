# Contributing

## Development prerequisites

Install Bash, AWS CLI, Packer (for AMI tests), and prek.

The generated command is the release artifact. Edit src/ec2 and the source files
under environment/; regenerate bin/ec2 with:

```
scripts/build
```

Run the complete local validation with:

```
prek run --all-files
```

The hook suite includes shell syntax, ShellCheck, Markdown formatting, generated
artifact reproducibility, and mocked lifecycle tests. Packer template validation is
also run by the dedicated CI Packer job.

## Change guidelines

Keep production changes and formatting-only changes separate. Add a focused
tests/test\_\*.sh regression test for every bug fix; new test scripts are discovered
automatically by the aggregate shell test.

Use English Conventional Commit subjects. For non-trivial changes, include concise
intent(scope), decision(scope), constraint(scope), or learned(scope) lines in
the commit body so future maintenance retains the reason for the change.

## Releases

Update the version in src/ec2, regenerate bin/ec2, and verify that the generated
command reports the same version as the release tag. Releases are created from
version tags and publish the generated command plus its checksum.
