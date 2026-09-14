#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
work_dir=${TMPDIR:-/tmp}/ec2-environment-config-test

mapfile -t shell_files < <(find bin environment/scripts environment/packer/scripts scripts tests -type f -not -name '*.json' -not -name '*.bak' -not -name '*.orig' -not -name '*~' -print)
for file in "${shell_files[@]}"; do bash -n "$file"; done

# An untouched environment.example must be rejected for its unset required settings.
if CONFIG=environment/environment.example WORKDIR="$work_dir" bash -c '
  set -euo pipefail
  source environment/environment.example
  source environment/scripts/variables.sh' >/dev/null 2>&1; then
  echo 'Expected environment.example to be rejected for its unset required settings.' >&2
  exit 1
fi

# Every REQUIRED setting must actually be reported, so that none of them can be
# quietly dropped from environment.example or from scripts/variables.sh.
mapfile -t required < <(sed -n 's/^REQUIRED_SETTINGS\(_EC2\)\{0,1\}=(\(.*\))$/\2/p' environment/scripts/variables.sh | tr ' ' '\n')
((${#required[@]} > 0)) || { echo 'Could not read REQUIRED_SETTINGS from scripts/variables.sh.' >&2; exit 1; }
reported=$(CONFIG=environment/environment.example WORKDIR="$work_dir" REQUIRE_EC2_SETTINGS=1 bash -c '
  source environment/environment.example
  source environment/scripts/variables.sh' 2>&1 || true)
for name in "${required[@]}"; do
  # A required <X>_IDS is reported as "<X>_IDS (or <X>_NAMES)".
  grep -qE "^ *$name( \(or [A-Z_]+\))?\$" <<<"$reported" || {
    echo "scripts/variables.sh did not report the missing required setting $name." >&2
    exit 1
  }
  grep -qE "^$name=\"\"" environment/environment.example || {
    echo "environment.example must ship $name uncommented and empty." >&2
    exit 1
  }
done

# Keep only the two commonly customized EC2 filters active in a fresh template.
# Other optional EC2 settings should inherit defaults from scripts/variables.sh so
# that future default changes are not pinned by `ec2 init_environment` output.
mapfile -t active_ec2_settings < <(sed -n 's/^\(EC2_[A-Z0-9_]*\)=.*/\1/p' environment/environment.example | sort)
expected_active_ec2_settings=(EC2_IMAGE_NAME_FILTER EC2_KEY_NAME EC2_NAME_FILTER)
if [[ "${active_ec2_settings[*]}" != "${expected_active_ec2_settings[*]}" ]];then
  echo 'environment.example must activate only EC2_NAME_FILTER and EC2_IMAGE_NAME_FILTER.' >&2
  printf '  active: %s\n' "${active_ec2_settings[*]:-(none)}" >&2
  exit 1
fi

# With the required settings filled in it must load cleanly, so that every
# variable the scripts read has a value or a default in scripts/variables.sh.
filled=$(mktemp "${TMPDIR:-/tmp}/ec2-environment-config.XXXXXX")
mkdir -p "$root/tmp"
runtime_dir=$(mktemp -d "$root/tmp/ec2-environment-fs-warning.XXXXXX")
trap 'rm -f "$filled"; rm -rf "$runtime_dir"' EXIT
cp environment/environment.example "$filled"
for name in "${required[@]}"; do
  printf '%s=%s\n' "$name" "placeholder" >> "$filled"
done
if ! CONFIG="$filled" WORKDIR="$work_dir" bash -c '
  set -euo pipefail
  source "$CONFIG"
  source environment/scripts/variables.sh
  source environment/scripts/common.sh'; then
  echo 'environment.example does not load cleanly once the required settings are set.' >&2
  exit 1
fi

# FS persistence settings without USER_ENV_ROOT_DIR must warn and be skipped while the
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
AWS_REGION=ap-northeast-1
CPU_OUTPUT_AMI_NAME=fs-warning-test
AWS_SUBNET_IDS=subnet-fs-warning-test
EC2_KEY_NAME=fs-warning-test
EC2_SSH_PRIVATE_KEY=/tmp/fs-warning-test.pem
USER_ENV_DOTFILES_FILE=.bash_history
USER_ENV_DOTFILES_DIR=.cache,.local
EOF
if ! generated=$(PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$runtime_work" --environment-config "$runtime_config" --install-config 0 2>&1); then
  echo 'setup_ec2 must continue when USER_ENV_ROOT_DIR is empty.' >&2
  echo "$generated" >&2
  exit 1
fi
grep -q 'Warning: USER_ENV_ROOT_DIR is empty; ignoring user environment settings: USER_ENV_ENABLE_USR_SYMLINK USER_ENV_DOTFILES_FILE USER_ENV_DOTFILES_DIR' <<<"$generated" || {
  echo 'setup_ec2 did not report the ignored enabled FS settings.' >&2
  exit 1
}
user_data="$runtime_dir/work/ec2/user_data.sh"
[[ -f "$user_data" ]] || { echo 'setup_ec2 did not generate user-data after the FS warning.' >&2; exit 1; }
# shellcheck disable=SC2016  # Match the literal variable reference in generated user-data.
if grep -q '\$fs_dir' "$user_data"; then
  echo 'Generated user-data must not reference fs_dir when USER_ENV_ROOT_DIR is empty.' >&2
  exit 1
fi

disabled_config="$runtime_dir/config-disabled"
disabled_work=${runtime_dir#"$root/"}/work-disabled
cp "$runtime_config" "$disabled_config"
cat >> "$disabled_config" <<'EOF'
USER_ENV_ENABLE_USR_SYMLINK=0
USER_ENV_DOTFILES_FILE=
USER_ENV_DOTFILES_DIR=
EOF
if ! disabled_output=$(PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$disabled_work" --environment-config "$disabled_config" --install-config 0 2>&1); then
  echo 'setup_ec2 must continue when FS settings are disabled.' >&2
  echo "$disabled_output" >&2
  exit 1
fi
if grep -q 'Warning: USER_ENV_ROOT_DIR is empty' <<<"$disabled_output"; then
  echo 'setup_ec2 must not warn when USER_ENV_ROOT_DIR and all dependent FS settings are disabled.' >&2
  exit 1
fi

config_dotfiles_config="$runtime_dir/config-dotfiles-config"
config_dotfiles_work=${runtime_dir#"$root/"}/work-dotfiles-config
cp "$runtime_config" "$config_dotfiles_config"
cat >> "$config_dotfiles_config" <<'EOF'
USER_ENV_ROOT_DIR=/mnt/fs-warning-test
USER_ENV_ENABLE_USR_SYMLINK=0
USER_ENV_DOTFILES_FILE=
USER_ENV_DOTFILES_DIR=
USER_ENV_CONFIG_DOTFILES_FILE=tool/config
EOF
if ! config_dotfiles_output=$(PATH="$mock_bin:$PATH" bin/ec2 setup --workdir "$config_dotfiles_work" --environment-config "$config_dotfiles_config" --install-config 0 2>&1); then
  echo 'setup_ec2 must support USER_ENV_CONFIG_DOTFILES_FILE without home dotfile settings.' >&2
  echo "$config_dotfiles_output" >&2
  exit 1
fi
config_dotfiles_user_data="$runtime_dir/work-dotfiles-config/ec2/user_data.sh"
grep -q 'Setting dotfiles' "$config_dotfiles_user_data" || {
  echo 'USER_ENV_CONFIG_DOTFILES_FILE alone must enable dotfile setup.' >&2
  exit 1
}

# Every upper-case variable the scripts read must be defined by scripts/variables.sh
# (or by the shell itself), so that a rename cannot leave a script reading a name
# nothing sets any more.
# packer/scripts/* are excluded: Packer supplies their environment.
mapfile -t driver_files < <(find environment/scripts -type f -not -name '*.bak' -not -name '*.orig' -not -name '*~' -print)
# The REQUIRED_SETTINGS come from the config file, not from scripts/variables.sh.
shell_provided=" AWS_ARGS BASH_REMATCH BASH_SOURCE PWD SECONDS ${required[*]} "
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
bash tests/test_ami_failure_cleanup.sh
bash tests/test_process_cleanup.sh
bash tests/test_generated_artifacts.sh
bash tests/test_generated_content.sh
bash tests/test_reproducible_build_inputs.sh
bash tests/test_packer_template.sh
bash tests/test_resource_lifecycle.sh
bash tests/test_environment_config_install.sh
bash tests/test_missing_config_guidance.sh
bash tests/test_ssh_arguments.sh
bash tests/test_generated_bin.sh
bash tests/test_variable_precedence.sh
bash tests/test_aws_authentication.sh
bash tests/test_connection_method.sh

echo "All static checks passed."
