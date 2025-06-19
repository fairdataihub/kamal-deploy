#! /bin/sh

set -eu
set -o pipefail

source ./env.sh

echo "Creating backup of $POSTGRES_DATABASE database..."
pg_dump --format=custom \
        -h $POSTGRES_HOST \
        -p $POSTGRES_PORT \
        -U $POSTGRES_USER \
        -d $POSTGRES_DATABASE \
        $PGDUMP_EXTRA_OPTS \
        > db.dump

timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}/${POSTGRES_DATABASE}_${timestamp}.dump"

if [ -n "$PASSPHRASE" ]; then
  echo "Encrypting backup..."
  rm -f db.dump.gpg
  gpg --symmetric --batch --passphrase "$PASSPHRASE" db.dump
  rm db.dump
  local_file="db.dump.gpg"
  s3_uri="${s3_uri_base}.gpg"
else
  local_file="db.dump"
  s3_uri="$s3_uri_base"
fi

set -x # Remove this line to disable debug output

echo "Uploading backup to $S3_BUCKET..."
aws $aws_args s3 cp "$local_file" "$s3_uri"
rm "$local_file"

echo "Backup complete."


# TODO: Debug list-objects-v2 --query filtering
if [ -n "$BACKUP_KEEP_DAYS" ]; then
  sec=$((86400 * BACKUP_KEEP_DAYS))
  date_from_remove=$(date -u -d "@$(($(date +%s) - sec))" +"%Y-%m-%dT%H:%M:%S.%6N+00:00")
  backups_query="Contents[?LastModified<=\`${date_from_remove}\`].Key"

  echo "Removing old backups from $S3_BUCKET..."
  keys=$(aws $aws_args s3api list-objects-v2 \
    --bucket "${S3_BUCKET}" \
    --prefix "${S3_PREFIX}" \
    --no-paginate \
    --query "${backups_query}" \
    --output text 2>/dev/null || echo "")

  if [ -n "$keys" ]; then
    echo "$keys" | xargs -n1 -t -I {} aws $aws_args s3 rm s3://"${S3_BUCKET}"/{}
  else
    echo "No old backups found."
  fi
  echo "Removal complete."
fi