#!/usr/bin/env bash
########################################################
#  Installer — Automated Log Archive & Rotation        #
#                                                      #
#  Checks dependencies, sets permissions, creates      #
#  directories, and optionally sets up a cron job.     #
########################################################
set -euo pipefail

# ─── Colours ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║  Automated Log Archive & Rotation — Installer   ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ─── 1. Check Required Dependencies ──────────────────
echo -e "${BOLD}[1/5] Checking dependencies...${NC}"

REQUIRED_CMDS=("bash" "find" "date" "gzip" "wc" "du" "touch" "mkdir")
OPTIONAL_CMDS=("bzip2" "xz" "crontab")
MISSING=()
MISSING_OPT=()

for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✔${NC} $cmd"
    else
        echo -e "  ${RED}✘${NC} $cmd  ${RED}(REQUIRED — not found!)${NC}"
        MISSING+=("$cmd")
    fi
done

echo ""
echo -e "${BOLD}  Optional dependencies:${NC}"
for cmd in "${OPTIONAL_CMDS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✔${NC} $cmd"
    else
        echo -e "  ${YELLOW}⚠${NC} $cmd  ${YELLOW}(optional — not found)${NC}"
        MISSING_OPT+=("$cmd")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}[ERROR] Missing required dependencies: ${MISSING[*]}${NC}"
    echo -e "${RED}        Please install them and re-run this installer.${NC}"
    exit 1
fi

echo ""

# ─── 2. Set File Permissions ─────────────────────────
echo -e "${BOLD}[2/5] Setting file permissions...${NC}"

chmod +x "$SCRIPT_DIR/log_rotator.sh" 2>/dev/null && \
    echo -e "  ${GREEN}✔${NC} log_rotator.sh  → executable" || \
    echo -e "  ${YELLOW}⚠${NC} log_rotator.sh  → could not set permissions (Windows?)"

chmod +x "$SCRIPT_DIR/test_setup.sh" 2>/dev/null && \
    echo -e "  ${GREEN}✔${NC} test_setup.sh   → executable" || \
    echo -e "  ${YELLOW}⚠${NC} test_setup.sh   → could not set permissions (Windows?)"

chmod +x "$SCRIPT_DIR/install.sh" 2>/dev/null && \
    echo -e "  ${GREEN}✔${NC} install.sh      → executable" || \
    echo -e "  ${YELLOW}⚠${NC} install.sh      → could not set permissions (Windows?)"

echo ""

# ─── 3. Create Required Directories ──────────────────
echo -e "${BOLD}[3/5] Creating directories...${NC}"

# Source config to get directory paths
CONFIG_FILE="$SCRIPT_DIR/config.conf"
LOG_DIR="./sample_logs"
ARCHIVE_DIR="./archives"

if [ -f "$CONFIG_FILE" ]; then
    # Safe source — only extract known variables
    while IFS='=' read -r key value; do
        # Skip comments and blank lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed 's/^"//;s/"$//')
        case "$key" in
            LOG_DIR)     LOG_DIR="$value" ;;
            ARCHIVE_DIR) ARCHIVE_DIR="$value" ;;
        esac
    done < "$CONFIG_FILE"
fi

mkdir -p "$SCRIPT_DIR/$LOG_DIR"
echo -e "  ${GREEN}✔${NC} $LOG_DIR"

mkdir -p "$SCRIPT_DIR/$ARCHIVE_DIR"
echo -e "  ${GREEN}✔${NC} $ARCHIVE_DIR"

mkdir -p "$SCRIPT_DIR/docs"
echo -e "  ${GREEN}✔${NC} docs/"

echo ""

# ─── 4. Validate Configuration ──────────────────────
echo -e "${BOLD}[4/5] Validating configuration...${NC}"

if [ -f "$CONFIG_FILE" ]; then
    echo -e "  ${GREEN}✔${NC} config.conf found at: ${CONFIG_FILE}"
    
    # Basic validation
    errors=0
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed 's/^"//;s/"$//')
        case "$key" in
            MAX_AGE_DAYS|MAX_SIZE_KB|RETENTION_DAYS)
                if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                    echo -e "  ${RED}✘${NC} $key=$value  ${RED}(must be a positive integer)${NC}"
                    errors=$((errors + 1))
                fi
                ;;
            COMPRESSION)
                if [[ "$value" != "gzip" && "$value" != "bzip2" && "$value" != "xz" ]]; then
                    echo -e "  ${RED}✘${NC} COMPRESSION=$value  ${RED}(must be gzip, bzip2, or xz)${NC}"
                    errors=$((errors + 1))
                fi
                ;;
        esac
    done < "$CONFIG_FILE"
    
    if [ $errors -eq 0 ]; then
        echo -e "  ${GREEN}✔${NC} Configuration is valid"
    else
        echo -e "  ${YELLOW}⚠${NC} Found $errors configuration issue(s) — please fix config.conf"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} config.conf not found — will use defaults"
fi

echo ""

# ─── 5. Optional Cron Job Setup ──────────────────────
echo -e "${BOLD}[5/5] Cron job setup (optional)...${NC}"

if command -v crontab &>/dev/null; then
    echo -e "  ${CYAN}Would you like to set up a daily cron job for log rotation?${NC}"
    echo -e "  This will run log_rotator.sh every day at 2:00 AM."
    echo ""
    read -rp "  Set up cron job? [y/N]: " cron_answer
    
    if [[ "$cron_answer" =~ ^[Yy]$ ]]; then
        CRON_CMD="0 2 * * * cd $SCRIPT_DIR && bash log_rotator.sh --config config.conf >> /tmp/log_rotator_cron.log 2>&1"
        
        # Check if cron entry already exists
        if crontab -l 2>/dev/null | grep -q "log_rotator.sh"; then
            echo -e "  ${YELLOW}⚠${NC} Cron job already exists — skipping"
        else
            (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
            echo -e "  ${GREEN}✔${NC} Cron job installed: daily at 2:00 AM"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Skipped cron setup"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} crontab not available — skipping cron setup"
fi

# ─── Summary ─────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    1. Generate sample logs:  ${CYAN}bash test_setup.sh${NC}"
echo -e "    2. Preview (dry run):     ${CYAN}bash log_rotator.sh --dry-run${NC}"
echo -e "    3. Run for real:          ${CYAN}bash log_rotator.sh${NC}"
echo -e "    4. Check audit log:       ${CYAN}cat audit.log${NC}"
echo ""
