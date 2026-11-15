# Automated Log Archive & Rotation Utility

> A production-grade shell utility that scans a configured log directory, archives logs older than a chosen age or larger than a size limit, applies a retention policy, and maintains a comprehensive audit trail.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Algorithm Analysis](#algorithm-analysis)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

---

## Overview

Log files grow continuously in any system — web servers, application backends, batch jobs, and system daemons all produce logs that consume disk space. Without a rotation and archiving strategy, logs can fill up the filesystem, degrade performance, and make debugging nearly impossible.

**Automated Log Archive & Rotation** solves this by providing a configurable shell utility that:

1. **Scans** a directory for log files matching configurable patterns.
2. **Archives** files that exceed an age threshold OR a size limit.
3. **Compresses** archived files using gzip, bzip2, or xz.
4. **Names** archives with date-stamped filenames for traceability.
5. **Prevents** overwriting by detecting filename collisions.
6. **Enforces** a retention policy by deleting old archives.
7. **Logs** every action to an audit trail for accountability.

---

## Features

| Feature | Description |
|---------|-------------|
| **Age-Based Archiving** | Archive logs older than N days (configurable) |
| **Size-Based Archiving** | Archive logs larger than N KB (configurable) |
| **Date-Stamped Names** | Archives named as `filename_YYYY-MM-DD_HHMMSS.ext.gz` |
| **Overwrite Protection** | Detects collisions and appends numeric suffixes |
| **Multiple Compression** | Supports `gzip`, `bzip2`, and `xz` |
| **Retention Policy** | Auto-deletes archives older than N days |
| **Audit Logging** | Records every action with timestamps and severity levels |
| **Dry-Run Mode** | Preview all actions without making changes |
| **CLI Interface** | Supports `--config`, `--dry-run`, `--force`, `--verbose`, `--help` |
| **Summary Report** | Displays files processed, space saved, and compression ratios |
| **Configurable Patterns** | Scan for `*.log`, `*.txt`, `*.out`, or custom patterns |
| **Cron Integration** | Optional automated scheduling via cron job |

---

## Project Structure

```
UNIX/
├── log_rotator.sh      # Main utility script
├── config.conf         # Configuration file
├── install.sh          # Dependency checker & installer
├── test_setup.sh       # Sample log file generator
├── README.md           # This documentation
├── docs/
│   ├── ARCHITECTURE.md # System architecture & design
│   └── FLOWCHART.md    # Visual algorithm flowcharts
├── sample_logs/        # Generated sample logs (created by test_setup.sh)
├── archives/           # Compressed archives (created by log_rotator.sh)
└── audit.log           # Audit trail (created by log_rotator.sh)
```

---

## Prerequisites

The following tools must be available on your system:

| Tool | Required | Purpose |
|------|----------|---------|
| `bash` | ✅ Yes | Shell interpreter (v4.0+) |
| `find` | ✅ Yes | File discovery by age/size |
| `date` | ✅ Yes | Timestamp generation |
| `gzip` | ✅ Yes | Default compression |
| `wc` | ✅ Yes | File size calculation |
| `du` | ✅ Yes | Directory size reporting |
| `touch` | ✅ Yes | File timestamp manipulation |
| `bc` | ⚡ Recommended | Arithmetic for compression ratios |
| `bzip2` | ⚪ Optional | Alternative compression |
| `xz` | ⚪ Optional | Alternative compression |
| `crontab` | ⚪ Optional | Automated scheduling |

---

## Installation

```bash
# 1. Navigate to the project directory
cd UNIX/

# 2. Run the installer
bash install.sh

# 3. Generate sample logs for testing
bash test_setup.sh
```

The installer will:
- ✅ Check all required dependencies
- ✅ Set executable permissions
- ✅ Create required directories
- ✅ Validate the configuration file
- ✅ Optionally set up a cron job

---

## Configuration

Edit `config.conf` to customise the utility:

```bash
# Directory containing log files to scan
LOG_DIR="./sample_logs"

# Where compressed archives are stored
ARCHIVE_DIR="./archives"

# Audit log file path
AUDIT_LOG="./audit.log"

# Archive logs older than this many days
MAX_AGE_DAYS=7

# Archive logs larger than this many KB
MAX_SIZE_KB=1024

# Delete archives older than this many days
RETENTION_DAYS=30

# Compression tool: gzip | bzip2 | xz
COMPRESSION="gzip"

# File patterns to scan (space-separated)
LOG_EXTENSIONS="*.log *.txt *.out"

# Preview mode (true/false)
DRY_RUN=false

# Extra output (true/false)
VERBOSE=false
```

---

## Usage

### Basic Run
```bash
bash log_rotator.sh
```

### Dry Run (Preview)
```bash
bash log_rotator.sh --dry-run
```

### Custom Configuration
```bash
bash log_rotator.sh --config /path/to/custom.conf
```

### Verbose Mode with No Prompts
```bash
bash log_rotator.sh --verbose --force
```

### Help
```bash
bash log_rotator.sh --help
```

### All Options

| Flag | Description |
|------|-------------|
| `--config <path>` | Use a custom configuration file |
| `--dry-run` | Preview actions without making changes |
| `--force` | Skip the confirmation prompt |
| `--verbose` | Show extra detail during execution |
| `--help` | Display usage information |

---

## How It Works

### Phase 1: Scanning & Archiving

1. The script reads `config.conf` and validates all parameters.
2. It scans `LOG_DIR` for files matching `LOG_EXTENSIONS` patterns.
3. For each file, it checks two criteria:
   - **Age**: Is the file's modification time older than `MAX_AGE_DAYS`?
   - **Size**: Is the file larger than `MAX_SIZE_KB`?
4. If **either** criterion is met, the file is archived:
   - A date-stamped filename is generated.
   - **Overwrite protection**: If the name already exists, a numeric suffix is appended.
   - The file is compressed using the configured tool.
   - The original file is deleted.
   - The action is logged to the audit log.

### Phase 2: Retention Policy

1. The script scans `ARCHIVE_DIR` for compressed files.
2. Archives older than `RETENTION_DAYS` are deleted.
3. Each deletion is logged to the audit log.

### Audit Log Format

```
[2026-11-11 23:05:00] [INFO] Archived: app.log → app_2026-11-11_230500.log.gz | 1.2 MB → 340 KB (72.0% reduction) | Reason: older than 7 days
[2026-11-11 23:05:01] [WARN] Archive name collision detected — using: app_2026-11-11_230500_1.log.gz
[2026-11-11 23:05:02] [INFO] Deleted expired archive: old_2026-10-01_120000.log.gz (450 KB)
[2026-11-11 23:05:02] [ERROR] Failed to compress: locked_file.log
```

---

## Algorithm Analysis

### Time Complexity

| Operation | Complexity | Explanation |
|-----------|-----------|-------------|
| File scanning | O(n) | Iterates over all n files in LOG_DIR |
| Age/size filtering | O(n) | Each file checked against thresholds |
| Archive name generation | O(1) amortised | Collision resolution is rare |
| Compression | O(m) | Proportional to file size m |
| Retention cleanup | O(a) | Iterates over a archived files |
| **Overall** | **O(n × m)** | Dominated by compression of large files |

### Space Complexity

| Component | Complexity | Explanation |
|-----------|-----------|-------------|
| File list | O(n) | Stores paths of matched files |
| Compressed output | O(m) | Compressed file stored on disk |
| Audit log | O(1) per entry | Appended incrementally |
| **Overall** | **O(n + m)** | File list + largest compressed file |

### Design Choices

- **Union criteria (OR)**: A file is archived if it exceeds the age limit OR the size limit. This is more aggressive than intersection (AND) and prevents any single oversized log from consuming disk indefinitely.
- **Rename-then-delete**: The original file is only deleted after successful compression, preventing data loss.
- **Monotonic collision resolution**: Appending `_1`, `_2`, etc. guarantees uniqueness without expensive lookups.

---

## Examples

### Example 1: First Run

```bash
$ bash test_setup.sh       # Create sample logs
$ bash log_rotator.sh --force --verbose
```

**Expected output**: Old and large files are archived, recent small files are skipped.

### Example 2: Dry Run

```bash
$ bash log_rotator.sh --dry-run
```

**Expected output**: All planned actions are printed but no files are changed.

### Example 3: Check Audit Log

```bash
$ cat audit.log
[2026-11-11 23:05:00] [INFO] Log Rotator v1.0.0 — Run started
[2026-11-11 23:05:00] [INFO] Configuration loaded from: config.conf
[2026-11-11 23:05:01] [INFO] Archived: auth-service.log → auth-service_2026-11-11_230501.log.gz
...
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Log directory does not exist" | Ensure `LOG_DIR` in config.conf points to a valid directory |
| "Compression tool not installed" | Install the tool: `sudo apt install gzip` |
| "Permission denied" | Run `bash install.sh` to fix permissions |
| No files archived | Check `MAX_AGE_DAYS` and `MAX_SIZE_KB` thresholds |
| Audit log not created | Ensure write permission in the project directory |

---

## License

This project is developed as an academic mini-project for the Analysis and Design of Algorithms course.

---

*Built with ❤️ using Bash Shell Scripting*
