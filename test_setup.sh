#!/usr/bin/env bash
########################################################
#  Test Setup — Generate Sample Log Files              #
#                                                      #
#  Creates realistic log files of varying ages and     #
#  sizes inside ./sample_logs for demonstration.       #
########################################################
set -euo pipefail

SAMPLE_DIR="./sample_logs"

# ─── Colours ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   Test Setup — Sample Log File Generator        ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── Create sample_logs directory ─────────────────────
mkdir -p "$SAMPLE_DIR"
echo -e "${GREEN}[✔]${NC} Created directory: ${BOLD}${SAMPLE_DIR}${NC}"

# ─── Helper: Generate realistic log content (small files) ─────────
# Used for files with fewer lines (≤500). Calls date per line.
generate_log_content() {
    local lines=$1
    local app_name=$2
    local levels=("INFO" "DEBUG" "WARN" "ERROR" "TRACE")
    local messages=(
        "Application started successfully"
        "Processing incoming request from client"
        "Database connection pool initialised"
        "Cache hit ratio: 94.3%"
        "User authentication successful for user_id=42"
        "Scheduled task completed in 234ms"
        "Memory usage: 67% of allocated heap"
        "HTTP request handled: GET /api/v1/status 200"
        "Background worker thread started"
        "Configuration reloaded from disk"
        "Connection timeout after 30000ms — retrying"
        "Disk space warning: 82% utilisation on /var/log"
        "Rate limiter triggered: 429 Too Many Requests"
        "SSL certificate expires in 14 days"
        "Garbage collection pause: 12ms"
        "Failed to parse JSON payload — malformed input"
        "Session expired for token=abc123def456"
        "Load balancer health check passed"
        "New deployment detected — version 3.2.1"
        "Shutting down gracefully — drain timeout 60s"
    )

    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2026-11-12 12:00:00")

    for ((i = 1; i <= lines; i++)); do
        local level=${levels[$((RANDOM % ${#levels[@]}))]}
        local msg=${messages[$((RANDOM % ${#messages[@]}))]}
        echo "[$ts] [$level] [$app_name] $msg"
    done
}

# ─── Helper: Generate large log files FAST ────────────────────────
# Generates a small seed block, then replicates it to reach target KB.
# This avoids calling date/subprocess thousands of times.
generate_large_log_file() {
    local target_kb=$1
    local app_name=$2
    local output_file=$3

    # Step 1: Generate a seed block of 50 realistic lines (no subprocess per line)
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2026-11-12 12:00:00")

    local seed_lines=(
        "[$ts] [INFO] [$app_name] Application started successfully"
        "[$ts] [DEBUG] [$app_name] Processing incoming request from client"
        "[$ts] [INFO] [$app_name] Database connection pool initialised"
        "[$ts] [DEBUG] [$app_name] Cache hit ratio: 94.3%"
        "[$ts] [INFO] [$app_name] User authentication successful for user_id=42"
        "[$ts] [INFO] [$app_name] Scheduled task completed in 234ms"
        "[$ts] [WARN] [$app_name] Memory usage: 67% of allocated heap"
        "[$ts] [DEBUG] [$app_name] HTTP request handled: GET /api/v1/status 200"
        "[$ts] [INFO] [$app_name] Background worker thread started"
        "[$ts] [INFO] [$app_name] Configuration reloaded from disk"
        "[$ts] [ERROR] [$app_name] Connection timeout after 30000ms — retrying"
        "[$ts] [WARN] [$app_name] Disk space warning: 82% utilisation on /var/log"
        "[$ts] [WARN] [$app_name] Rate limiter triggered: 429 Too Many Requests"
        "[$ts] [WARN] [$app_name] SSL certificate expires in 14 days"
        "[$ts] [DEBUG] [$app_name] Garbage collection pause: 12ms"
        "[$ts] [ERROR] [$app_name] Failed to parse JSON payload — malformed input"
        "[$ts] [INFO] [$app_name] Session expired for token=abc123def456"
        "[$ts] [INFO] [$app_name] Load balancer health check passed"
        "[$ts] [INFO] [$app_name] New deployment detected — version 3.2.1"
        "[$ts] [INFO] [$app_name] Shutting down gracefully — drain timeout 60s"
        "[$ts] [TRACE] [$app_name] Entering method processRequest() at line 142"
        "[$ts] [DEBUG] [$app_name] Thread pool active count: 8/16"
        "[$ts] [INFO] [$app_name] Response sent: 200 OK in 45ms"
        "[$ts] [WARN] [$app_name] Slow query detected: SELECT * FROM users (820ms)"
        "[$ts] [ERROR] [$app_name] OutOfMemoryError: Java heap space"
        "[$ts] [INFO] [$app_name] Retry attempt 2/3 for upstream service"
        "[$ts] [DEBUG] [$app_name] Heartbeat received from node cluster-02"
        "[$ts] [INFO] [$app_name] File upload completed: report_2026.csv (2.4 MB)"
        "[$ts] [WARN] [$app_name] Deprecated API endpoint called: /v1/legacy/auth"
        "[$ts] [INFO] [$app_name] Cron job executed: cleanup_temp_files"
        "[$ts] [TRACE] [$app_name] Exiting method processRequest() — 52ms elapsed"
        "[$ts] [DEBUG] [$app_name] Cache eviction: removed 342 stale entries"
        "[$ts] [INFO] [$app_name] WebSocket connection established: client_id=ws-7891"
        "[$ts] [ERROR] [$app_name] DNS resolution failed for api.external-service.com"
        "[$ts] [INFO] [$app_name] Batch processing: 1500/5000 records completed"
        "[$ts] [DEBUG] [$app_name] GC pause: Young generation collected in 8ms"
        "[$ts] [WARN] [$app_name] Circuit breaker OPEN for payment-gateway (5 failures)"
        "[$ts] [INFO] [$app_name] TLS handshake completed with cipher TLS_AES_256_GCM"
        "[$ts] [DEBUG] [$app_name] Request queued: position 3 in worker pool"
        "[$ts] [INFO] [$app_name] Health check endpoint returned 200 OK"
        "[$ts] [TRACE] [$app_name] SQL query executed in 12ms: SELECT id FROM orders"
        "[$ts] [WARN] [$app_name] Response time exceeded SLA: 2450ms > 2000ms threshold"
        "[$ts] [INFO] [$app_name] Metrics flushed to monitoring backend (847 datapoints)"
        "[$ts] [DEBUG] [$app_name] Message consumed from Kafka topic: events.user.login"
        "[$ts] [ERROR] [$app_name] SMTP connection refused: port 587 unreachable"
        "[$ts] [INFO] [$app_name] Scheduled maintenance window begins in 30 minutes"
        "[$ts] [DEBUG] [$app_name] Object serialized: UserProfile (1.2 KB)"
        "[$ts] [INFO] [$app_name] API rate limit reset: 1000 requests/minute"
        "[$ts] [WARN] [$app_name] Log file approaching size limit: 980 MB / 1 GB"
        "[$ts] [INFO] [$app_name] Service discovery: registered with consul agent"
    )

    # Step 2: Write the seed block to a temp file
    local seed_file
    seed_file=$(mktemp "${TMPDIR:-/tmp}/logseed.XXXXXX" 2>/dev/null || echo "$SAMPLE_DIR/.seed_$$")
    printf '%s\n' "${seed_lines[@]}" > "$seed_file"

    # Step 3: Get seed size and calculate how many copies we need
    local seed_bytes
    seed_bytes=$(wc -c < "$seed_file" | tr -d '[:space:]')
    local target_bytes=$((target_kb * 1024))
    local copies=$(( (target_bytes / seed_bytes) + 1 ))

    # Step 4: Replicate the seed block to reach the target size (FAST)
    > "$output_file"
    for ((c = 0; c < copies; c++)); do
        cat "$seed_file" >> "$output_file"
    done

    # Cleanup temp file
    rm -f "$seed_file"
}

# ─── Generate small, recent log files (should NOT be archived) ──
echo ""
echo -e "${YELLOW}► Creating recent, small log files (should NOT be archived)...${NC}"

for name in "webapp" "api-gateway" "scheduler"; do
    file="$SAMPLE_DIR/${name}.log"
    generate_log_content 50 "$name" > "$file"
    echo -e "  ${GREEN}✔${NC} ${file}  ($(wc -c < "$file") bytes, age: today)"
done

# ─── Generate old log files (should be archived by age) ──────────
echo ""
echo -e "${YELLOW}► Creating old log files (should be archived by AGE)...${NC}"

old_ages=(10 15 20 25)
for i in "${!old_ages[@]}"; do
    age=${old_ages[$i]}
    names=("auth-service" "payment-processor" "notification-engine" "data-pipeline")
    name=${names[$i]}
    file="$SAMPLE_DIR/${name}.log"
    generate_log_content 100 "$name" > "$file"
    # Backdate the file's modification time
    touch -d "-${age} days" "$file" 2>/dev/null || touch -t "$(date -d "-${age} days" '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202610010000.00')" "$file"
    echo -e "  ${GREEN}✔${NC} ${file}  ($(wc -c < "$file") bytes, age: ${age} days)"
done

# ─── Generate large log files (should be archived by size) ───────
echo ""
echo -e "${YELLOW}► Creating large log files (should be archived by SIZE)...${NC}"

for name in "access" "error" "debug"; do
    file="$SAMPLE_DIR/${name}.log"
    # Generate ~1.5 MB of log data using fast replication
    generate_large_log_file 1536 "$name" "$file"
    size_kb=$(( $(wc -c < "$file") / 1024 ))
    echo -e "  ${GREEN}✔${NC} ${file}  (${size_kb} KB, age: today)"
done

# ─── Generate old AND large log files ────────────────────────────
echo ""
echo -e "${YELLOW}► Creating old AND large log files (archived by BOTH criteria)...${NC}"

for name in "system-monitor" "audit-trail"; do
    file="$SAMPLE_DIR/${name}.log"
    # Generate ~1.2 MB of log data using fast replication
    generate_large_log_file 1230 "$name" "$file"
    touch -d "-14 days" "$file" 2>/dev/null || touch -t "$(date -d "-14 days" '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202610280000.00')" "$file"
    size_kb=$(( $(wc -c < "$file") / 1024 ))
    echo -e "  ${GREEN}✔${NC} ${file}  (${size_kb} KB, age: 14 days)"
done

# ─── Generate .txt and .out files for extension testing ──────────
echo ""
echo -e "${YELLOW}► Creating .txt and .out log files (extension testing)...${NC}"

file="$SAMPLE_DIR/legacy-output.txt"
generate_log_content 200 "legacy-app" > "$file"
touch -d "-12 days" "$file" 2>/dev/null || touch -t "$(date -d "-12 days" '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202610300000.00')" "$file"
echo -e "  ${GREEN}✔${NC} ${file}  ($(wc -c < "$file") bytes, age: 12 days)"

file="$SAMPLE_DIR/batch-job.out"
generate_log_content 300 "batch-runner" > "$file"
touch -d "-9 days" "$file" 2>/dev/null || touch -t "$(date -d "-9 days" '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202611020000.00')" "$file"
echo -e "  ${GREEN}✔${NC} ${file}  ($(wc -c < "$file") bytes, age: 9 days)"

# ─── Summary ─────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────${NC}"
total=$(find "$SAMPLE_DIR" -type f | wc -l)
total_size=$(du -sh "$SAMPLE_DIR" 2>/dev/null | cut -f1)
echo -e "${BOLD}  Total files created: ${GREEN}${total}${NC}"
echo -e "${BOLD}  Total size:          ${GREEN}${total_size}${NC}"
echo -e "${BOLD}${CYAN}──────────────────────────────────────────────────${NC}"
echo ""
echo -e "${GREEN}[✔]${NC} Test setup complete. Run ${BOLD}bash log_rotator.sh${NC} to archive."
