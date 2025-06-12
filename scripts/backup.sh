#!/bin/sh

set -e

POSTGRES_DB="${POSTGRES_DB:-$POSTGRES_DATABASE}"
export PGPASSWORD="$POSTGRES_PASS"

# Timestamp for this run
TS=$(date +%Y%m%d_%H%M%S)
OUT="/backups/${POSTGRES_DB}_${TS}.sql.gz"


echo "[$(date)] Dumping $POSTGRES_DB → $OUT"
/usr/bin/pg_dump \
  --username="$POSTGRES_USER" \
  --host="$POSTGRES_HOST" \
  --port="$POSTGRES_PORT" \
  "$POSTGRES_DB" \
| gzip > "$OUT"


echo "[$(date)] Uploading to R2 bucket $BUCKET"
aws --endpoint-url "https://${HOST_BASE}" \
    s3 cp "$OUT" "s3://${BUCKET}/${TS}.sql.gz" \
    --no-guess-mime-type --content-type application/octet-stream

echo "[$(date)] Pruning local dumps older than $REMOVE_BEFORE days"
find /backups -type f -name "${POSTGRES_DB}_*.sql.gz" -mtime +${REMOVE_BEFORE} -delete