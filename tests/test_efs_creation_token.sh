#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=environment/scripts/lib.sh
source "$root/environment/scripts/lib.sh"

token_a=$(efs_creation_token 'foo!bar')
token_b=$(efs_creation_token 'foobar')
token_repeat=$(efs_creation_token 'foo!bar')
token_symbols=$(efs_creation_token '---')
token_unicode=$(efs_creation_token 'ファイルシステム')
token_long=$(efs_creation_token 'this-is-a-very-long-file-system-name-that-must-not-overflow-the-creation-token-limit')

[[ "$token_a" == "$token_repeat" ]] || {
  echo 'EFS creation tokens must be stable for repeated runs.' >&2
  exit 1
}
[[ "$token_a" != "$token_b" ]] || {
  echo 'Names that sanitize to the same prefix must still get different tokens.' >&2
  exit 1
}
for token in "$token_a" "$token_b" "$token_symbols" "$token_unicode" "$token_long";do
  [[ -n "$token" && ${#token} -le 64 && "$token" =~ ^[a-zA-Z0-9._-]+$ ]] || {
    echo "Invalid EFS creation token: $token" >&2
    exit 1
  }
done
[[ "$token_symbols" == ec2env-efs-* && "$token_unicode" == ec2env-efs-* ]] || {
  echo 'Names without ASCII letters or digits must use a readable fallback prefix.' >&2
  exit 1
}

echo 'EFS creation token tests passed.'
