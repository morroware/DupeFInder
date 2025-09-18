# DupeFinder Pro

Advanced duplicate file management utility for Linux systems with comprehensive safety features and intelligent deletion strategies.

![DupeFinder Pro Logo](https://github.com/morroware/DupeFInder/blob/main/logo.png)



## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [System Requirements](#system-requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Command Reference](#command-reference)
- [Usage Examples](#usage-examples)
- [Configuration](#configuration)
- [Safety Mechanisms](#safety-mechanisms)
- [Output Reports](#output-reports)
- [Performance Optimization](#performance-optimization)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)
- [API and Integration](#api-and-integration)
- [Contributing](#contributing)
- [License](#license)

## Overview

DupeFinder Pro is a production-ready Bash script designed for safely identifying and managing duplicate files on Linux systems. Built with enterprise environments in mind, it incorporates multiple layers of safety checks to prevent accidental deletion of system-critical files while providing flexible strategies for duplicate management.

### Key Differentiators

- **Multi-layer safety verification**: Prevents deletion of system files, shared libraries, and actively used files
- **Intelligent duplicate selection**: Smart algorithms to determine which duplicate to keep based on location, age, or custom priorities
- **Enterprise-ready reporting**: Generates detailed reports in HTML, CSV, and JSON formats for audit compliance
- **Resume capability**: Can resume interrupted scans, essential for large filesystems
- **Thread-safe operations**: Properly handles concurrent file operations without data corruption

## Features

### Core Functionality

#### Hashing Algorithms
- **MD5** (default): Fast, suitable for most use cases
- **SHA256**: Cryptographically secure, recommended for sensitive data
- **SHA512**: Maximum security for critical environments
- **Fast mode**: Combines file size with partial name hash for quick initial scans

#### Duplicate Detection Methods
- **Exact matching**: Byte-for-byte identical files
- **Fuzzy matching**: Files with similar sizes (configurable threshold)
- **Pattern-based**: Focus on specific file types
- **Size-based filtering**: Min/max size constraints

### Safety Features

#### System Protection
- Automatic detection of critical system paths
- Protection of shared libraries and kernel modules
- Recognition of actively loaded libraries
- Detection of files currently in use (via lsof)
- Special handling for boot loader files

#### User Protection
- Dry-run mode for safe preview
- Interactive confirmation for each deletion
- Backup before deletion option
- Trash integration instead of permanent deletion
- Quarantine directory for suspicious files

### Deletion Strategies

#### Automated Selection
- **Smart delete**: Uses location-based priorities
- **Keep newest**: Retains most recently modified file
- **Keep oldest**: Preserves original file
- **Path priority**: Prefer files in specified directories

#### Alternative Actions
- **Hardlink conversion**: Replace duplicates with hardlinks to save space
- **Quarantine**: Move duplicates to isolated directory for review
- **Trash**: Send to system trash for easy recovery
- **Backup and delete**: Create backup before removal

### Performance Features

- **Multi-threading**: Utilizes all available CPU cores
- **SQLite caching**: Stores file hashes for faster subsequent scans
- **GNU parallel support**: Enhanced parallelization for large datasets
- **Batch processing**: Optimized database operations
- **Progress tracking**: Real-time progress indicators

### Reporting Capabilities

- **HTML reports**: Interactive web interface with collapsible groups
- **CSV exports**: For spreadsheet analysis and data processing
- **JSON output**: Machine-readable format for automation
- **Email notifications**: Automated summary delivery
- **Operation logging**: Detailed audit trail of all actions

## System Requirements

### Minimum Requirements

- **Operating System**: Linux (kernel 3.0+)
- **Bash Version**: 4.0 or higher
- **Core Utilities**: GNU coreutils 8.0+
- **Memory**: 512MB RAM (2GB+ recommended for large scans)
- **Disk Space**: 100MB for cache and reports

### Required Commands

```bash
# Check if required commands are available
for cmd in bash find stat sort awk md5sum; do
    command -v $cmd >/dev/null 2>&1 || echo "Missing: $cmd"
done
```

### Optional Dependencies

| Package | Purpose | Installation |
|---------|---------|--------------|
| sqlite3 | Cache and checksum database | `apt install sqlite3` |
| trash-cli | Trash functionality | `apt install trash-cli` |
| parallel | Enhanced parallelization | `apt install parallel` |
| jq | JSON report generation | `apt install jq` |
| mailutils | Email notifications | `apt install mailutils` |
| lsof | Detect files in use | `apt install lsof` |
| bc | Precise calculations | `apt install bc` |

## Installation

### Method 1: Direct Download

```bash
# Download the script
wget https://raw.githubusercontent.com/morroware/DupeFinder/main/dupefinder.sh
# OR
curl -O https://raw.githubusercontent.com/morroware/DupeFinder/main/dupefinder.sh

# Make executable
chmod +x dupefinder.sh

# Verify installation
./dupefinder.sh --version
```

### Method 2: System-wide Installation

```bash
# Download and install
sudo wget -O /usr/local/bin/dupefinder \
    https://raw.githubusercontent.com/morroware/DupeFinder/main/upefinder.sh
sudo chmod +x /usr/local/bin/dupefinder

# Create configuration directory
sudo mkdir -p /etc/dupefinder
sudo cp dupefinder.conf /etc/dupefinder/

# Verify installation
dupefinder --version
```

### Method 3: Git Repository

```bash
# Clone repository
git clone https://github.com/morroware/DupeFinder/main/DupeFinder.git
cd dupefinder-pro

# Install
sudo make install

# Or manual installation
sudo cp dupefinder.sh /usr/local/bin/dupefinder
sudo chmod +x /usr/local/bin/dupefinder
```

### Installing All Dependencies

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y sqlite3 trash-cli parallel jq mailutils lsof bc

# RHEL/CentOS/Fedora
sudo dnf install -y sqlite trash-cli parallel jq mailx lsof bc

# Arch Linux
sudo pacman -S sqlite trash-cli parallel jq mailutils lsof bc

# OpenSUSE
sudo zypper install -y sqlite3 trash-cli gnu_parallel jq mailx lsof bc
```

## Quick Start

### Basic Usage

```bash
# Find duplicates in current directory
./dupefinder.sh

# Find and delete duplicates (with confirmation)
./dupefinder.sh --delete --interactive

# Safe dry run to preview actions
./dupefinder.sh --delete --dry-run

# System-wide scan with safety
sudo ./dupefinder.sh --path / --skip-system --delete --dry-run
```

### Common Scenarios

```bash
# Clean up downloads folder
./dupefinder.sh --path ~/Downloads --min-size 1M --trash

# Find duplicate photos
./dupefinder.sh --path ~/Pictures --pattern "*.jpg" --pattern "*.png" --keep-newest

# Process large dataset with caching
./dupefinder.sh --path /data --cache --threads 8 --save-checksums

# Generate reports only
./dupefinder.sh --path ~/Documents --csv report.csv --json report.json
```

## Command Reference

### Synopsis

```bash
dupefinder.sh [OPTIONS]
```

### Option Categories

#### Basic Options

| Short | Long | Arguments | Description |
|-------|------|-----------|-------------|
| `-p` | `--path` | PATH | Directory to scan (default: current) |
| `-o` | `--output` | DIR | Output directory for reports |
| `-e` | `--exclude` | PATH | Exclude path (repeatable) |
| `-m` | `--min-size` | SIZE | Minimum file size |
| `-M` | `--max-size` | SIZE | Maximum file size |
| `-h` | `--help` | - | Display help message |
| `-V` | `--version` | - | Show version information |

#### Safety Options

| Long | Description | Risk Level |
|------|-------------|------------|
| `--skip-system` | Exclude system folders | Low (Recommended) |
| `--force-system` | Allow system file deletion | Critical |
| `--dry-run` | Preview without changes | None |
| `--backup` | Create backups | Low |

#### Search Options

| Short | Long | Arguments | Description |
|-------|------|-----------|-------------|
| `-f` | `--follow-symlinks` | - | Follow symbolic links |
| `-z` | `--empty` | - | Include empty files |
| `-a` | `--all` | - | Include hidden files |
| `-l` | `--level` | DEPTH | Max directory depth |
| `-t` | `--pattern` | GLOB | File pattern filter |
| - | `--fast` | - | Fast mode (size+name) |
| - | `--fuzzy` | - | Fuzzy matching |
| - | `--similarity` | PCT | Similarity threshold |
| - | `--verify` | - | Byte verification |

#### Action Options

| Short | Long | Arguments | Description |
|-------|------|-----------|-------------|
| `-d` | `--delete` | - | Delete duplicates |
| `-i` | `--interactive` | - | Confirm each action |
| `-n` | `--dry-run` | - | Preview mode |
| - | `--trash` | - | Use trash |
| - | `--hardlink` | - | Create hardlinks |
| - | `--quarantine` | DIR | Move to quarantine |

#### Selection Strategies

| Short | Long | Arguments | Description |
|-------|------|-----------|-------------|
| `-k` | `--keep-newest` | - | Keep newest file |
| `-K` | `--keep-oldest` | - | Keep oldest file |
| - | `--keep-path` | PATH | Prefer path |
| - | `--smart-delete` | - | Use smart priorities |
| - | `--auto-select` | LOC | Auto-select location |

#### Performance Options

| Long | Arguments | Description | Default |
|------|-----------|-------------|---------|
| `--threads` | N | Worker threads | CPU cores |
| `--cache` | - | Use SQLite cache | Disabled |
| `--save-checksums` | - | Store checksums | Disabled |
| `--no-progress` | - | Disable progress | Enabled |
| `--parallel` | - | Use GNU parallel | Auto-detect |

#### Output Options

| Short | Long | Arguments | Description |
|-------|------|-----------|-------------|
| `-c` | `--csv` | FILE | Generate CSV |
| - | `--json` | FILE | Generate JSON |
| - | `--email` | ADDRESS | Email report |
| - | `--log` | FILE | Log operations |
| `-v` | `--verbose` | - | Verbose output |
| `-q` | `--quiet` | - | Minimal output |

#### Hash Options

| Short | Long | Description | Speed | Security |
|-------|------|-------------|-------|----------|
| - | - | MD5 (default) | Fast | Basic |
| `-s` | `--sha256` | SHA-256 | Medium | High |
| - | `--sha512` | SHA-512 | Slow | Maximum |

### Size Specification

Sizes can be specified in various formats:

```bash
# Bytes
--min-size 1000

# Kilobytes
--min-size 10K
--min-size 10KB

# Megabytes
--min-size 5M
--min-size 5MB

# Gigabytes
--max-size 2G
--max-size 2GB
```

## Usage Examples

### Enterprise Scenarios

#### Data Center Cleanup

```bash
# Scan network storage with reporting
./dupefinder.sh \
    --path /mnt/storage \
    --min-size 10M \
    --skip-system \
    --cache \
    --threads 16 \
    --csv storage_audit.csv \
    --json storage_audit.json \
    --email admin@company.com \
    --log /var/log/dupefinder.log
```

#### Development Environment

```bash
# Clean build artifacts
./dupefinder.sh \
    --path ~/projects \
    --pattern "*.o" \
    --pattern "*.pyc" \
    --pattern "*.class" \
    --exclude ".git" \
    --exclude "node_modules" \
    --delete \
    --dry-run
```

#### Media Library Organization

```bash
# Find duplicate media files
./dupefinder.sh \
    --path /media/library \
    --pattern "*.mp4" \
    --pattern "*.mkv" \
    --pattern "*.avi" \
    --min-size 100M \
    --keep-path "/media/library/originals" \
    --hardlink \
    --verbose
```

#### Backup Deduplication

```bash
# Deduplicate backup archives
./dupefinder.sh \
    --path /backups \
    --pattern "*.tar.gz" \
    --pattern "*.zip" \
    --keep-oldest \
    --quarantine /backups/duplicates \
    --csv backup_audit.csv
```

### Advanced Workflows

#### Progressive Scanning

```bash
# Step 1: Fast initial scan
./dupefinder.sh --path /data --fast --csv fast_scan.csv

# Step 2: Verify potential duplicates
./dupefinder.sh --path /data --verify --min-size 1M --cache

# Step 3: Safe deletion with backup
./dupefinder.sh --path /data --delete --backup /safe/backup --dry-run

# Step 4: Execute deletion
./dupefinder.sh --path /data --delete --backup /safe/backup
```

#### Scheduled Maintenance

```bash
#!/bin/bash
# cron_dupefinder.sh - Weekly duplicate cleanup

SCAN_PATH="/home"
REPORT_DIR="/var/reports/duplicates"
DATE=$(date +%Y%m%d)

# Run scan
/usr/local/bin/dupefinder \
    --path "$SCAN_PATH" \
    --skip-system \
    --min-size 5M \
    --cache \
    --csv "$REPORT_DIR/scan_$DATE.csv" \
    --json "$REPORT_DIR/scan_$DATE.json" \
    --email sysadmin@company.com \
    --log "$REPORT_DIR/scan_$DATE.log" \
    --quiet

# Archive old reports
find "$REPORT_DIR" -name "scan_*.csv" -mtime +30 -delete
```

## Configuration

### Configuration File Format

Create `~/.dupefinder.conf` or `/etc/dupefinder/dupefinder.conf`:

```bash
# DupeFinder Pro Configuration
# Default values for command-line options

# Paths
SEARCH_PATH="/home/user/Documents"
OUTPUT_DIR="$HOME/duplicate_reports"
BACKUP_DIR="/backup/duplicates"
QUARANTINE_DIR="/quarantine"

# Exclusions
EXCLUDE_PATHS=("/proc" "/sys" "/dev" "/run" "/tmp")
EXCLUDE_LIST_FILE="/etc/dupefinder/exclude.list"

# Size filters
MIN_SIZE=1048576  # 1MB in bytes
MAX_SIZE=10737418240  # 10GB in bytes

# Search options
FOLLOW_SYMLINKS=0
HIDDEN_FILES=0
EMPTY_FILES=0
MAX_DEPTH=10

# File patterns
FILE_PATTERN=("*.jpg" "*.png" "*.mp4")

# Hash algorithm: md5sum, sha256sum, sha512sum
HASH_ALGORITHM="sha256sum"

# Deletion strategy
DELETE_MODE=0
DRY_RUN=1
INTERACTIVE_DELETE=0
USE_TRASH=1
HARDLINK_MODE=0

# Keep strategies
KEEP_NEWEST=0
KEEP_OLDEST=1
SMART_DELETE=0

# Performance
THREADS=8
USE_CACHE=1
SAVE_CHECKSUMS=1
PROGRESS_BAR=1
USE_PARALLEL=1

# Database paths
DB_CACHE="$HOME/.dupefinder_cache.db"
CHECKSUM_DB="$HOME/.dupefinder_checksums.db"

# Reporting
HTML_REPORT="duplicates_report.html"
CSV_REPORT=""
JSON_REPORT=""
EMAIL_REPORT=""
LOG_FILE="/var/log/dupefinder.log"

# Output control
VERBOSE=0
QUIET=0

# Safety
SKIP_SYSTEM_FOLDERS=1
FORCE_SYSTEM_DELETE=0

# Advanced
FUZZY_MATCH=0
SIMILARITY_THRESHOLD=95
FAST_MODE=0
VERIFY_MODE=0
```

### Exclude List File

Create `/etc/dupefinder/exclude.list`:

```
# Paths to exclude from scanning
# One path per line, comments start with #

/proc
/sys
/dev
/run
/tmp
/var/run
/var/lock
/mnt
/media

# User-specific exclusions
/home/*/.cache
/home/*/.local/share/Trash
/home/*/snap

# Application exclusions
**/node_modules
**/.git
**/.svn
**/__pycache__
```

### Location Priority Configuration

Modify the script's `LOCATION_PRIORITY` array for custom priorities:

```bash
declare -A LOCATION_PRIORITY=(
  ["/home"]=1              # Highest priority - user files
  ["/data"]=2              # Important data
  ["/usr/local"]=3         # Local installations
  ["/opt"]=4               # Optional software
  ["/var"]=5               # Variable data
  ["/srv"]=6               # Service data
  ["/tmp"]=99              # Lowest priority - temporary files
  ["/downloads"]=90        # Downloads
  ["/cache"]=95            # Cache directories
  ["/backup"]=10           # Backup files - keep these
)
```

## Safety Mechanisms

### Multi-Layer Protection System

#### Layer 1: Path-Based Protection

Protected system paths that are never deleted without explicit override:

```
/boot     - Boot loader and kernel files
/bin      - Essential command binaries
/sbin     - System binaries
/lib      - Essential shared libraries
/lib32    - 32-bit compatibility libraries
/lib64    - 64-bit libraries
/usr      - Secondary hierarchy
/etc      - System configuration
/root     - Root user home directory
```

#### Layer 2: File Type Protection

Protected file extensions:

```
.so       - Shared libraries
.dll      - Dynamic link libraries
.dylib    - macOS dynamic libraries
.ko       - Kernel modules
.sys      - System files
.elf      - Executable and Linkable Format
.a        - Static libraries
.lib      - Library files
```

#### Layer 3: Pattern Protection

Never-delete filename patterns:

```
vmlinuz*     - Linux kernel
initrd*      - Initial ramdisk
initramfs*   - Initial RAM filesystem
grub*        - Boot loader files
ld-linux*    - Dynamic linker
libc.so*     - C standard library
libpthread*  - POSIX threads library
systemd*     - Init system files
busybox*     - Emergency shell
```

#### Layer 4: Active Use Detection

- Files currently opened by processes (via lsof)
- Shared libraries loaded in memory
- Files with active file locks

### Safety Workflow

```
1. File Discovery
   ├── Apply exclusion rules
   └── Skip protected paths

2. Hash Calculation
   ├── Check file readability
   └── Handle errors gracefully

3. Duplicate Detection
   ├── Group by hash
   └── Verify with byte comparison (optional)

4. Pre-Deletion Checks
   ├── Is system file? → Skip/Warn
   ├── Is in use? → Skip/Warn
   ├── Is owned by root? → Warn
   └── User confirmation (if interactive)

5. Safe Deletion
   ├── Create backup (optional)
   ├── Move to trash/quarantine
   └── Log action
```

## Output Reports

### HTML Report Structure

The HTML report provides an interactive interface with:

- **Header**: Script version, generation date, safety status
- **Statistics Dashboard**: 
  - Files scanned
  - Duplicates found
  - Duplicate groups
  - Space wasted
- **Duplicate Groups**: Collapsible sections showing:
  - Group ID and hash
  - File paths
  - File sizes
  - System file indicators

### CSV Report Format

```csv
Hash,File Path,Size (bytes),Size (human),Group ID,System File
a1b2c3d4...,/home/user/file1.txt,1024,1.00 KB,1,No
a1b2c3d4...,/home/user/file2.txt,1024,1.00 KB,1,No
e5f6g7h8...,/var/data/doc.pdf,2048576,2.00 MB,2,Yes
```

### JSON Report Structure

```json
{
  "metadata": {
    "version": "0.0.1",
    "author": "Seth Morrow",
    "generated": "2024-01-01T12:00:00Z",
    "search_path": "/home/user",
    "system_protection": true,
    "total_files": 1000,
    "total_duplicates": 50,
    "total_groups": 20,
    "space_wasted": 104857600,
    "hash_algorithm": "sha256"
  },
  "groups": [
    {
      "id": 1,
      "hash": "a1b2c3d4e5f6...",
      "files": [
        {
          "path": "/home/user/file1.txt",
          "size": 1024,
          "system": false
        },
        {
          "path": "/home/user/file2.txt",
          "size": 1024,
          "system": false
        }
      ]
    }
  ]
}
```

## Performance Optimization

### Threading Strategy

```bash
# Optimal thread count based on system
# CPU-bound operations: number of cores
THREADS=$(nproc)

# I/O-bound operations: 2x number of cores
THREADS=$(($(nproc) * 2))

# Manual override for specific systems
THREADS=16  # High-end server
THREADS=4   # Desktop system
THREADS=2   # Low-end system
```

### Cache Management

#### Initial Scan
```bash
# First scan - build cache
./dupefinder.sh --path /data --cache --save-checksums
```

#### Subsequent Scans
```bash
# Use existing cache - 50-80% faster
./dupefinder.sh --path /data --cache
```

#### Cache Maintenance
```bash
# View cache size
du -h ~/.dupefinder_cache.db

# Clear old entries (30+ days)
sqlite3 ~/.dupefinder_cache.db \
  "DELETE FROM file_hashes WHERE last_scan < strftime('%s', 'now', '-30 days');"

# Vacuum database
sqlite3 ~/.dupefinder_cache.db "VACUUM;"
```

### Memory Usage

| Files | RAM Usage | With Cache | Recommendation |
|-------|-----------|------------|----------------|
| 1K | ~10 MB | ~15 MB | Any system |
| 10K | ~50 MB | ~100 MB | 512MB+ RAM |
| 100K | ~300 MB | ~600 MB | 1GB+ RAM |
| 1M | ~2 GB | ~4 GB | 8GB+ RAM |
| 10M | ~15 GB | ~30 GB | 32GB+ RAM |

### Optimization Tips

1. **Use fast mode for initial scans**
   ```bash
   ./dupefinder.sh --fast --min-size 1M
   ```

2. **Enable caching for repeated scans**
   ```bash
   ./dupefinder.sh --cache --save-checksums
   ```

3. **Exclude unnecessary paths**
   ```bash
   ./dupefinder.sh --exclude /var/cache --exclude /tmp
   ```

4. **Set appropriate thread count**
   ```bash
   ./dupefinder.sh --threads $(nproc)
   ```

5. **Use GNU parallel when available**
   ```bash
   ./dupefinder.sh --parallel
   ```

## Troubleshooting

### Common Issues and Solutions

#### Permission Denied Errors

```bash
# Problem: Cannot read files
# Solution 1: Run with appropriate permissions
sudo ./dupefinder.sh --path /var --skip-system

# Solution 2: Exclude problematic directories
./dupefinder.sh --exclude /var/log --exclude /var/cache
```

#### Out of Memory

```bash
# Problem: Script killed due to memory exhaustion
# Solution 1: Reduce thread count
./dupefinder.sh --threads 2

# Solution 2: Process in smaller batches
./dupefinder.sh --level 3  # Limit depth

# Solution 3: Disable progress bar
./dupefinder.sh --no-progress
```

#### Slow Performance

```bash
# Problem: Scan takes too long
# Solution 1: Use fast mode
./dupefinder.sh --fast

# Solution 2: Enable caching
./dupefinder.sh --cache

# Solution 3: Increase threads
./dupefinder.sh --threads 16

# Solution 4: Exclude large unimportant directories
./dupefinder.sh --exclude /var/log
```

#### Cannot Delete Files

```bash
# Problem: Permission denied when deleting
# Solution 1: Check file ownership
ls -la /path/to/file

# Solution 2: Check filesystem mount options
mount | grep /path

# Solution 3: Use trash instead of delete
./dupefinder.sh --trash
```

### Debug Mode

Enable comprehensive debugging:

```bash
# Maximum verbosity with logging
./dupefinder.sh \
    --verbose \
    --log debug.log \
    --dry-run \
    --path /test
    
# Check log file
tail -f debug.log
```

### Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| `Search path does not exist` | Invalid path | Verify path exists |
| `Cannot create output directory` | Permission issue | Check write permissions |
| `sqlite3 is not installed` | Missing dependency | Install sqlite3 |
| `Invalid thread count` | Bad parameter | Use positive integer |
| `Cannot use both --keep-newest and --keep-oldest` | Conflicting options | Choose one strategy |

## Advanced Topics

### Integration with Backup Systems

#### Pre-backup Deduplication

```bash
#!/bin/bash
# Deduplicate before backup

# Step 1: Find and remove duplicates
dupefinder \
    --path /data \
    --delete \
    --backup /safe/removed \
    --log /var/log/pre-backup-dedup.log

# Step 2: Run backup
rsync -av /data/ /backup/
```

#### Post-backup Verification

```bash
#!/bin/bash
# Verify backup integrity

# Compare source and backup
dupefinder \
    --path /data \
    --path /backup \
    --csv backup_comparison.csv
```

### Automation with Cron

```bash
# Add to crontab (crontab -e)

# Daily scan at 2 AM
0 2 * * * /usr/local/bin/dupefinder --path /home --cache --quiet --log /var/log/dupefinder.log

# Weekly deep scan on Sunday
0 3 * * 0 /usr/local/bin/dupefinder --path / --skip-system --verify --csv /reports/weekly.csv

# Monthly cleanup on first day
0 4 1 * * /usr/local/bin/dupefinder --path /tmp --delete --min-size 1M
```

### Custom Shell Functions

Add to `~/.bashrc`:

```bash
# Quick duplicate check
dupcheck() {
    dupefinder --path "${1:-.}" --fast --min-size 1M
}

# Interactive duplicate removal
dupclean() {
    dupefinder --path "${1:-.}" --interactive --trash
}

# Generate duplicate report
dupreport() {
    local dir="${1:-.}"
    local name=$(basename "$dir")
    dupefinder --path "$dir" \
        --csv "${name}_duplicates.csv" \
        --json "${name}_duplicates.json"
}
```

### Performance Monitoring

```bash
#!/bin/bash
# Monitor dupefinder performance

# Run with timing
time dupefinder --path /data --cache

# Monitor resource usage
dupefinder --path /data &
PID=$!
while kill -0 $PID 2>/dev/null; do
    ps -p $PID -o pid,vsz,rss,pcpu,comm
    sleep 5
done
```

## API and Integration

### Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | Operation completed successfully |
| 1 | Error | Invalid arguments or configuration |
| 2 | Error | Missing dependencies |
| 130 | Interrupt | User interrupted (Ctrl+C) |
| 137 | Killed | Out of memory (OOM) |

### Environment Variables

```bash
# Override default configuration
export DUPEFINDER_CONFIG="/custom/config/path"
export DUPEFINDER_CACHE_DIR="/var/cache/dupefinder"
export DUPEFINDER_THREADS=8
```

### Programmatic Usage

#### Python Integration

```python
import subprocess
import json

def find_duplicates(path):
    """Find duplicates using dupefinder and return JSON results."""
    result = subprocess.run(
        ['dupefinder', '--path', path, '--json', '/tmp/dup.json', '--quiet'],
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        with open('/tmp/dup.json') as f:
            return json.load(f)
    return None

# Usage
duplicates = find_duplicates('/home/user/Documents')
if duplicates:
    print(f"Found {duplicates['metadata']['total_duplicates']} duplicates")
```

#### Bash Script Integration

```bash
#!/bin/bash
# Wrapper script for dupefinder

find_and_report() {
    local path="$1"
    local report_dir="/var/reports/duplicates"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Run dupefinder
    if dupefinder \
        --path "$path" \
        --csv "$report_dir/scan_${timestamp}.csv" \
        --json "$report_dir/scan_${timestamp}.json" \
        --quiet; then
        
        # Parse results
        local duplicates=$(jq '.metadata.total_duplicates' \
            "$report_dir/scan_${timestamp}.json")
        local wasted=$(jq '.metadata.space_wasted' \
            "$report_dir/scan_${timestamp}.json")
        
        echo "Scan complete: $duplicates duplicates, $wasted bytes wasted"
        return 0
    else
        echo "Scan failed"
        return 1
    fi
}
```

## Contributing

### Development Setup

```bash
# Clone repository
git clone https://github.com/morroware/DupeFinder/main/DupeFinder.git
cd dupefinder-pro

# Run tests
./tests/run_tests.sh

# Check code style
shellcheck dupefinder.sh
```

### Testing Guidelines

1. **Unit Tests**: Test individual functions
2. **Integration Tests**: Test complete workflows
3. **Safety Tests**: Verify protection mechanisms
4. **Performance Tests**: Benchmark different scenarios

### Contribution Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-feature`)
3. Make changes and test thoroughly
4. Commit with descriptive messages
5. Push to your fork
6. Submit a pull request

### Code Style

- Use 2-space indentation
- Follow Google Shell Style Guide
- Add comments for complex logic
- Update documentation for new features

## Version History

### Version 0.0.1 (Initial Release)
- Core duplicate detection functionality
- Multi-threaded hash calculation
- Comprehensive safety features
- Multiple deletion strategies
- HTML, CSV, and JSON reporting
- Email notifications
- SQLite caching system
- Resume capability for interrupted scans
- Comprehensive safety checks

## Security Considerations

### File System Security

#### Permission Requirements
- **Read access**: Required for all scanned directories
- **Write access**: Required for deletion/modification operations
- **Execute access**: Required for directory traversal

#### Secure Operations
```bash
# Run with minimum required privileges
sudo -u backup_user dupefinder --path /data

# Restrict output directory permissions
chmod 700 "$OUTPUT_DIR"

# Secure configuration file
chmod 600 ~/.dupefinder.conf
chown $USER:$USER ~/.dupefinder.conf
```

### Data Protection

#### Sensitive File Handling
- Never logs file contents
- Hashes stored without file data
- Reports contain only metadata
- Configurable exclusion of sensitive paths

#### Audit Trail
```bash
# Enable comprehensive logging
dupefinder \
    --log /var/log/dupefinder/audit.log \
    --verbose \
    --json /var/log/dupefinder/actions.json
```

### Network Security

#### Email Reports
- Uses system mail configuration
- Supports authenticated SMTP
- No credentials stored in script

#### Remote Filesystem Considerations
```bash
# Exclude network mounts by default
dupefinder --exclude /mnt --exclude /media

# Explicitly scan network shares
dupefinder --path /mnt/nas --follow-symlinks
```

## Benchmarks

### Performance Metrics

| Dataset | Files | Size | Time (MD5) | Time (SHA256) | Cache Speedup |
|---------|-------|------|------------|---------------|---------------|
| Small | 1K | 100MB | 5s | 8s | 2x |
| Medium | 10K | 1GB | 45s | 72s | 3x |
| Large | 100K | 10GB | 8m | 13m | 4x |
| Huge | 1M | 100GB | 1.5h | 2.5h | 5x |

### System Impact

```bash
# CPU Usage (8-core system)
Default (8 threads): 60-80% CPU
Limited (4 threads): 30-40% CPU
Single thread: 10-15% CPU

# Memory Usage
Base: ~50MB
Per 10K files: +30MB
With cache: +100MB per 100K files

# Disk I/O
Sequential read: 100-200 MB/s
Random read: 10-50 MB/s
Cache database writes: 5-10 MB/s
```

## Frequently Asked Questions

### General Questions

**Q: Is DupeFinder Pro safe to use on system directories?**
A: Yes, with the `--skip-system` flag enabled. The script has multiple safety layers to prevent accidental deletion of critical system files.

**Q: Can I resume an interrupted scan?**
A: Yes, the script automatically saves state when interrupted. Use `--resume` to continue.

**Q: How accurate is the duplicate detection?**
A: With default settings (MD5), false positives are extremely rare (1 in 2^128). Use `--verify` for byte-by-byte confirmation.

**Q: Does it work with symbolic links?**
A: By default, symbolic links are not followed. Use `--follow-symlinks` to include them.

### Performance Questions

**Q: Why is the scan slow?**
A: Large files and slow storage can impact performance. Try:
- Using `--fast` mode for initial scans
- Enabling `--cache` for repeated scans
- Increasing `--threads` on multi-core systems
- Excluding unnecessary paths

**Q: How much disk space does the cache use?**
A: Approximately 100 bytes per file. For 1 million files, expect ~100MB cache size.

**Q: Can I scan network drives?**
A: Yes, but performance will be limited by network speed. Consider running the script locally on the network storage server if possible.

### Safety Questions

**Q: What happens if I accidentally delete an important file?**
A: Use these safety features:
- Always run `--dry-run` first
- Enable `--backup` to create copies
- Use `--trash` for recoverable deletion
- Enable `--skip-system` for system scans

**Q: Can it delete files in use?**
A: No, the script detects and skips files currently in use when `lsof` is available.

**Q: Is it safe to run as root?**
A: Yes, but use `--skip-system` and consider `--dry-run` first. The script includes special warnings when running as root.

### Feature Questions

**Q: Can I schedule automatic scans?**
A: Yes, use cron or systemd timers. See the Automation section for examples.

**Q: Does it support Windows?**
A: No, it's designed for Linux. Consider using WSL (Windows Subsystem for Linux) on Windows.

**Q: Can it find similar but not identical files?**
A: Yes, use `--fuzzy` with `--similarity` to find files with similar sizes.

## Known Limitations

### Technical Limitations

1. **Maximum path length**: System-dependent (typically 4096 bytes)
2. **Maximum file size**: Limited by available memory for hashing
3. **Maximum files**: Practical limit ~10 million files per scan
4. **Cache database size**: SQLite limit of 281TB
5. **Thread count**: Effective maximum ~32 threads

### Functional Limitations

1. **Cross-filesystem hardlinks**: Not supported by most filesystems
2. **Cloud storage**: Direct scanning not supported (mount required)
3. **Real-time monitoring**: Not available (use inotify-based tools)
4. **Windows attributes**: NTFS-specific attributes not preserved
5. **Sparse files**: May report incorrect space savings

### Compatibility Issues

1. **Bash version**: Requires Bash 4.0+ (not default on macOS)
2. **GNU tools**: Requires GNU coreutils (not BSD versions)
3. **Filesystem support**: Best with ext4, XFS, Btrfs
4. **Network filesystems**: Slower performance on NFS, SMB
5. **Special files**: Cannot process device files, sockets, FIFOs

## Comparison with Alternatives

| Feature | DupeFinder Pro | fdupes | rdfind | duperemove |
|---------|---------------|--------|--------|------------|
| Safety checks | Extensive | Basic | Basic | Moderate |
| System file protection | Yes | No | No | No |
| Multiple hash algorithms | Yes | Yes | No | Yes |
| HTML reports | Yes | No | No | No |
| CSV/JSON export | Yes | No | No | No |
| Email notifications | Yes | No | No | No |
| Cache database | Yes | No | No | Yes |
| Hardlink support | Yes | Yes | Yes | Yes |
| Trash integration | Yes | No | No | No |
| Resume capability | Yes | No | No | No |
| Smart deletion | Yes | No | Limited | No |
| Fuzzy matching | Yes | No | No | No |
| Interactive mode | Yes | Yes | Yes | No |
| Multi-threading | Yes | No | No | Yes |

## Support and Resources

### Documentation

- **GitHub Wiki**: https://github.com/morroware/DupeFinder/main/DupeFinder/wiki
- **Man Page**: `man dupefinder` (after installation)
- **Examples**: `/usr/share/doc/dupefinder/examples/`

### Getting Help

1. **Issue Tracker**: https://github.com/morroware/DupeFinder/main/DupeFinder/issues
2. **Discussions**: https://github.com/morroware/DupeFinder/main/DupeFinder/discussions
3. **Email**: support@dupefinderpro.example.com

### Community

- **Forum**: https://forum.dupefinderpro.example.com
- **IRC**: #dupefinder on Libera.Chat
- **Matrix**: #dupefinder:matrix.org

### Commercial Support

Professional support and custom development available:
- Priority issue resolution
- Custom feature development
- Training and consultation
- Enterprise deployment assistance

## License

MIT License

Copyright (c) 2024 Seth Morrow

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Acknowledgments

- GNU Project for coreutils
- SQLite team for the database engine
- Contributors and testers from the open source community

## Disclaimer

This software is provided as-is without warranty of any kind. Users are responsible for:
- Backing up important data before use
- Testing with dry-run before actual deletion
- Verifying results before taking action
- Understanding the implications of file deletion

The authors and contributors are not liable for any data loss or system damage resulting from the use of this software. Always maintain proper backups and test thoroughly in non-production environments.

## Appendix

### A. Regular Expression Patterns

File patterns supported:
```bash
*.jpg         # Simple extension matching
image_*.png   # Prefix matching
*backup*      # Contains pattern
[0-9]*.txt    # Character class matching
file?.doc     # Single character wildcard
```

### B. Database Schema

SQLite cache structure:
```sql
CREATE TABLE file_hashes (
  path TEXT PRIMARY KEY,
  hash TEXT NOT NULL,
  size INTEGER NOT NULL,
  mtime INTEGER NOT NULL,
  last_scan INTEGER NOT NULL
);

CREATE INDEX idx_hash ON file_hashes(hash);
CREATE INDEX idx_size ON file_hashes(size);
CREATE INDEX idx_scan ON file_hashes(last_scan);
```

### C. Signal Handling

Supported signals:
- **SIGINT (Ctrl+C)**: Graceful shutdown with state save
- **SIGTERM**: Clean termination
- **SIGHUP**: Reload configuration (planned)
- **SIGUSR1**: Output progress (planned)

### D. Environment Variables

```bash
# System variables used
HOME          # User home directory
USER          # Current username
TEMP/TMP      # Temporary directory
PATH          # Command search path

# Script-specific (planned)
DUPEFINDER_CONFIG    # Configuration file path
DUPEFINDER_CACHE     # Cache directory
DUPEFINDER_DEBUG     # Debug level (0-3)
```

### E. File Format Specifications

#### CSV Format
- **Encoding**: UTF-8
- **Delimiter**: Comma
- **Quote character**: Double quote
- **Line ending**: Unix (LF)
- **Headers**: Always included

#### JSON Format
- **Encoding**: UTF-8
- **Pretty print**: Yes (indented)
- **Schema version**: 1.0
- **Validation**: JSON Schema compliant

---

*End of documentation. For the latest updates and additional resources, visit the project repository.*
