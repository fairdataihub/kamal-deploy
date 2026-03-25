# -------- Base --------
# Base stage with minimal dependencies needed across build stages
FROM node:22-alpine AS base

# Install OpenSSL (required by Prisma)
RUN apk add --no-cache openssl

WORKDIR /app


# -------- Dependencies --------
# Separate stage for installing dependencies - improves layer caching
FROM base AS deps

# Copy only package files for dependency installation
COPY package.json yarn.lock ./

# Install dependencies without running scripts (Prisma generate happens in build stage)
# This prevents postinstall scripts from running before source code is available
RUN yarn install --frozen-lockfile --ignore-scripts \
  && yarn cache clean


# -------- Build --------
# Build stage - generates Prisma Client and builds Nuxt application
FROM base AS build

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy source files
COPY . .

# Build-time argument for Prisma
ARG DATABASE_URL

# Generate Prisma Client and build Nuxt application
RUN yarn prisma:generate \
  && yarn run build


# -------- Runtime --------
# Lean production image with only runtime dependencies
FROM node:22-alpine AS runner

LABEL maintainer="FAIR Data Innovations Hub <contact@fairdataihub.org>" \
  description="Nuxt + Prisma + PostgreSQL optimized Docker image"

# Install only runtime dependencies:
# - openssl: required by Prisma Client
# - busybox-extras: provides netcat for DB readiness check
RUN apk add --no-cache openssl busybox-extras

WORKDIR /app

ENV NODE_ENV=production
ENV NITRO_HOST=0.0.0.0

# Install minimal Prisma CLI for running migrations at startup
# We copy yarn.lock to extract exact Prisma version, then remove it
COPY yarn.lock ./
RUN PRISMA_VERSION=$(grep -A 2 'prisma@\^' yarn.lock | grep '  version' | head -1 | sed 's/.*version "\(.*\)"/\1/') \
  && echo "Installing Prisma ${PRISMA_VERSION}" \
  && yarn add --production --no-lockfile prisma@${PRISMA_VERSION} \
  && yarn cache clean \
  && rm yarn.lock

# Copy compiled Nuxt application from build stage
# Nitro bundles most dependencies, but some (like Prisma) remain in .output/server/node_modules
COPY --from=build /app/.output ./.output

# Copy Prisma schema and migrations for `prisma migrate deploy`
COPY --from=build /app/prisma ./prisma

# Copy startup script and make it executable
COPY scripts/start.sh ./scripts/start.sh
RUN chmod +x ./scripts/start.sh

EXPOSE 3000

# Use startup script to run migrations before starting the app
CMD ["./scripts/start.sh"]
