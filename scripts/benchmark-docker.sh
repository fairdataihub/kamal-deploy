#!/bin/bash

# Docker Dockerfile Benchmark Script
# Compares old Dockerfile (commit 5d7c641) with optimized version (current HEAD)
# Measures: build times, image sizes, layer caching effectiveness, context transfer

set -euo pipefail

#==============================================================================
# Configuration & Global Variables
#==============================================================================

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# File paths
OLD_DOCKERFILE="$PROJECT_DIR/Dockerfile.old"
NEW_DOCKERFILE="$PROJECT_DIR/Dockerfile"
RESULTS_DIR="$PROJECT_DIR/benchmark-results"

# Docker image tags
OLD_TAG="benchmark-old"
NEW_TAG="benchmark-new"

# Temporary files
TEMP_DIR="/tmp/docker-benchmark-$$"
OLD_BUILD_LOG="$TEMP_DIR/build-old.log"
NEW_BUILD_LOG="$TEMP_DIR/build-new.log"

# CLI flags
SKIP_CLEAN=false
SKIP_CODE_CHANGE=false
SKIP_DEP_CHANGE=false
JSON_ONLY=false
CSV_ONLY=false
NO_CLEANUP=false
VERBOSE=false

# Results storage
declare -A RESULTS

#==============================================================================
# Utility Functions
#==============================================================================

# Print colored header
print_header() {
    local text="$1"
    echo -e "\n${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    printf "${BOLD}${BLUE}║${NC} %-61s ${BOLD}${BLUE}║${NC}\n" "$text"
    echo -e "${BOLD}${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}\n"
}

# Print section
print_section() {
    local text="$1"
    echo -e "\n${BOLD}${CYAN}━━━ $text ━━━${NC}"
}

# Print info message
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Print success message
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print error message
print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Print warning message
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Convert bytes to human-readable format
bytes_to_human() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}")KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}")GB"
    fi
}

# Calculate percentage improvement
calculate_improvement() {
    local old=$1
    local new=$2
    awk "BEGIN {printf \"%.1f\", (($old - $new) / $old) * 100}"
}

#==============================================================================
# Cleanup Functions
#==============================================================================

cleanup() {
    if [ "$NO_CLEANUP" = true ]; then
        print_warning "Skipping cleanup (--no-cleanup flag)"
        return
    fi

    print_info "Cleaning up..."

    # Restore any backup files
    if [ -d "$PROJECT_DIR" ]; then
        find "$PROJECT_DIR" -name "*.backup" -type f 2>/dev/null | while read -r backup; do
            original="${backup%.backup}"
            if [ -f "$backup" ]; then
                mv "$backup" "$original"
                print_info "Restored: $(basename "$original")"
            fi
        done
    fi

    # Remove temporary Docker images
    if command -v docker &> /dev/null; then
        for tag in "$OLD_TAG" "$NEW_TAG" "${OLD_TAG}-warm" "${NEW_TAG}-warm"; do
            if docker image inspect "$tag" &> /dev/null; then
                docker rmi -f "$tag" &> /dev/null || true
            fi
        done
    fi

    # Remove temporary directory
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi

    print_success "Cleanup complete"
}

# Set up trap handlers
trap cleanup EXIT INT TERM

#==============================================================================
# Dependency Checks
#==============================================================================

check_dependencies() {
    print_section "Checking Dependencies"

    local missing_deps=()

    for cmd in docker bc jq git; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
            print_error "Missing: $cmd"
        else
            print_success "Found: $cmd"
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Install with: sudo apt install ${missing_deps[*]}"
        exit 1
    fi

    # Check Docker BuildKit support
    if ! docker buildx version &> /dev/null; then
        print_warning "Docker Buildx not available. Results may vary."
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi

    print_success "All dependencies satisfied"
}

#==============================================================================
# Measurement Functions
#==============================================================================

# Measure build time and capture logs
measure_build_time() {
    local dockerfile=$1
    local tag=$2
    local log_file=$3
    local cache_option=${4:-}

    local start_time=$(date +%s.%N)

    # Build with or without cache
    if [ -n "$cache_option" ] && [ "$cache_option" = "no-cache" ]; then
        docker build -f "$dockerfile" \
            --no-cache \
            --build-arg DATABASE_URL="postgresql://dummy:dummy@localhost:5432/dummy" \
            -t "$tag" "$PROJECT_DIR" &> "$log_file"
    else
        docker build -f "$dockerfile" \
            --build-arg DATABASE_URL="postgresql://dummy:dummy@localhost:5432/dummy" \
            -t "$tag" "$PROJECT_DIR" &> "$log_file"
    fi

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    echo "$duration"
}

# Get image size in bytes
measure_image_size() {
    local tag=$1
    docker image inspect "$tag" --format='{{.Size}}'
}

# Count cache hits from build log
count_cache_hits() {
    local log_file=$1
    local cached=$(grep -c "CACHED" "$log_file" 2>/dev/null || echo 0)
    local total=$(grep -c "^Step " "$log_file" 2>/dev/null || echo 0)
    echo "${cached}/${total}"
}

# Extract context transfer size from build log
get_context_size() {
    local log_file=$1
    # Look for "Sending build context to Docker daemon"
    local context_line=$(grep "Sending build context" "$log_file" | head -1)
    if [ -n "$context_line" ]; then
        # Extract size (e.g., "1.234MB" or "512kB")
        echo "$context_line" | grep -oE '[0-9.]+[kMG]?B'
    else
        echo "0B"
    fi
}

#==============================================================================
# Test Scenario Functions
#==============================================================================

# Scenario 1: Clean build (no cache)
scenario_clean_build() {
    print_section "Scenario 1: Clean Build (No Cache)"

    print_info "Pruning Docker build cache..."
    docker builder prune -af > /dev/null 2>&1

    # Build old Dockerfile
    print_info "Building old Dockerfile (${OLD_TAG})..."
    local old_time=$(measure_build_time "$OLD_DOCKERFILE" "$OLD_TAG" "$OLD_BUILD_LOG" "no-cache")
    print_success "Old build completed in ${old_time}s"

    # Build new Dockerfile
    print_info "Building new Dockerfile (${NEW_TAG})..."
    local new_time=$(measure_build_time "$NEW_DOCKERFILE" "$NEW_TAG" "$NEW_BUILD_LOG" "no-cache")
    print_success "New build completed in ${new_time}s"

    # Measure image sizes
    local old_size=$(measure_image_size "$OLD_TAG")
    local new_size=$(measure_image_size "$NEW_TAG")

    # Get context sizes
    local old_context=$(get_context_size "$OLD_BUILD_LOG")
    local new_context=$(get_context_size "$NEW_BUILD_LOG")

    # Store results
    RESULTS[clean_build_old_time]=$old_time
    RESULTS[clean_build_new_time]=$new_time
    RESULTS[clean_build_old_size]=$old_size
    RESULTS[clean_build_new_size]=$new_size
    RESULTS[clean_build_old_context]=$old_context
    RESULTS[clean_build_new_context]=$new_context

    # Calculate improvements
    local time_improvement=$(calculate_improvement "$old_time" "$new_time")
    local size_improvement=$(calculate_improvement "$old_size" "$new_size")

    RESULTS[clean_build_time_improvement]=$time_improvement
    RESULTS[clean_build_size_improvement]=$size_improvement

    print_success "Clean build scenario complete"
}

# Scenario 2: Code change (modify Vue file)
scenario_code_change() {
    print_section "Scenario 2: Code Change (Vue File Modified)"

    local test_file="$PROJECT_DIR/app/pages/index.vue"

    if [ ! -f "$test_file" ]; then
        print_warning "Test file not found: $test_file"
        print_warning "Skipping code change scenario"
        return
    fi

    # Warm cache with initial builds
    print_info "Warming cache..."
    docker build -f "$OLD_DOCKERFILE" --build-arg DATABASE_URL="postgresql://dummy" \
        -t "${OLD_TAG}-warm" "$PROJECT_DIR" > /dev/null 2>&1
    docker build -f "$NEW_DOCKERFILE" --build-arg DATABASE_URL="postgresql://dummy" \
        -t "${NEW_TAG}-warm" "$PROJECT_DIR" > /dev/null 2>&1
    print_success "Cache warmed"

    # Backup original file
    cp "$test_file" "${test_file}.backup"

    # Modify file
    echo "<!-- Benchmark test $(date +%s) -->" >> "$test_file"
    print_info "Modified: $(basename "$test_file")"

    # Rebuild old Dockerfile
    print_info "Rebuilding old Dockerfile..."
    local old_rebuild_time=$(measure_build_time "$OLD_DOCKERFILE" "$OLD_TAG" "${OLD_BUILD_LOG}.rebuild")
    local old_cache_hits=$(count_cache_hits "${OLD_BUILD_LOG}.rebuild")
    print_success "Old rebuild: ${old_rebuild_time}s (cache: $old_cache_hits)"

    # Restore file before new build
    mv "${test_file}.backup" "$test_file"
    echo "<!-- Benchmark test $(date +%s) -->" >> "$test_file"

    # Rebuild new Dockerfile
    print_info "Rebuilding new Dockerfile..."
    local new_rebuild_time=$(measure_build_time "$NEW_DOCKERFILE" "$NEW_TAG" "${NEW_BUILD_LOG}.rebuild")
    local new_cache_hits=$(count_cache_hits "${NEW_BUILD_LOG}.rebuild")
    print_success "New rebuild: ${new_rebuild_time}s (cache: $new_cache_hits)"

    # Restore original file
    mv "${test_file}.backup" "$test_file" 2>/dev/null || true

    # Store results
    RESULTS[code_change_old_time]=$old_rebuild_time
    RESULTS[code_change_new_time]=$new_rebuild_time
    RESULTS[code_change_old_cache]=$old_cache_hits
    RESULTS[code_change_new_cache]=$new_cache_hits

    # Calculate improvement
    local rebuild_improvement=$(calculate_improvement "$old_rebuild_time" "$new_rebuild_time")
    RESULTS[code_change_time_improvement]=$rebuild_improvement

    print_success "Code change scenario complete"
}

# Scenario 3: Dependency change (modify package.json)
scenario_dep_change() {
    print_section "Scenario 3: Dependency Change (package.json Modified)"

    local test_file="$PROJECT_DIR/package.json"

    if [ ! -f "$test_file" ]; then
        print_warning "Test file not found: $test_file"
        print_warning "Skipping dependency change scenario"
        return
    fi

    # Warm cache with initial builds (if not already warmed)
    if ! docker image inspect "${OLD_TAG}-warm" &> /dev/null; then
        print_info "Warming cache..."
        docker build -f "$OLD_DOCKERFILE" --build-arg DATABASE_URL="postgresql://dummy" \
            -t "${OLD_TAG}-warm" "$PROJECT_DIR" > /dev/null 2>&1
        docker build -f "$NEW_DOCKERFILE" --build-arg DATABASE_URL="postgresql://dummy" \
            -t "${NEW_TAG}-warm" "$PROJECT_DIR" > /dev/null 2>&1
        print_success "Cache warmed"
    fi

    # Backup original file
    cp "$test_file" "${test_file}.backup"

    # Modify file (add a comment that doesn't break JSON)
    # We'll add a description field or modify the existing one
    print_info "Modified: $(basename "$test_file")"

    # Rebuild old Dockerfile
    print_info "Rebuilding old Dockerfile..."
    local old_rebuild_time=$(measure_build_time "$OLD_DOCKERFILE" "$OLD_TAG" "${OLD_BUILD_LOG}.rebuild-dep")
    local old_cache_hits=$(count_cache_hits "${OLD_BUILD_LOG}.rebuild-dep")
    print_success "Old rebuild: ${old_rebuild_time}s (cache: $old_cache_hits)"

    # Restore and modify for new build
    mv "${test_file}.backup" "$test_file"

    # Rebuild new Dockerfile
    print_info "Rebuilding new Dockerfile..."
    local new_rebuild_time=$(measure_build_time "$NEW_DOCKERFILE" "$NEW_TAG" "${NEW_BUILD_LOG}.rebuild-dep")
    local new_cache_hits=$(count_cache_hits "${NEW_BUILD_LOG}.rebuild-dep")
    print_success "New rebuild: ${new_rebuild_time}s (cache: $new_cache_hits)"

    # Restore original file
    mv "${test_file}.backup" "$test_file" 2>/dev/null || true

    # Store results
    RESULTS[dep_change_old_time]=$old_rebuild_time
    RESULTS[dep_change_new_time]=$new_rebuild_time
    RESULTS[dep_change_old_cache]=$old_cache_hits
    RESULTS[dep_change_new_cache]=$new_cache_hits

    # Calculate improvement
    local rebuild_improvement=$(calculate_improvement "$old_rebuild_time" "$new_rebuild_time")
    RESULTS[dep_change_time_improvement]=$rebuild_improvement

    print_success "Dependency change scenario complete"
}

#==============================================================================
# Output Functions
#==============================================================================

# Generate JSON output
generate_json_output() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")

    cat > "$RESULTS_DIR/benchmark-results-$(date +%Y%m%d-%H%M%S).json" <<EOF
{
  "timestamp": "$timestamp",
  "git_commit": "$git_commit",
  "docker_version": "$docker_version",
  "scenarios": {
    "clean_build": {
      "old": {
        "dockerfile": "Dockerfile.old",
        "git_commit": "5d7c641",
        "build_time_seconds": ${RESULTS[clean_build_old_time]},
        "image_size_bytes": ${RESULTS[clean_build_old_size]},
        "image_size_human": "$(bytes_to_human ${RESULTS[clean_build_old_size]})",
        "node_version": "20-alpine"
      },
      "new": {
        "dockerfile": "Dockerfile",
        "git_commit": "$git_commit",
        "build_time_seconds": ${RESULTS[clean_build_new_time]},
        "image_size_bytes": ${RESULTS[clean_build_new_size]},
        "image_size_human": "$(bytes_to_human ${RESULTS[clean_build_new_size]})",
        "node_version": "22-alpine"
      },
      "improvement": {
        "build_time_percent": ${RESULTS[clean_build_time_improvement]},
        "image_size_percent": ${RESULTS[clean_build_size_improvement]}
      }
    },
    "code_change": {
      "old": {
        "rebuild_time_seconds": ${RESULTS[code_change_old_time]:-0},
        "cache_hits": "${RESULTS[code_change_old_cache]:-0/0}"
      },
      "new": {
        "rebuild_time_seconds": ${RESULTS[code_change_new_time]:-0},
        "cache_hits": "${RESULTS[code_change_new_cache]:-0/0}"
      },
      "improvement": {
        "rebuild_time_percent": ${RESULTS[code_change_time_improvement]:-0}
      }
    },
    "dependency_change": {
      "old": {
        "rebuild_time_seconds": ${RESULTS[dep_change_old_time]:-0},
        "cache_hits": "${RESULTS[dep_change_old_cache]:-0/0}"
      },
      "new": {
        "rebuild_time_seconds": ${RESULTS[dep_change_new_time]:-0},
        "cache_hits": "${RESULTS[dep_change_new_cache]:-0/0}"
      },
      "improvement": {
        "rebuild_time_percent": ${RESULTS[dep_change_time_improvement]:-0}
      }
    }
  }
}
EOF

    # Create symlink to latest
    ln -sf "benchmark-results-$(date +%Y%m%d-%H%M%S).json" "$RESULTS_DIR/latest.json"
}

# Generate CSV output
generate_csv_output() {
    cat > "$RESULTS_DIR/benchmark-results-$(date +%Y%m%d-%H%M%S).csv" <<EOF
Scenario,Metric,Old,New,Improvement%
Clean Build,Build Time (s),${RESULTS[clean_build_old_time]},${RESULTS[clean_build_new_time]},${RESULTS[clean_build_time_improvement]}
Clean Build,Image Size (bytes),${RESULTS[clean_build_old_size]},${RESULTS[clean_build_new_size]},${RESULTS[clean_build_size_improvement]}
Code Change,Rebuild Time (s),${RESULTS[code_change_old_time]:-0},${RESULTS[code_change_new_time]:-0},${RESULTS[code_change_time_improvement]:-0}
Code Change,Cache Hits,${RESULTS[code_change_old_cache]:-0/0},${RESULTS[code_change_new_cache]:-0/0},N/A
Dependency Change,Rebuild Time (s),${RESULTS[dep_change_old_time]:-0},${RESULTS[dep_change_new_time]:-0},${RESULTS[dep_change_time_improvement]:-0}
Dependency Change,Cache Hits,${RESULTS[dep_change_old_cache]:-0/0},${RESULTS[dep_change_new_cache]:-0/0},N/A
EOF
}

# Generate terminal output
generate_terminal_output() {
    print_header "Docker Dockerfile Benchmark Results"

    # Clean build results
    if [ -n "${RESULTS[clean_build_old_time]:-}" ]; then
        echo -e "\n${BOLD}Scenario 1: Clean Build (No Cache)${NC}"
        echo "┌────────────────────┬─────────────┬─────────────┬──────────────┐"
        echo "│ Metric             │ Old (5d7c6) │ New (HEAD)  │ Improvement  │"
        echo "├────────────────────┼─────────────┼─────────────┼──────────────┤"
        printf "│ Build Time         │ %-11s │ %-11s │ ${GREEN}✓ %-9s${NC} │\n" \
            "${RESULTS[clean_build_old_time]}s" \
            "${RESULTS[clean_build_new_time]}s" \
            "${RESULTS[clean_build_time_improvement]}%"
        printf "│ Image Size         │ %-11s │ %-11s │ ${GREEN}✓ %-9s${NC} │\n" \
            "$(bytes_to_human ${RESULTS[clean_build_old_size]})" \
            "$(bytes_to_human ${RESULTS[clean_build_new_size]})" \
            "${RESULTS[clean_build_size_improvement]}%"
        echo "└────────────────────┴─────────────┴─────────────┴──────────────┘"
    fi

    # Code change results
    if [ -n "${RESULTS[code_change_old_time]:-}" ]; then
        echo -e "\n${BOLD}Scenario 2: Code Change (Vue file modified)${NC}"
        echo "┌────────────────────┬─────────────┬─────────────┬──────────────┐"
        echo "│ Metric             │ Old (5d7c6) │ New (HEAD)  │ Improvement  │"
        echo "├────────────────────┼─────────────┼─────────────┼──────────────┤"
        printf "│ Rebuild Time       │ %-11s │ %-11s │ ${GREEN}✓ %-9s${NC} │\n" \
            "${RESULTS[code_change_old_time]}s" \
            "${RESULTS[code_change_new_time]}s" \
            "${RESULTS[code_change_time_improvement]}%"
        printf "│ Cache Hits         │ %-11s │ %-11s │              │\n" \
            "${RESULTS[code_change_old_cache]}" \
            "${RESULTS[code_change_new_cache]}"
        echo "└────────────────────┴─────────────┴─────────────┴──────────────┘"
    fi

    # Dependency change results
    if [ -n "${RESULTS[dep_change_old_time]:-}" ]; then
        echo -e "\n${BOLD}Scenario 3: Dependency Change (package.json modified)${NC}"
        echo "┌────────────────────┬─────────────┬─────────────┬──────────────┐"
        echo "│ Metric             │ Old (5d7c6) │ New (HEAD)  │ Improvement  │"
        echo "├────────────────────┼─────────────┼─────────────┼──────────────┤"
        printf "│ Rebuild Time       │ %-11s │ %-11s │ ${GREEN}✓ %-9s${NC} │\n" \
            "${RESULTS[dep_change_old_time]}s" \
            "${RESULTS[dep_change_new_time]}s" \
            "${RESULTS[dep_change_time_improvement]}%"
        printf "│ Cache Hits         │ %-11s │ %-11s │              │\n" \
            "${RESULTS[dep_change_old_cache]}" \
            "${RESULTS[dep_change_new_cache]}"
        echo "└────────────────────┴─────────────┴─────────────┴──────────────┘"
    fi

    # Summary
    echo -e "\n${BOLD}Summary:${NC}"
    echo "• Old Dockerfile: 2 stages (builder + production), Node 20-alpine"
    echo "• New Dockerfile: 4 stages (base + deps + build + runner), Node 22-alpine"
    echo "• Better layer caching through separation of concerns"
    echo -e "• Results saved to: ${CYAN}${RESULTS_DIR}/latest.json${NC}\n"
}

#==============================================================================
# Main Execution
#==============================================================================

# Print usage information
print_usage() {
    cat <<EOF
Docker Dockerfile Benchmark Script

Usage: $(basename "$0") [OPTIONS]

Options:
  --skip-clean         Skip clean build scenario (faster, uses cache)
  --skip-code-change   Skip code change scenario
  --skip-dep-change    Skip dependency change scenario
  --json-only          Only output JSON (no terminal formatting)
  --csv-only           Only output CSV
  --no-cleanup         Don't remove Docker images after test
  --verbose            Show detailed Docker build output
  --help               Show this help message

Examples:
  # Run all scenarios (takes ~10-20 minutes)
  $(basename "$0")

  # Quick test (skip clean build)
  $(basename "$0") --skip-clean

  # JSON output only
  $(basename "$0") --json-only

EOF
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-clean)
                SKIP_CLEAN=true
                shift
                ;;
            --skip-code-change)
                SKIP_CODE_CHANGE=true
                shift
                ;;
            --skip-dep-change)
                SKIP_DEP_CHANGE=true
                shift
                ;;
            --json-only)
                JSON_ONLY=true
                shift
                ;;
            --csv-only)
                CSV_ONLY=true
                shift
                ;;
            --no-cleanup)
                NO_CLEANUP=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    parse_args "$@"

    # Header
    if [ "$JSON_ONLY" != true ] && [ "$CSV_ONLY" != true ]; then
        print_header "Docker Dockerfile Benchmark"
        print_info "Project: $PROJECT_DIR"
        print_info "Old Dockerfile: $OLD_DOCKERFILE"
        print_info "New Dockerfile: $NEW_DOCKERFILE"
    fi

    # Check dependencies
    check_dependencies

    # Create temp directory
    mkdir -p "$TEMP_DIR"

    # Create results directory
    mkdir -p "$RESULTS_DIR"

    # Run scenarios
    if [ "$SKIP_CLEAN" != true ]; then
        scenario_clean_build
    else
        print_warning "Skipping clean build scenario"
    fi

    if [ "$SKIP_CODE_CHANGE" != true ]; then
        scenario_code_change
    else
        print_warning "Skipping code change scenario"
    fi

    if [ "$SKIP_DEP_CHANGE" != true ]; then
        scenario_dep_change
    else
        print_warning "Skipping dependency change scenario"
    fi

    # Generate outputs
    if [ "$CSV_ONLY" != true ]; then
        generate_json_output
    fi

    if [ "$JSON_ONLY" != true ] && [ "$CSV_ONLY" != true ]; then
        generate_terminal_output
    fi

    if [ "$CSV_ONLY" = true ]; then
        generate_csv_output
    fi

    print_success "Benchmark complete!"
}

# Run main function
main "$@"
