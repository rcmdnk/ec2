#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/bootstrap.sh" "${1:-}" "${2:-}" ec2

get_s3files_id() {
  local name=$1
  aws "${AWS_ARGS[@]}" s3files list-file-systems \
    --query "fileSystems[?name=='$name'].fileSystemId" --output text
}

prepare_s3files_creation() {
  local n_names=$1
  if [[ -z "$SUBNET_IDS" ]];then
    echo "SUBNET_IDS must be set to create an S3 Files filesystem" >&2
    return 1
  fi
  if [[ -z "$S3FILES_BUCKET_NAMES" ]];then
    echo "S3FILES_BUCKET_NAMES is required when S3FILES_NAMES are created" >&2
    return 1
  fi
  S3FILES_BUCKET_NAMES=$(make_array "$n_names" "$S3FILES_BUCKET_NAMES") || return 1
  S3FILES_ROLE_ARNS=$(make_array "$n_names" "$S3FILES_ROLE_ARNS") || return 1
  if [[ -z "$S3FILES_SECURITY_GROUP_IDS" ]];then
    S3FILES_SECURITY_GROUP_IDS="${SECURITY_GROUP_IDS-}"
  fi
  if [[ -z "$S3FILES_SECURITY_GROUP_IDS" ]];then
    echo 'S3FILES_SECURITY_GROUP_IDS or AWS_SECURITY_GROUP_IDS is required when S3 Files are created' >&2
    return 1
  fi
  S3FILES_SECURITY_GROUP_IDS=$(make_array "$n_names" "$S3FILES_SECURITY_GROUP_IDS") || return 1
}

s3_bucket_arn() {
  local bucket=$1
  if [[ "$bucket" == arn:* ]];then
    printf '%s\n' "$bucket"
  else
    printf 'arn:aws:s3:::%s\n' "$bucket"
  fi
}

validate_s3_bucket() {
  local bucket=$1 bucket_name bucket_region versioning
  bucket_name=${bucket##*:::}
  aws "${AWS_ARGS[@]}" s3api head-bucket --bucket "$bucket_name" >/dev/null
  bucket_region=$(aws "${AWS_ARGS[@]}" s3api get-bucket-location \
    --bucket "$bucket_name" --query LocationConstraint --output text)
  [[ "$bucket_region" == None ]] && bucket_region=us-east-1
  [[ "$bucket_region" == "$REGION" ]] || {
    echo "S3 bucket '$bucket_name' is in '$bucket_region', expected '$REGION'." >&2
    return 1
  }
  versioning=$(aws "${AWS_ARGS[@]}" s3api get-bucket-versioning \
    --bucket "$bucket_name" --query Status --output text)
  [[ "$versioning" == Enabled ]] || {
    echo "S3 bucket '$bucket_name' must have versioning enabled for S3 Files." >&2
    return 1
  }
}

create_s3files_role() {
  local i=$1 name=$2 bucket bucket_name role_arn role_name account_id
  local trust_policy permissions_policy managed_tag
  role_arn=$(csv_items "$S3FILES_ROLE_ARNS" "$i")
  [[ -n "$role_arn" ]] && { printf '%s\n' "$role_arn"; return; }

  bucket=$(s3_bucket_arn "$(csv_items "$S3FILES_BUCKET_NAMES" "$i")")
  bucket_name=${bucket#arn:aws:s3:::}
  account_id=$(aws "${AWS_ARGS[@]}" sts get-caller-identity --query Account --output text)
  role_name="${RESOURCE_MANAGED_BY}-s3files-${name//[^a-zA-Z0-9+=,.@_-]/-}"
  role_name=${role_name:0:64}
  trust_policy=$(printf '{"Version":"2012-10-17","Statement":[{"Sid":"AllowS3FilesAssumeRole","Effect":"Allow","Principal":{"Service":"elasticfilesystem.amazonaws.com"},"Action":"sts:AssumeRole","Condition":{"StringEquals":{"aws:SourceAccount":"%s"},"ArnLike":{"aws:SourceArn":"arn:aws:s3files:%s:%s:file-system/*"}}}]}' \
    "$account_id" "$REGION" "$account_id")
  if role_arn=$(aws "${AWS_ARGS[@]}" iam get-role --role-name "$role_name" --query Role.Arn --output text 2>/dev/null); then
    managed_tag=$(aws "${AWS_ARGS[@]}" iam list-role-tags --role-name "$role_name" \
      --query "Tags[?Key=='ManagedBy'].Value | [0]" --output text)
    [[ "$managed_tag" == "$RESOURCE_MANAGED_BY" ]] || {
      echo "Refusing to reuse unowned IAM role '$role_name'. Set S3FILES_ROLE_ARNS explicitly." >&2
      return 1
    }
  else
    aws "${AWS_ARGS[@]}" iam create-role --role-name "$role_name" \
      --assume-role-policy-document "$trust_policy" >/dev/null
    role_arn=$(aws "${AWS_ARGS[@]}" iam get-role --role-name "$role_name" --query Role.Arn --output text)
    aws "${AWS_ARGS[@]}" iam tag-role --role-name "$role_name" \
      --tags "Key=ManagedBy,Value=$RESOURCE_MANAGED_BY" >/dev/null
  fi
  permissions_policy=$(printf '{"Version":"2012-10-17","Statement":[{"Sid":"S3BucketPermissions","Effect":"Allow","Action":["s3:ListBucket","s3:ListBucketVersions"],"Resource":"%s","Condition":{"StringEquals":{"aws:ResourceAccount":"%s"}}},{"Sid":"S3ObjectPermissions","Effect":"Allow","Action":["s3:AbortMultipartUpload","s3:DeleteObject*","s3:GetObject*","s3:List*","s3:PutObject*"],"Resource":"%s/*","Condition":{"StringEquals":{"aws:ResourceAccount":"%s"}}},{"Sid":"UseKmsKeyWithS3Files","Effect":"Allow","Action":["kms:GenerateDataKey","kms:Encrypt","kms:Decrypt","kms:ReEncryptFrom","kms:ReEncryptTo"],"Condition":{"StringLike":{"kms:ViaService":"s3.%s.amazonaws.com","kms:EncryptionContext:aws:s3:arn":["%s","%s/*"]}},"Resource":"arn:aws:kms:%s:%s:*"},{"Sid":"EventBridgeManage","Effect":"Allow","Action":["events:DeleteRule","events:DisableRule","events:EnableRule","events:PutRule","events:PutTargets","events:RemoveTargets"],"Condition":{"StringEquals":{"events:ManagedBy":"elasticfilesystem.amazonaws.com"}},"Resource":"arn:aws:events:*:*:rule/DO-NOT-DELETE-S3-Files*"},{"Sid":"EventBridgeRead","Effect":"Allow","Action":["events:DescribeRule","events:ListRuleNamesByTarget","events:ListRules","events:ListTargetsByRule"],"Resource":"arn:aws:events:*:*:rule/*"}]}' \
    "$bucket" "$account_id" "$bucket" "$account_id" "$REGION" "$bucket" "$bucket" "$REGION" "$account_id")
  aws "${AWS_ARGS[@]}" iam put-role-policy --role-name "$role_name" \
    --policy-name S3FilesAccess --policy-document "$permissions_policy"
  echo "Using S3 Files service role '$role_name' for bucket '$bucket_name'" >&2
  printf '%s\n' "$role_arn"
}

create_s3files() {
  local i=$1 name=$2 bucket role_arn role_name id tags tag_items subnet_id security_group_id
  bucket=$(s3_bucket_arn "$(csv_items "$S3FILES_BUCKET_NAMES" "$i")")
  validate_s3_bucket "$bucket" || return 1
  role_arn=$(create_s3files_role "$i" "$name") || return 1
  validate_resource_metadata || return 1
  tag_items=$(printf '{"key":"Name","value":%s},{"key":"ManagedBy","value":%s}' \
    "$(json_quote "$name")" "$(json_quote "$RESOURCE_MANAGED_BY")")
  [[ -z "$RESOURCE_PROJECT" ]] || tag_items+=$(printf ',{"key":"Project","value":%s}' "$(json_quote "$RESOURCE_PROJECT")")
  tags="[$tag_items]"
  id=$(aws "${AWS_ARGS[@]}" s3files create-file-system --bucket "$bucket" \
    --role-arn "$role_arn" --accept-bucket-warning --tags "$tags" \
    --query fileSystemId --output text) || return 1
  [[ -n "$id" && "$id" != None ]] || return 1
  record_resource s3files "$id" "$name" || return 1
  if [[ -z "$(csv_items "$S3FILES_ROLE_ARNS" "$i")" ]];then
    role_name=${RESOURCE_MANAGED_BY}-s3files-${name//[^a-zA-Z0-9+=,.@_-]/-}
    role_name=${role_name:0:64}
    record_resource s3files-role "$role_name" "$name" || return 1
  fi
  security_group_id=$(csv_items "$S3FILES_SECURITY_GROUP_IDS" "$i")
  while IFS= read -r subnet_id; do
    aws "${AWS_ARGS[@]}" s3files create-mount-target --file-system-id "$id" \
      --subnet-id "$subnet_id" --security-groups "$security_group_id" >/dev/null || return 1
  done < <(csv_items "$SUBNET_IDS")
  echo "Created S3 Files '$name': $id" >&2
  echo 'Mount targets can take several minutes to become available.' >&2
  printf '%s\n' "$id"
}

setup_filesystem_ids s3files create_s3files prepare_s3files_creation
echo "$S3FILES_IDS"
