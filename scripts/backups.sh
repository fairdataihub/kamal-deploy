#!/bin/sh
set -eu
set -o pipefail

# Load environment variables from the built-in env.sh
. ./env.sh

echo "[$(date)] Creating backup of database '$POSTGRES_DATABASE'..."
# Ensure pg_dump can authenticate
export PGPASSWORD="$POSTGRES_PASSWORD"

# Timestamp and output path
ts=$(date +"%Y%m%d_%H%M%S")
out="/backups/${POSTGRES_DATABASE}_${ts}.sql.gz"

# Dump and compress the database
default_port="${POSTGRES_PORT:-5432}"
/usr/bin/pg_dump \
  --format=custom \
  --host="$POSTGRES_HOST" \
  --port="$default_port" \
  --username="$POSTGRES_USER" \
  --dbname="$POSTGRES_DATABASE" \
  $PGDUMP_EXTRA_OPTS \
| gzip > "$out"

# Prepare S3 URI
s3_uri="s3://${S3_BUCKET}/${S3_PREFIX}/${POSTGRES_DATABASE}_${ts}.sql.gz"

# Encrypt if needed
if [ -n "${PASSPHRASE:-}" ]; then
  echo "[$(date)] Encrypting backup..."
  gpg --symmetric --batch --passphrase="$PASSPHRASE" "$out"
  rm "$out"
  out_gpg="${out}.gpg"
  mv "${out}.gpg" "$out_gpg"
  s3_uri="${s3_uri}.gpg"
  local_file="$out_gpg"
else
  local_file="$out"
fi

echo "[$(date)] Uploading backup to ${S3_BUCKET}..."
aws --no-verify-ssl \
    --endpoint-url "$S3_ENDPOINT" \
    s3 cp "$local_file" "$s3_uri" \
    --no-guess-mime-type \
    --content-type application/octet-stream
rm "$local_file"

# Prune old backups if configured
if [ -n "${BACKUP_KEEP_DAYS:-}" ]; then
  echo "[$(date)] Pruning old backups older than ${BACKUP_KEEP_DAYS} days..."
  sec=$(( BACKUP_KEEP_DAYS * 86400 ))
  cutoff=$(date -d "@$(($(date +%s) - sec))" +"%Y-%m-%d")
  query="Contents[?LastModified<=\'${cutoff} 00:00:00\'].{Key: Key}"

  aws --no-verify-ssl \
      --endpoint-url "$S3_ENDPOINT" \
      s3api list-objects \
      --bucket "$S3_BUCKET" \
      --prefix "$S3_PREFIX" \
      --query "$query" \
      --output text \
  | xargs -r -n1 -I '{}' aws --no-verify-ssl \
      --endpoint-url "$S3_ENDPOINT" \
      s3 rm "s3://$S3_BUCKET/{}"
  echo "[$(date)] Prune complete."
fi

echo "[$(date)] Backup finished."