# DupeFinder 🔍

**Advanced Duplicate File Manager for Linux**

A production-ready, feature-rich duplicate file finder with comprehensive safety checks, intelligent deletion strategies, and robust error handling. Perfect for system administrators and power users who need reliable duplicate file management.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Linux](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)
[![GitHub](https://img.shields.io/badge/GitHub-morroware%2FDupeFinder-blue.svg)](https://github.com/morroware/DupeFinder)

## ✨ Features

### 🛡️ **Safety First**
- **System Protection**: Automatically excludes critical system directories (`/bin`, `/lib`, `/usr`, etc.)
- **Process Awareness**: Detects files in use and prevents deletion of active libraries
- **Dry Run Mode**: Test operations safely without making changes
- **Interactive Mode**: Review and confirm each deletion with file preview
- **Smart Backups**: Optional backup creation before deletion

### 🚀 **Performance**
- **Multi-threaded**: Parallel hash calculation for faster processing
- **Smart Caching**: SQLite-based cache for faster re-scans
- **Memory Monitoring**: Automatic thread adjustment based on available memory
- **Fast Mode**: Quick scanning using size + filename hashes

### 🎯 **Intelligent Deletion**
- **Keep Strategies**: Keep newest, oldest, or files in preferred locations
- **Smart Location Priority**: Automatically prefer files in better locations
- **Hardlink Mode**: Replace duplicates with hardlinks to save space
- **Quarantine**: Move duplicates to quarantine instead of deleting

### 📊 **Comprehensive Reporting**
- **HTML Reports**: Beautiful, interactive web reports
- **CSV Export**: Spreadsheet-compatible data export
- **JSON Output**: Machine-readable structured data
- **Email Reports**: Automatic email delivery of results

### 🔧 **Advanced Options**
- **Multiple Hash Algorithms**: MD5, SHA256, SHA512
- **Fuzzy Matching**: Find similar files using ssdeep
- **Symlink Support**: Follow or ignore symbolic links
- **Pattern Matching**: Include/exclude files by glob patterns
- **Resume Support**: Continue interrupted scans

## 📥 Installation

### Quick Install
```bash
# Download the script
curl -O https://raw.githubusercontent.com/morroware/DupeFinder/main/dupefinder.sh
chmod +x dupefinder.sh

# Basic dependencies (usually pre-installed)
sudo apt update
sudo apt install sqlite3 lsof
```

### Clone Repository
```bash
# Clone the full repository
git clone https://github.com/morroware/DupeFinder.git
cd DupeFinder
chmod +x dupefinder.sh
```

### Full Feature Installation
```bash
# Install all optional dependencies for complete functionality
sudo apt install sqlite3 lsof bc trash-cli jq ssdeep mailutils gawk
```

### Dependencies
| Component | Package | Required | Purpose |
|-----------|---------|----------|---------|
| Core tools | `coreutils findutils` | ✅ Yes | Basic file operations |
| SQLite | `sqlite3` | ⭐ Recommended | File caching |
| Process monitor | `lsof` | ⭐ Recommended | Safety checks |
| Trash support | `trash-cli` | ❌ Optional | Safe deletion |
| JSON processing | `jq` | ❌ Optional | Enhanced reports |
| Fuzzy matching | `ssdeep` | ❌ Optional | Similar file detection |
| Email reports | `mailutils` | ❌ Optional | Report delivery |

## 🚀 Quick Start

### Basic Usage
```bash
# Safe scan of Downloads folder
./dupefinder.sh --path ~/Downloads --dry-run --verbose

# Interactive cleanup with system protection
./dupefinder.sh --path ~/Documents --skip-system --interactive

# Fast scan of Pictures folder
./dupefinder.sh --path ~/Pictures --fast --min-size 1M
```

### System-Wide Scan (Advanced)
```bash
# Safe system-wide duplicate detection
./dupefinder.sh --path / --skip-system --dry-run --min-size 10M
```

## 📚 Usage Examples

### 🏠 **Home Directory Cleanup**
```bash
# Clean up Downloads with interactive confirmation
./dupefinder.sh \
  --path ~/Downloads \
  --min-size 1M \
  --interactive \
  --trash \
  --verbose
```

### 📸 **Photo Management**
```bash
# Find duplicate photos, keep newest
./dupefinder.sh \
  --path ~/Pictures \
  --pattern "*.jpg" --pattern "*.png" --pattern "*.jpeg" \
  --keep-newest \
  --delete \
  --backup ~/photo_backups \
  --csv photo_duplicates.csv
```

### 💾 **Storage Optimization**
```bash
# Replace duplicates with hardlinks to save space
./dupefinder.sh \
  --path ~/Documents \
  --min-size 100K \
  --hardlink \
  --verbose
```

### 🔍 **Similar File Detection**
```bash
# Find similar files using fuzzy matching
./dupefinder.sh \
  --path ~/Music \
  --fuzzy \
  --threshold 90 \
  --quarantine ~/similar_files
```

### 🏢 **Enterprise Scanning**
```bash
# High-performance scan with full reporting
./dupefinder.sh \
  --path /data/shared \
  --threads 8 \
  --cache \
  --sha256 \
  --csv report.csv \
  --json report.json \
  --email admin@company.com \
  --log /var/log/dupefinder.log
```

## ⚙️ Command Reference

### Basic Options
| Option | Description |
|--------|-------------|
| `-p, --path PATH` | Search directory (default: current) |
| `-o, --output DIR` | Output directory for reports |
| `-h, --help` | Show help message |
| `-V, --version` | Show version information |

### Search Filters
| Option | Description |
|--------|-------------|
| `-m, --min-size SIZE` | Minimum file size (e.g., 1M, 500K) |
| `-M, --max-size SIZE` | Maximum file size |
| `-t, --pattern GLOB` | File pattern (e.g., "*.mp3") |
| `-e, --exclude PATH` | Exclude directory |
| `-l, --level DEPTH` | Maximum directory depth |
| `-z, --empty` | Include empty files |
| `-a, --all` | Include hidden files |
| `-f, --follow-symlinks` | Follow symbolic links |

### Safety Options
| Option | Description |
|--------|-------------|
| `--skip-system` | Skip system directories (recommended) |
| `--force-system` | Allow system file deletion (dangerous!) |
| `-n, --dry-run` | Preview actions without execution |
| `-i, --interactive` | Confirm each deletion |
| `--verify` | Byte-by-byte verification |

### Deletion Modes
| Option | Description |
|--------|-------------|
| `-d, --delete` | Delete duplicate files |
| `--hardlink` | Replace with hardlinks |
| `--trash` | Move to trash (requires trash-cli) |
| `--quarantine DIR` | Move to quarantine directory |

### Keep Strategies
| Option | Description |
|--------|-------------|
| `-k, --keep-newest` | Keep the newest file |
| `-K, --keep-oldest` | Keep the oldest file |
| `--keep-path PATH` | Prefer files in specific path |
| `--smart-delete` | Use intelligent location priorities |

### Performance
| Option | Description |
|--------|-------------|
| `--threads N` | Number of processing threads |
| `--fast` | Fast mode (size + name hash) |
| `--cache` | Use SQLite cache for re-scans |

### Hash Algorithms
| Option | Description |
|--------|-------------|
| `-s, --sha256` | Use SHA256 hashing |
| `--sha512` | Use SHA512 hashing |
| Default | MD5 hashing (fastest) |

### Reports
| Option | Description |
|--------|-------------|
| `-c, --csv FILE` | Generate CSV report |
| `--json FILE` | Generate JSON report |
| `--email EMAIL` | Email HTML report |
| `--log FILE` | Log file location |
| `-v, --verbose` | Detailed output |
| `-q, --quiet` | Minimal output |

### Advanced
| Option | Description |
|--------|-------------|
| `--fuzzy` | Fuzzy matching (requires ssdeep) |
| `--threshold PCT` | Similarity threshold (default: 95) |
| `--backup DIR` | Backup before deletion |
| `--resume` | Resume interrupted scan |
| `--config FILE` | Load configuration file |

## 🛡️ Safety Features

### Automatic Protection
- **Critical System Files**: Never deletes essential system binaries or libraries
- **Files in Use**: Detects and skips files currently being used by processes
- **Permission Checks**: Respects file ownership and permissions
- **Cross-Filesystem**: Prevents hardlinks across different filesystems

### Built-in Safeguards
- **Root Protection**: Non-root users cannot delete root-owned files
- **Shared Library Detection**: Checks if libraries are loaded in memory
- **Interactive Confirmation**: Manual approval for critical operations
- **Backup Creation**: Optional file backup before deletion

## 📊 Report Examples

### HTML Report Features
- 📈 **Visual Statistics**: Files scanned, duplicates found, space wasted
- 🗂️ **Expandable Groups**: Click to view all files in each duplicate group
- ⚠️ **Safety Indicators**: System files clearly marked
- 📱 **Responsive Design**: Works on desktop and mobile
- 🎨 **Modern UI**: Clean, professional appearance

### CSV Report Columns
- Hash, File Path, Size (bytes), Size (human), Group ID, System File

### JSON Structure
```json
{
  "metadata": {
    "version": "1.2.4",
    "generated": "2024-01-15T10:30:00Z",
    "total_files": 15420,
    "total_duplicates": 1205,
    "space_wasted": 2847362048
  },
  "groups": [...]
}
```

## ⚠️ Important Safety Notes

1. **Always use `--dry-run` first** to preview actions
2. **Enable `--skip-system`** for system-wide scans
3. **Test with small directories** before large scans
4. **Use `--backup`** for important files
5. **Never run as root** unless absolutely necessary

## 🐛 Troubleshooting

### Common Issues

**"GNU awk required" error:**
```bash
sudo apt install gawk
```

**Permission denied errors:**
```bash
# Check file ownership and permissions
ls -la problematic_file
```

**Out of memory during large scans:**
```bash
# Reduce thread count
./dupefinder.sh --path /large/directory --threads 2
```

**Hash calculation timeout:**
```bash
# Use fast mode for large files
./dupefinder.sh --path /directory --fast
```

### Getting Help
- Check log files for detailed error information
- Use `--verbose` mode for debugging
- Reduce scope with `--max-depth` or file patterns
- Test with `--dry-run` to identify issues safely

## 🔧 Configuration File

Create `~/.dupefinder.conf` for default settings:

```bash
# Default configuration
SEARCH_PATH="/home/user/Documents"
OUTPUT_DIR="/home/user/duplicate_reports"
SKIP_SYSTEM_FOLDERS=1
VERBOSE=1
MIN_SIZE=1048576
THREADS=4
USE_CACHE=1
```

## 🚀 Performance Tips

1. **Use SSD storage** for better I/O performance
2. **Enable caching** (`--cache`) for repeated scans
3. **Adjust thread count** based on CPU cores and available memory
4. **Use fast mode** (`--fast`) for initial scans
5. **Filter by size** (`--min-size`) to skip small files
6. **Exclude unnecessary directories** (`--exclude`)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests or create issues for bugs and feature requests.

### Development Setup
```bash
git clone https://github.com/morroware/DupeFinder.git
cd DupeFinder
chmod +x dupefinder.sh
```

### Testing
```bash
# Create test directory with duplicates
mkdir -p test/dir1 test/dir2
echo "duplicate content" > test/dir1/file1.txt
echo "duplicate content" > test/dir2/file1.txt

# Test the script
./dupefinder.sh --path test --dry-run --verbose
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.



*DupeFinder v1.2.4 - Advanced Duplicate File Manager*
