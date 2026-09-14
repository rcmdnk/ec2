#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-environment-ami-failure.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
mock_bin="$runtime_dir/bin"
mkdir -p "$mock_bin"

cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" sts get-caller-identity "* ]]; then
  exit 0
fi
if [[ " $* " == *" describe-images "* && " $* " == *" BlockDeviceMappings "* ]]; then
  echo snap-failedbuild
elif [[ " $* " == *ManagedBy* ]]; then
  echo ec2-environment
fi
exit 0
EOF
cat > "$mock_bin/packer" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  version) echo 'Packer v-test' ;;
  build)
    echo 'Creating AMI failed-build from instance i-failedbuild'
    echo 'AMI: ami-failedbuild'
    exit 1
    ;;
esac
EOF
chmod 755 "$mock_bin"/*

config="$runtime_dir/config"
manifest="$runtime_dir/resources.tsv"
cat > "$config" <<EOF
AWS_REGION=ap-northeast-1
CPU_ENABLED=1
GPU_ENABLED=0
CPU_OUTPUT_AMI_NAME=failed-build
CPU_SOURCE_AMI_ID=ami-source
AMI_PACKER_ON_ERROR=cleanup
RESOURCE_MANIFEST=$manifest
EOF
work=${runtime_dir#"$root/"}/work
if PATH="$mock_bin:$PATH" bin/ec2 make_ami --workdir "$work" --environment-config "$config" >/dev/null 2>&1; then
  echo 'A failed Packer build must return a failure status.' >&2
  exit 1
fi
grep -q $'^ami\tami-failedbuild\tfailed-build\t' "$manifest" || {
  echo 'The failed AMI was not recorded in the resource manifest.' >&2
  exit 1
}
grep -q $'^instance\ti-failedbuild\tfailed-build\t' "$manifest" || {
  echo 'The failed build instance was not recorded in the resource manifest.' >&2
  exit 1
}

PATH="$mock_bin:$PATH" bin/ec2 cleanup_resources --workdir "$work" \
  --environment-config "$config" --manifest "$manifest" --execute 1 >/dev/null
[[ $(wc -l < "$manifest" | tr -d ' ') == 1 ]] || {
  echo 'Failed-build resources were not fully removed from the manifest.' >&2
  exit 1
}

echo 'AMI failure cleanup tests passed.'
