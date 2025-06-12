#!/bin/sh
set -eu
set -o pipefail

# load in all the env vars (S3_*, POSTGRES_*, BACKUP_KEEP_DAYS, etc.)
source ./env.sh

echo "[$(date)] Dumping database '$POSTGRES_DATABASE' → /backups/${POSTGRES_DATABASE}_*.sql.gz"
export PGPASSWORD="$POSTGRES_PASSWORD"
TS=$(date +"%Y%m%d_%H%M%S")
OUT="/backups/${POSTGRES_DATABASE}_${TS}.sql.gz"

pg_dump --format=custom \
        --username="$POSTGRES_USER" \
        --host="$POSTGRES_HOST" \
        --port="${POSTGRES_PORT:-5432}" \
        "$POSTGRES_DATABASE" \
| gzip > "$OUT"

echo "[$(date)] Uploading to s3://${S3_BUCKET}/${S3_PREFIX}/"
# disable SSL verify and use the correct endpoint
aws --no-verify-ssl \
    --endpoint-url "https://${S3_ENDPOINT}" \
    s3 cp "$OUT" "s3://${S3_BUCKET}/${S3_PREFIX}/${POSTGRES_DATABASE}_${TS}.sql.gz" \
    --no-guess-mime-type \
    --content-type application/octet-stream

rm "$OUT"

if [ -n "${BACKUP_KEEP_DAYS:-}" ]; then
  echo "[$(date)] Pruning local dumps older than $BACKUP_KEEP_DAYS days"
  find /backups -type f -name "${POSTGRES_DATABASE}_*.sql.gz" \
       -mtime +${BACKUP_KEEP_DAYS} -delete
fi

echo "[$(date)] Backup complete."