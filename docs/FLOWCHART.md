# Flowcharts — Automated Log Archive & Rotation

Visual representations of the algorithms used in the log rotation utility.

---

## 1. Main Execution Flow

```mermaid
flowchart TD
    A([Start]) --> B[Parse CLI Arguments]
    B --> C[Load config.conf]
    C --> D{Config Valid?}
    D -- No --> E[Log ERROR & Exit]
    D -- Yes --> F[Print Configuration]
    F --> G{Dry Run?}
    G -- Yes --> H[Print DRY-RUN Warning]
    G -- No --> I{Force Mode?}
    I -- No --> J{User Confirms?}
    J -- No --> K[Log Cancel & Exit]
    J -- Yes --> L[Phase 1: Scan & Archive]
    I -- Yes --> L
    H --> L
    L --> M[Phase 2: Retention Policy]
    M --> N[Print Summary Report]
    N --> O{Errors > 0?}
    O -- Yes --> P[Exit Code 1]
    O -- No --> Q([Exit Code 0])
```

---

## 2. File Scanning & Filtering Algorithm

```mermaid
flowchart TD
    A([Start Scan]) --> B[Build find command\nfrom LOG_EXTENSIONS]
    B --> C["Execute: find LOG_DIR\n-name '*.log' -o -name '*.txt' ..."]
    C --> D{Files Found?}
    D -- No --> E[Log: No files found]
    D -- Yes --> F[Get Next File]
    F --> G[Read file metadata\nsize, modification time]
    G --> H{Age > MAX_AGE_DAYS?}
    H -- Yes --> J[Mark for archiving\nreason = age]
    H -- No --> I{Size > MAX_SIZE_KB?}
    I -- Yes --> K[Mark for archiving\nreason = size]
    I -- No --> L[Skip file\nFILES_SKIPPED++]
    J --> M{Also Size > MAX_SIZE_KB?}
    M -- Yes --> N[Update reason:\nage AND size]
    M -- No --> O[Archive File]
    K --> O
    N --> O
    L --> P{More Files?}
    O --> P
    P -- Yes --> F
    P -- No --> Q([Scan Complete])

    style J fill:#fbbf24,stroke:#92400e
    style K fill:#fbbf24,stroke:#92400e
    style L fill:#6ee7b7,stroke:#065f46
    style O fill:#f87171,stroke:#991b1b
```

---

## 3. Archive Name Generation & Overwrite Protection

```mermaid
flowchart TD
    A([Generate Archive Name]) --> B["Extract base name\ne.g., 'app' from 'app.log'"]
    B --> C["Generate timestamp\nYYYY-MM-DD_HHMMSS"]
    C --> D["Compose name:\napp_2026-11-11_230500.log.gz"]
    D --> E{File exists\nin ARCHIVE_DIR?}
    E -- No --> F[Return archive path]
    E -- Yes --> G[Set counter = 1]
    G --> H["Try: app_2026-11-11_230500_1.log.gz"]
    H --> I{File exists?}
    I -- Yes --> J[counter++]
    J --> H
    I -- No --> K[Log WARNING:\ncollision detected]
    K --> L[Return archive path\nwith suffix]

    style F fill:#6ee7b7,stroke:#065f46
    style L fill:#fbbf24,stroke:#92400e
    style K fill:#fbbf24,stroke:#92400e
```

---

## 4. Compression Workflow

```mermaid
flowchart TD
    A([Compress File]) --> B{Compression\nTool?}
    B -- gzip --> C["gzip -c source > dest.gz"]
    B -- bzip2 --> D["bzip2 -c source > dest.bz2"]
    B -- xz --> E["xz -c source > dest.xz"]
    C --> F{Success?}
    D --> F
    E --> F
    F -- Yes --> G[Calculate compression ratio]
    G --> H[Delete original file]
    H --> I[Log INFO:\nfile archived with stats]
    I --> J[FILES_ARCHIVED++]
    J --> K([Done])
    F -- No --> L[Log ERROR:\ncompression failed]
    L --> M[ERRORS++]
    M --> N([Skip File])

    style I fill:#6ee7b7,stroke:#065f46
    style L fill:#f87171,stroke:#991b1b
```

---

## 5. Retention Policy Enforcement

```mermaid
flowchart TD
    A([Start Retention]) --> B{ARCHIVE_DIR\nexists?}
    B -- No --> C[Log: nothing to clean]
    B -- Yes --> D["find ARCHIVE_DIR\n-mtime +RETENTION_DAYS"]
    D --> E{Expired files\nfound?}
    E -- No --> F[Log: all within\nretention window]
    E -- Yes --> G[Get Next Expired File]
    G --> H{Dry Run?}
    H -- Yes --> I["Print: Would delete\nFILES_DELETED++"]
    H -- No --> J["rm -f file\nFILES_DELETED++"]
    I --> K{More expired?}
    J --> L[Log INFO: deleted]
    L --> K
    K -- Yes --> G
    K -- No --> M([Retention Complete])

    style J fill:#f87171,stroke:#991b1b
    style I fill:#fbbf24,stroke:#92400e
```

---

## 6. Complete System Overview

```mermaid
flowchart LR
    subgraph Input
        A[config.conf]
        B[CLI Arguments]
        C[Log Directory]
    end

    subgraph Processing
        D[Config Loader\n& Validator]
        E[Scanner Engine]
        F[Filter Engine\nAge OR Size]
        G[Archive Engine\nCompress + Name]
        H[Retention Engine\nDelete Expired]
    end

    subgraph Output
        I[Archive Directory\nCompressed Files]
        J[Audit Log\nAction History]
        K[Summary Report\nStats & Metrics]
    end

    A --> D
    B --> D
    D --> E
    C --> E
    E --> F
    F --> G
    G --> I
    G --> J
    H --> I
    H --> J
    G --> H
    H --> K

    style D fill:#818cf8,stroke:#3730a3,color:#fff
    style E fill:#818cf8,stroke:#3730a3,color:#fff
    style F fill:#818cf8,stroke:#3730a3,color:#fff
    style G fill:#818cf8,stroke:#3730a3,color:#fff
    style H fill:#818cf8,stroke:#3730a3,color:#fff
```

---

## 7. Audit Log Event Flow

```mermaid
sequenceDiagram
    participant U as User
    participant S as Script
    participant A as Audit Log
    participant FS as File System

    U->>S: bash log_rotator.sh
    S->>A: [INFO] Run started
    S->>A: [INFO] Config loaded
    S->>FS: Scan LOG_DIR
    FS-->>S: File list

    loop For each file
        S->>S: Check age & size
        alt Meets criteria
            S->>FS: Compress & archive
            FS-->>S: Success
            S->>A: [INFO] Archived: file → archive
            S->>FS: Delete original
        else Does not meet criteria
            S->>S: Skip
        end
    end

    S->>FS: Scan ARCHIVE_DIR for expired
    loop For each expired archive
        S->>FS: Delete archive
        S->>A: [INFO] Deleted expired: archive
    end

    S->>A: [INFO] Summary: scanned/archived/deleted
    S->>U: Print Summary Report
```
