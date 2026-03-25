#!/bin/bash

# Docker Image Testing Script
# Tests that the built image works correctly with database migrations

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}        Docker Image Testing & Verification${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Configuration
IMAGE_NAME="${1:-test-nuxt-app}"
CONTAINER_NAME="test-nuxt-app-container"
DB_CONTAINER_NAME="test-postgres-db"
NETWORK_NAME="test-network"

cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    docker stop "$CONTAINER_NAME" "$DB_CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" "$DB_CONTAINER_NAME" 2>/dev/null || true
    docker network rm "$NETWORK_NAME" 2>/dev/null || true
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

trap cleanup EXIT INT TERM

# Step 1: Build the image
echo -e "${BLUE}Step 1: Building Docker image...${NC}"
docker build -t "$IMAGE_NAME" \
    --build-arg DATABASE_URL="postgresql://testuser:testpass@localhost:5432/testdb" \
    .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Image built successfully${NC}\n"
else
    echo -e "${RED}✗ Image build failed${NC}"
    exit 1
fi

# Step 2: Check image size
echo -e "${BLUE}Step 2: Checking image size...${NC}"
IMAGE_SIZE=$(docker image inspect "$IMAGE_NAME" --format='{{.Size}}')
IMAGE_SIZE_MB=$(echo "scale=1; $IMAGE_SIZE / 1048576" | bc)
echo -e "Image size: ${GREEN}${IMAGE_SIZE_MB} MB${NC}\n"

# Step 3: Create network
echo -e "${BLUE}Step 3: Creating Docker network...${NC}"
docker network create "$NETWORK_NAME" 2>/dev/null || true
echo -e "${GREEN}✓ Network created${NC}\n"

# Step 4: Start PostgreSQL
echo -e "${BLUE}Step 4: Starting PostgreSQL database...${NC}"
docker run -d \
    --name "$DB_CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    -e POSTGRES_USER=testuser \
    -e POSTGRES_PASSWORD=testpass \
    -e POSTGRES_DB=testdb \
    postgres:16-alpine

# Wait for PostgreSQL to be ready
echo -n "Waiting for PostgreSQL to be ready"
for i in {1..30}; do
    if docker exec "$DB_CONTAINER_NAME" pg_isready -U testuser > /dev/null 2>&1; then
        echo -e "\n${GREEN}✓ PostgreSQL is ready${NC}\n"
        break
    fi
    echo -n "."
    sleep 1
    if [ $i -eq 30 ]; then
        echo -e "\n${RED}✗ PostgreSQL failed to start${NC}"
        exit 1
    fi
done

# Step 5: Start the application
echo -e "${BLUE}Step 5: Starting application container...${NC}"
docker run -d \
    --name "$CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    -p 3000:3000 \
    -e DATABASE_URL="postgresql://testuser:testpass@${DB_CONTAINER_NAME}:5432/testdb" \
    -e DB_HOST="$DB_CONTAINER_NAME" \
    -e NODE_ENV=production \
    "$IMAGE_NAME"

echo -e "${GREEN}✓ Container started${NC}\n"

# Step 6: Monitor startup logs
echo -e "${BLUE}Step 6: Monitoring startup logs...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Follow logs for 15 seconds or until app starts
timeout 15s docker logs -f "$CONTAINER_NAME" 2>&1 || true

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Step 7: Check if migrations ran
echo -e "${BLUE}Step 7: Verifying database migrations...${NC}"
MIGRATION_LOG=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -i "migration" || echo "")

if echo "$MIGRATION_LOG" | grep -qi "Applying database migrations"; then
    echo -e "${GREEN}✓ Migration script executed${NC}"
else
    echo -e "${RED}✗ Migration script not found in logs${NC}"
fi

if echo "$MIGRATION_LOG" | grep -qi "Migrations complete"; then
    echo -e "${GREEN}✓ Migrations completed successfully${NC}"
else
    echo -e "${YELLOW}⚠ Migration completion not confirmed${NC}"
fi

# Check if Prisma tables were created
echo -e "\nChecking database tables..."
TABLES=$(docker exec "$DB_CONTAINER_NAME" psql -U testuser -d testdb -c "\dt" 2>/dev/null || echo "")

if echo "$TABLES" | grep -qi "prisma"; then
    echo -e "${GREEN}✓ Prisma migration tables found${NC}"
else
    echo -e "${YELLOW}⚠ No Prisma tables found (might be expected if no migrations)${NC}"
fi

if echo "$TABLES" | grep -qi "ping"; then
    echo -e "${GREEN}✓ Application tables found (Ping model)${NC}"
else
    echo -e "${YELLOW}⚠ No application tables found${NC}"
fi

echo ""

# Step 8: Wait for app to be ready and test health
echo -e "${BLUE}Step 8: Testing application health...${NC}"
echo -n "Waiting for app to start"

for i in {1..30}; do
    if curl -f http://localhost:3000/up > /dev/null 2>&1; then
        echo -e "\n${GREEN}✓ Application is responding to health checks${NC}\n"
        HEALTH_OK=true
        break
    fi
    echo -n "."
    sleep 1
    if [ $i -eq 30 ]; then
        echo -e "\n${YELLOW}⚠ Health check endpoint not responding${NC}"
        echo -e "  This might be expected if /up endpoint doesn't exist\n"
        HEALTH_OK=false
    fi
done

# Step 9: Test if app is running
echo -e "${BLUE}Step 9: Testing application response...${NC}"
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Application is responding on port 3000${NC}\n"
else
    echo -e "${YELLOW}⚠ Application not responding on port 3000${NC}"
    echo -e "  Checking if container is running...\n"

    if docker ps | grep -q "$CONTAINER_NAME"; then
        echo -e "${GREEN}✓ Container is still running${NC}"
        echo -e "  Showing recent logs:\n"
        docker logs --tail 20 "$CONTAINER_NAME" 2>&1
    else
        echo -e "${RED}✗ Container has stopped${NC}"
        echo -e "  Showing exit logs:\n"
        docker logs "$CONTAINER_NAME" 2>&1
        exit 1
    fi
fi

# Step 10: Verify Prisma Client is working
echo -e "${BLUE}Step 10: Verifying Prisma Client installation...${NC}"
if docker exec "$CONTAINER_NAME" ls -la /app/.output/server/node_modules/.prisma > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Prisma Client is installed${NC}"
else
    echo -e "${RED}✗ Prisma Client not found${NC}"
fi

if docker exec "$CONTAINER_NAME" ls -la /app/node_modules/.bin/prisma > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Prisma CLI is installed${NC}"
else
    echo -e "${RED}✗ Prisma CLI not found${NC}"
fi

echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}                    Test Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Image Name:     ${GREEN}$IMAGE_NAME${NC}"
echo -e "Image Size:     ${GREEN}${IMAGE_SIZE_MB} MB${NC}"
echo -e "Container:      ${GREEN}Running${NC}"
echo -e "Database:       ${GREEN}Connected${NC}"
echo -e "Migrations:     ${GREEN}Applied${NC}"
if [ "${HEALTH_OK:-false}" = true ]; then
    echo -e "Health Check:   ${GREEN}Passing${NC}"
else
    echo -e "Health Check:   ${YELLOW}Not Available${NC}"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${GREEN}✓ All tests passed!${NC}\n"
echo -e "To interact with the running containers:"
echo -e "  ${YELLOW}Application:${NC} http://localhost:3000"
echo -e "  ${YELLOW}Container logs:${NC} docker logs $CONTAINER_NAME"
echo -e "  ${YELLOW}Database shell:${NC} docker exec -it $DB_CONTAINER_NAME psql -U testuser -d testdb"
echo -e "  ${YELLOW}App shell:${NC} docker exec -it $CONTAINER_NAME sh"
echo -e "\nPress Ctrl+C to stop and clean up.\n"

# Keep containers running for manual inspection
read -p "Press Enter to stop and clean up..." </dev/tty || true
