#!/bin/sh
set -e

echo "Waiting for database at ${DB_HOST}:5432..."
until nc -z "${DB_HOST}" 5432; do
  echo "  waiting… sleeping 2s"
  sleep 2
done

echo "Running migration..."
npx prisma migrate deploy

echo "Migrations complete. Starting..."
exec node /app/server/index.mjs