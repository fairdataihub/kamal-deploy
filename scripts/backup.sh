#! /bin/sh

# PostgreSQL Database Backup Script
# This script creates encrypted backups of a PostgreSQL database and uploads them to S3
# It also handles cleanup of old backups based on retention policy

# Exit on any error and treat unset variables as errors
set -eu
set -o pipefail

# Load environment variables from env.sh file
# Expected variables: POSTGRES_*, S3_*, PASSPHRASE, BACKUP_KEEP_DAYS, aws_args
source ./env.sh

echo "Creating backup of $POSTGRES_DATABASE database..."

# Create a PostgreSQL dump using pg_dump with custom format
# Custom format allows for selective restore and is more efficient than plain text
pg_dump --format=custom \
        -h $POSTGRES_HOST \
        -p $POSTGRES_PORT \
        -U $POSTGRES_USER \
        -d $POSTGRES_DATABASE \
        $PGDUMP_EXTRA_OPTS \
        > db.dump

# Generate timestamp for unique backup filename
timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}/${POSTGRES_DATABASE}_${timestamp}.dump"

# Handle encryption if PASSPHRASE is provided
if [ -n "$PASSPHRASE" ]; then
  echo "Encrypting backup..."
  # Remove any existing encrypted file to avoid conflicts
  rm -f db.dump.gpg
  # Encrypt the dump file using GPG symmetric encryption
  gpg --symmetric --batch --passphrase "$PASSPHRASE" db.dump
  # Remove the unencrypted dump file for security
  rm db.dump
  local_file="db.dump.gpg"
  s3_uri="${s3_uri_base}.gpg"
else
  # Use unencrypted file if no passphrase provided
  local_file="db.dump"
  s3_uri="$s3_uri_base"
fi

# Enable debug output to show commands being executed
set -x # Remove this line to disable debug output

echo "Uploading backup to $S3_BUCKET..."

# Upload the backup file (encrypted or unencrypted) to S3
# aws_args should contain any additional AWS CLI arguments (e.g., --profile, --region)
aws $aws_args s3 cp "$local_file" "$s3_uri"

# Clean up local backup file after successful upload
rm "$local_file"

echo "Backup complete."

# Cleanup old backups based on retention policy
# TODO: Debug list-objects-v2 --query filtering
if [ -n "$BACKUP_KEEP_DAYS" ]; then
  # Calculate the cutoff date in seconds from epoch
  sec=$((86400 * BACKUP_KEEP_DAYS))
  # Convert to ISO 8601 format for AWS CLI query
  date_from_remove=$(date -u -d "@$(($(date +%s) - sec))" +"%Y-%m-%dT%H:%M:%S.%6N+00:00")
  # JMESPath query to find objects older than the cutoff date
  backups_query="Contents[?LastModified<=\`${date_from_remove}\`].Key"

  echo "Removing old backups from $S3_BUCKET..."
  
  # List objects in S3 bucket that are older than the retention period
  # --no-paginate ensures we get all results in one call
  # --query filters results to only include keys of old backups
  # 2>/dev/null suppresses errors if no objects match the criteria
  keys=$(aws $aws_args s3api list-objects-v2 \
    --bucket "${S3_BUCKET}" \
    --prefix "${S3_PREFIX}" \
    --no-paginate \
    --query "${backups_query}" \
    --output text 2>/dev/null || echo "")

  # Delete old backup files if any were found
  if [ -n "$keys" ]; then
    # Use xargs to delete each backup file individually
    # -n1: process one argument at a time
    # -t: print the command before executing
    # -I {}: use {} as placeholder for the key
    echo "$keys" | xargs -n1 -t -I {} aws $aws_args s3 rm s3://"${S3_BUCKET}"/{}
  else
    echo "No old backups found."
  fi
  echo "Removal complete."
fi