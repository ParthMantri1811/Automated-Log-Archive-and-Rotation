#!/usr/bin/env bash
####################################################################
#                                                                  #
#   Automated Log Archive & Rotation Utility                       #
#                                                                  #
#   Scans a configured log directory, archives logs older than     #
#   a chosen age or larger than a size limit, applies a retention  #
#   policy, and maintains a detailed audit log.                    #
#                                                                  #
#   Usage:                                                         #
#     bash log_rotator.sh [OPTIONS]                                #
#                                                                  #
#   Options:                                                       #
#     --config <path>   Use a custom configuration file            #
#     --dry-run         Preview actions without executing          #
#     --force           Skip confirmation prompts                  #
#     --verbose         Enable extra verbose output                #
#     --help            Show this help message                     #
#                                                                  #
####################################################################
set -euo pipefail

# ═══════════════════════════════════════════════════════
#  GLOBAL VARIABLES & DEFAULTS
# ═══════════════════════════════════════════════════════
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults (overridden by config.conf)
LOG_DIR="./sample_logs"
ARCHIVE_DIR="./archives"
AUDIT_LOG="./audit.log"
MAX_AGE_DAYS=7
MAX_SIZE_KB=1024
RETENTION_DAYS=30
COMPRESSION="gzip"
LOG_EXTENSIONS="*.log *.txt *.out"
DRY_RUN=false
VERBOSE=false

# CLI overrides
CONFIG_FILE="$SCRIPT_DIR/config.conf"
FORCE=false

# Counters for summary report
FILES_SCANNED=0
FILES_ARCHIVED=0
FILES_SKIPPED=0
FILES_DELETED=0
BYTES_BEFORE=0
BYTES_AFTER=0
ERRORS=0
WARNINGS=0
START_TIME=""

# ═══════════════════════════════════════════════════════
#  COLOUR DEFINITIONS
# ═══════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════
#  UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════

# Print a formatted timestamp
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Write to the audit log
audit() {
    local level="$1"
    shift
    local message="$*"
    local ts
    ts=$(timestamp)
    
    if [ "$DRY_RUN" = true ]; then
        echo "[${ts}] [DRY-RUN] [${level}] ${message}" >> "$AUDIT_LOG"
    else
        echo "[${ts}] [${level}] ${message}" >> "$AUDIT_LOG"
    fi
}

# Print info messages
info() {
    echo -e "${GREEN}[INFO]${NC} $*"
    audit "INFO" "$*"
}

# Print warning messages
warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    audit "WARN" "$*"
    WARNINGS=$((WARNINGS + 1))
}

# Print error messages
error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    audit "ERROR" "$*"
    ERRORS=$((ERRORS + 1))
}

# Print verbose messages (only when --verbose)
verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${DIM}[VERBOSE]${NC} $*"
    fi
}

# Print the banner
print_banner() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                        ║"
    echo "║   Automated Log Archive & Rotation Utility  v${SCRIPT_VERSION}     ║"
    echo "║                                                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Print help/usage
print_help() {
    print_banner
    echo "USAGE:"
    echo "  bash $SCRIPT_NAME [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --config <path>   Use a custom configuration file (default: config.conf)"
    echo "  --dry-run         Preview all actions without executing them"
    echo "  --force           Skip confirmation prompts"
    echo "  --verbose         Enable extra verbose output"
    echo "  --help            Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  bash $SCRIPT_NAME                          # Run with default config"
    echo "  bash $SCRIPT_NAME --dry-run                # Preview what would happen"
    echo "  bash $SCRIPT_NAME --config /etc/myapp.conf # Use custom config"
    echo "  bash $SCRIPT_NAME --verbose --force        # Verbose, no prompts"
    echo ""
    echo "CONFIGURATION:"
    echo "  Edit config.conf to set log directory, archive directory,"
    echo "  age/size thresholds, retention policy, and more."
    echo ""
}

# Get human-readable file size (pure bash, no bc needed)
human_size() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        local whole=$((bytes / 1073741824))
        local frac=$(( (bytes % 1073741824) * 100 / 1073741824 ))
        printf '%d.%02d GB' "$whole" "$frac"
    elif [ "$bytes" -ge 1048576 ]; then
        local whole=$((bytes / 1048576))
        local frac=$(( (bytes % 1048576) * 100 / 1048576 ))
        printf '%d.%02d MB' "$whole" "$frac"
    elif [ "$bytes" -ge 1024 ]; then
        local whole=$((bytes / 1024))
        local frac=$(( (bytes % 1024) * 100 / 1024 ))
        printf '%d.%02d KB' "$whole" "$frac"
    else
        echo "${bytes} B"
    fi
}

# Get file size in bytes (portable)
file_size_bytes() {
    local file="$1"
    wc -c < "$file" | tr -d '[:space:]'
}

# Get compression extension based on tool
get_compression_ext() {
    case "$COMPRESSION" in
        gzip)  echo "gz" ;;
        bzip2) echo "bz2" ;;
        xz)    echo "xz" ;;
        *)     echo "gz" ;;
    esac
}

# ═══════════════════════════════════════════════════════
#  CONFIGURATION LOADER
# ═══════════════════════════════════════════════════════
load_config() {
    local config_path="$1"
    
    if [ ! -f "$config_path" ]; then
        warn "Configuration file not found: $config_path — using defaults"
        return
    fi
    
    verbose "Loading configuration from: $config_path"
    
    while IFS='=' read -r key value; do
        # Skip comments and blank lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${key// /}" ]] && continue
        
        # Trim whitespace and quotes
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed 's/^"//;s/"$//')
        
        case "$key" in
            LOG_DIR)         LOG_DIR="$value" ;;
            ARCHIVE_DIR)     ARCHIVE_DIR="$value" ;;
            AUDIT_LOG)       AUDIT_LOG="$value" ;;
            MAX_AGE_DAYS)    MAX_AGE_DAYS="$value" ;;
            MAX_SIZE_KB)     MAX_SIZE_KB="$value" ;;
            RETENTION_DAYS)  RETENTION_DAYS="$value" ;;
            COMPRESSION)     COMPRESSION="$value" ;;
            LOG_EXTENSIONS)  LOG_EXTENSIONS="$value" ;;
            DRY_RUN)         DRY_RUN="$value" ;;
            VERBOSE)         VERBOSE="$value" ;;
            *)               verbose "Unknown config key: $key" ;;
        esac
    done < "$config_path"
    
    info "Configuration loaded from: $config_path"
}

# ═══════════════════════════════════════════════════════
#  CONFIGURATION VALIDATOR
# ═══════════════════════════════════════════════════════
validate_config() {
    local valid=true
    
    verbose "Validating configuration..."
    
    # Validate numeric fields
    if ! [[ "$MAX_AGE_DAYS" =~ ^[0-9]+$ ]] || [ "$MAX_AGE_DAYS" -le 0 ]; then
        error "MAX_AGE_DAYS must be a positive integer (got: $MAX_AGE_DAYS)"
        valid=false
    fi
    
    if ! [[ "$MAX_SIZE_KB" =~ ^[0-9]+$ ]] || [ "$MAX_SIZE_KB" -le 0 ]; then
        error "MAX_SIZE_KB must be a positive integer (got: $MAX_SIZE_KB)"
        valid=false
    fi
    
    if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [ "$RETENTION_DAYS" -le 0 ]; then
        error "RETENTION_DAYS must be a positive integer (got: $RETENTION_DAYS)"
        valid=false
    fi
    
    # Validate compression tool
    case "$COMPRESSION" in
        gzip|bzip2|xz)
            if ! command -v "$COMPRESSION" &>/dev/null; then
                error "Compression tool '$COMPRESSION' is not installed"
                valid=false
            fi
            ;;
        *)
            error "Unsupported compression tool: $COMPRESSION (use gzip, bzip2, or xz)"
            valid=false
            ;;
    esac
    
    # Validate LOG_DIR exists
    if [ ! -d "$LOG_DIR" ]; then
        error "Log directory does not exist: $LOG_DIR"
        valid=false
    fi
    
    # Validate boolean fields
    if [[ "$DRY_RUN" != "true" && "$DRY_RUN" != "false" ]]; then
        error "DRY_RUN must be 'true' or 'false' (got: $DRY_RUN)"
        valid=false
    fi
    
    if [[ "$VERBOSE" != "true" && "$VERBOSE" != "false" ]]; then
        error "VERBOSE must be 'true' or 'false' (got: $VERBOSE)"
        valid=false
    fi
    
    if [ "$valid" = false ]; then
        echo ""
        error "Configuration validation failed. Please fix the issues above."
        exit 1
    fi
    
    info "Configuration validated successfully"
}

# ═══════════════════════════════════════════════════════
#  PARSE COMMAND-LINE ARGUMENTS
# ═══════════════════════════════════════════════════════
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                if [ -z "${2:-}" ]; then
                    error "--config requires a file path argument"
                    exit 1
                fi
                CONFIG_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Run '$SCRIPT_NAME --help' for usage."
                exit 1
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════
#  PRINT ACTIVE CONFIGURATION
# ═══════════════════════════════════════════════════════
print_config() {
    echo -e "${BOLD}${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${CYAN}│  Active Configuration                            │${NC}"
    echo -e "${BOLD}${CYAN}├──────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC}  Log Directory    : ${BOLD}${LOG_DIR}${NC}"
    echo -e "${CYAN}│${NC}  Archive Directory: ${BOLD}${ARCHIVE_DIR}${NC}"
    echo -e "${CYAN}│${NC}  Audit Log        : ${BOLD}${AUDIT_LOG}${NC}"
    echo -e "${CYAN}│${NC}  Max Age (days)   : ${BOLD}${MAX_AGE_DAYS}${NC}"
    echo -e "${CYAN}│${NC}  Max Size (KB)    : ${BOLD}${MAX_SIZE_KB}${NC}"
    echo -e "${CYAN}│${NC}  Retention (days) : ${BOLD}${RETENTION_DAYS}${NC}"
    echo -e "${CYAN}│${NC}  Compression      : ${BOLD}${COMPRESSION}${NC}"
    echo -e "${CYAN}│${NC}  File Patterns    : ${BOLD}${LOG_EXTENSIONS}${NC}"
    echo -e "${CYAN}│${NC}  Dry Run          : ${BOLD}${DRY_RUN}${NC}"
    echo -e "${CYAN}│${NC}  Verbose          : ${BOLD}${VERBOSE}${NC}"
    echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════
#  GENERATE UNIQUE ARCHIVE FILENAME (Overwrite Protection)
# ═══════════════════════════════════════════════════════
generate_archive_name() {
    local base_name="$1"
    local ext
    ext=$(get_compression_ext)
    
    # Extract filename without extension
    local name_no_ext="${base_name%.*}"
    local orig_ext="${base_name##*.}"
    
    # Generate date-stamped name
    local date_stamp
    date_stamp=$(date '+%Y-%m-%d_%H%M%S')
    
    local archive_name="${name_no_ext}_${date_stamp}.${orig_ext}.${ext}"
    local archive_path="${ARCHIVE_DIR}/${archive_name}"
    
    # ── Overwrite Protection ──
    # If the archive filename already exists, append a numeric suffix
    if [ -f "$archive_path" ]; then
        local counter=1
        while [ -f "${ARCHIVE_DIR}/${name_no_ext}_${date_stamp}_${counter}.${orig_ext}.${ext}" ]; do
            counter=$((counter + 1))
        done
        archive_name="${name_no_ext}_${date_stamp}_${counter}.${orig_ext}.${ext}"
        archive_path="${ARCHIVE_DIR}/${archive_name}"
        warn "Archive name collision detected — using: $archive_name"
    fi
    
    echo "$archive_path"
}

# ═══════════════════════════════════════════════════════
#  COMPRESS A FILE
# ═══════════════════════════════════════════════════════
compress_file() {
    local source_file="$1"
    local dest_file="$2"
    
    case "$COMPRESSION" in
        gzip)
            gzip -c "$source_file" > "$dest_file"
            ;;
        bzip2)
            bzip2 -c "$source_file" > "$dest_file"
            ;;
        xz)
            xz -c "$source_file" > "$dest_file"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════
#  SCAN AND ARCHIVE LOG FILES
# ═══════════════════════════════════════════════════════
scan_and_archive() {
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Phase 1: Scanning & Archiving Log Files${NC}"
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    audit "INFO" "=== SCAN & ARCHIVE PHASE STARTED ==="
    audit "INFO" "Scanning directory: $LOG_DIR"
    audit "INFO" "Age threshold: $MAX_AGE_DAYS days | Size threshold: $MAX_SIZE_KB KB"
    
    # Create archive directory if it doesn't exist
    if [ ! -d "$ARCHIVE_DIR" ]; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY-RUN] Would create archive directory: $ARCHIVE_DIR"
        else
            mkdir -p "$ARCHIVE_DIR"
            info "Created archive directory: $ARCHIVE_DIR"
        fi
    fi
    
    # Build find command for matching file extensions
    # IMPORTANT: Disable glob expansion so *.log is not expanded by the shell
    local find_args=()
    local first=true
    set -f  # Disable globbing
    for pattern in $LOG_EXTENSIONS; do
        if [ "$first" = true ]; then
            find_args+=("-name" "$pattern")
            first=false
        else
            find_args+=("-o" "-name" "$pattern")
        fi
    done
    set +f  # Re-enable globbing
    
    # Find all matching files
    local all_files
    all_files=$(find "$LOG_DIR" -maxdepth 1 -type f \( "${find_args[@]}" \) 2>/dev/null || true)
    
    if [ -z "$all_files" ]; then
        info "No log files found matching patterns: $LOG_EXTENSIONS"
        return
    fi
    
    # Process each file
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        FILES_SCANNED=$((FILES_SCANNED + 1))
        
        local filename
        filename=$(basename "$file")
        local file_size
        file_size=$(file_size_bytes "$file")
        local file_size_kb=$((file_size / 1024))
        local should_archive=false
        local reason=""
        
        verbose "Examining: $filename (${file_size_kb} KB)"
        
        # ── Check Age Criterion ──
        local age_files
        age_files=$(find "$file" -mtime +"$MAX_AGE_DAYS" 2>/dev/null || true)
        if [ -n "$age_files" ]; then
            should_archive=true
            reason="older than ${MAX_AGE_DAYS} days"
        fi
        
        # ── Check Size Criterion ──
        if [ "$file_size_kb" -gt "$MAX_SIZE_KB" ]; then
            should_archive=true
            if [ -n "$reason" ]; then
                reason="$reason AND larger than ${MAX_SIZE_KB} KB (${file_size_kb} KB)"
            else
                reason="larger than ${MAX_SIZE_KB} KB (${file_size_kb} KB)"
            fi
        fi
        
        # ── Archive or Skip ──
        if [ "$should_archive" = true ]; then
            local archive_path
            archive_path=$(generate_archive_name "$filename")
            local archive_name
            archive_name=$(basename "$archive_path")
            
            if [ "$DRY_RUN" = true ]; then
                echo -e "  ${YELLOW}[DRY-RUN]${NC} Would archive: ${BOLD}$filename${NC}"
                echo -e "            → ${CYAN}$archive_name${NC}  (reason: $reason)"
                info "[DRY-RUN] Would archive: $filename → $archive_name (reason: $reason)"
                FILES_ARCHIVED=$((FILES_ARCHIVED + 1))
            else
                # Perform compression
                if compress_file "$file" "$archive_path"; then
                    local archive_size
                    archive_size=$(file_size_bytes "$archive_path")
                    local ratio="0.0"
                    if [ "$file_size" -gt 0 ]; then
                        local saved_bytes=$((file_size - archive_size))
                        local ratio_int=$((saved_bytes * 1000 / file_size))
                        ratio="$((ratio_int / 10)).$((ratio_int % 10))"
                    fi
                    
                    BYTES_BEFORE=$((BYTES_BEFORE + file_size))
                    BYTES_AFTER=$((BYTES_AFTER + archive_size))
                    
                    # Remove the original file after successful archiving
                    rm -f "$file"
                    
                    echo -e "  ${GREEN}[ARCHIVED]${NC} ${BOLD}$filename${NC}"
                    echo -e "             → ${CYAN}$archive_name${NC}"
                    echo -e "             Size: $(human_size $file_size) → $(human_size $archive_size) (${ratio}% reduction)"
                    echo -e "             Reason: $reason"
                    
                    info "Archived: $filename → $archive_name | $(human_size $file_size) → $(human_size $archive_size) (${ratio}% reduction) | Reason: $reason"
                    FILES_ARCHIVED=$((FILES_ARCHIVED + 1))
                else
                    error "Failed to compress: $filename"
                fi
            fi
        else
            FILES_SKIPPED=$((FILES_SKIPPED + 1))
            verbose "Skipping: $filename (does not meet archiving criteria)"
        fi
        
        echo ""
    done <<< "$all_files"
    
    audit "INFO" "=== SCAN & ARCHIVE PHASE COMPLETED ==="
}

# ═══════════════════════════════════════════════════════
#  APPLY RETENTION POLICY
# ═══════════════════════════════════════════════════════
apply_retention_policy() {
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Phase 2: Applying Retention Policy${NC}"
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    audit "INFO" "=== RETENTION POLICY PHASE STARTED ==="
    audit "INFO" "Retention threshold: $RETENTION_DAYS days"
    audit "INFO" "Scanning archive directory: $ARCHIVE_DIR"
    
    if [ ! -d "$ARCHIVE_DIR" ]; then
        info "Archive directory does not exist — nothing to clean"
        return
    fi
    
    # Find archives older than RETENTION_DAYS
    local ext
    ext=$(get_compression_ext)
    
    local expired_files
    expired_files=$(find "$ARCHIVE_DIR" -maxdepth 1 -type f \( -name "*.${ext}" \) -mtime +"$RETENTION_DAYS" 2>/dev/null || true)
    
    if [ -z "$expired_files" ]; then
        info "No expired archives found (all within ${RETENTION_DAYS}-day retention window)"
        echo ""
        return
    fi
    
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        local filename
        filename=$(basename "$file")
        local file_size
        file_size=$(file_size_bytes "$file")
        
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${YELLOW}[DRY-RUN]${NC} Would delete expired archive: ${BOLD}$filename${NC} ($(human_size $file_size))"
            info "[DRY-RUN] Would delete expired archive: $filename ($(human_size $file_size))"
        else
            rm -f "$file"
            echo -e "  ${RED}[DELETED]${NC} Expired archive: ${BOLD}$filename${NC} ($(human_size $file_size))"
            info "Deleted expired archive: $filename ($(human_size $file_size))"
        fi
        FILES_DELETED=$((FILES_DELETED + 1))
    done <<< "$expired_files"
    
    echo ""
    audit "INFO" "=== RETENTION POLICY PHASE COMPLETED ==="
}

# ═══════════════════════════════════════════════════════
#  PRINT SUMMARY REPORT
# ═══════════════════════════════════════════════════════
print_summary() {
    local end_time
    end_time=$(date '+%s')
    local duration=$((end_time - START_TIME))
    
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                    Summary Report                        ║${NC}"
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}║${NC}  ${YELLOW}⚠  DRY-RUN MODE — No changes were made${NC}"
        echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
    fi
    
    echo -e "${CYAN}║${NC}  Files scanned         : ${BOLD}${FILES_SCANNED}${NC}"
    echo -e "${CYAN}║${NC}  Files archived        : ${BOLD}${GREEN}${FILES_ARCHIVED}${NC}"
    echo -e "${CYAN}║${NC}  Files skipped         : ${BOLD}${FILES_SKIPPED}${NC}"
    echo -e "${CYAN}║${NC}  Archives deleted      : ${BOLD}${RED}${FILES_DELETED}${NC}"
    
    if [ "$BYTES_BEFORE" -gt 0 ] && [ "$DRY_RUN" = false ]; then
        local saved=$((BYTES_BEFORE - BYTES_AFTER))
        local ratio_int=$((saved * 1000 / BYTES_BEFORE))
        local ratio="$((ratio_int / 10)).$((ratio_int % 10))"
        echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  Original size        : ${BOLD}$(human_size $BYTES_BEFORE)${NC}"
        echo -e "${CYAN}║${NC}  Compressed size      : ${BOLD}$(human_size $BYTES_AFTER)${NC}"
        echo -e "${CYAN}║${NC}  Space saved          : ${BOLD}${GREEN}$(human_size $saved) (${ratio}%)${NC}"
    fi
    
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Warnings             : ${BOLD}${YELLOW}${WARNINGS}${NC}"
    echo -e "${CYAN}║${NC}  Errors               : ${BOLD}${RED}${ERRORS}${NC}"
    echo -e "${CYAN}║${NC}  Duration             : ${BOLD}${duration}s${NC}"
    echo -e "${CYAN}║${NC}  Audit log            : ${BOLD}${AUDIT_LOG}${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Log summary to audit log
    audit "INFO" "=== RUN SUMMARY ==="
    audit "INFO" "Files scanned: $FILES_SCANNED | Archived: $FILES_ARCHIVED | Skipped: $FILES_SKIPPED | Deleted: $FILES_DELETED"
    if [ "$BYTES_BEFORE" -gt 0 ] && [ "$DRY_RUN" = false ]; then
        audit "INFO" "Original: $(human_size $BYTES_BEFORE) | Compressed: $(human_size $BYTES_AFTER) | Saved: $(human_size $((BYTES_BEFORE - BYTES_AFTER)))"
    fi
    audit "INFO" "Warnings: $WARNINGS | Errors: $ERRORS | Duration: ${duration}s"
    audit "INFO" "=========================================="
}

# ═══════════════════════════════════════════════════════
#  CONFIRMATION PROMPT
# ═══════════════════════════════════════════════════════
confirm_execution() {
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo -e "${YELLOW}This will archive and potentially delete log files.${NC}"
    read -rp "Continue? [y/N]: " answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
}

# ═══════════════════════════════════════════════════════
#  MAIN EXECUTION
# ═══════════════════════════════════════════════════════
main() {
    # Record start time
    START_TIME=$(date '+%s')
    
    # Parse command-line arguments
    parse_args "$@"
    
    # Print banner
    print_banner
    
    # Load and validate configuration
    load_config "$CONFIG_FILE"
    validate_config
    
    echo ""
    
    # Print active configuration
    print_config
    
    # Log the start of this run
    audit "INFO" "=========================================="
    audit "INFO" "Log Rotator v${SCRIPT_VERSION} — Run started"
    audit "INFO" "Configuration: $CONFIG_FILE"
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}${BOLD}⚠  DRY-RUN MODE ACTIVE — No files will be modified${NC}"
        echo ""
        audit "INFO" "Mode: DRY-RUN (no changes will be made)"
    fi
    
    # Confirm execution
    confirm_execution
    echo ""
    
    # Phase 1: Scan and Archive
    scan_and_archive
    
    # Phase 2: Retention Policy
    apply_retention_policy
    
    # Print summary
    print_summary
    
    # Exit with error code if errors occurred
    if [ "$ERRORS" -gt 0 ]; then
        exit 1
    fi
}

# Run main with all arguments
main "$@"
