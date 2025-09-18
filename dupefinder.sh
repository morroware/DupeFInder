#!/usr/bin/env bash
#############################################################################
# DupeFinder Pro - Advanced Duplicate File Manager for Linux
# Version: 3.3.0
# Author: Seth Morrow
# License: MIT
#
# Description:
#   Professional duplicate file finder with advanced management, reporting,
#   caching, and smart deletion strategies. This is a monolithic, pasteable
#   script containing ALL features with improvements discussed.
#
# CHANGES IN v3.3.0:
#   - Fixed cleanup() SCAN_END_TIME guard (prevents unbound variable error).
#   - Hardened load_state() with file permission/ownership validation before source.
#   - Improved sql_escape() to handle quotes and backslashes safely.
#   - Batched SQLite writes; one transaction per run for performance.
#   - Progress bar avoids tight wc -l polling; uses a counter file increment.
#   - Clearer warnings when excluding /mnt and /media.
#   - Safer filename handling (NUL-delimited lists; consistent quoting).
#   - Minor robustness fixes across deletion, reporting, and argument parsing.
#############################################################################

# -------------------------------
# Terminal Colors & Formatting
# -------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

# -------------------------------
# Default Configuration
# -------------------------------
VERSION="3.3.0"
AUTHOR="Seth Morrow"
SEARCH_PATH="$(pwd)"
EXCLUDE_PATHS=("/proc" "/sys" "/dev" "/run" "/tmp" "/var/run" "/var/lock" "/mnt" "/media")
MIN_SIZE=1
MAX_SIZE=""
OUTPUT_DIR="$HOME/duplicate_reports"
HTML_REPORT="duplicates_$(date +%Y%m%d_%H%M%S).html"
CSV_REPORT=""
JSON_REPORT=""
DELETE_MODE=0
DRY_RUN=0
VERBOSE=0
QUIET=0
FOLLOW_SYMLINKS=0
EMPTY_FILES=0
HIDDEN_FILES=0
MAX_DEPTH=""
FILE_PATTERN=()
HASH_ALGORITHM="md5sum"
INTERACTIVE_DELETE=0
KEEP_NEWEST=0
KEEP_OLDEST=0
KEEP_PATH_PRIORITY=""
PROGRESS_BAR=1
TEMP_DIR=""
BACKUP_DIR=""
USE_TRASH=0
HARDLINK_MODE=0
QUARANTINE_DIR=""
DB_CACHE="$HOME/.dupefinder_cache.db"
USE_CACHE=0
THREADS=$(nproc)
EMAIL_REPORT=""
CONFIG_FILE=""
FUZZY_MATCH=0
SIMILARITY_THRESHOLD=95
AUTO_SELECT_LOCATION=""
SAVE_CHECKSUMS=0
CHECKSUM_DB="$HOME/.dupefinder_checksums.db"
EXCLUDE_LIST_FILE=""
FAST_MODE=0
SMART_DELETE=0
LOG_FILE=""
VERIFY_MODE=0
USE_PARALLEL=0
RESUME_STATE=""

# -------------------------------
# Statistics Counters
# -------------------------------
TOTAL_FILES=0
TOTAL_DUPLICATES=0
TOTAL_DUPLICATE_GROUPS=0
TOTAL_SPACE_WASTED=0
FILES_DELETED=0
SPACE_FREED=0
SCAN_START_TIME=""
SCAN_END_TIME=""
DUPLICATE_GROUPS=""

# -------------------------------
# Smart location priorities (lower = preferred keep)
# -------------------------------
declare -A LOCATION_PRIORITY=(
  ["/home"]=1
  ["/usr/local"]=2
  ["/opt"]=3
  ["/var"]=4
  ["/tmp"]=99
  ["/downloads"]=90
  ["/cache"]=95
)

# -------------------------------
# Cleanup and Signal Handling
# -------------------------------
cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
  [[ -n "$LOG_FILE" ]] && echo "$(date): Session ended" >> "$LOG_FILE"
  # Only remove resume state if a scan actually completed (guard var first)
  if [[ -n "$SCAN_END_TIME" && "$SCAN_END_TIME" -gt 0 ]]; then
    rm -f "$HOME/.dupefinder_state"
  fi
}

handle_interrupt() {
  echo -e "\n${YELLOW}Interrupted!${NC}"
  if [[ $TOTAL_FILES -gt 0 ]]; then
    echo "Processed files before interruption."
    echo -n "Save state for resume? (y/n): "
    read -r response
    if [[ "$response" == "y" ]]; then
      save_state
      echo -e "${GREEN}State saved. Run script again to resume.${NC}"
    fi
  fi
  cleanup
  exit 130
}

trap handle_interrupt INT TERM
trap cleanup EXIT

# Create temp directory early
TEMP_DIR="/tmp/dupefinder_$$"
mkdir -p "$TEMP_DIR"

# -------------------------------
# Header / Help
# -------------------------------
show_header() {
  clear
  echo -e "${CYAN}"
  cat << "EOF"
    ____                   _____ _           _           ____            
   |  _ \ _   _ _ __   ___|  ___(_)_ __   __| | ___ _ __|  _ \ _ __ ___  
   | | | | | | | '_ \ / _ \ |_  | | '_ \ / _` |/ _ \ '__| |_) | '__/ _ \ 
   | |_| | |_| | |_) |  __/  _| | | | | | (_| |  __/ |  |  __/| | | (_) |
   |____/ \__,_| .__/ \___|_|   |_|_| |_|\__,_|\___|_|  |_|   |_|  \___/ 
               |_|                                                        
EOF
  echo -e "${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}        Advanced Duplicate File Manager v${VERSION}${NC}"
  echo -e "${DIM}                by ${AUTHOR}${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

show_help() {
  show_header
  cat << EOF
${BOLD}USAGE:${NC}
    $0 [OPTIONS]

${BOLD}BASIC OPTIONS:${NC}
    ${GREEN}-p, --path PATH${NC}          Search path (default: current directory)
    ${GREEN}-o, --output DIR${NC}         Output directory for reports
    ${GREEN}-e, --exclude PATH${NC}       Exclude path (can be used multiple times)
    ${GREEN}-m, --min-size SIZE${NC}      Min size (e.g., 100, 10K, 5M, 1G)
    ${GREEN}-M, --max-size SIZE${NC}      Max size (e.g., 100, 10K, 5M, 1G)
    ${GREEN}-h, --help${NC}               Show this help
    ${GREEN}-V, --version${NC}            Show version

${BOLD}SEARCH:${NC}
    ${GREEN}-f, --follow-symlinks${NC}    Follow symlinks
    ${GREEN}-z, --empty${NC}              Include empty files
    ${GREEN}-a, --all${NC}                Include hidden files
    ${GREEN}-l, --level DEPTH${NC}        Max directory depth
    ${GREEN}-t, --pattern GLOB${NC}       File pattern (e.g., "*.jpg")
    ${GREEN}--fast${NC}                   Fast mode (size+name hash)
    ${GREEN}--fuzzy${NC}                  Fuzzy match by size similarity
    ${GREEN}--similarity PCT${NC}         Fuzzy threshold (1-100, default 95)
    ${GREEN}--verify${NC}                 Byte-by-byte verification before deletion

${BOLD}DELETION:${NC}
    ${GREEN}-d, --delete${NC}             Delete duplicates
    ${GREEN}-i, --interactive${NC}        Prompt for each duplicate
    ${GREEN}-n, --dry-run${NC}            Show actions only
    ${GREEN}--trash${NC}                  Use trash (trash-cli) if available
    ${GREEN}--hardlink${NC}               Replace dupes with hardlinks
    ${GREEN}--quarantine DIR${NC}         Move dupes to quarantine

${BOLD}KEEP STRATEGIES:${NC}
    ${GREEN}-k, --keep-newest${NC}        Prefer newest
    ${GREEN}-K, --keep-oldest${NC}        Prefer oldest
    ${GREEN}--keep-path PATH${NC}         Prefer PATH
    ${GREEN}--smart-delete${NC}           Location-based priorities
    ${GREEN}--auto-select LOC${NC}        Auto-select by location priority

${BOLD}PERFORMANCE:${NC}
    ${GREEN}--threads N${NC}              Threads for hashing
    ${GREEN}--cache${NC}                  Use SQLite cache DB
    ${GREEN}--save-checksums${NC}         Save checksums to DB
    ${GREEN}--no-progress${NC}            Disable progress bar
    ${GREEN}--parallel${NC}               Use GNU parallel if available

${BOLD}REPORTING:${NC}
    ${GREEN}-c, --csv FILE${NC}           CSV report filename
    ${GREEN}--json FILE${NC}              JSON report filename
    ${GREEN}--email ADDRESS${NC}          Email a summary
    ${GREEN}--log FILE${NC}               Log file path
    ${GREEN}-v, --verbose${NC}            Verbose logs
    ${GREEN}-q, --quiet${NC}              Quiet mode

${BOLD}ADVANCED:${NC}
    ${GREEN}-s, --sha256${NC}             Use SHA256
    ${GREEN}--sha512${NC}                 Use SHA512
    ${GREEN}--backup DIR${NC}             Backup before deletion
    ${GREEN}--config FILE${NC}            Load config
    ${GREEN}--exclude-list FILE${NC}      Extra excludes (one per line)
    ${GREEN}--db-path FILE${NC}           Custom DB path
    ${GREEN}--resume${NC}                 Resume previous scan

EOF
}

# -------------------------------
# Utility: size parsing
# -------------------------------
parse_size() {
  local s="$1"
  if [[ "$s" =~ ^([0-9]+)([KMG]?)B?$ ]]; then
    local n="${BASH_REMATCH[1]}"; local u="${BASH_REMATCH[2]}"
    case "$u" in
      K) echo $((n*1024));;
      M) echo $((n*1024*1024));;
      G) echo $((n*1024*1024*1024));;
      *) echo "$n";;
    esac
  else
    echo "$s"
  fi
}

# -------------------------------
# State save/load (secured)
# -------------------------------
save_state() {
  cat > "$HOME/.dupefinder_state" << EOF
SEARCH_PATH="$SEARCH_PATH"
OUTPUT_DIR="$OUTPUT_DIR"
HASH_ALGORITHM="$HASH_ALGORITHM"
TEMP_DIR="$TEMP_DIR"
SCAN_START_TIME="$SCAN_START_TIME"
EOF
  chmod 600 "$HOME/.dupefinder_state"
  [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}State saved to ~/.dupefinder_state${NC}"
}

load_state() {
  if [[ -f "$HOME/.dupefinder_state" ]]; then
    local owner perm
    owner=$(stat -c "%U" "$HOME/.dupefinder_state" 2>/dev/null)
    perm=$(stat -c "%a" "$HOME/.dupefinder_state" 2>/dev/null)
    if [[ "$owner" != "$USER" || "$perm" -gt 600 ]]; then
      echo -e "${RED}Unsafe resume file permissions/ownership; ignoring.${NC}"
      return 1
    fi
    # shellcheck disable=SC1090
    source "$HOME/.dupefinder_state"
    echo -e "${CYAN}Resuming previous scan...${NC}"
    return 0
  fi
  return 1
}

# -------------------------------
# SQLite escaping
# -------------------------------
sql_escape() {
  # Escape single quotes and backslashes. Keep other bytes intact.
  echo "$1" | sed "s/'/''/g; s/\\/\\\\/g"
}

# -------------------------------
# Load external config
# -------------------------------
load_config() {
  if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    echo -e "${CYAN}Loading configuration from $CONFIG_FILE...${NC}"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
}

# -------------------------------
# Parse CLI arguments
# -------------------------------
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -p|--path) SEARCH_PATH="$2"; shift 2 ;;
      -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
      -e|--exclude) EXCLUDE_PATHS+=("$2"); shift 2 ;;
      -m|--min-size) MIN_SIZE=$(parse_size "$2"); shift 2 ;;
      -M|--max-size) MAX_SIZE=$(parse_size "$2"); shift 2 ;;
      -d|--delete) DELETE_MODE=1; shift ;;
      -i|--interactive) INTERACTIVE_DELETE=1; DELETE_MODE=1; shift ;;
      -n|--dry-run) DRY_RUN=1; shift ;;
      -v|--verbose) VERBOSE=1; shift ;;
      -q|--quiet) QUIET=1; PROGRESS_BAR=0; shift ;;
      -f|--follow-symlinks) FOLLOW_SYMLINKS=1; shift ;;
      -z|--empty) EMPTY_FILES=1; MIN_SIZE=0; shift ;;
      -a|--all) HIDDEN_FILES=1; shift ;;
      -l|--level) MAX_DEPTH="$2"; shift 2 ;;
      -t|--pattern) FILE_PATTERN+=("$2"); shift 2 ;;
      -c|--csv) CSV_REPORT="$2"; shift 2 ;;
      -s|--sha256) HASH_ALGORITHM="sha256sum"; shift ;;
      --sha512) HASH_ALGORITHM="sha512sum"; shift ;;
      -k|--keep-newest) KEEP_NEWEST=1; shift ;;
      -K|--keep-oldest) KEEP_OLDEST=1; shift ;;
      --keep-path) KEEP_PATH_PRIORITY="$2"; shift 2 ;;
      --smart-delete) SMART_DELETE=1; shift ;;
      --auto-select) AUTO_SELECT_LOCATION="$2"; shift 2 ;;
      --trash) USE_TRASH=1; shift ;;
      --hardlink) HARDLINK_MODE=1; shift ;;
      --quarantine) QUARANTINE_DIR="$2"; shift 2 ;;
      --backup) BACKUP_DIR="$2"; shift 2 ;;
      --threads) THREADS="$2"; shift 2 ;;
      --cache) USE_CACHE=1; shift ;;
      --save-checksums) SAVE_CHECKSUMS=1; shift ;;
      --json) JSON_REPORT="$2"; shift 2 ;;
      --email) EMAIL_REPORT="$2"; shift 2 ;;
      --log) LOG_FILE="$2"; shift 2 ;;
      --config) CONFIG_FILE="$2"; shift 2 ;;
      --exclude-list) EXCLUDE_LIST_FILE="$2"; shift 2 ;;
      --db-path) DB_CACHE="$2"; CHECKSUM_DB="${2%.db}_checksums.db"; shift 2 ;;
      --fast) FAST_MODE=1; shift ;;
      --fuzzy) FUZZY_MATCH=1; shift ;;
      --similarity) SIMILARITY_THRESHOLD="$2"; shift 2 ;;
      --verify) VERIFY_MODE=1; shift ;;
      --parallel) USE_PARALLEL=1; shift ;;
      --resume) RESUME_STATE=1; shift ;;
      --no-progress) PROGRESS_BAR=0; shift ;;
      -h|--help) show_help; exit 0 ;;
      -V|--version) echo "DupeFinder Pro v$VERSION by $AUTHOR"; exit 0 ;;
      *) echo -e "${RED}Unknown option: $1${NC}"; show_help; exit 1 ;;
    esac
  done
}

# -------------------------------
# Logging & Dependencies
# -------------------------------
init_logging() {
  if [[ -n "$LOG_FILE" ]]; then
    echo "$(date): DupeFinder Pro v$VERSION started by $USER" >> "$LOG_FILE"
    echo "$(date): Search path: $SEARCH_PATH" >> "$LOG_FILE"
  fi
}

check_dependencies() {
  if [[ $USE_CACHE -eq 1 || $SAVE_CHECKSUMS -eq 1 ]]; then
    if ! command -v sqlite3 &>/dev/null; then
      echo -e "${RED}Error: sqlite3 is not installed. Cache/checksum disabled.${NC}"
      echo -e "${YELLOW}Install with: sudo apt install sqlite3${NC}"
      USE_CACHE=0; SAVE_CHECKSUMS=0
    fi
  fi
  if [[ $USE_TRASH -eq 1 ]] && ! command -v trash-put &>/dev/null; then
    echo -e "${YELLOW}Warning: trash-cli not installed. Falling back to rm.${NC}"
    USE_TRASH=0
  fi
  if [[ $USE_PARALLEL -eq 1 ]] && ! command -v parallel &>/dev/null; then
    echo -e "${YELLOW}Warning: GNU parallel not installed. Using xargs.${NC}"
    USE_PARALLEL=0
  fi
  if [[ -n "$EMAIL_REPORT" ]] && ! command -v mail &>/dev/null; then
    echo -e "${YELLOW}Warning: 'mail' command not found. Email disabled.${NC}"
    EMAIL_REPORT=""
  fi
  if [[ -n "$JSON_REPORT" ]] && ! command -v jq &>/dev/null; then
    echo -e "${RED}Error: jq is not installed. JSON report disabled.${NC}"
    echo -e "${YELLOW}Install with: sudo apt install jq${NC}"
    JSON_REPORT=""
  fi
}

# -------------------------------
# Validation
# -------------------------------
validate_inputs() {
  if [[ $RESUME_STATE -eq 1 ]] && load_state; then
    echo -e "${GREEN}Resuming previous scan${NC}"
  fi
  if [[ ! -d "$SEARCH_PATH" ]]; then
    echo -e "${RED}Error: Search path does not exist: $SEARCH_PATH${NC}"
    exit 1
  fi
  mkdir -p "$OUTPUT_DIR" || { echo -e "${RED}Cannot create output dir: $OUTPUT_DIR${NC}"; exit 1; }
  if [[ ! -w "$OUTPUT_DIR" ]]; then
    echo -e "${RED}Error: Cannot write to output directory: $OUTPUT_DIR${NC}"
    exit 1
  fi
  if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || [[ "$THREADS" -lt 1 ]]; then
    THREADS=$(nproc)
    [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}Invalid thread count, using $THREADS threads${NC}"
  fi
  if [[ $KEEP_NEWEST -eq 1 && $KEEP_OLDEST -eq 1 ]]; then
    echo -e "${RED}Error: Cannot use both --keep-newest and --keep-oldest${NC}"
    exit 1
  fi
  if [[ -n "$QUARANTINE_DIR" ]]; then
    mkdir -p "$QUARANTINE_DIR" || { echo -e "${RED}Cannot create quarantine dir${NC}"; exit 1; }
    [[ ! -w "$QUARANTINE_DIR" ]] && { echo -e "${RED}Quarantine dir not writable${NC}"; exit 1; }
  fi
  if [[ -n "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR" || { echo -e "${RED}Cannot create backup dir${NC}"; exit 1; }
    [[ ! -w "$BACKUP_DIR" ]] && { echo -e "${RED}Backup dir not writable${NC}"; exit 1; }
  fi
  if [[ -n "$EXCLUDE_LIST_FILE" && -f "$EXCLUDE_LIST_FILE" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" && ! "$line" =~ ^# ]] && EXCLUDE_PATHS+=("$line")
    done < "$EXCLUDE_LIST_FILE"
  fi
  # Friendly note on external media excludes
  if printf '%s\n' "${EXCLUDE_PATHS[@]}" | grep -qE '^/mnt$|^/media$'; then
    echo -e "${YELLOW}Note:${NC} /mnt and /media are excluded by default. Remove from --exclude to scan external drives."
  fi
}

# -------------------------------
# Cache DB init/cleanup (batched)
# -------------------------------
init_cache() {
  if [[ $USE_CACHE -eq 1 || $SAVE_CHECKSUMS -eq 1 ]]; then
    [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Initializing cache DB...${NC}"
    sqlite3 "$DB_CACHE" << 'EOF'
CREATE TABLE IF NOT EXISTS file_hashes (
  path TEXT PRIMARY KEY,
  hash TEXT NOT NULL,
  size INTEGER NOT NULL,
  mtime INTEGER NOT NULL,
  last_scan INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_hash ON file_hashes(hash);
CREATE INDEX IF NOT EXISTS idx_size ON file_hashes(size);
EOF
    local cutoff=$(($(date +%s) - 2592000))
    sqlite3 "$DB_CACHE" "DELETE FROM file_hashes WHERE last_scan < $cutoff;" >/dev/null 2>&1
    : > "$TEMP_DIR/sql_buffer.sql"
  fi
}

flush_cache_batch() {
  if [[ $USE_CACHE -eq 1 || $SAVE_CHECKSUMS -eq 1 ]]; then
    if [[ -s "$TEMP_DIR/sql_buffer.sql" ]]; then
      [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Flushing batched SQLite writes...${NC}"
      printf 'BEGIN IMMEDIATE;\n' > "$TEMP_DIR/sql_txn.sql"
      cat "$TEMP_DIR/sql_buffer.sql" >> "$TEMP_DIR/sql_txn.sql"
      printf 'COMMIT;\n' >> "$TEMP_DIR/sql_txn.sql"
      sqlite3 "$DB_CACHE" < "$TEMP_DIR/sql_txn.sql" >/dev/null 2>&1
      : > "$TEMP_DIR/sql_buffer.sql"
    fi
  fi
}

# -------------------------------
# File discovery (find)
# -------------------------------
find_files() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}🔍 Scanning filesystem...${NC}"
  local find_cmd="find"
  local args=("$SEARCH_PATH")
  [[ -n "$MAX_DEPTH" ]] && args+=(-maxdepth "$MAX_DEPTH")
  # Properly grouped excludes; prune them, then -type f on the rest
  if [[ ${#EXCLUDE_PATHS[@]} -gt 0 ]]; then
    args+=(\()
    local first=1
    for ex in "${EXCLUDE_PATHS[@]}"; do
      if [[ $first -eq 1 ]]; then
        args+=(-path "$ex" -prune)
        first=0
      else
        args+=(-o -path "$ex" -prune)
      fi
    done
    args+=(\) -o)
  fi
  args+=(-type f)
  [[ $HIDDEN_FILES -eq 0 ]] && args+=(-not -path '*/.*')
  [[ $FOLLOW_SYMLINKS -eq 0 ]] && args+=(-not -type l)
  [[ $MIN_SIZE -gt 0 ]] && args+=(-size "+${MIN_SIZE}c")
  [[ -n "$MAX_SIZE" ]] && args+=(-size "-${MAX_SIZE}c")
  if [[ ${#FILE_PATTERN[@]} -gt 0 ]]; then
    args+=(\()
    local firstp=1
    for pat in "${FILE_PATTERN[@]}"; do
      if [[ $firstp -eq 1 ]]; then
        args+=(-name "$pat")
        firstp=0
      else
        args+=(-o -name "$pat")
      fi
    done
    args+=(\))
  fi
  args+=(-print0)
  [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Find command:${NC} $find_cmd ${args[*]}"
  "$find_cmd" "${args[@]}" 2>/dev/null > "$TEMP_DIR/files.list"
}

# -------------------------------
# Hash worker (exported for xargs/parallel)
# Notes:
#   - Uses fast mode if requested (size+name md5 fragment).
#   - Updates batch SQL file for cache; flushed later in one transaction.
# -------------------------------
hash_worker() {
  local file="$1" algo="$2" fast="$3" use_cache="$4" db="$5" save_checksums="$6"
  [[ ! -r "$file" ]] && return 0
  local mtime size hash
  mtime=$(stat -c%Y "$file" 2>/dev/null) || mtime=0
  size=$(stat -c%s "$file" 2>/dev/null) || size=0

  if [[ "$fast" == "1" ]]; then
    local name_hash
    name_hash=$(basename "$file" | md5sum | cut -d' ' -f1)
    hash="${size}_${name_hash:0:16}"
  else
    hash=$($algo "$file" 2>/dev/null | cut -d' ' -f1)
  fi
  [[ -z "$hash" ]] && return 0

  printf '%s|%s|%s\n' "$hash" "$size" "$file"

  if [[ "$use_cache" == "1" || "$save_checksums" == "1" ]]; then
    local esc
    esc=$(sql_escape "$file")
    printf "INSERT OR REPLACE INTO file_hashes VALUES ('%s','%s',%s,%s,%s);\n" \
      "$esc" "$hash" "$size" "$mtime" "$(date +%s)" >> "$TEMP_DIR/sql_buffer.sql"
  fi
}
export -f hash_worker
export HASH_ALGORITHM FAST_MODE USE_CACHE DB_CACHE SAVE_CHECKSUMS

# -------------------------------
# Progress (counter file to avoid polling output file)
# -------------------------------
show_progress() {
  local current=$1 total=$2
  [[ $PROGRESS_BAR -eq 0 || $QUIET -eq 1 ]] && return
  local width=50
  (( total == 0 )) && return
  local pct=$(( current * 100 / total ))
  (( pct > 100 )) && pct=100
  local filled=$(( pct * width / 100 ))
  printf "\r${CYAN}Progress: [${NC}"
  printf "%${filled}s" | tr ' ' '█'
  printf "%$((width - filled))s" | tr ' ' '░'
  printf "${CYAN}] %3d%% (%d/%d)${NC}" $pct $current $total
}

# -------------------------------
# Hashing driver (parallel/xargs)
# -------------------------------
calculate_hashes() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📊 Calculating file hashes (threads: $THREADS)...${NC}"
  local total
  total=$(tr -cd '\0' < "$TEMP_DIR/files.list" | wc -c)
  TOTAL_FILES=$total
  : > "$TEMP_DIR/hashes.txt"
  : > "$TEMP_DIR/prog.count"

  if [[ $total -eq 0 ]]; then
    [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}No files matched criteria.${NC}"
    return
  fi

  if [[ $USE_PARALLEL -eq 1 ]]; then
    # GNU parallel; each job appends a line to prog.count for cheap progress
    < "$TEMP_DIR/files.list" parallel -0 -j "$THREADS" --no-notice --linebuffer \
      "hash_worker {} '$HASH_ALGORITHM' '$FAST_MODE' '$USE_CACHE' '$DB_CACHE' '$SAVE_CHECKSUMS' | tee -a '$TEMP_DIR/hashes.txt' >/dev/null; echo 1 >> '$TEMP_DIR/prog.count'" &
  else
    # xargs parallelization
    < "$TEMP_DIR/files.list" xargs -0 -P "$THREADS" -I {} bash -c \
      'hash_worker "$1" "$2" "$3" "$4" "$5" "$6" | tee -a "$7" >/dev/null; echo 1 >> "$8"' _ \
      {} "$HASH_ALGORITHM" "$FAST_MODE" "$USE_CACHE" "$DB_CACHE" "$SAVE_CHECKSUMS" \
      "$TEMP_DIR/hashes.txt" "$TEMP_DIR/prog.count" &
  fi

  local pid=$!
  while kill -0 $pid 2>/dev/null; do
    local processed
    processed=$(wc -l < "$TEMP_DIR/prog.count" 2>/dev/null || echo 0)
    show_progress "$processed" "$total"
    sleep 0.3
  done
  wait $pid

  # Final progress flush
  show_progress "$total" "$total"
  [[ $PROGRESS_BAR -eq 1 && $QUIET -eq 0 ]] && echo ""

  # Flush cache writes in a single SQL transaction
  flush_cache_batch
}

# -------------------------------
# Duplicate detection (exact)
# -------------------------------
find_duplicates() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}🔎 Analyzing duplicates...${NC}"
  sort -t'|' -k1,1 "$TEMP_DIR/hashes.txt" > "$TEMP_DIR/sorted_hashes.txt"

  awk -F'|' '
  {
    hash=$1; size=$2; file=$3
    if (hash == prev_hash) {
      if (!(hash in groups)) {
        groups[hash] = prev_file "|" prev_size
        gcount++
      }
      groups[hash] = groups[hash] "\n" file "|" size
      dupcount++
      wasted += size
    }
    prev_hash = hash
    prev_file = file
    prev_size = size
  }
  END {
    for (h in groups) {
      print h ":" groups[h]
      print "---"
    }
    print "STATS:" dupcount "|" wasted "|" gcount
  }' "$TEMP_DIR/sorted_hashes.txt" > "$TEMP_DIR/duplicates.txt"

  local stats
  stats=$(grep "^STATS:" "$TEMP_DIR/duplicates.txt" | cut -d: -f2)
  if [[ -n "$stats" ]]; then
    TOTAL_DUPLICATES=$(echo "$stats" | cut -d'|' -f1)
    TOTAL_SPACE_WASTED=$(echo "$stats" | cut -d'|' -f2)
    TOTAL_DUPLICATE_GROUPS=$(echo "$stats" | cut -d'|' -f3)
  fi

  DUPLICATE_GROUPS=$(grep -v "^STATS:" "$TEMP_DIR/duplicates.txt")
  [[ $FUZZY_MATCH -eq 1 ]] && find_similar_files
}

# -------------------------------
# Fuzzy matching (by size similarity only)
# -------------------------------
find_similar_files() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}🔍 Finding similar files (fuzzy)...${NC}"
  awk -F'|' -v threshold="$SIMILARITY_THRESHOLD" '
  BEGIN { print "---SIMILAR FILES---" }
  {
    size=$2; file=$3
    for (s in sizes) {
      diff = (s > size) ? s - size : size - s
      if (s > 0) {
        pct = 100 - (diff * 100 / s)
        if (pct >= threshold) print "SIMILAR:" file "|" sizes[s] "|" pct "%"
      }
    }
    sizes[size] = file
  }' "$TEMP_DIR/sorted_hashes.txt" >> "$TEMP_DIR/duplicates.txt"
}

# -------------------------------
# Smart delete helpers
# -------------------------------
get_location_priority() {
  local path="$1" pr=50
  for loc in "${!LOCATION_PRIORITY[@]}"; do
    [[ "$path" == *"$loc"* ]] && pr=${LOCATION_PRIORITY[$loc]} && break
  done
  echo "$pr"
}

select_file_to_keep() {
  local files=("$@") keep=0 best=999
  for i in "${!files[@]}"; do
    local p="${files[$i]}"
    local pr
    pr=$(get_location_priority "$p")
    if (( pr < best )); then best=$pr; keep=$i; fi
  done
  echo "$keep"
}

# -------------------------------
# Human size
# -------------------------------
format_size() {
  local size=${1:-0}
  if command -v bc >/dev/null 2>&1; then
    local units=(B KB MB GB TB) u=0 val=$size
    while [[ $(echo "$val >= 1024" | bc 2>/dev/null || echo 0) -eq 1 && $u -lt 4 ]]; do
      val=$(echo "scale=2; $val/1024" | bc 2>/dev/null || echo 0)
      ((u++))
    done
    printf "%.2f %s" "$val" "${units[$u]}"
  else
    local units=(B KB MB GB TB) u=0
    while [[ $size -ge 1024 && $u -lt 4 ]]; do size=$((size/1024)); ((u++)); done
    echo "$size ${units[$u]}"
  fi
}

# -------------------------------
# Backup, Verify, Deletion/Hardlink/Quarantine
# -------------------------------
backup_file() {
  local file="$1"
  [[ -z "$BACKUP_DIR" ]] && return 0
  local ts dir rel target
  ts=$(date +%Y%m%d_%H%M%S)
  dir="$BACKUP_DIR/$ts"
  mkdir -p "$dir"
  rel="${file#/}"
  target="$dir/$rel"
  mkdir -p "$(dirname "$target")"
  cp -p -- "$file" "$target" 2>/dev/null && { [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}  Backed up: $file${NC}"; return 0; }
  return 1
}

verify_identical() {
  local f1="$1" f2="$2"
  [[ $VERIFY_MODE -eq 0 ]] && return 0
  if cmp -s -- "$f1" "$f2"; then return 0; fi
  echo -e "${YELLOW}  Warning: Same hash but content differs!${NC}"
  echo -e "${YELLOW}  A: $f1${NC}"
  echo -e "${YELLOW}  B: $f2${NC}"
  return 1
}

delete_duplicates() {
  if [[ $DELETE_MODE -eq 0 && $HARDLINK_MODE -eq 0 && -z "$QUARANTINE_DIR" ]]; then
    return
  fi
  local action="Processing"
  [[ $DELETE_MODE -eq 1 ]] && action="Deleting"
  [[ $HARDLINK_MODE -eq 1 ]] && action="Hardlinking"
  [[ -n "$QUARANTINE_DIR" ]] && action="Quarantining"
  [[ $DRY_RUN -eq 1 ]] && action="Would $action"
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}🗑️  $action duplicate files...${NC}"

  local deleted=0 freed=0 links=0

  # Iterate groups
  while IFS= read -r line; do
    if [[ "$line" =~ ^([a-f0-9]+):(.+)$ ]]; then
      local files="${BASH_REMATCH[2]}"
      local arr=()
      while IFS='|' read -r fp sz; do
        [[ -n "$fp" ]] && arr+=("$fp|$sz")
      done <<< "$files"

      (( ${#arr[@]} < 2 )) && continue

      local keep_idx=0
      if [[ $SMART_DELETE -eq 1 ]]; then
        local only_paths=()
        for f in "${arr[@]}"; do only_paths+=("$(echo "$f" | cut -d'|' -f1)"); done
        keep_idx=$(select_file_to_keep "${only_paths[@]}")
      elif [[ -n "$KEEP_PATH_PRIORITY" ]]; then
        for i in "${!arr[@]}"; do
          local p; p=$(echo "${arr[$i]}" | cut -d'|' -f1)
          if [[ "$p" == "$KEEP_PATH_PRIORITY"* ]]; then keep_idx=$i; break; fi
        done
      elif [[ $KEEP_NEWEST -eq 1 || $KEEP_OLDEST -eq 1 ]]; then
        IFS=$'\n' read -r -d '' -a arr < <(
          for f in "${arr[@]}"; do
            local p m
            p=$(echo "$f" | cut -d'|' -f1)
            m=$(stat -c '%Y' -- "$p" 2>/dev/null || echo 0)
            echo "$m|$f"
          done | { [[ $KEEP_NEWEST -eq 1 ]] && sort -rn || sort -n; } | cut -d'|' -f2- && printf '\0'
        )
        keep_idx=0
      else
        IFS=$'\n' read -r -d '' -a arr < <(printf '%s\n' "${arr[@]}" | sort && printf '\0')
        keep_idx=0
      fi

      local keep_file; keep_file=$(echo "${arr[$keep_idx]}" | cut -d'|' -f1)
      [[ $VERBOSE -eq 1 ]] && echo -e "${GREEN}  ✓ Keeping: $keep_file${NC}"

      for i in "${!arr[@]}"; do
        [[ $i -eq $keep_idx ]] && continue
        local path size
        path=$(echo "${arr[$i]}" | cut -d'|' -f1)
        size=$(echo "${arr[$i]}" | cut -d'|' -f2)

        if [[ $VERIFY_MODE -eq 1 ]]; then
          verify_identical "$keep_file" "$path" || { echo -e "${RED}  Skipping non-identical${NC}"; continue; }
        fi

        if [[ $INTERACTIVE_DELETE -eq 1 ]]; then
          echo -e "${CYAN}Duplicate:${NC}"
          echo -e "  Keep: $keep_file"
          echo -e "  File: $path"
          echo -e "  Size: $(format_size "$size")"
          echo -ne "${YELLOW}Action? (d)elete/(s)kip/(h)ardlink/(q)uit [d]: ${NC}"
          read -r resp
          case "${resp:-d}" in
            d|D) : ;;
            h|H) HARDLINK_MODE=1; DELETE_MODE=0 ;;
            q|Q) echo -e "${YELLOW}Quitting...${NC}"; break 2 ;;
            *) echo -e "${GREEN}  Skipped: $path${NC}"; continue ;;
          esac
        fi

        # Back up if requested (and not a dry run)
        if [[ -n "$BACKUP_DIR" && $DRY_RUN -eq 0 ]]; then
          backup_file "$path"
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
          if [[ $HARDLINK_MODE -eq 1 ]]; then
            echo -e "${YELLOW}  Would hardlink: $path -> $keep_file${NC}"
          elif [[ -n "$QUARANTINE_DIR" ]]; then
            echo -e "${YELLOW}  Would quarantine: $path${NC}"
          else
            echo -e "${YELLOW}  Would delete: $path${NC}"
          fi
          ((deleted++)); ((freed+=size))
        elif [[ $HARDLINK_MODE -eq 1 ]]; then
          if ln -f -- "$keep_file" "$path" 2>/dev/null; then
            ((links++)); ((freed+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}  ↔ Hardlinked: $path${NC}"
            [[ -n "$LOG_FILE" ]] && echo "$(date): Hardlinked: $path -> $keep_file" >> "$LOG_FILE"
          else
            echo -e "${RED}  Failed to hardlink: $path${NC}"
          fi
        elif [[ -n "$QUARANTINE_DIR" ]]; then
          local qfile="$QUARANTINE_DIR/$(basename "$path")_$(date +%s)"
          if mv -- "$path" "$qfile" 2>/dev/null; then
            ((deleted++)); ((freed+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ⚠ Quarantined: $path${NC}"
            [[ -n "$LOG_FILE" ]] && echo "$(date): Quarantined: $path -> $qfile" >> "$LOG_FILE"
          fi
        elif [[ $USE_TRASH -eq 1 ]]; then
          if trash-put -- "$path" 2>/dev/null; then
            ((deleted++)); ((freed+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  🗑 Trashed: $path${NC}"
            [[ -n "$LOG_FILE" ]] && echo "$(date): Trashed: $path" >> "$LOG_FILE"
          fi
        else
          if rm -f -- "$path" 2>/dev/null; then
            ((deleted++)); ((freed+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${RED}  ✗ Deleted: $path${NC}"
            [[ -n "$LOG_FILE" ]] && echo "$(date): Deleted: $path" >> "$LOG_FILE"
          fi
        fi
      done
    fi
  done <<< "$DUPLICATE_GROUPS"

  FILES_DELETED=$deleted
  SPACE_FREED=$freed
  if [[ $QUIET -eq 0 ]]; then
    if [[ $HARDLINK_MODE -eq 1 ]]; then
      echo -e "${GREEN}✅ Created $links hardlinks, freed $(format_size $freed)${NC}"
    else
      echo -e "${GREEN}✅ Processed $deleted files, freed $(format_size $freed)${NC}"
    fi
  fi
}

# -------------------------------
# Reports (HTML / CSV / JSON)
# -------------------------------
generate_html_report() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📄 Generating HTML report...${NC}"
  local report_file="$OUTPUT_DIR/$HTML_REPORT"
  {
    cat << EOF
<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>DupeFinder Pro Report</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;background:#f1f3f5;margin:0}
.container{max-width:1200px;margin:40px auto;background:#fff;border-radius:12px;box-shadow:0 20px 60px rgba(0,0,0,0.1);overflow:hidden}
header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;padding:24px 28px}
h1{margin:0;font-size:28px}
.subtitle{opacity:.9;margin-top:6px}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;padding:20px;background:#f8f9fa}
.card{background:#fff;border:1px solid #eceff1;border-radius:8px;padding:16px;text-align:center}
.val{font-size:22px;color:#667eea;font-weight:700}
.label{color:#6c757d;text-transform:uppercase;font-size:12px;margin-top:4px}
.group{border-top:1px solid #f1f3f5}
.group .hdr{background:#fafbfc;padding:12px 16px;cursor:pointer;font-weight:600}
.group .files{padding:6px 16px 16px 16px;display:none}
.file{padding:8px 0;border-bottom:1px solid #f6f7f8}
.file:last-child{border-bottom:0}
.code{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;color:#495057}
.show .files{display:block}
.footer{padding:16px 20px;background:#fff;border-top:1px solid #eceff1}
</style>
<script>
function toggle(id){var el=document.getElementById(id); if(el){el.classList.toggle('show');}}
</script>
</head><body>
<div class="container">
<header>
  <h1>DupeFinder Pro Report</h1>
  <div class="subtitle">by ${AUTHOR} | Generated: $(date '+%B %d, %Y %H:%M:%S')</div>
</header>
<div class="stats">
  <div class="card"><div class="val">${TOTAL_FILES}</div><div class="label">Files Scanned</div></div>
  <div class="card"><div class="val">${TOTAL_DUPLICATES}</div><div class="label">Duplicates Found</div></div>
  <div class="card"><div class="val">${TOTAL_DUPLICATE_GROUPS}</div><div class="label">Duplicate Groups</div></div>
  <div class="card"><div class="val">$(format_size "${TOTAL_SPACE_WASTED:-0}")</div><div class="label">Space Wasted</div></div>
</div>
<div>
EOF
    local gid=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^([a-f0-9]+):(.+)$ ]]; then
        ((gid++))
        local hash="${BASH_REMATCH[1]}"; local files="${BASH_REMATCH[2]}"
        echo "<div id=\"g$gid\" class=\"group\"><div class=\"hdr\" onclick=\"toggle('g$gid')\">Group $gid (Hash: ${hash:0:16}…)</div><div class=\"files\">"
        while IFS='|' read -r filepath size; do
          [[ -z "$filepath" ]] && continue
          printf '<div class="file"><div class="code">%s</div><div>Size: %s</div></div>\n' \
            "$(printf '%s' "$filepath" | sed 's/&/\&amp;/g;s/</\&lt;/g')" "$(format_size "$size")"
        done <<< "$files"
        echo "</div></div>"
      fi
    done <<< "$DUPLICATE_GROUPS"
    cat << 'EOF'
</div>
<div class="footer">End of report.</div>
</div></body></html>
EOF
  } > "$report_file"
  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✅ HTML report saved to: $report_file${NC}"
}

generate_csv_report() {
  [[ -z "$CSV_REPORT" ]] && return
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📊 Generating CSV report...${NC}"
  local csv="$OUTPUT_DIR/$CSV_REPORT"
  echo "Hash,File Path,Size (bytes),Size (human),Group ID" > "$csv"
  local gid=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^([a-f0-9]+):(.+)$ ]]; then
      ((gid++))
      local hash="${BASH_REMATCH[1]}"; local files="${BASH_REMATCH[2]}"
      while IFS='|' read -r fp sz; do
        [[ -z "$fp" ]] && continue
        printf '%s,"%s",%s,"%s",%s\n' "$hash" "$fp" "$sz" "$(format_size "$sz")" "$gid" >> "$csv"
      done <<< "$files"
    fi
  done <<< "$DUPLICATE_GROUPS"
  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✅ CSV report saved to: $csv${NC}"
}

generate_json_report() {
  [[ -z "$JSON_REPORT" ]] && return
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📋 Generating JSON report...${NC}"
  local json="$OUTPUT_DIR/$JSON_REPORT"
  # Build a raw JSON-ish text then reformat via jq to ensure valid JSON.
  {
    echo '{'
    echo '  "metadata": {'
    printf '    "version": "%s", "author": "%s", "generated": "%s", "search_path": "%s", ' \
      "$VERSION" "$AUTHOR" "$(date -Iseconds)" "$SEARCH_PATH"
    printf '"total_files": %s, "total_duplicates": %s, "total_groups": %s, "space_wasted": %s, ' \
      "${TOTAL_FILES:-0}" "${TOTAL_DUPLICATES:-0}" "${TOTAL_DUPLICATE_GROUPS:-0}" "${TOTAL_SPACE_WASTED:-0}"
    printf '"hash_algorithm": "%s"\n' "${HASH_ALGORITHM%%sum}"
    echo '  },'
    echo '  "groups": ['
    local first_group=1 gid=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^([a-f0-9]+):(.+)$ ]]; then
        ((gid++))
        local hash="${BASH_REMATCH[1]}"; local files="${BASH_REMATCH[2]}"
        [[ $first_group -eq 0 ]] && echo ','
        echo '    {'
        printf '      "id": %s, "hash": "%s", "files": [' "$gid" "$hash"
        local first_file=1
        while IFS='|' read -r fp sz; do
          [[ -z "$fp" ]] && continue
          [[ $first_file -eq 0 ]] && echo -n ','
          printf '\n        {"path": %s, "size": %s}' "$(printf '%s' "$fp" | jq -Rsa . | sed 's/^"//;s/"$//' )" "$sz"
          first_file=0
        done <<< "$files"
        echo -e '\n      ]'
        echo -n '    }'
        first_group=0
      fi
    done <<< "$DUPLICATE_GROUPS"
    echo -e '\n  ]'
    echo '}'
  } | jq . > "$json" 2>/dev/null
  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✅ JSON report saved to: $json${NC}"
}

# -------------------------------
# Email Summary
# -------------------------------
calculate_duration() {
  local d=$((SCAN_END_TIME - SCAN_START_TIME))
  local h=$((d/3600)) m=$(((d%3600)/60)) s=$((d%60))
  (( h > 0 )) && printf "%dh %dm %ds" "$h" "$m" "$s" || { (( m>0 )) && printf "%dm %ds" "$m" "$s" || printf "%ds" "$s"; }
}

send_email_report() {
  [[ -z "$EMAIL_REPORT" ]] && return
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📧 Sending email report...${NC}"
  local subject="DupeFinder Pro Report - $(date '+%Y-%m-%d')"
  local body="DupeFinder Pro Scan Results

Search Path: $SEARCH_PATH
Total Files Scanned: $TOTAL_FILES
Duplicate Files Found: $TOTAL_DUPLICATES
Duplicate Groups: $TOTAL_DUPLICATE_GROUPS
Space Wasted: $(format_size ${TOTAL_SPACE_WASTED:-0})
Files Processed: $FILES_DELETED
Space Freed: $(format_size ${SPACE_FREED:-0})
Scan Duration: $(calculate_duration)

HTML Report: $OUTPUT_DIR/$HTML_REPORT"
  if command -v mail &>/dev/null; then
    echo "$body" | mail -s "$subject" "$EMAIL_REPORT"
    [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✅ Email sent to: $EMAIL_REPORT${NC}"
  else
    [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}⚠ Mail command not available${NC}"
  fi
}

# -------------------------------
# Summary
# -------------------------------
show_summary() {
  [[ $QUIET -eq 1 ]] && return
  echo ""
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}                    SCAN SUMMARY${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}📁 Search Path:${NC}          $SEARCH_PATH"
  echo -e "${CYAN}📊 Files Scanned:${NC}        $TOTAL_FILES"
  echo -e "${CYAN}🔄 Duplicates Found:${NC}     $TOTAL_DUPLICATES"
  echo -e "${CYAN}📂 Duplicate Groups:${NC}     $TOTAL_DUPLICATE_GROUPS"
  echo -e "${CYAN}💾 Space Wasted:${NC}         $(format_size ${TOTAL_SPACE_WASTED:-0})"
  if [[ $FILES_DELETED -gt 0 || $HARDLINK_MODE -eq 1 ]]; then
    echo -e "${CYAN}✅ Files Processed:${NC}      $FILES_DELETED"
    echo -e "${CYAN}💚 Space Freed:${NC}          $(format_size ${SPACE_FREED:-0})"
  fi
  echo -e "${CYAN}⏱️  Scan Duration:${NC}        $(calculate_duration)"
  echo -e "${CYAN}🔧 Hash Algorithm:${NC}       ${HASH_ALGORITHM%%sum}"
  echo -e "${CYAN}⚡ Threads Used:${NC}         $THREADS"
  echo -e "${WHITE}─────────────────────────────────────────────────────────${NC}"
  echo -e "${CYAN}📄 HTML Report:${NC}          $OUTPUT_DIR/$HTML_REPORT"
  [[ -n "$CSV_REPORT" ]] && echo -e "${CYAN}📊 CSV Report:${NC}           $OUTPUT_DIR/$CSV_REPORT"
  [[ -n "$JSON_REPORT" ]] && echo -e "${CYAN}📋 JSON Report:${NC}          $OUTPUT_DIR/$JSON_REPORT"
  [[ -n "$LOG_FILE" ]] && echo -e "${CYAN}📝 Log File:${NC}             $LOG_FILE"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
}

# -------------------------------
# Main
# -------------------------------
main() {
  load_config
  check_dependencies
  SCAN_START_TIME=$(date +%s)
  init_logging
  [[ $QUIET -eq 0 ]] && show_header
  validate_inputs
  init_cache
  find_files
  calculate_hashes
  find_duplicates
  generate_html_report
  generate_csv_report
  generate_json_report
  delete_duplicates
  SCAN_END_TIME=$(date +%s)
  send_email_report
  show_summary
  [[ $QUIET -eq 0 ]] && echo -e "\n${GREEN}✨ Scan completed successfully!${NC}"
  [[ $QUIET -eq 0 ]] && echo -e "${DIM}DupeFinder Pro v$VERSION by $AUTHOR${NC}\n"
}

# -------------------------------
# Entry Point
# -------------------------------
parse_arguments "$@"
main
exit 0
