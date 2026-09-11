#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
work_dir=${TMPDIR:-/tmp}/ec2-environment-config-test

mapfile -t shell_files < <(find bin environment/scripts environment/packer/scripts scripts tests -type f -not -name '*.json' -not -name '*.bak' -not -name '*.orig' -not -name '*~' -print)
for file in "${shell_files[@]}"; do bash -n "$file"; done

# An untouched config.example must be rejected for its unset required settings.
if CONFIG=environment/config.example WORKDIR="$work_dir" bash -c '
  set -euo pipefail
  source environment/config.example
  source environment/scripts/variables' >/dev/null 2>&1; then
  echo 'Expected config.example to be rejected for its unset required settings.' >&2
  exit 1
fi

# Every REQUIRED setting must actually be reported, so that none of them can be
# quietly dropped from config.example or from scripts/variables.
mapfile -t required < <(sed -n 's/^REQUIRED_SETTINGS\(_EC2\)\{0,1\}=(\(.*\))$/\2/p' environment/scripts/variables | tr ' ' '\n')
((${#required[@]} > 0)) || { echo 'Could not read REQUIRED_SETTINGS from scripts/variables.' >&2; exit 1; }
reported=$(CONFIG=environment/config.example WORKDIR="$work_dir" REQUIRE_EC2_SETTINGS=1 bash -c '
  source environment/config.example
  source environment/scripts/variables' 2>&1 || true)
for name in "${required[@]}"; do
  # A required <X>_IDS is reported as "<X>_IDS (or <X>_NAMES)".
  grep -qE "^ *$name( \(or [A-Z_]+\))?\$" <<<"$reported" || {
    echo "scripts/variables did not report the missing required setting $name." >&2
    exit 1
  }
  grep -qE "^$name=\"\"" environment/config.example || {
    echo "config.example must ship $name uncommented and empty." >&2
    exit 1
  }
done

# With the required settings filled in it must load cleanly, so that every
# variable the scripts read has a value or a default in scripts/variables.
filled=$(mktemp "${TMPDIR:-/tmp}/ec2-environment-config.XXXXXX")
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-environment-fs-warning.XXXXXX")
trap 'rm -f "$filled"; rm -rf "$runtime_dir"' EXIT
cp environment/config.example "$filled"
for name in "${required[@]}"; do
  printf '%s=%s\n' "$name" "placeholder" >> "$filled"
done
if ! CONFIG="$filled" WORKDIR="$work_dir" bash -c '
  set -euo pipefail
  source "$CONFIG"
  source environment/scripts/variables
  source environment/scripts/lib.sh'; then
  echo 'config.example does not load cleanly once the required settings are set.' >&2
  exit 1
fi

# FS persistence settings without FS_DIR must warn and be skipped while the
# rest of setup_ec2 continues to generate its output.
mock_bin="$runtime_dir/bin"
runtime_config="$runtime_dir/config"
runtime_work=${runtime_dir#"$root/"}/work
mkdir -p "$mock_bin"
cat > "$mock_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" ec2 describe-images "* ]]; then
  echo ami-fs-warning-test
fi
EOF
chmod 755 "$mock_bin/aws"
cat > "$runtime_config" <<'EOF'
REGION=ap-northeast-1
CPU_AMI_NAME=fs-warning-test
SUBNET_IDS=subnet-fs-warning-test
KEY_NAME=fs-warning-test
EC2_SSH_KEY=/tmp/fs-warning-test.pem
FS_DOTFILES_FILE=.bash_history
FS_DOTFILES_DIR=.cache,.local
EOF
if ! generated=$(PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$runtime_work" --environment-config "$runtime_config" --install-config 0 2>&1); then
  echo 'setup_ec2 must continue when FS_DIR is empty.' >&2
  echo "$generated" >&2
  exit 1
fi
grep -q 'Warning: FS_DIR is empty; ignoring FS settings: FS_USR FS_DOTFILES_FILE FS_DOTFILES_DIR' <<<"$generated" || {
  echo 'setup_ec2 did not report the ignored enabled FS settings.' >&2
  exit 1
}
user_data="$runtime_dir/work/ec2/user_data.sh"
[[ -f "$user_data" ]] || { echo 'setup_ec2 did not generate user-data after the FS warning.' >&2; exit 1; }
# shellcheck disable=SC2016  # Match the literal variable reference in generated user-data.
if grep -q '\$fs_dir' "$user_data"; then
  echo 'Generated user-data must not reference fs_dir when FS_DIR is empty.' >&2
  exit 1
fi

disabled_config="$runtime_dir/config-disabled"
disabled_work=${runtime_dir#"$root/"}/work-disabled
cp "$runtime_config" "$disabled_config"
cat >> "$disabled_config" <<'EOF'
FS_USR=0
FS_DOTFILES_FILE=
FS_DOTFILES_DIR=
EOF
if ! disabled_output=$(PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$disabled_work" --environment-config "$disabled_config" --install-config 0 2>&1); then
  echo 'setup_ec2 must continue when FS settings are disabled.' >&2
  echo "$disabled_output" >&2
  exit 1
fi
if grep -q 'Warning: FS_DIR is empty' <<<"$disabled_output"; then
  echo 'setup_ec2 must not warn when FS_DIR and all dependent FS settings are disabled.' >&2
  exit 1
fi

config_dotfiles_config="$runtime_dir/config-dotfiles-config"
config_dotfiles_work=${runtime_dir#"$root/"}/work-dotfiles-config
cp "$runtime_config" "$config_dotfiles_config"
cat >> "$config_dotfiles_config" <<'EOF'
FS_DIR=/mnt/fs-warning-test
FS_USR=0
FS_DOTFILES_FILE=
FS_DOTFILES_DIR=
FS_DOTFILES_CONFIG_FILE=tool/config
EOF
if ! config_dotfiles_output=$(PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$config_dotfiles_work" --environment-config "$config_dotfiles_config" --install-config 0 2>&1); then
  echo 'setup_ec2 must support FS_DOTFILES_CONFIG_FILE without home dotfile settings.' >&2
  echo "$config_dotfiles_output" >&2
  exit 1
fi
config_dotfiles_user_data="$runtime_dir/work-dotfiles-config/ec2/user_data.sh"
grep -q 'Setting dotfiles' "$config_dotfiles_user_data" || {
  echo 'FS_DOTFILES_CONFIG_FILE alone must enable dotfile setup.' >&2
  exit 1
}

# Every upper-case variable the scripts read must be defined by scripts/variables
# (or by the shell itself), so that a rename cannot leave a script reading a name
# nothing sets any more.
# packer/scripts/* are excluded: Packer supplies their environment.
mapfile -t driver_files < <(find environment/scripts -type f -not -name '*.bak' -not -name '*.orig' -not -name '*~' -print)
# The REQUIRED_SETTINGS come from the config file, not from scripts/variables.
shell_provided=" AWS_ARGS BASH_REMATCH BASH_SOURCE PWD ${required[*]} "
defined() { grep -qE "^[[:space:]]*(local )?$1=|for $1 in" "${driver_files[@]}"; }
undefined=()

# Plain $NAME references.
# shellcheck disable=SC2016  # The regular expression intentionally matches a literal dollar sign.
mapfile -t referenced < <(grep -ohE '\$\{?[A-Z][A-Z0-9_]*' "${driver_files[@]}" | tr -d '${' | sort -u)
for name in "${referenced[@]}"; do
  [[ "$shell_provided" == *" $name "* ]] && continue
  defined "$name" && continue
  undefined+=("$name")
done

# make_ami dereferences these indirectly, and they carry no $ so the grep above
# cannot see them. family_value tries <FAMILY>_NAME first and only falls back to
# the bare NAME, so either the bare name or every family variant must exist.
# shellcheck disable=SC2016  # The patterns intentionally match literal shell source text.
mapfile -t family_referenced < <(grep -ohE 'family_value "\$family" [A-Z][A-Z0-9_]*' "${driver_files[@]}" | awk '{print $3}' | sort -u)
for name in "${family_referenced[@]}"; do
  [[ "$shell_provided" == *" $name "* ]] && continue
  defined "$name" && continue
  defined "CPU_$name" && defined "GPU_$name" && continue
  undefined+=("$name")
done

if ((${#undefined[@]} > 0)); then
  echo "Variables read by the scripts but defined nowhere:" >&2
  printf '  %s\n' "${undefined[@]}" >&2
  exit 1
fi

bash tests/test_filesystem_reconciliation.sh
bash tests/test_storage_readiness.sh
bash tests/test_efs_creation_token.sh
bash tests/test_generated_artifacts.sh
bash tests/test_generated_content.sh
bash tests/test_reproducible_build_inputs.sh
bash tests/test_packer_template.sh
bash tests/test_resource_lifecycle.sh
bash tests/test_environment_config_install.sh
bash tests/test_ssh_arguments.sh
bash tests/test_generated_bin.sh

echo "All static checks passed."
