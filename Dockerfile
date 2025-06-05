# Build stage
FROM node:20-alpine AS builder

# Use alpine-based image and install only necessary dependencies
RUN apk add --no-cache openssl

WORKDIR /app

# Only needed for prisma build
ARG DATABASE_URL

# Copy only necessary files for dependency installation
COPY package.json yarn.lock ./
COPY prisma ./prisma/

RUN yarn install --frozen-lockfile \
  && yarn prisma:generate \
  && yarn cache clean

# Copy source files and build
COPY . .
RUN yarn run build

# Production stage
FROM node:20-alpine

LABEL maintainer="FAIR Data Innovations Hub <contact@fairdataihub.org>" \
  description="Testing Kamal workflow..."

# Busybox is used netcat for waiting for Postgres to be ready
RUN apk add --no-cache openssl busybox-extras

WORKDIR /app

# Copy only the necessary files from builder stage
# COPY --from=builder /app/package.json ./
COPY --from=builder /app/.output ./
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma
# Copy the Prisma schema & migrations, so `prisma migrate deploy` can see them
COPY --from=builder /app/prisma ./prisma

# Create startup script that runs migrations before starting the app
#  1) loops until Postgres is reachable using netcat
#  2) runs Prisma migrations
#  3) finally launches Nuxt
RUN printf '%s\n' \
    '#!/bin/sh' \
    'set -e' \
    '' \
    'echo "Waiting for database at ${DB_HOST}:5432..."' \
    'until nc -z "${DB_HOST}" 5432; do' \
    '  echo "  waiting… sleeping 2s"' \
    '  sleep 2' \
    'done' \
    '' \
    'echo "Running migration..."' \
    'npx prisma migrate deploy' \
    '' \
    'echo "Migrations complete. Starting..."' \
    'exec node /app/server/index.mjs' \
  > /app/start.sh && \
  chmod +x /app/start.sh

EXPOSE 3000

HEALTHCHECK --interval=5s --timeout=2s --start-period=10s \
  CMD wget --spider --quiet http://localhost:3000/up || exit 1

CMD ["/bin/sh", "/app/start.sh"]