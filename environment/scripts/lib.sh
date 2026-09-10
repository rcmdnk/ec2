#!/usr/bin/env bash
set -euo pipefail

# Fill <IDS_VAR> by looking each entry of <NAMES_VAR> up through an aws describe
# call. Does nothing when <IDS_VAR> already has a value, so an explicit ID always
# wins. A name that matches nothing, or more than one resource, is an error:
# names are not unique in AWS and silently picking one is how you end up
# attached to the wrong network.
#
#   resolve_ids IDS_VAR NAMES_VAR "<service> <operation>" <filter> <query> [extra filter ...]
resolve_ids() {
  local ids_var=$1 names_var=$2 operation=$3 filter=$4 query=$5
  shift 5
  local ids=${!ids_var-} names=${!names_var-} name resolved=''
  local cache_var="RESOLVED_${ids_var}" cache_key_var="RESOLVED_${ids_var}_FROM"
  local -a operation_args extra_filters=("$@") matches name_list
  [[ -n "$ids" || -z "$names" ]] && return 0
  # setup_ec2 runs setup_efs, setup_fsx and setup_io2 as child processes, and
  # each of them sources the config again, which resets <X>_IDS. Caching the
  # answer under a name the config never writes keeps the lookup to one call per
  # run instead of one per script.
  # Keyed on the names it was resolved from, so a value left over from another
  # config or an earlier run with different names is never reused.
  if [[ -n "${!cache_var-}" && "${!cache_key_var-}" == "$names" ]]; then
    printf -v "$ids_var" '%s' "${!cache_var}"
    return 0
  fi
  read -r -a operation_args <<<"$operation"
  # Quoted, because a Name tag or a security group name may contain spaces.
  mapfile -t name_list < <(csv_items "$names")
  for name in "${name_list[@]}"; do
    [[ -n "$name" ]] || continue
    mapfile -t matches < <(aws "${AWS_ARGS[@]}" "${operation_args[@]}" \
      --filters "Name=$filter,Values=$name" ${extra_filters[@]+"${extra_filters[@]}"} \
      --query "$query" --output text | tr '\t' '\n' | awk 'NF && $0 != "None"')
    case ${#matches[@]} in
      0)
        echo "$names_var: nothing matches '$name'" >&2
        return 1
        ;;
      1)
        resolved="${resolved:+$resolved,}${matches[0]}"
        ;;
      *)
        echo "$names_var: '$name' matches ${#matches[@]} resources: ${matches[*]}" >&2
        echo "Names are not unique in AWS. Set $ids_var to pick one." >&2
        return 1
        ;;
    esac
  done
  printf -v "$ids_var" '%s' "$resolved"
  printf -v "$cache_var" '%s' "$resolved"
  printf -v "$cache_key_var" '%s' "$names"
  # shellcheck disable=SC2163  # exporting the name each variable holds is the point
  export "$cache_var" "$cache_key_var"
}

csv_items() {
  local value=${1:-} n=${2:-} values
  if [[ -z "$value" ]]; then
    return
  fi
  values=$(tr ',' '\n' <<<"$value")
  if [[ -z "$n" ]]; then
    echo "$values"
    return
  fi
  # values to aaray
  mapfile -t values <<<"$values"
  echo "${values[$n]:-}"
}

json_quote() {
  local value=${1:-}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '"%s"' "$value"
}

json_array_from_csv() {
  local value=${1:-} item result=''
  IFS=, read -r -a items <<<"$value"
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || continue
    result+="${result:+,}$(json_quote "$item")"
  done
  printf '[%s]' "$result"
}

sha256_string() {
  local value=${1-}
  if command -v sha256sum >/dev/null 2>&1;then
    printf '%s' "$value" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1;then
    printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
  else
    echo 'A SHA-256 utility (sha256sum or shasum) is required.' >&2
    return 1
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1;then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1;then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo 'A SHA-256 utility (sha256sum or shasum) is required.' >&2
    return 1
  fi
}

efs_creation_token() {
  local name=$1 prefix digest
  digest=$(sha256_string "$name") || return 1
  prefix=${name//[^a-zA-Z0-9._-]/-}
  [[ "$prefix" =~ [a-zA-Z0-9] ]] || prefix=efs
  prefix=${prefix:0:39}
  printf 'ec2env-%s-%s' "$prefix" "${digest:0:16}"
}

shell_assignment() {
  local name=$1 value=${2-}
  printf '%s=' "$name"
  printf '%q\n' "$value"
}

base64_string() {
  printf '%s' "${1-}" | base64 | tr -d '\n'
}

base64_file() {
  base64 < "$1" | tr -d '\n'
}

validate_resource_metadata() {
  local name value
  for name in RESOURCE_MANAGED_BY RESOURCE_PROJECT RESOURCE_OWNER RESOURCE_EXPIRES_AT;do
    value=${!name-}
    [[ "$value" != *$'\n'* && "$value" != *$'\t'* ]] || {
      echo "$name must not contain tabs or newlines." >&2
      return 1
    }
  done
  [[ -n "${RESOURCE_MANAGED_BY:-ec2-environment}" ]] || {
    echo 'RESOURCE_MANAGED_BY must not be empty.' >&2
    return 1
  }
}

resource_tags_json() {
  local resource_name=$1 result
  validate_resource_metadata || return 1
  result=$(printf '{"Key":"Name","Value":%s},{"Key":"ManagedBy","Value":%s}' \
    "$(json_quote "$resource_name")" "$(json_quote "$RESOURCE_MANAGED_BY")")
  [[ -z "$RESOURCE_PROJECT" ]] || result+=",$(printf '{"Key":"Project","Value":%s}' "$(json_quote "$RESOURCE_PROJECT")")"
  [[ -z "$RESOURCE_OWNER" ]] || result+=",$(printf '{"Key":"Owner","Value":%s}' "$(json_quote "$RESOURCE_OWNER")")"
  [[ -z "$RESOURCE_EXPIRES_AT" ]] || result+=",$(printf '{"Key":"ExpiresAt","Value":%s}' "$(json_quote "$RESOURCE_EXPIRES_AT")")"
  printf '[%s]' "$result"
}

record_resource() {
  local type=$1 id=$2 name=$3 created_at manifest_dir
  [[ "$type$id$name" != *$'\n'* && "$type$id$name" != *$'\t'* ]] || {
    echo 'Resource manifest fields must not contain tabs or newlines.' >&2
    return 1
  }
  manifest_dir=$(dirname "$RESOURCE_MANIFEST")
  mkdir -p "$manifest_dir"
  if [[ ! -f "$RESOURCE_MANIFEST" ]];then
    printf 'type\tid\tname\tcreated_at\n' > "$RESOURCE_MANIFEST"
  fi
  if ! awk -F '\t' -v type="$type" -v id="$id" '$1 == type && $2 == id { found=1 } END { exit !found }' "$RESOURCE_MANIFEST";then
    created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s\t%s\t%s\t%s\n' "$type" "$id" "$name" "$created_at" >> "$RESOURCE_MANIFEST"
  fi
}
subnet_az() {
  local subnet_id=$1
  aws "${AWS_ARGS[@]}" ec2 describe-subnets --subnet-ids "$subnet_id" \
    --query 'Subnets[0].AvailabilityZone' --output text
}

make_array() {
  local length=$1 var=$2 default=${3:-}
  n_var=$(tr ',' '\n' <<<"$var" | wc -l | tr -d ' ')
  if [[ "$n_var" -eq "$length" ]]; then
    echo "$var"
    return
  fi
  if [[ "$n_var" -eq 1 ]];then
    default=$var
  elif [[ "$n_var" -gt 1 ]];then
    echo "Cannot make array of length $length from $var" >&2
    return 1
  fi
  local result=''
  for ((i=0; i<length; i++)); do
    result+="${result:+,}$default"
  done
  echo "$result"
}

compare_length() {
  local var1_name=$1 var2_name=$2 var1 var2
  var1=${!var1_name} var2=${!var2_name}
  n_1=$(tr ',' '\n' <<<"$var1" | wc -l | tr -d ' ')
  n_2=$(tr ',' '\n' <<<"$var2" | wc -l | tr -d ' ')
  [[ "$n_1" == "$n_2" ]] || { echo "$var1_name and $var2_name must have equal lengths" >&2; return 1; }
}

setup_filesystem_ids() {
  local system=$1 create_func=${2:-} prepare_func=${3:-}
  local name id lookup_output
  local ids_var="${system^^}_IDS" names_var="${system^^}_NAMES" mount_points_var="${system^^}_MOUNT_POINTS" id_func="get_${system}_id"
  local ids=${!ids_var} names=${!names_var}
  local i missing_i
  local -a matches=() name_list=() resolved_ids=() missing_indices=() missing_names=()

  if [[ -n "$ids" ]];then
    compare_length "$ids_var" "$mount_points_var" || return 1
    return 0
  fi
  [[ -z "$names" ]] && return 0

  compare_length "$names_var" "$mount_points_var" || return 1
  mapfile -t name_list < <(csv_items "$names")

  # Resolve every name before creating anything. This avoids creating resources
  # only to discover an ambiguous name later in the same request.
  for i in "${!name_list[@]}"; do
    name=${name_list[i]}
    if [[ -z "$name" ]];then
      echo "${names_var}[$i] is empty" >&2
      return 1
    fi
    if ! lookup_output=$("$id_func" "$name");then
      echo "$names_var: lookup failed for '$name'" >&2
      return 1
    fi
    mapfile -t matches < <(tr '\t' '\n' <<<"$lookup_output" | awk 'NF && $0 != "None"')
    case ${#matches[@]} in
      0)
        missing_indices+=("$i")
        missing_names+=("$name")
        ;;
      1)
        resolved_ids[i]=${matches[0]}
        ;;
      *)
        echo "$names_var: '$name' matches ${#matches[@]} ${system} file systems: ${matches[*]}" >&2
        echo "Names are not unique in AWS. Set $ids_var to pick one." >&2
        return 1
        ;;
    esac
  done

  if ((${#missing_indices[@]} > 0));then
    if [[ "${CREATE_FILE_SYSTEMS:-0}" != 1 || -z "$create_func" ]];then
      printf '%s: no %s file system matches:\n' "$names_var" "$system" >&2
      printf '  %s\n' "${missing_names[@]}" >&2
      [[ -n "$create_func" ]] && echo 'Set CREATE_FILE_SYSTEMS=1 to create the missing resources.' >&2
      return 1
    fi

    validate_resource_metadata || return 1
    printf 'Creation plan (%s):\n' "$system" >&2
    for name in "${missing_names[@]}";do
      printf '  create %s name=%s ManagedBy=%s\n' "$system" "$name" "${RESOURCE_MANAGED_BY:-ec2-environment}" >&2
    done
    if [[ "${RESOURCE_DRY_RUN:-0}" == 1 ]];then
      echo 'RESOURCE_DRY_RUN=1: no resources were created.' >&2
      printf -v "$ids_var" '%s' ''
      return 0
    fi

    if [[ -n "$prepare_func" ]];then
      "$prepare_func" "${#name_list[@]}" || return 1
    fi
    for missing_i in "${!missing_indices[@]}"; do
      i=${missing_indices[missing_i]}
      name=${missing_names[missing_i]}
      if ! id=$("$create_func" "$i" "$name");then
        echo "$names_var: failed to create '$name'" >&2
        return 1
      fi
      if [[ -z "$id" || "$id" == None ]];then
        echo "$names_var: creating '$name' returned no ID" >&2
        return 1
      fi
      resolved_ids[i]=$id
    done
  fi

  local IFS=,
  printf -v "$ids_var" '%s' "${resolved_ids[*]}"
}
