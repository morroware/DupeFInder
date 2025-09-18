# DupeFinder Pro - Advanced Duplicate File Manager for Linux

![DupeFinder Pro Logo](https://github.com/morroware/DupeFinder/logo.png)

**DupeFinder Pro** is a powerful and versatile Bash script for finding and managing duplicate files on Linux systems.
It goes beyond simple `find` and `md5sum` combinations, offering advanced features like multithreaded hashing, smart deletion strategies, caching, and comprehensive reporting.

---

## 🚀 Features

* **Fast & Efficient:** Utilizes multi-threading with `xargs` or `GNU parallel` for rapid hashing.
* **Intelligent Deletion:** Includes options to automatically keep the newest/oldest files, prioritize files in specific paths, or use location-based *smart deletion*.
* **Safe Operations:** Supports dry-runs, moving files to a quarantine directory, or sending them to the trash (`trash-cli`).
* **Comprehensive Reporting:** Generates human-readable **HTML reports**, and machine-readable **CSV** and **JSON** outputs for easy analysis.
* **Persistent Caching:** Uses an **SQLite database** to cache checksums, significantly speeding up subsequent scans of the same directories.
* **Flexible Search:** Filter files by size, name patterns, or directory depth.
* **Robustness:** NUL-delimited file handling prevents issues with filenames containing spaces or special characters.

---

## ⚠️ Safety First: Read Before Use

**DupeFinder Pro is a powerful tool that can permanently delete files.**
Please understand the following before running the script:

* Always use a **`--dry-run` first**.
  This will show you exactly which files would be affected without changing anything on your system.
* Do **not** use `--delete` without a clear understanding of the script’s behavior, especially when combined with deletion strategies like `--keep-newest` or `--smart-delete`.
* Consider using **`--quarantine`** or **`--trash`** to move files instead of permanently deleting them.
  This provides a safety net to restore files if needed.

---

## 📋 Prerequisites

DupeFinder Pro requires a standard Linux environment with the following utilities (most are pre-installed on modern distributions).
The script will warn you if an optional dependency is missing.

* `bash` (version 4.0 or higher)
* `find`, `xargs`, `sort`, `awk`, `cut`, `stat`, `rm`
* **Optional:**

  * `sqlite3` (for caching)
  * `trash-cli` (for trashing)
  * `jq` (for JSON reports)
  * `parallel` (for faster multi-threading)
  * `mail` (for email reports)

---

## 🚀 Getting Started

1. **Clone the repository**

   ```bash
   git clone https://github.com/morroware/DupeFinder.git
   cd DupeFinder
   ```

2. **Make the script executable**

   ```bash
   chmod +x dupefinder.sh
   ```

3. **Run a dry-run (highly recommended)**

   ```bash
   ./dupefinder.sh --path /path/to/search --dry-run
   ```

---

## 📖 Usage

```bash
./dupefinder.sh [OPTIONS]
```

### Basic Options

* `-p, --path PATH` : Search path (default: current directory).
* `-o, --output DIR` : Output directory for reports.
* `-e, --exclude PATH` : Exclude a path from the scan (can be used multiple times).
* `-m, --min-size SIZE` : Minimum file size to consider (e.g., 100K, 5M).
* `-M, --max-size SIZE` : Maximum file size to consider.
* `-h, --help` : Show the help menu.
* `-V, --version` : Display the script version.

### Deletion & Management

* `-d, --delete` : ⚠️ Permanently deletes files. Use with caution.
* `-i, --interactive` : Prompt for each file before deletion.
* `-n, --dry-run` : Show which files would be processed without making any changes.
* `--trash` : Use **trash-cli** to move files to the trash instead of deleting them.
* `--quarantine DIR` : Move duplicate files to a specified directory.
* `--hardlink` : Replace duplicate files with hard links to the original.
* `--keep-newest` : Keep the newest file in each duplicate group.
* `--keep-oldest` : Keep the oldest file in each duplicate group.
* `--keep-path PATH` : Keep the file that resides in the specified path.
* `--smart-delete` : Use built-in location priorities to determine which file to keep
  (e.g., keep files in `/home` over `/tmp`).

### Advanced & Performance

* `--threads N` : Number of threads for hashing (default: number of CPU cores).
* `--cache` : Enable SQLite caching to reuse checksums from previous scans.
* `--save-checksums` : Save all file checksums to the database.
* `--sha256` / `--sha512` : Use a different hashing algorithm.
* `--parallel` : Force the use of GNU parallel if available.

### Reporting

* `-c, --csv FILE` : Generate a CSV report.
* `--json FILE` : Generate a JSON report.
* `--email ADDRESS` : Send a summary report via email.

---

## 💡 Examples

1. **Find duplicates in your home directory (dry-run):**

   ```bash
   ./dupefinder.sh --path ~/ --dry-run
   ```

2. **Delete duplicates in the Downloads folder, keeping the oldest copy:**

   ```bash
   ./dupefinder.sh --path ~/Downloads --delete --keep-oldest
   ```

3. **Quarantine large duplicate photos and generate a report:**

   ```bash
   ./dupefinder.sh --path /media/photos --min-size 10M --pattern "*.jpg" \
   --quarantine ~/dupe_quarantine --output ~/dupe_reports
   ```

4. **Use fast mode with caching to quickly check for duplicates:**

   ```bash
   ./dupefinder.sh --path / --fast --cache
   ```

---
