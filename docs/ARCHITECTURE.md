# System Architecture — Automated Log Archive & Rotation

## High-Level Architecture

The utility follows a **pipeline architecture** with four sequential stages:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   CONFIG     │────▶│   SCANNER   │────▶│  ARCHIVER   │────▶│  RETENTION  │
│   LOADER     │     │   ENGINE    │     │   ENGINE    │     │   ENFORCER  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
       │                    │                   │                    │
       ▼                    ▼                   ▼                    ▼
  ┌─────────┐         ┌─────────┐         ┌─────────┐         ┌─────────┐
  │ config  │         │ file    │         │ archive │         │ deleted │
  │ .conf   │         │ list    │         │ files   │         │ expired │
  └─────────┘         └─────────┘         └─────────┘         └─────────┘
                                                │
                                                ▼
                                          ┌──────────┐
                                          │ AUDIT    │
                                          │ LOGGER   │
                                          └──────────┘
                                                │
                                                ▼
                                          ┌──────────┐
                                          │ audit    │
                                          │ .log     │
                                          └──────────┘
```

---

## Component Descriptions

### 1. Configuration Loader

**Purpose**: Reads and parses `config.conf`, overrides defaults with user-specified values.

**Algorithm**: 
- Line-by-line parsing: O(L) where L = number of lines in config
- Key-value extraction using `IFS='='` field separation
- Comment and blank line filtering using regex
- Quote stripping with `sed`

**Design Decision**: We parse the config manually rather than using `source` to prevent arbitrary code execution from the configuration file (security best practice).

### 2. Scanner Engine

**Purpose**: Discovers log files in `LOG_DIR` that match the configured file patterns.

**Algorithm**:
- Uses `find` with `-name` predicates joined by `-o` (logical OR)
- Time complexity: O(n) where n = total files in the directory
- `-maxdepth 1` limits the search to avoid recursive descent (configurable)

**Key Commands**:
```bash
# Age-based detection
find "$file" -mtime +$MAX_AGE_DAYS

# Size-based detection  
file_size_kb=$(($(wc -c < "$file") / 1024))
[ "$file_size_kb" -gt "$MAX_SIZE_KB" ]
```

### 3. Archiver Engine

**Purpose**: Compresses qualifying files with date-stamped names and overwrite protection.

**Sub-components**:

#### a. Name Generator
- Format: `<name>_<YYYY-MM-DD_HHMMSS>.<ext>.<compression_ext>`
- Collision detection: checks if target path exists
- Resolution: appends `_1`, `_2`, ... until unique

#### b. Compression Module
- Supports three algorithms:
  
  | Algorithm | Extension | Ratio | Speed |
  |-----------|-----------|-------|-------|
  | gzip      | .gz       | Good  | Fast  |
  | bzip2     | .bz2      | Better| Slow  |
  | xz        | .xz       | Best  | Slowest |

- Uses stream compression (`-c` flag) to write to a named output file
- Original file deleted only after successful compression

#### c. Overwrite Protection
```
Generate name → Check exists? ─── No ──→ Use name
                     │
                    Yes
                     │
                     ▼
              Append suffix _N
              Check exists? ─── No ──→ Use name
                     │
                    Yes (loop)
```

### 4. Retention Enforcer

**Purpose**: Deletes archives that exceed the retention window.

**Algorithm**:
- Uses `find -mtime +$RETENTION_DAYS` on the archive directory
- Time complexity: O(a) where a = number of archived files
- Each deletion is logged before execution

### 5. Audit Logger

**Purpose**: Maintains a complete action history for accountability.

**Log Levels**:
| Level | Colour | Purpose |
|-------|--------|---------|
| INFO  | Green  | Successful operations |
| WARN  | Yellow | Non-critical issues (collisions, skips) |
| ERROR | Red    | Failures (permission, compression errors) |

**Format**: `[YYYY-MM-DD HH:MM:SS] [LEVEL] Message`

---

## Data Flow Diagram

```
                          ┌──────────────────┐
                          │   config.conf    │
                          └────────┬─────────┘
                                   │ read
                                   ▼
                          ┌──────────────────┐
                          │  Parse & Validate │
                          └────────┬─────────┘
                                   │
                                   ▼
                 ┌─────────────────────────────────┐
                 │        LOG DIRECTORY             │
                 │  ┌─────┐ ┌─────┐ ┌─────┐       │
                 │  │.log │ │.txt │ │.out │  ...   │
                 │  └──┬──┘ └──┬──┘ └──┬──┘       │
                 └─────┼───────┼───────┼───────────┘
                       │       │       │
                       ▼       ▼       ▼
                 ┌─────────────────────────────┐
                 │     FILTER ENGINE            │
                 │  ┌──────────┐ ┌──────────┐  │
                 │  │ Age > N? │ │ Size > M?│  │
                 │  └────┬─────┘ └────┬─────┘  │
                 │       │   OR       │        │
                 │       └─────┬──────┘        │
                 └─────────────┼───────────────┘
                      ┌────────┴────────┐
                      ▼                 ▼
               ┌───────────┐     ┌───────────┐
               │  ARCHIVE  │     │   SKIP    │
               │  (compress│     │  (no-op)  │
               │  + rename)│     └───────────┘
               └─────┬─────┘
                     │
                     ▼
              ┌──────────────┐
              │ ARCHIVE DIR  │
              │  ┌────────┐  │
              │  │.log.gz │  │
              │  └────────┘  │
              └──────┬───────┘
                     │
                     ▼
              ┌──────────────┐
              │  RETENTION   │
              │  age > R?    │
              │  → DELETE    │
              └──────────────┘
```

---

## Complexity Summary

### Time Complexity: O(n × m)

Where:
- **n** = number of log files in the directory
- **m** = average size of a log file (compression is linear in file size)

The dominant cost is compression. Scanning and filtering are O(n). The overall complexity is O(n × m) because each of the n qualifying files requires O(m) time to compress.

### Space Complexity: O(n + m)

Where:
- **O(n)** = in-memory list of file paths
- **O(m)** = disk space for the largest compressed archive (temporary)

The utility processes files sequentially (one at a time), so it only needs disk space for one compressed file at a time in addition to the file list.

---

## Error Handling Strategy

| Scenario | Handling |
|----------|----------|
| Config file missing | Use defaults, log warning |
| Invalid config value | Log error, exit with code 1 |
| LOG_DIR doesn't exist | Log error, exit with code 1 |
| Compression failure | Log error, skip file, continue |
| Permission denied | Log error, skip file, continue |
| Archive name collision | Append numeric suffix, log warning |
| No files match criteria | Log info, skip archiving phase |
| ARCHIVE_DIR doesn't exist | Create it automatically |

---

## Security Considerations

1. **No `source` for config**: Configuration is parsed line-by-line to prevent code injection.
2. **`set -euo pipefail`**: Script exits on undefined variables and pipe failures.
3. **Post-compression deletion**: Original files are deleted only after successful compression, preventing data loss.
4. **Audit trail**: Every action is logged for forensic analysis.
