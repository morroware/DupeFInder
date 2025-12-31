#!/usr/bin/env bash
#############################################################################
# DupeFinder Pro - Advanced Duplicate File Manager for Linux
# Version: 1.2.4 (Final)
# Author: Seth Morrow
# License: MIT
#
# Description:
#   Production-ready duplicate file finder with comprehensive safety checks,
#   robust error handling, and reliable operation for large-scale deployments.
#
#############################################################################

# Remove errexit for explicit error handling
set -o nounset
set -o pipefail

# ═══════════════════════════════════════════════════════════════════════════
# TERMINAL COLORS AND FORMATTING
# ═══════════════════════════════════════════════════════════════════════════
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL DELIMITERS AND CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════
# Use a non-empty delimiter (tab) for hash records
readonly DELIM=$'\t'
readonly TAB=$'\t'

# ═══════════════════════════════════════════════════════════════════════════
# DEFAULT CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════
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
BACKUP_DIR=""
USE_TRASH=0
HARDLINK_MODE=0
QUARANTINE_DIR=""
DB_CACHE="$HOME/.dupefinder_cache.db"
USE_CACHE=0
THREADS=0
EMAIL_REPORT=""
CONFIG_FILE=""
FUZZY_MATCH=0
SIMILARITY_THRESHOLD=95
SAVE_CHECKSUMS=0
CHECKSUM_DB="$HOME/.dupefinder_checksums.db"
EXCLUDE_LIST_FILE=""
FAST_MODE=0
SMART_DELETE=0
LOG_FILE=""
VERIFY_MODE=0
USE_PARALLEL=0
RESUME_STATE=0
LSOF_CHECKS=0  # Disabled by default - lsof is slow for large file sets
TEMP_DIR=""
MEMORY_CHECK_INTERVAL=100 # Check memory every N files
readonly VERSION="1.3.0"  # Performance improvements: xargs parallelism, partial hashing
readonly AUTHOR="Seth Morrow"
readonly MAX_MEMORY_MB=2048 # Maximum memory usage in MB
readonly HASH_TIMEOUT=30   # Timeout for hash calculation per file
readonly MAX_RETRIES=3     # Maximum retries for failed operations
AWK_BIN="awk" # Will be set to gawk if available
ME="$(id -un 2>/dev/null || echo "$USER")"
IONICE_PREFIX=""
NICE_PREFIX=""
if command -v ionice >/dev/null 2>&1; then IONICE_PREFIX="ionice -c 3"; fi
if command -v nice >/dev/null 2>&1; then NICE_PREFIX="nice -n 19"; fi
MAIL_BIN=""
for b in mail mailx; do command -v "$b" >/dev/null && MAIL_BIN="$b" && break; done

# ═══════════════════════════════════════════════════════════════════════════
# CRITICAL SYSTEM PROTECTION CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════
readonly -a CRITICAL_EXTENSIONS=(
  ".so" ".dll" ".dylib" ".ko" ".sys" ".elf" ".a" ".lib" ".pdb" ".exe"
)

readonly -a CRITICAL_PATHS=(
  "/boot" "/lib" "/lib64" "/usr/lib" "/usr/lib64" "/usr/bin" "/bin"
  "/sbin" "/usr/sbin" "/etc" "/usr/share/dbus-1" "/usr/share/applications"
)

readonly -a SYSTEM_FOLDERS=(
  "/boot" "/bin" "/sbin" "/lib" "/lib32" "/lib64" "/libx32" "/usr"
  "/etc" "/root" "/snap" "/sys" "/proc" "/dev" "/run" "/srv"
)

readonly -a NEVER_DELETE_PATTERNS=(
  "vmlinuz*" "initrd*" "initramfs*" "grub*" "ld-linux*" "libc.so*"
  "libpthread*" "libdl*" "libm.so*" "busybox*" "systemd*" "bash"
  "sh" "python" "perl" "awk" "sed" "find" "grep" "xargs" "ln" "rm" "mv"
)

SKIP_SYSTEM_FOLDERS=0
FORCE_SYSTEM_DELETE=0

# ═══════════════════════════════════════════════════════════════════════════
# STATISTICS COUNTERS
# ═══════════════════════════════════════════════════════════════════════════
TOTAL_FILES=0
TOTAL_DUPLICATES=0
TOTAL_DUPLICATE_GROUPS=0
TOTAL_SPACE_WASTED=0
FILES_DELETED=0
SPACE_FREED=0
FILES_HARDLINKED=0
FILES_QUARANTINED=0
SCAN_START_TIME=""
SCAN_END_TIME=""
FILES_PROCESSED=0
HASH_ERRORS=0

# ═══════════════════════════════════════════════════════════════════════════
# SMART LOCATION PRIORITIES
# ═══════════════════════════════════════════════════════════════════════════
declare -A LOCATION_PRIORITY=(
  ["/home"]=1 ["/usr/local"]=2 ["/opt"]=3 ["/var"]=4
  ["/tmp"]=99 ["/downloads"]=90 ["/cache"]=95
)

# ═══════════════════════════════════════════════════════════════════════════
# ERROR HANDLING AND LOGGING
# ═══════════════════════════════════════════════════════════════════════════
error_exit() {
  echo -e "${RED}Error: $1${NC}" >&2
  cleanup
  exit "${2:-1}"
}

log_action() {
  local level="$1"
  local message="$2"
  
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="$HOME/.dupefinder.log"
  fi
  
  local log_dir
  log_dir=$(dirname "$LOG_FILE")
  if [[ ! -w "$log_dir" && -w "/tmp" ]]; then
    echo -e "${YELLOW}Warning: Log directory '$log_dir' not writable. Using /tmp.${NC}" >&2
    LOG_FILE="/tmp/dupefinder_$$_${ME}.log"
  fi

  if [[ ! -f "$LOG_FILE" ]]; then
    mkdir -p "$log_dir" 2>/dev/null || return
    touch "$LOG_FILE" 2>/dev/null || return
  fi
  
  local msg
  printf -v msg "%q" "$2"
  echo "$(date +'%Y-%m-%d %H:%M:%S') [${level^^}] $msg" >> "$LOG_FILE"
}

get_available_mb() {
  if command -v free >/dev/null 2>&1; then
    free -m | awk '/^Mem:/ {print $7}'
  elif [[ -r /proc/meminfo ]]; then
    awk '/^MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo
  else
    echo "0"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# CLEANUP AND SIGNAL HANDLING
# ═══════════════════════════════════════════════════════════════════════════
cleanup_done=0
cleanup() {
  if [[ $cleanup_done -eq 1 ]]; then
    return
  fi
  cleanup_done=1

  local pids
  pids=$(jobs -p)
  if [[ -n "$pids" ]]; then
    kill $pids 2>/dev/null || true
  fi
  wait 2>/dev/null || true

  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR" 2>/dev/null || true
  fi
  
  # NEW: Optionally clean up cache on exit
  if [[ $USE_CACHE -eq 1 && -f "$DB_CACHE" ]]; then
    sqlite3 "$DB_CACHE" "VACUUM;" 2>/dev/null || true
    log_action "info" "Cleaned SQLite cache"
  fi
  
  [[ -n "$LOG_FILE" ]] && log_action "info" "Session ended"
  
  if [[ -n "$SCAN_END_TIME" ]]; then
    rm -f -- "$HOME/.dupefinder_state" "$HOME/.dupefinder_state.dups" "$HOME/.dupefinder_state.cksum" 2>/dev/null || true
  fi
}

handle_interrupt() {
  echo -e "\n${YELLOW}Interrupted!${NC}" >&2
  if [[ $TOTAL_FILES -gt 0 && $FILES_PROCESSED -gt 0 ]]; then
    echo "Processed $FILES_PROCESSED/$TOTAL_FILES files before interruption."
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

# ═══════════════════════════════════════════════════════════════════════════
# SECURE TEMPORARY DIRECTORY CREATION (FIXED for atomic mv)
# Uses /tmp for high IOPS and proper FIFO/socket support instead of OUTPUT_DIR
# ═══════════════════════════════════════════════════════════════════════════
create_temp_dir() {
  # Use /tmp or /var/tmp for performance - named pipes and SQLite work poorly on network shares
  local temp_base=""
  local attempt=0

  # Try to find a suitable temp location
  for candidate in "${TMPDIR:-}" "/tmp" "/var/tmp"; do
    if [[ -n "$candidate" && -d "$candidate" && -w "$candidate" ]]; then
      temp_base="$candidate"
      break
    fi
  done

  if [[ -z "$temp_base" ]]; then
    # Fallback to OUTPUT_DIR if no temp location available
    temp_base="$OUTPUT_DIR"
    [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}Warning: Using OUTPUT_DIR for temp files (no /tmp available)${NC}"
  fi

  # Ensure output directory exists for final reports
  mkdir -p -- "$OUTPUT_DIR" 2>/dev/null || error_exit "Cannot create or access output directory: $OUTPUT_DIR"

  local perms owner p_group p_other
  owner=$(stat -c "%U" "$OUTPUT_DIR")
  perms=$(stat -c "%a" "$OUTPUT_DIR"); p_group=${perms:1:1}; p_other=${perms:2:1}
  if [[ "$owner" != "$ME" || ! -O "$OUTPUT_DIR" || "$p_group" =~ [2367] || "$p_other" =~ [2367] ]]; then
    error_exit "Output directory '$OUTPUT_DIR' is unsafe (must be owned by current user and not group/other-writable)"
  fi

  while [[ $attempt -lt 5 ]]; do
    TEMP_DIR=$(mktemp -d -p "$temp_base" dupefinder.XXXXXXXXXX 2>/dev/null) || {
      ((attempt++)); sleep 1; continue
    }

    if [[ -d "$TEMP_DIR" ]]; then
      chmod 700 "$TEMP_DIR" || { rm -rf -- "$TEMP_DIR"; error_exit "Failed to secure temporary directory"; }
      log_action "info" "Created secure temp directory: $TEMP_DIR"
      return 0
    fi
  done

  error_exit "Failed to create temporary directory after $attempt attempts"
}

# ═══════════════════════════════════════════════════════════════════════════
# USER INTERFACE FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════
show_header() {
  [[ -t 1 ]] && clear
  echo -e "${CYAN}"
  cat << "EOF"
    ____             ____  _          ____              
   | _ \ _  _ _ __  ___| ___(_)_ __  __| | ___ _ __| _ \ _ __ ___ 
   | | | | | | '_ \ / _ \ |_  | | '_ \ / _` |/ _ \ '__| |_) | '__/ _ \ 
   | |_| | |_| | |_) | __/ _| | | | | | (_| | __/ |  | __/| | | (_) |
   |____/ \__,_| .__/ \___|_|  |_|_| |_|\__,_|\___|_|  |_|  |_|  \___/ 
             |_|                                                    
EOF
  echo -e "${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}      Advanced Duplicate File Manager v${VERSION}${NC}"
  echo -e "${DIM}            by ${AUTHOR}${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

show_help() {
  show_header
  cat << EOF
${BOLD}USAGE:${NC}
    $0 [OPTIONS]

${BOLD}BASIC OPTIONS:${NC}
    ${GREEN}-p, --path PATH${NC}       Search path (default: current directory)
    ${GREEN}-o, --output DIR${NC}      Output directory for reports
    ${GREEN}-e, --exclude PATH${NC}    Exclude path (can be used multiple times)
    ${GREEN}-m, --min-size SIZE${NC}   Min size (e.g., 100, 10K, 5M, 1G)
    ${GREEN}-M, --max-size SIZE${NC}   Max size (e.g., 100, 10K, 5M, 1G)
    ${GREEN}-h, --help${NC}            Show this help
    ${GREEN}-V, --version${NC}         Show version
    ${GREEN}--config FILE${NC}         Load options from a config file

${BOLD}SAFETY OPTIONS:${NC}
    ${GREEN}--skip-system${NC}         Skip all system folders (/usr, /lib, /bin, etc.)
    ${GREEN}--force-system${NC}        Allow deletion of system files (DANGEROUS!)

${BOLD}SEARCH:${NC}
    ${GREEN}-f, --follow-symlinks${NC} Follow symbolic links (recursively)
    ${GREEN}-z, --empty${NC}           Include empty files
    ${GREEN}-a, --all${NC}             Include hidden files
    ${GREEN}-l, --level DEPTH${NC}     Max directory depth
    ${GREEN}-t, --pattern GLOB${NC}    File pattern (e.g., "*.jpg")
    ${GREEN}--fast${NC}                Fast mode (size + first 64KB hash)
    ${GREEN}--verify${NC}              Byte-by-byte verification before deletion
    ${GREEN}--fuzzy${NC}               Fuzzy matching for similar files (requires ssdeep)
    ${GREEN}--threshold PCT${NC}       Similarity threshold for fuzzy matching (default: 95)

${BOLD}DELETION:${NC}
    ${GREEN}-d, --delete${NC}          Delete duplicates
    ${GREEN}-i, --interactive${NC}     Enhanced interactive mode with file preview
    ${GREEN}-n, --dry-run${NC}         Show actions without executing
    ${GREEN}--trash${NC}               Use trash (trash-cli) if available
    ${GREEN}--hardlink${NC}            Replace duplicates with hardlinks.
                                  (Works only within the same filesystem; replaces duplicates
                                  in-place with a hardlink to the kept file's inode).
    ${GREEN}--quarantine DIR${NC}      Move duplicates to quarantine directory

${BOLD}KEEP STRATEGIES:${NC}
    ${GREEN}-k, --keep-newest${NC}     Keep newest file from each group
    ${GREEN}-K, --keep-oldest${NC}     Keep oldest file from each group
    ${GREEN}--keep-path PATH${NC}      Prefer files in PATH
    ${GREEN}--smart-delete${NC}        Use location-based priorities

${BOLD}PERFORMANCE:${NC}
    ${GREEN}--threads N${NC}           Number of threads for hashing

${BOLD}REPORTING:${NC}
    ${GREEN}-c, --csv FILE${NC}        Generate CSV report
    ${GREEN}--json FILE${NC}           Generate JSON report
    ${GREEN}--log FILE${NC}            Log operations to FILE
    ${GREEN}-v, --verbose${NC}         Enable verbose output
    ${GREEN}-q, --quiet${NC}           Quiet mode (minimal output)
    ${GREEN}--email EMAIL${NC}         Email HTML report on completion (requires 'mail' command)

${BOLD}ADVANCED:${NC}
    ${GREEN}-s, --sha256${NC}          Use SHA256 hashing
    ${GREEN}--sha512${NC}              Use SHA512 hashing
    ${GREEN}--backup DIR${NC}          Backup files before deletion
    ${GREEN}--exclude-list FILE${NC}   File with paths to exclude
    ${GREEN}--resume${NC}              Resume from a previous interrupted scan
    ${GREEN}--cache${NC}               Use a file-based cache for faster re-scans
    ${GREEN}--enable-lsof${NC}         Enable lsof checks for open files (slow on large sets)

${BOLD}EXAMPLES:${NC}
    # Safe system-wide scan
    $0 --path / --skip-system --delete --dry-run
    
    # Interactive cleanup with enhanced UI
    $0 --path ~/Downloads --min-size 1M --interactive --verbose
    
    # Find duplicate photos and auto-select based on path priority
    $0 --path ~/Pictures --pattern "*.jpg" --pattern "*.png" --smart-delete -v

EOF
}

# ═══════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════
parse_size() {
  local s="$1"
  if [[ "$s" =~ ^([0-9]+)([KMGTP]?)B?$ ]]; then
    local n="${BASH_REMATCH[1]}"
    local u="${BASH_REMATCH[2]}"
    case "${u^^}" in
      K) echo $((n*1024));;
      M) echo $((n*1024*1024));;
      G) echo $((n*1024*1024*1024));;
      T) echo $((n*1024*1024*1024*1024));;
      P) echo $((n*1024*1024*1024*1024*1024));;
      *) echo "$n";;
    esac
  else
    echo "$s"
  fi
}

format_size() {
  local size=${1:-0}
  if command -v bc >/dev/null 2>&1; then
    local units=(B KB MB GB TB PB)
    local u=0
    local val=$size
    while [[ $(echo "$val >= 1024" | bc 2>/dev/null || echo 0) -eq 1 && $u -lt 5 ]]; do
      val=$(echo "scale=2; $val/1024" | bc 2>/dev/null || echo 0)
      ((u++))
    done
    printf "%.2f %s" "$val" "${units[$u]}"
  else
    local units=(B KB MB GB TB PB)
    local u=0
    while [[ $size -ge 1024 && $u -lt 5 ]]; do
      size=$((size/1024))
      ((u++))
    done
    echo "$size ${units[$u]}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# SAFE FILE OPERATIONS
# ═══════════════════════════════════════════════════════════════════════════

# Escape a string for safe use in SQLite queries
sql_escape() {
  local str="$1"
  # SQLite uses doubled single quotes for escaping
  printf '%s' "${str//\'/\'\'}"
}

safe_stat() {
  local file="$1"
  local format="$2"
  
  if [[ ! -e "$file" ]]; then
    echo "0"
    return 1
  fi
  
  stat -c "$format" -- "$file" 2>/dev/null || echo "0"
}

verify_identical() {
  local file1="$1"
  local file2="$2"
  
  [[ ! -f "$file1" || ! -f "$file2" ]] && return 1
  
  local size1 size2
  size1=$(safe_stat "$file1" "%s")
  size2=$(safe_stat "$file2" "%s")
  
  [[ "$size1" != "$size2" ]] && return 1
  
  if command -v cmp >/dev/null 2>&1; then
    cmp -s -- "$file1" "$file2" 2>/dev/null
    return $?
  else
    diff -q -- "$file1" "$file2" >/dev/null 2>&1
    return $?
  fi
}

fuzzy_match() {
  local file1="$1"
  local file2="$2"
  local threshold="$3"
  
  if ! command -v ssdeep >/dev/null 2>&1; then
    log_action "warning" "Fuzzy matching requires ssdeep"
    return 1
  fi
  
  local output
  output=$(ssdeep -l -p -s "$file1" "$file2" 2>/dev/null)
  local similarity
  similarity=$(echo "$output" | grep -o '[0-9]\+%' | tr -d '%')
  [[ -z "$similarity" ]] && return 1
  
  if [[ "$similarity" -ge "$threshold" ]]; then
    return 0
  fi
  
  return 1
}

backup_file() {
  local file="$1"
  
  [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]] && {
    log_action "warning" "Backup directory not available"
    return 1
  }
  
  [[ ! -f "$file" ]] && {
    log_action "error" "File to backup does not exist: $file"
    return 1
  }
  
  local backup_name backup_path
  backup_name="$(basename -- "$file")_$(date +%Y%m%d_%H%M%S)_$(echo "$file" | sha256sum | cut -c1-8)"
  backup_path="$BACKUP_DIR/$backup_name"
  
  if cp --preserve=all -- "$file" "$backup_path" 2>/dev/null; then
    [[ $VERBOSE -eq 1 ]] && echo -e "${GREEN}  + Backed up: $file -> $backup_path${NC}"
    log_action "info" "Backed up: $file -> $backup_path"
    return 0
  else
    log_action "error" "Failed to backup: $file"
    return 1
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# CRITICAL SAFETY VERIFICATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════
is_critical_system_file() {
  local file="$1"
  local basename_file
  basename_file=$(basename -- "$file")
  
  for ext in "${CRITICAL_EXTENSIONS[@]}"; do
    [[ "$file" == *"$ext" ]] && return 0
  done
  
  for path in "${CRITICAL_PATHS[@]}"; do
    [[ "$file" == "$path"/* ]] && return 0
  done
  
  for pattern in "${NEVER_DELETE_PATTERNS[@]}"; do
    if [[ "$basename_file" == $pattern ]]; then
      return 0
    fi
  done
  
  if [[ -x "$file" ]]; then
    case "$(dirname -- "$file")" in
      /bin|/sbin|/usr/bin|/usr/sbin|/usr/local/bin|/usr/local/sbin)
        return 0
        ;;
    esac
  fi
  
  return 1
}

verify_safe_to_delete() {
  local file="$1"
  
  local real_file
  real_file=$(realpath -e "$file") || return 1
  
  if is_critical_system_file "$real_file"; then
    if [[ $FORCE_SYSTEM_DELETE -eq 1 ]]; then
      if [[ -t 0 ]]; then
        echo -e "${RED}WARNING: Critical system file detected: $real_file${NC}"
        echo -ne "${RED}Type 'YES DELETE' to proceed: ${NC}"
        read -r confirmation
        [[ "$confirmation" != "YES DELETE" ]] && return 1
      else
        log_action "error" "Refusing to prompt in non-interactive mode: $real_file"
        return 1
      fi
    else
      [[ $VERBOSE -eq 1 ]] && echo -e "${RED}  X Skipping critical system file: $real_file${NC}"
      log_action "info" "Skipping critical system file: $real_file"
      return 1
    fi
  fi
  
  if [[ $LSOF_CHECKS -eq 1 ]] && command -v lsof &>/dev/null; then
    if timeout 5 lsof -- "$file" >/dev/null 2>&1; then
      echo -e "${YELLOW}  ! File is currently in use: $file${NC}"
      if [[ $INTERACTIVE_DELETE -eq 1 ]]; then
        echo -ne "${YELLOW}  Force delete anyway? (y/N): ${NC}"
        read -r response
        [[ "$response" != "y" && "$response" != "Y" ]] && return 1
      else
        log_action "info" "Skipping file in use: $file"
        return 1
      fi
    fi
  fi
  
  if [[ "$file" == *.so* ]]; then
    if grep -qF -- "$(basename -- "$file")" /proc/*/maps 2>/dev/null; then
      echo -e "${RED}  X Shared library is currently loaded: $file${NC}"
      log_action "info" "Skipping loaded shared library: $file"
      return 1
    fi
  fi
  
  local owner
  owner=$(safe_stat "$file" "%U")
  if [[ "$owner" == "root" && "$ME" != "root" ]]; then
    echo -e "${YELLOW}  ! File is owned by root: $file${NC}"
    log_action "warning" "File is owned by root: $file"
    return 1
  fi
  
  return 0
}

is_in_system_folder() {
  local file="$1"
  local real
  real=$(realpath -e "$file" 2>/dev/null) || real="$file"
  for sys_folder in "${SYSTEM_FOLDERS[@]}"; do
    [[ "$real" == "$sys_folder"/* ]] && return 0
  done
  return 1
}

show_safety_summary() {
  if [[ $DELETE_MODE -eq 1 || $HARDLINK_MODE -eq 1 ]]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}      SAFETY CHECK SUMMARY${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}System Protection:${NC}      $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    echo -e "${CYAN}Force System Delete:${NC}       $([ $FORCE_SYSTEM_DELETE -eq 1 ] && echo -e "${RED}ENABLED${NC}" || echo "DISABLED")"
    echo -e "${CYAN}Running as:${NC}              $ME"
    echo -e "${CYAN}Delete Mode:${NC}             $([ $DELETE_MODE -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    echo -e "${CYAN}Interactive Mode:${NC}        $([ $INTERACTIVE_DELETE -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    echo -e "${CYAN}Dry Run:${NC}                 $([ $DRY_RUN -eq 1 ] && echo "YES" || echo "NO")"
    echo -e "${YELLOW}─────────────────────────────────────────────────────────${NC}"
    if [[ $DELETE_MODE -eq 1 && $DRY_RUN -eq 0 && $FORCE_SYSTEM_DELETE -eq 0 && $INTERACTIVE_DELETE -eq 0 ]]; then
      if [[ -t 0 ]]; then
        echo -ne "${YELLOW}Proceed with these settings? (y/N): ${NC}"
        read -r response
        [[ "$response" != "y" && "$response" != "Y" ]] && exit 0
      else
        echo -e "${YELLOW}Non-interactive session detected; aborting destructive actions. Use --dry-run or --interactive.${NC}"
        exit 2
      fi
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION AND STATE MANAGEMENT (Hardened)
# ═══════════════════════════════════════════════════════════════════════════
safe_source() {
  local filename="$1"
  [[ ! -f "$filename" ]] && return 1
  
  local -a allowed_vars=("SEARCH_PATH" "OUTPUT_DIR" "HASH_ALGORITHM" "SCAN_START_TIME" "STATE_DUPS_FILE" "FILES_PROCESSED" "EXCLUDE_PATHS" "MIN_SIZE" "MAX_SIZE" "DELETE_MODE" "DRY_RUN" "VERBOSE" "QUIET" "FOLLOW_SYMLINKS" "EMPTY_FILES" "HIDDEN_FILES" "MAX_DEPTH" "FILE_PATTERN" "INTERACTIVE_DELETE" "KEEP_NEWEST" "KEEP_OLDEST" "KEEP_PATH_PRIORITY" "BACKUP_DIR" "USE_TRASH" "HARDLINK_MODE" "QUARANTINE_DIR" "USE_CACHE" "THREADS" "EMAIL_REPORT" "CONFIG_FILE" "FUZZY_MATCH" "SIMILARITY_THRESHOLD" "SAVE_CHECKSUMS" "CHECKSUM_DB" "EXCLUDE_LIST_FILE" "FAST_MODE" "SMART_DELETE" "LOG_FILE" "VERIFY_MODE" "USE_PARALLEL" "RESUME_STATE" "LSOF_CHECKS")

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Only strip comments if # is at start or preceded by whitespace
    # This preserves paths like /mnt/drive#1
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      # Line starts with optional whitespace then #, skip it
      continue
    fi
    # Strip inline comments only if # is preceded by whitespace
    if [[ "$line" =~ ^(.*)([[:space:]]#.*)$ ]]; then
      line="${BASH_REMATCH[1]}"
    fi
    # Trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "$line" ]] && continue
    
    if [[ "$line" =~ ^([[:alnum:]_]+)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"

      # Check for unsafe shell characters in value (backticks, $, (), ;)
      local unsafe_pattern='[`$();]'
      if [[ "$val" =~ $unsafe_pattern ]]; then
          log_action "error" "Unsafe value rejected for $key in $1"
          continue
      fi

      [[ "$val" == \"*\" ]] && val="${val%\"}" && val="${val#\"}"

      local is_allowed=0
      for var_name in "${allowed_vars[@]}"; do
        if [[ "$key" == "$var_name" ]]; then
          is_allowed=1
          break
        fi
      done
      if [[ $is_allowed -eq 1 ]]; then
        printf -v "$key" "%s" "$val"
      fi
    fi
  done < "$filename"
}

parse_arguments() {
  local default_config="$HOME/.dupefinder.conf"
  if [[ -f "$default_config" ]]; then
    safe_source "$default_config"
  fi

  while [[ $# -gt 0 ]]; do
    local arg="$1"
    case "$arg" in
      -p|--path)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a path"
        SEARCH_PATH="$2"; shift 2 ;;
      -o|--output)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a directory path"
        OUTPUT_DIR="$2"; shift 2 ;;
      -e|--exclude)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a path"
        EXCLUDE_PATHS+=("$2"); shift 2 ;;
      -m|--min-size)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a size value"
        MIN_SIZE=$(parse_size "$2"); shift 2 ;;
      -M|--max-size)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a size value"
        MAX_SIZE=$(parse_size "$2"); shift 2 ;;
      -h|--help) show_help; exit 0 ;;
      -V|--version) echo "DupeFinder Pro v$VERSION by $AUTHOR"; exit 0 ;;
      --skip-system) SKIP_SYSTEM_FOLDERS=1; shift ;;
      --force-system) FORCE_SYSTEM_DELETE=1; shift ;;
      -f|--follow-symlinks) FOLLOW_SYMLINKS=1; shift ;;
      -z|--empty) EMPTY_FILES=1; MIN_SIZE=0; shift ;;
      -a|--all) HIDDEN_FILES=1; shift ;;
      -l|--level)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a depth value"
        MAX_DEPTH="$2"; shift 2 ;;
      -t|--pattern)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a glob pattern"
        FILE_PATTERN+=("$2"); shift 2 ;;
      --fast) FAST_MODE=1; shift ;;
      --verify) VERIFY_MODE=1; shift ;;
      --fuzzy) FUZZY_MATCH=1; shift ;;
      --threshold)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a percentage value"
        SIMILARITY_THRESHOLD="$2"; shift 2 ;;
      -d|--delete) DELETE_MODE=1; shift ;;
      -i|--interactive) INTERACTIVE_DELETE=1; DELETE_MODE=1; shift ;;
      -n|--dry-run) DRY_RUN=1; shift ;;
      --trash) USE_TRASH=1; shift ;;
      --hardlink) HARDLINK_MODE=1; shift ;;
      --quarantine)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a directory path"
        QUARANTINE_DIR="$2"; shift 2 ;;
      -k|--keep-newest) KEEP_NEWEST=1; shift ;;
      -K|--keep-oldest) KEEP_OLDEST=1; shift ;;
      --keep-path)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a path"
        KEEP_PATH_PRIORITY="$2"; shift 2 ;;
      --smart-delete) SMART_DELETE=1; shift ;;
      --threads)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a number"
        THREADS="$2"; shift 2 ;;
      -c|--csv)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a filename"
        CSV_REPORT="$2"; shift 2 ;;
      --json)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a filename"
        JSON_REPORT="$2"; shift 2 ;;
      --log)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a filename"
        LOG_FILE="$2"; shift 2 ;;
      -v|--verbose) VERBOSE=1; shift ;;
      -q|--quiet) QUIET=1; shift ;;
      --email)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires an email address"
        EMAIL_REPORT="$2"; shift 2 ;;
      -s|--sha256) HASH_ALGORITHM="sha256sum"; shift ;;
      --sha512) HASH_ALGORITHM="sha512sum"; shift ;;
      --backup)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a directory path"
        BACKUP_DIR="$2"; shift 2 ;;
      --exclude-list)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a filename"
        EXCLUDE_LIST_FILE="$2"; shift 2 ;;
      --resume) RESUME_STATE=1; shift ;;
      --cache) USE_CACHE=1; shift ;;
      --enable-lsof) LSOF_CHECKS=1; shift ;;  # Opt-in for slow lsof checks
      --config)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a filename"
        safe_source "$2"; shift 2 ;;
      *)
        echo -e "${RED}Unknown option: $arg${NC}"; show_help; exit 1 ;;
    esac
  done
}

save_state() {
  local state_file="$HOME/.dupefinder_state"
  local state_dups="$HOME/.dupefinder_state.dups"
  local state_checksum_file="$HOME/.dupefinder_state.cksum"
  
  [[ ! -f "$TEMP_DIR/duplicates.nul" ]] && {
    log_action "warning" "No duplicates file found to save state"
    return 1
  }
  
  cp -- "$TEMP_DIR/duplicates.nul" "$state_dups" 2>/dev/null || {
    log_action "error" "Failed to save duplicates file for resume"
    return 1
  }

  {
    echo "SEARCH_PATH=\"$SEARCH_PATH\""
    echo "OUTPUT_DIR=\"$OUTPUT_DIR\""
    echo "HASH_ALGORITHM=\"$HASH_ALGORITHM\""
    echo "SCAN_START_TIME=\"$SCAN_START_TIME\""
    echo "STATE_DUPS_FILE=\"$state_dups\""
    echo "FILES_PROCESSED=\"$FILES_PROCESSED\""
  } > "$state_file"
  
  sha256sum -- "$state_file" "$state_dups" > "$state_checksum_file" 2>/dev/null || {
    log_action "error" "Failed to create checksums for resume files"
    rm -f -- "$state_file" "$state_dups"
    return 1
  }
  
  chmod 600 "$state_file" "$state_dups" "$state_checksum_file"
  [[ $VERBOSE -eq 1 ]] && echo -e "${GREEN}State saved to ~/.dupefinder_state${NC}"
  log_action "info" "State saved for resume"
}

load_state() {
  local state_file="$HOME/.dupefinder_state"
  local state_checksum_file="$HOME/.dupefinder_state.cksum"
  
  [[ ! -f "$state_file" ]] && return 1
  
  local owner perm
  owner=$(safe_stat "$state_file" "%U")
  perm=$(safe_stat "$state_file" "%a")
  
  if [[ "$owner" != "$ME" || "$perm" != "600" ]]; then
    log_action "warning" "Unsafe resume file permissions/ownership"
    echo -e "${RED}Unsafe resume file permissions/ownership${NC}"
    return 1
  fi
  
  safe_source "$state_file"
  
  [[ -n "${STATE_DUPS_FILE:-}" && -f "$STATE_DUPS_FILE" ]] || return 1
  
  (cd "$(dirname "$state_file")" && sha256sum -c "$(basename "$state_checksum_file")") &>/dev/null || {
    log_action "error" "Resume file checksum mismatch"
    echo -e "${RED}Error: Resume file checksum mismatch${NC}"
    return 1
  }
  
  cp -- "$STATE_DUPS_FILE" "$TEMP_DIR/duplicates.nul"
  echo -e "${GREEN}Resuming previous scan...${NC}"
  log_action "info" "Resume state loaded successfully"
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION AND VALIDATION
# ═══════════════════════════════════════════════════════════════════════════
init_logging() {
  if [[ -n "$LOG_FILE" ]]; then
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ ! -w "$log_dir" && -w "/tmp" ]]; then
      echo -e "${YELLOW}Warning: Log directory '$log_dir' not writable. Using /tmp.${NC}" >&2
      LOG_FILE="/tmp/dupefinder_$$_${ME}.log"
    fi
    
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || LOG_FILE="$HOME/.dupefinder.log"
    {
      echo "$(date): DupeFinder Pro v$VERSION started by $ME"
      echo "$(date): Search path: $SEARCH_PATH"
      echo "$(date): System protection: $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    } >> "$LOG_FILE" 2>/dev/null || true
  fi
}

init_cache() {
  [[ $USE_CACHE -ne 1 ]] && return
  mkdir -p -- "$(dirname -- "$DB_CACHE")" 2>/dev/null || true
  sqlite3 "$DB_CACHE" "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;
    CREATE TABLE IF NOT EXISTS files(
      path TEXT PRIMARY KEY,
      hash TEXT NOT NULL,
      size INTEGER NOT NULL,
      mtime INTEGER NOT NULL
    );" 2>/dev/null || { echo -e "${YELLOW}Warning: cache DB init failed; disabling cache.${NC}"; USE_CACHE=0; }
}

check_dependencies() {
  if ! command -v "$HASH_ALGORITHM" &>/dev/null; then
    error_exit "$HASH_ALGORITHM not found. Try: sudo apt install coreutils"
  fi
  
  for cmd in find stat sort; do
    if ! command -v "$cmd" &>/dev/null; then
      error_exit "$cmd command not found"
    fi
  done
  
  if awk --version 2>&1 | grep -qi 'GNU Awk'; then
    AWK_BIN="awk"
  elif command -v gawk >/dev/null 2>&1; then
    AWK_BIN="gawk"
  else
    local pkg_manager_hint
    if command -v apt-get >/dev/null; then
      pkg_manager_hint="Install with: sudo apt update && sudo apt install gawk"
    elif command -v dnf >/dev/null; then
      pkg_manager_hint="Install with: sudo dnf install gawk"
    elif command -v pacman >/dev/null; then
      pkg_manager_hint="Install with: sudo pacman -S gawk"
    else
      pkg_manager_hint="Please install gawk manually."
    fi
    error_exit "GNU awk required (supports RS='\\0'). $pkg_manager_hint"
  fi
  
  command -v timeout >/dev/null 2>&1 || error_exit "'timeout' not found (usually in coreutils)."
  command -v md5sum >/dev/null 2>&1 || error_exit "'md5sum' not found (used in --fast and names)."
  command -v sha256sum >/dev/null 2>&1 || error_exit "'sha256sum' not found."
  
  if [[ $USE_TRASH -eq 1 ]] && ! command -v trash-put &>/dev/null; then
    echo -e "${YELLOW}Warning: trash-cli not installed. Falling back to rm.${NC}"
    USE_TRASH=0
  fi
  
  if [[ -n "$JSON_REPORT" ]] && ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}Warning: jq not installed. JSON report will be basic format.${NC}"
  fi
  
  if [[ $FUZZY_MATCH -eq 1 ]] && ! command -v ssdeep &>/dev/null; then
    echo -e "${YELLOW}Warning: ssdeep not found. Fuzzy matching disabled.${NC}"
    FUZZY_MATCH=0
  fi
  
  if [[ -n "$EMAIL_REPORT" ]] && ! [[ -n "$MAIL_BIN" ]]; then
    echo -e "${YELLOW}Warning: 'mail' or 'mailx' not found. Email reports disabled.${NC}"
    EMAIL_REPORT=""
  fi
  
  if [[ $USE_CACHE -eq 1 ]] && ! command -v sqlite3 &>/dev/null; then
    echo -e "${YELLOW}Warning: sqlite3 not found. File cache disabled.${NC}"
    USE_CACHE=0
  fi
}

validate_inputs() {
  [[ ! -d "$SEARCH_PATH" ]] && error_exit "Search path does not exist: $SEARCH_PATH"
  [[ ! -r "$SEARCH_PATH" ]] && error_exit "Search path is not readable: $SEARCH_PATH"
  
  mkdir -p -- "$OUTPUT_DIR" 2>/dev/null || error_exit "Cannot create output directory: $OUTPUT_DIR"
  [[ ! -w "$OUTPUT_DIR" ]] && error_exit "Cannot write to output directory: $OUTPUT_DIR"
  
  if [[ $THREADS -eq 0 ]]; then
    THREADS=$(nproc 2>/dev/null || echo 4)
  fi
  
  if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || [[ "$THREADS" -lt 1 ]]; then
    THREADS=4
    [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}Invalid thread count, using $THREADS threads${NC}"
  fi
  
  [[ $KEEP_NEWEST -eq 1 && $KEEP_OLDEST -eq 1 ]] && \
    error_exit "Cannot use both --keep-newest and --keep-oldest"
  
  if [[ -n "$QUARANTINE_DIR" ]]; then
    mkdir -p -- "$QUARANTINE_DIR" 2>/dev/null || error_exit "Cannot create quarantine directory"
    [[ ! -w "$QUARANTINE_DIR" ]] && error_exit "Quarantine directory not writable"
  fi
  
  if [[ -n "$BACKUP_DIR" ]]; then
    mkdir -p -- "$BACKUP_DIR" 2>/dev/null || error_exit "Cannot create backup directory"
    [[ ! -w "$BACKUP_DIR" ]] && error_exit "Backup directory not writable"
  fi
  
  if [[ -n "$EXCLUDE_LIST_FILE" && -f "$EXCLUDE_LIST_FILE" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" && ! "$line" =~ ^# ]] && EXCLUDE_PATHS+=("$line")
    done < "$EXCLUDE_LIST_FILE"
  fi
  
  if [[ $SKIP_SYSTEM_FOLDERS -eq 1 ]]; then
    for sys_folder in "${SYSTEM_FOLDERS[@]}"; do
      if [[ -d "$sys_folder" ]]; then
        local already_excluded=0
        for ex in "${EXCLUDE_PATHS[@]}"; do
          [[ "$ex" == "$sys_folder" ]] && already_excluded=1 && break
        done
        [[ $already_excluded -eq 0 ]] && EXCLUDE_PATHS+=("$sys_folder")
      fi
    done
    [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Excluding system folders${NC}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# FILE DISCOVERY (IMPROVED)
# ═══════════════════════════════════════════════════════════════════════════
find_files() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Searching filesystem for files...${NC}"
  
  local find_cmd="find"
  local -a args=()

  [[ $FOLLOW_SYMLINKS -eq 1 ]] && args+=(-L)
  
  args+=("$SEARCH_PATH")
  
  [[ -n "$MAX_DEPTH" ]] && args+=(-maxdepth "$MAX_DEPTH")
  
  # Build exclusion list for find command
  if [[ ${#EXCLUDE_PATHS[@]} -gt 0 || $HIDDEN_FILES -eq 0 ]]; then
    args+=( \( )
    local first=1
    # Exclude hidden directories if not including hidden files
    if [[ $HIDDEN_FILES -eq 0 ]]; then
      args+=( -name '.*' )
      first=0
    fi
    # Add each exclusion path
    for ex in "${EXCLUDE_PATHS[@]}"; do
      # Normalize path - remove trailing slash if present
      ex="${ex%/}"
      if [[ $first -eq 1 ]]; then
        args+=( -path "$ex" )
        first=0
      else
        args+=( -o -path "$ex" )
      fi
      # Also exclude subdirectories of the excluded path
      args+=( -o -path "$ex/*" )
    done
    args+=( \) -prune -o )
  fi

  args+=(-type f)
  # find -size +Nc means "strictly greater than N", so use MIN_SIZE-1 to include files of exactly MIN_SIZE
  if [[ $MIN_SIZE -gt 1 ]]; then
    args+=(-size "+$((MIN_SIZE - 1))c")
  elif [[ $MIN_SIZE -eq 1 ]]; then
    # For MIN_SIZE=1, we want files >= 1 byte (exclude empty files)
    args+=(-size "+0c")
  fi
  # find -size -Nc means "strictly less than N", so use MAX_SIZE+1 to include files of exactly MAX_SIZE
  [[ -n "$MAX_SIZE" ]] && args+=(-size "-$((MAX_SIZE + 1))c")

  if [[ ${#FILE_PATTERN[@]} -gt 0 ]]; then
    args+=( \( )
    local firstp=1
    for pat in "${FILE_PATTERN[@]}"; do
      if [[ $firstp -eq 1 ]]; then
        args+=(-name "$pat")
        firstp=0
      else
        args+=( -o -name "$pat" )
      fi
    done
    args+=( \) )
  fi

  args+=(-print0)
  
  if ! "$find_cmd" "${args[@]}" 2>/dev/null > "$TEMP_DIR/files.list"; then
    log_action "error" "Find command failed"
    [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Warning: Some directories could not be accessed${NC}"
  fi
  
  if [[ ! -s "$TEMP_DIR/files.list" ]]; then
    [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}No files matched criteria.${NC}"
    TOTAL_FILES=0
    return 1
  fi
  
  TOTAL_FILES=$(tr -cd '\0' < "$TEMP_DIR/files.list" | wc -c)
  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}Found $TOTAL_FILES files to process${NC}"
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# HASH CALCULATION - Standalone worker for xargs parallel processing
# ═══════════════════════════════════════════════════════════════════════════

# SQL escape helper - must be exported for xargs worker
_sql_escape() {
  local str="$1"
  printf '%s' "${str//\'/\'\'}"
}
export -f _sql_escape

# Standalone hash worker function for xargs - outputs null-terminated hash records
# This is called by xargs with file path as argument
# Supports caching when DUPEFINDER_USE_CACHE=1 and DUPEFINDER_DB_CACHE is set
_hash_worker() {
  local file="$1"
  local algo="$DUPEFINDER_ALGO"
  local fast="$DUPEFINDER_FAST"
  local use_cache="${DUPEFINDER_USE_CACHE:-0}"
  local db_cache="$DUPEFINDER_DB_CACHE"
  local delim=$'\t'

  [[ ! -f "$file" ]] && return 1

  # Single stat call for both mtime and size (avoids double syscall)
  local stat_output mtime size
  stat_output=$(stat -c "%Y %s" -- "$file" 2>/dev/null) || return 1
  read -r mtime size <<< "$stat_output"

  local result=""
  local hash_val=""

  # Check cache first if enabled
  if [[ "$use_cache" == "1" && -n "$db_cache" && -f "$db_cache" ]]; then
    local sql_path
    sql_path=$(_sql_escape "$file")
    local cached_hash
    cached_hash=$(sqlite3 "$db_cache" "SELECT hash FROM files WHERE path='$sql_path' AND mtime=$mtime AND size=$size;" 2>/dev/null)
    if [[ -n "$cached_hash" ]]; then
      result="${cached_hash}${delim}${size}${delim}${mtime}${delim}${file}"
      printf '%s\0' "$result"
      return 0
    fi
  fi

  # Calculate hash
  if [[ "$fast" == "1" ]]; then
    # Fast mode: Hash first 64KB of the file
    local partial_hash
    partial_hash=$(head -c 65536 -- "$file" 2>/dev/null | md5sum | cut -d' ' -f1)
    [[ -z "$partial_hash" ]] && return 1
    hash_val="${size}_${partial_hash}"
    result="${hash_val}${delim}${size}${delim}${mtime}${delim}${file}"
  else
    local hash
    hash=$(timeout "${DUPEFINDER_TIMEOUT:-30}" "$algo" -- "$file" 2>/dev/null | cut -d' ' -f1)
    [[ -z "$hash" ]] && return 1
    hash_val="$hash"
    result="${hash_val}${delim}${size}${delim}${mtime}${delim}${file}"
  fi

  # Store in cache if enabled
  if [[ "$use_cache" == "1" && -n "$db_cache" && -n "$hash_val" ]]; then
    local sql_path
    sql_path=$(_sql_escape "$file")
    sqlite3 "$db_cache" "INSERT OR REPLACE INTO files (path, hash, size, mtime) VALUES ('$sql_path', '$hash_val', $size, $mtime);" 2>/dev/null || true
  fi

  [[ -n "$result" ]] && printf '%s\0' "$result"
}

# Export the worker function for xargs
export -f _hash_worker

calculate_hashes() {
  local mode_text="standard"
  [[ $FAST_MODE -eq 1 ]] && mode_text="fast"
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Calculating file hashes ($mode_text mode, threads: $THREADS)...${NC}"

  [[ $TOTAL_FILES -eq 0 ]] && return

  local available_mb
  available_mb=$(get_available_mb 2>/dev/null || echo 0)
  if [[ "$available_mb" -gt 0 && "$available_mb" -lt 500 ]]; then
    local new_threads=$(( THREADS>1 ? THREADS/2 : 1 ))
    if [[ "$new_threads" -ge 1 ]]; then
      THREADS="$new_threads"
      [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}Reduced to $THREADS threads due to low memory (${available_mb}MB free).${NC}"
    fi
  fi

  local hashes_temp="$TEMP_DIR/hashes.temp"

  # Export variables needed by the worker function
  export DUPEFINDER_ALGO="$HASH_ALGORITHM"
  export DUPEFINDER_FAST="$FAST_MODE"
  export DUPEFINDER_TIMEOUT="$HASH_TIMEOUT"
  export DUPEFINDER_USE_CACHE="$USE_CACHE"
  export DUPEFINDER_DB_CACHE="$DB_CACHE"

  # Use xargs for parallel processing - much more efficient than spawning subshells
  # This eliminates the "fork bomb" issue by using a process pool
  if [[ $VERBOSE -eq 1 && $QUIET -eq 0 ]]; then
    echo -e "${DIM}Processing files with xargs -P $THREADS...${NC}"
    [[ $USE_CACHE -eq 1 ]] && echo -e "${DIM}Cache enabled: $DB_CACHE${NC}"
  fi

  # xargs -0: null-terminated input, -P: parallel processes, -n1: one file per invocation
  # The worker outputs null-terminated records which are collected into hashes.temp
  if ! xargs -0 -P "$THREADS" -n 1 bash -c '_hash_worker "$@"' _ < "$TEMP_DIR/files.list" > "$hashes_temp" 2>/dev/null; then
    log_action "warning" "Some files may have failed to hash"
  fi

  # Count processed files
  FILES_PROCESSED=$TOTAL_FILES

  # Clean up exported variables
  unset DUPEFINDER_ALGO DUPEFINDER_FAST DUPEFINDER_TIMEOUT DUPEFINDER_USE_CACHE DUPEFINDER_DB_CACHE

  if [[ ! -s "$hashes_temp" ]]; then
    echo -e "${RED}Error: No files were successfully hashed.${NC}"
    return 1
  fi

  mv -- "$hashes_temp" "$TEMP_DIR/hashes.txt"
  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}Hash calculation completed${NC}"

  # Count hash errors by comparing input vs output
  local hashed_count
  hashed_count=$(tr -cd '\0' < "$TEMP_DIR/hashes.txt" | wc -c)
  HASH_ERRORS=$((TOTAL_FILES - hashed_count))
  [[ $HASH_ERRORS -gt 0 ]] && echo -e "${YELLOW}Warning: $HASH_ERRORS files could not be hashed${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════
# DUPLICATE DETECTION (IMPROVED AWK PROCESSING)
# ═══════════════════════════════════════════════════════════════════════════
find_duplicates() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Analyzing duplicates...${NC}"
  
  [[ ! -s "$TEMP_DIR/hashes.txt" ]] && {
    echo -e "${YELLOW}No hashes found to analyze${NC}"
    return 1
  }
  
  sort -z -t"$DELIM" -k1,1 < "$TEMP_DIR/hashes.txt" | \
  "$AWK_BIN" -v DELIM="$DELIM" -v RS='\0' -v ORS='\0' '
  BEGIN {
    prev_hash = "";
    dup_count = 0;
    wasted = 0;
    gcount = 0;
    in_group = 0;
  }
  
  {
    if (length($0) == 0) next;
    
    split($0, a, DELIM);
    if (length(a) < 4) next;
    
    hash = a[1];
    size = a[2];
    mtime = a[3];
    file = a[4];
    
    if (length(hash) == 0 || length(file) == 0) next;
    if (size !~ /^[0-9]+$/) next;
    
    if (hash == prev_hash && prev_hash != "") {
      if (in_group == 0) {
        gcount++;
        in_group = 1;
        printf "G" DELIM prev_hash DELIM prev_file "|" prev_size "|" prev_mtime ORS;
      }
      printf "F" DELIM file "|" size "|" mtime ORS;
      dup_count++;
      wasted += size;
    } else {
      in_group = 0;
    }
    
    prev_hash = hash;
    prev_file = file;
    prev_size = size;
    prev_mtime = mtime;
  }
  
  END {
    # FIXED: Only emit the final stats line, not a trailing group record
    printf "S" DELIM dup_count DELIM wasted DELIM gcount ORS;
  }' > "$TEMP_DIR/duplicates.nul"
  
  local stats
  stats=$(cat "$TEMP_DIR/duplicates.nul" | tr '\0' '\n' | grep "^S" | tail -1 | cut -d"$DELIM" -f2-)
  
  if [[ -n "$stats" ]]; then
    TOTAL_DUPLICATES=$(echo "$stats" | cut -d"$DELIM" -f1)
    TOTAL_SPACE_WASTED=$(echo "$stats" | cut -d"$DELIM" -f2)
    TOTAL_DUPLICATE_GROUPS=$(echo "$stats" | cut -d"$DELIM" -f3)
    
    : ${TOTAL_DUPLICATES:=0}
    : ${TOTAL_SPACE_WASTED:=0}
    : ${TOTAL_DUPLICATE_GROUPS:=0}
  fi
  
  if [[ ${TOTAL_DUPLICATE_GROUPS:-0} -eq 0 ]]; then
    [[ $QUIET -eq 0 ]] && echo -e "${GREEN}No duplicate groups found${NC}"
    return 1
  fi
  
  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}Found ${TOTAL_DUPLICATE_GROUPS} groups with ${TOTAL_DUPLICATES} duplicate files${NC}"
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# SMART DELETION STRATEGIES
# ═══════════════════════════════════════════════════════════════════════════
get_location_priority() {
  local path="$1"
  local priority=50
  for loc in "${!LOCATION_PRIORITY[@]}"; do
    if [[ "$path" == *"$loc"* ]]; then
      priority=${LOCATION_PRIORITY[$loc]}
      break
    fi
  done
  echo "$priority"
}

select_file_to_keep() {
  local files_arr=("$@")
  local keep_file=""
  local best_priority=999
  
  for file_info in "${files_arr[@]}"; do
    local file_path
    file_path=$(echo "$file_info" | cut -d'|' -f1)
    local priority
    priority=$(get_location_priority "$file_path")
    if (( priority < best_priority )); then
      best_priority=$priority
      keep_file="$file_path"
    fi
  done
  echo "$keep_file"
}

# ═══════════════════════════════════════════════════════════════════════════
# ENHANCED VERBOSE OUTPUT
# ═══════════════════════════════════════════════════════════════════════════
show_duplicate_details() {
  [[ $VERBOSE -eq 0 || $QUIET -eq 1 ]] && return
  if [[ ${TOTAL_DUPLICATE_GROUPS:-0} -eq 0 ]]; then
    echo -e "${YELLOW}No duplicate groups found to display.${NC}"
    return
  fi

  echo ""
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}      DUPLICATE GROUPS FOUND${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  
  local gid=0
  
  while IFS= read -r -d '' rec; do
    local type
    type=$(printf '%s' "$rec" | cut -d"$TAB" -f1)
    
    if [[ "$type" == "G" ]]; then
      local hash file_info path size mtime
      IFS="$TAB" read -r _ hash file_info <<< "$rec"
      IFS='|' read -r path size mtime <<< "$file_info"
      ((gid++))
      
      echo -e "${BOLD}${CYAN}Group $gid:${NC} Hash ${hash:0:16}..."
      echo -e "  - $(format_size "$size")   ${DIM}${path}${NC}$( is_in_system_folder "$path" && echo -e " ${YELLOW}(system)${NC}")"
    elif [[ "$type" == "F" ]]; then
      local file_info path size mtime
      IFS="$TAB" read -r _ file_info <<< "$rec"
      IFS='|' read -r path size mtime <<< "$file_info"
      echo -e "  - $(format_size "$size")   ${DIM}${path}${NC}$( is_in_system_folder "$path" && echo -e " ${YELLOW}(system)${NC}")"
    fi
  done < "$TEMP_DIR/duplicates.nul"
  echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# FILE PROCESSING AND DELETION
# ═══════════════════════════════════════════════════════════════════════════
process_duplicate_group() {
  local -a files=("$@")
  local keep_idx=0
  local keep_file keep_size
  
  [[ ${#files[@]} -lt 2 ]] && return 0

  if [[ $SMART_DELETE -eq 1 ]]; then
    local keep_path
    keep_path=$(select_file_to_keep "${files[@]}")
    for i in "${!files[@]}"; do
      local path=$(echo "${files[$i]}" | cut -d'|' -f1)
      if [[ "$path" == "$keep_path" ]]; then
        keep_idx=$i
        break
      fi
    done
  elif [[ -n "$KEEP_PATH_PRIORITY" ]]; then
    for i in "${!files[@]}"; do
      local path=$(echo "${files[$i]}" | cut -d'|' -f1)
      if [[ "$path" == "$KEEP_PATH_PRIORITY"* ]]; then
        keep_idx=$i
        break
      fi
    done
  elif [[ $KEEP_NEWEST -eq 1 ]]; then
    local newest_time=0
    for i in "${!files[@]}"; do
      local mtime=$(echo "${files[$i]}" | cut -d'|' -f3)
      if [[ $mtime -gt $newest_time ]]; then
        newest_time=$mtime
        keep_idx=$i
      fi
    done
  elif [[ $KEEP_OLDEST -eq 1 ]]; then
    local oldest_time=9999999999
    for i in "${!files[@]}"; do
      local mtime=$(echo "${files[$i]}" | cut -d'|' -f3)
      if [[ $mtime -lt $oldest_time ]]; then
        oldest_time=$mtime
        keep_idx=$i
      fi
    done
  fi
  
  keep_file=$(echo "${files[$keep_idx]}" | cut -d'|' -f1)
  keep_size=$(echo "${files[$keep_idx]}" | cut -d'|' -f2)
  
  [[ $VERBOSE -eq 1 ]] && echo -e "${GREEN}  + Keeping: $keep_file${NC}"
  
  for i in "${!files[@]}"; do
    [[ $i -eq $keep_idx ]] && continue
    
    local path size mtime
    IFS='|' read -r path size mtime <<< "${files[$i]}"
    
    if ! verify_safe_to_delete "$path"; then
      [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ! Skipped (safety): $path${NC}"
      continue
    fi
    
    if [[ $SKIP_SYSTEM_FOLDERS -eq 1 ]] && is_in_system_folder "$path"; then
      [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ! Skipped (system): $path${NC}"
      continue
    fi
    
    local is_match=1
    if [[ $VERIFY_MODE -eq 1 ]] && ! verify_identical "$keep_file" "$path"; then
      if [[ $FUZZY_MATCH -eq 1 ]] && fuzzy_match "$keep_file" "$path" "$SIMILARITY_THRESHOLD"; then
        [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ~ Matched (fuzzy): $path${NC}"
      else
        [[ $VERBOSE -eq 1 ]] && echo -e "${RED}  ! Skipped (not identical): $path${NC}"
        is_match=0
      fi
    fi

    [[ $is_match -eq 0 ]] && continue
    
    local action="skip"
    if [[ $INTERACTIVE_DELETE -eq 1 ]]; then
      echo -e "${DIM}Duplicate file:${NC} ${path}"
      echo -ne "${BOLD}[d]elete, [h]ardlink, [s]kip, [q]uit? [s]: ${NC}"
      local response; read -r -n 1 response; echo ""
      response=${response,,}
      [[ -z "$response" ]] && response="s"
      case "$response" in
        q) exit 0 ;;
        d) action="delete" ;;
        h) action="hardlink" ;;
        s) action="skip" ;;
        *) action="skip" ;;
      esac
    else
      if [[ $HARDLINK_MODE -eq 1 ]]; then action="hardlink"; fi
      if [[ -n "$QUARANTINE_DIR" ]]; then action="quarantine"; fi
      if [[ $DELETE_MODE -eq 1 ]]; then action="delete"; fi
    fi
    
    [[ "$action" == "skip" ]] && continue
    
    if [[ $DRY_RUN -eq 1 ]]; then
      if [[ "$action" == "hardlink" ]]; then
        echo -e "${YELLOW}  Would hardlink: $path -> $keep_file${NC}"
        ((FILES_HARDLINKED++))
      elif [[ "$action" == "quarantine" ]]; then
        echo -e "${YELLOW}  Would quarantine: $path${NC}"
        ((FILES_QUARANTINED++))
      elif [[ "$action" == "delete" ]]; then
        echo -e "${YELLOW}  Would delete: $path${NC}"
        ((FILES_DELETED++))
      fi
      ((SPACE_FREED+=size))
    else
      if [[ "$action" == "hardlink" ]]; then
        if ! [[ -w "$path" && -w "$(dirname -- "$path")" ]]; then
          [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ! Skipped (readonly/immutable): $path${NC}"
          log_action "warning" "Readonly/immutable: $path"
          continue
        fi

        local keep_dev dup_dev
        keep_dev=$(safe_stat "$keep_file" "%d")
        dup_dev=$(safe_stat "$path" "%d")
        if [[ "$keep_dev" == "$dup_dev" ]]; then
          if ln -f -- "$keep_file" "$path" 2>/dev/null; then
            ((FILES_HARDLINKED++))
            ((SPACE_FREED+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}  - Hardlinked: $path${NC}"
            log_action "info" "Hardlinked: $path -> $keep_file"
          else
            echo -e "${RED}  - Failed to hardlink: $path${NC}"
            log_action "error" "Failed to hardlink: $path"
          fi
        else
          echo -e "${RED}  - Cannot hardlink across filesystems: $path${NC}"
        fi
      elif [[ "$action" == "quarantine" ]]; then
        local qfile="$QUARANTINE_DIR/$(basename -- "$path")_$(date +%s)_$(printf '%s' "$path" | sha256sum | cut -c1-8)"
        if mv -- "$path" "$qfile" 2>/dev/null; then
          ((FILES_QUARANTINED++))
          ((SPACE_FREED+=size))
          [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  - Quarantined: $path${NC}"
          log_action "info" "Quarantined: $path -> $qfile"
        fi
      elif [[ "$action" == "delete" ]]; then
        # NEW: call backup_file here
        if [[ -n "$BACKUP_DIR" ]]; then
          backup_file "$path" || true
        fi

        if [[ $USE_TRASH -eq 1 ]] && command -v trash-put &>/dev/null; then
          if trash-put -- "$path" 2>/dev/null; then
            ((FILES_DELETED++))
            ((SPACE_FREED+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  - Trashed: $path${NC}"
            log_action "info" "Trashed: $path"
          fi
        else
          if rm -- "$path" 2>/dev/null; then
            ((FILES_DELETED++))
            ((SPACE_FREED+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${RED}  - Deleted: $path${NC}"
            log_action "info" "Deleted: $path"
          fi
        fi
      fi
    fi
  done
}

delete_duplicates() {
  if [[ $DELETE_MODE -eq 0 && $HARDLINK_MODE -eq 0 && -z "$QUARANTINE_DIR" ]]; then
    return
  fi

  # Verify duplicates file exists and is readable
  if [[ ! -f "$TEMP_DIR/duplicates.nul" || ! -r "$TEMP_DIR/duplicates.nul" ]]; then
    log_action "error" "Duplicates file not found or not readable"
    echo -e "${RED}Error: Duplicates file not found or not readable${NC}"
    return 1
  fi

  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Processing duplicate files...${NC}"

  local gid=0
  local -a current_group=()

  while IFS= read -r -d '' rec; do
    local type
    type=$(printf '%s' "$rec" | cut -d"$TAB" -f1)
    
    if [[ "$type" == "G" ]]; then
      if [[ ${#current_group[@]} -gt 1 ]]; then
        ((gid++))
        [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Processing group $gid...${NC}"
        process_duplicate_group "${current_group[@]}"
      fi
      current_group=()
      local file_info
      IFS="$DELIM" read -r _ _ file_info <<< "$rec"
      current_group+=("$file_info")
    elif [[ "$type" == "F" ]]; then
      local file_info
      IFS="$DELIM" read -r _ file_info <<< "$rec"
      current_group+=("$file_info")
    fi
  done < "$TEMP_DIR/duplicates.nul"
  
  if [[ ${#current_group[@]} -gt 1 ]]; then
    ((gid++))
    [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Processing group $gid...${NC}"
    process_duplicate_group "${current_group[@]}"
  fi
  
  if [[ $QUIET -eq 0 ]]; then
    echo -e "${GREEN}Processing completed:${NC}"
    echo -e "  ${GREEN}Files deleted: ${FILES_DELETED}${NC}"
    echo -e "  ${GREEN}Files hardlinked: ${FILES_HARDLINKED}${NC}"
    echo -e "  ${GREEN}Files quarantined: ${FILES_QUARANTINED}${NC}"
    echo -e "  ${GREEN}Space freed: $(format_size "${SPACE_FREED}")${NC}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# REPORT GENERATION
# ═══════════════════════════════════════════════════════════════════════════
generate_html_report() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Generating HTML report...${NC}"
  local report_file="$OUTPUT_DIR/$HTML_REPORT"
  
  cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>DupeFinder Pro Report</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;background:#f1f3f5;margin:0}
.container{max-width:1200px;margin:40px auto;background:#fff;border-radius:12px;box-shadow:0 20px 60px rgba(0,0,0,0.1);overflow:hidden}
header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:#fff;padding:24px 28px}
h1{margin:0;font-size:28px}
.subtitle{opacity:.9;margin-top:6px}
.safety-badge{background:#4caf50;color:#fff;padding:4px 8px;border-radius:4px;font-size:12px;margin-left:10px}
.safety-warning{background:#ff9800}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;padding:20px;background:#f8f9fa}
.card{background:#fff;border:1px solid #eceff1;border-radius:8px;padding:16px;text-align:center}
.val{font-size:22px;color:#667eea;font-weight:700}
.label{color:#6c757d;text-transform:uppercase;font-size:12px;margin-top:4px}
.group{border-top:1px solid #f1f3f5;cursor:pointer}
.group:hover{background:#fafbfc}
.group .hdr{padding:12px 16px;font-weight:600}
.group .files{padding:6px 16px 16px 16px;display:none}
.file{padding:8px 0;border-bottom:1px solid #f6f7f8;font-family:monospace;font-size:12px}
.file:last-child{border-bottom:0}
.show .files{display:block}
.system-file{color:#d32f2f}
.footer{padding:16px 20px;background:#fff;border-top:1px solid #eceff1;text-align:center;color:#6c757d;font-size:12px}
</style>
<script>
function toggle(id){var el=document.getElementById(id);if(el){el.classList.toggle('show');}}
</script>
</head>
<body>
<div class="container">
EOF

  cat >> "$report_file" << EOF
<header>
  <h1>DupeFinder Pro Report
    $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo '<span class="safety-badge">System Protected</span>' || echo '<span class="safety-badge safety-warning">Full Scan</span>')
  </h1>
  <div class="subtitle">by ${AUTHOR} | Generated: $(date '+%B %d, %Y %H:%M:%S')</div>
</header>
<div class="stats">
  <div class="card"><div class="val">${TOTAL_FILES:-0}</div><div class="label">Files Scanned</div></div>
  <div class="card"><div class="val">${TOTAL_DUPLICATES:-0}</div><div class="label">Duplicates Found</div></div>
  <div class="card"><div class="val">${TOTAL_DUPLICATE_GROUPS:-0}</div><div class="label">Duplicate Groups</div></div>
  <div class="card"><div class="val">$(format_size "${TOTAL_SPACE_WASTED:-0}")</div><div class="label">Space Wasted</div></div>
</div>
<div>
EOF
  
  local gid=0
  local opened=0
  
  while IFS= read -r -d '' rec; do
    local type
    type=$(printf '%s' "$rec" | cut -d"$TAB" -f1)
    
    if [[ "$type" == "G" ]]; then
      local hash file_info
      IFS="$TAB" read -r _ hash file_info <<< "$rec"
      
      if [[ $opened -eq 1 ]]; then
        echo "</div></div>" >> "$report_file"
      fi
      opened=1
      ((gid++))
      
      local path size mtime
      IFS='|' read -r path size mtime <<< "$file_info"
      
      echo "<div id=\"g$gid\" class=\"group\" onclick=\"toggle('g$gid')\">" >> "$report_file"
      echo "<div class=\"hdr\">Group $gid (Hash: ${hash:0:16}...)</div>" >> "$report_file"
      echo "<div class=\"files\">" >> "$report_file"
      
      local class=""
      is_in_system_folder "$path" && class="system-file"
      printf '<div class="file %s">%s<br>Size: %s</div>\n' \
        "$class" \
        "$(printf '%s' "$path" | sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/"/\&quot;/g;s/'"'"'/\&#39;/g')" \
        "$(format_size "$size")" >> "$report_file"
        
    elif [[ "$type" == "F" ]]; then
      local file_info
      IFS="$TAB" read -r _ file_info <<< "$rec"
      local path size mtime
      IFS='|' read -r path size mtime <<< "$file_info"
      local class=""
      is_in_system_folder "$path" && class="system-file"
      printf '<div class="file %s">%s<br>Size: %s</div>\n' \
        "$class" \
        "$(printf '%s' "$path" | sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/"/\&quot;/g;s/'"'"'/\&#39;/g')" \
        "$(format_size "$size")" >> "$report_file"
    fi
  done < "$TEMP_DIR/duplicates.nul"
  
  if [[ $opened -eq 1 ]]; then
    echo "</div></div>" >> "$report_file"
  fi

  cat >> "$report_file" << EOF
</div>
<div class="footer">
  Report generated with DupeFinder Pro v${VERSION} | System protection: $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "enabled" || echo "disabled")
</div>
</div>
</body>
</html>
EOF
  
  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✓ HTML report saved: $report_file${NC}"
}

generate_csv_report() {
  [[ -z "$CSV_REPORT" ]] && return
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Generating CSV report...${NC}"
  
  local csv="$OUTPUT_DIR/$CSV_REPORT"
  echo "Hash,File Path,Size (bytes),Size (human),Group ID,System File" > "$csv"
  
  local gid=0
  local current_hash=""
  
  while IFS= read -r -d '' rec; do
    local type
    type=$(printf '%s' "$rec" | cut -d"$TAB" -f1)
    
    if [[ "$type" == "G" ]]; then
      local hash file_info
      IFS="$TAB" read -r _ hash file_info <<< "$rec"
      ((gid++))
      current_hash="$hash"
      local path size mtime
      IFS='|' read -r path size mtime <<< "$file_info"
      local is_system="No"
      is_in_system_folder "$path" && is_system="Yes"
      printf '%s,"%s",%s,"%s",%s,%s\n' "$current_hash" "${path//\"/\"\"}" "$size" "$(format_size "$size")" "$gid" "$is_system" >> "$csv"
    elif [[ "$type" == "F" ]]; then
      local file_info
      IFS="$TAB" read -r _ file_info <<< "$rec"
      local path size mtime
      IFS='|' read -r path size mtime <<< "$file_info"
      local is_system="No"
      is_in_system_folder "$path" && is_system="Yes"
      printf '%s,"%s",%s,"%s",%s,%s\n' "$current_hash" "${path//\"/\"\"}" "$size" "$(format_size "$size")" "$gid" "$is_system" >> "$csv"
    fi
  done < "$TEMP_DIR/duplicates.nul"

  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✓ CSV report saved: $csv${NC}"
}

# Safely escape a string for JSON output
# Uses jq when available for proper handling of newlines, tabs, and control chars
json_escape_string() {
  local str="$1"
  if command -v jq >/dev/null 2>&1; then
    # jq handles all escaping properly including newlines, tabs, control chars
    printf '%s' "$str" | jq -Rs '.'
  else
    # Manual fallback - escape backslash, quotes, and control characters
    local escaped="${str//\\/\\\\}"    # Backslash
    escaped="${escaped//\"/\\\"}"      # Double quote
    escaped="${escaped//$'\n'/\\n}"    # Newline
    escaped="${escaped//$'\r'/\\r}"    # Carriage return
    escaped="${escaped//$'\t'/\\t}"    # Tab
    printf '"%s"' "$escaped"
  fi
}

generate_json_report() {
  [[ -z "$JSON_REPORT" ]] && return
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Generating JSON report...${NC}"

  local json="$OUTPUT_DIR/$JSON_REPORT"
  local use_jq=0
  command -v jq >/dev/null 2>&1 && use_jq=1

  # Escape metadata strings
  local escaped_search_path escaped_author
  escaped_search_path=$(json_escape_string "$SEARCH_PATH")
  escaped_author=$(json_escape_string "$AUTHOR")

  cat > "$json" << EOF
{
  "metadata": {
    "version": "$VERSION",
    "author": ${escaped_author},
    "generated": "$(date -Iseconds 2>/dev/null || date)",
    "search_path": ${escaped_search_path},
    "total_files": ${TOTAL_FILES:-0},
    "total_duplicates": ${TOTAL_DUPLICATES:-0},
    "total_groups": ${TOTAL_DUPLICATE_GROUPS:-0},
    "space_wasted": ${TOTAL_SPACE_WASTED:-0},
    "hash_algorithm": "${HASH_ALGORITHM%%sum}",
    "system_protection": $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "true" || echo "false")
  },
  "groups": [
EOF

  local gid=0
  local first_group=1

  while IFS= read -r -d '' rec; do
    local type
    type=$(printf '%s' "$rec" | cut -d"$TAB" -f1)

    if [[ "$type" == "G" ]]; then
      local hash file_info
      IFS="$TAB" read -r _ hash file_info <<< "$rec"

      if [[ $first_group -eq 0 ]]; then
        echo "      ]" >> "$json"
        echo "    }," >> "$json"
      fi
      first_group=0
      ((gid++))

      echo "    {" >> "$json"
      echo "      \"id\": $gid," >> "$json"
      echo "      \"hash\": \"$hash\"," >> "$json"
      echo "      \"files\": [" >> "$json"

      local path size mtime
      IFS='|' read -r path size mtime <<< "$file_info"
      local is_system="false"
      is_in_system_folder "$path" && is_system="true"
      local jpath
      jpath=$(json_escape_string "$path")
      printf '        {"path": %s, "size": %s, "system": %s}' "$jpath" "$size" "$is_system" >> "$json"

    elif [[ "$type" == "F" ]]; then
      local file_info
      IFS="$TAB" read -r _ file_info <<< "$rec"
      local path size mtime
      IFS='|' read -r path size mtime <<< "$file_info"
      local is_system="false"
      is_in_system_folder "$path" && is_system="true"
      local jpath
      jpath=$(json_escape_string "$path")
      printf ',\n        {"path": %s, "size": %s, "system": %s}' "$jpath" "$size" "$is_system" >> "$json"
    fi
  done < "$TEMP_DIR/duplicates.nul"

  if [[ $first_group -eq 0 ]]; then
    echo "      ]" >> "$json"
    echo "    }" >> "$json"
  fi
  echo "  ]" >> "$json"
  echo "}" >> "$json"

  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✓ JSON report saved: $json${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY AND STATISTICS
# ═══════════════════════════════════════════════════════════════════════════
calculate_duration() {
  local duration=$((SCAN_END_TIME - SCAN_START_TIME))
  local hours=$((duration/3600))
  local minutes=$(((duration%3600)/60))
  local seconds=$((duration%60))
  if (( hours > 0 )); then 
    printf "%dh %dm %ds" "$hours" "$minutes" "$seconds"
  elif (( minutes > 0 )); then 
    printf "%dm %ds" "$minutes" "$seconds"
  else 
    printf "%ds" "$seconds"
  fi
}

send_email_report() {
  if [[ -n "$EMAIL_REPORT" && -f "$OUTPUT_DIR/$HTML_REPORT" ]]; then
    if [[ -n "$MAIL_BIN" ]]; then
      if "$MAIL_BIN" -a "Content-Type: text/html; charset=UTF-8" -s "DupeFinder Pro Report" "$EMAIL_REPORT" < "$OUTPUT_DIR/$HTML_REPORT" 2>/dev/null; then
        log_action "info" "Report emailed to $EMAIL_REPORT"
        [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✓ Email report sent to $EMAIL_REPORT${NC}"
      else
        log_action "error" "Failed to email report to $EMAIL_REPORT"
        [[ $QUIET -eq 0 ]] && echo -e "${RED}✗ Failed to send email report.${NC}"
      fi
    else
      log_action "warning" "Email report failed: 'mail' or 'mailx' command not found"
      [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Warning: 'mail' command not found. Email reports disabled.${NC}"
    fi
  fi
}

show_summary() {
  [[ $QUIET -eq 1 ]] && return
  
  echo ""
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}      SCAN SUMMARY${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}Search Path:${NC}               $SEARCH_PATH"
  echo -e "${CYAN}System Protection:${NC}      $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
  echo -e "${CYAN}Files Scanned:${NC}          ${TOTAL_FILES:-0}"
  echo -e "${CYAN}Duplicates Found:${NC}       ${TOTAL_DUPLICATES:-0}"
  echo -e "${CYAN}Duplicate Groups:${NC}       ${TOTAL_DUPLICATE_GROUPS:-0}"
  echo -e "${CYAN}Space Wasted:${NC}           $(format_size "${TOTAL_SPACE_WASTED:-0}")"
  
  if [[ ${FILES_DELETED:-0} -gt 0 || ${FILES_HARDLINKED:-0} -gt 0 || ${FILES_QUARANTINED:-0} -gt 0 ]]; then
    echo -e "${CYAN}Files Processed:${NC}          $((${FILES_DELETED:-0} + ${FILES_HARDLINKED:-0} + ${FILES_QUARANTINED:-0}))"
    echo -e "${CYAN}Space Freed:${NC}              $(format_size "${SPACE_FREED:-0}")"
    [[ ${FILES_DELETED:-0} -gt 0 ]] && echo -e "${DIM}  - Deleted: ${FILES_DELETED}${NC}"
    [[ ${FILES_HARDLINKED:-0} -gt 0 ]] && echo -e "${DIM}  - Hardlinked: ${FILES_HARDLINKED}${NC}"
    [[ ${FILES_QUARANTINED:-0} -gt 0 ]] && echo -e "${DIM}  - Quarantined: ${FILES_QUARANTINED}${NC}"
  fi
  
  [[ -n "$SCAN_START_TIME" && -n "$SCAN_END_TIME" ]] && \
    echo -e "${CYAN}Scan Duration:${NC}            $(calculate_duration)"
  echo -e "${CYAN}Hash Algorithm:${NC}           ${HASH_ALGORITHM%%sum}"
  [[ $FAST_MODE -eq 1 ]] && echo -e "${DIM}    (Fast mode: size + first 64KB hash)${NC}"
  echo -e "${CYAN}Threads Used:${NC}             $THREADS"
  [[ $HASH_ERRORS -gt 0 ]] && echo -e "${YELLOW}Hash Errors:${NC}              $HASH_ERRORS"
  echo -e "${WHITE}─────────────────────────────────────────────────────────${NC}"
  echo -e "${CYAN}HTML Report:${NC}              $OUTPUT_DIR/$HTML_REPORT"
  [[ -n "$CSV_REPORT" ]] && \
    echo -e "${CYAN}CSV Report:${NC}             ${OUTPUT_DIR}/$CSV_REPORT"
  [[ -n "$JSON_REPORT" ]] && \
    echo -e "${CYAN}JSON Report:${NC}            ${OUTPUT_DIR}/$JSON_REPORT"
  [[ -n "$LOG_FILE" ]] && \
    echo -e "${CYAN}Log File:${NC}               ${LOG_FILE}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════
main() {
  # Set locale for consistent sorting
  export LC_ALL=C
  
  parse_arguments "$@"
  check_dependencies
  
  if [[ $FAST_MODE -eq 1 && ($DELETE_MODE -eq 1 || $HARDLINK_MODE -eq 1 || -n "$QUARANTINE_DIR") && $VERIFY_MODE -eq 0 ]]; then
    [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Fast mode with deletion detected; enabling --verify for safety.${NC}"
    VERIFY_MODE=1
  fi
  
  if [[ $FAST_MODE -eq 1 && $VERIFY_MODE -eq 0 && $QUIET -eq 0 ]]; then
    echo -e "${YELLOW}Warning: Fast mode may report false positives. Use --verify for accuracy.${NC}"
  fi
  
  create_temp_dir
  init_cache
  
  SCAN_START_TIME=$(date +%s)
  init_logging
  
  [[ $QUIET -eq 0 ]] && show_header
  
  validate_inputs
  
  if [[ $RESUME_STATE -eq 1 ]] && load_state; then
    echo -e "${GREEN}Resuming from saved state...${NC}"
  else
    if ! find_files; then
      [[ $QUIET -eq 0 ]] && echo -e "${GREEN}No files found matching criteria.${NC}"
      SCAN_END_TIME=$(date +%s)
      show_summary
      exit 0
    fi
    
    if ! calculate_hashes; then
      echo -e "${RED}Hash calculation failed.${NC}"
      SCAN_END_TIME=$(date +%s)
      show_summary
      exit 1
    fi
    
    if ! find_duplicates; then
      [[ $QUIET -eq 0 ]] && echo -e "${GREEN}No duplicates found.${NC}"
      SCAN_END_TIME=$(date +%s)
      show_summary
      exit 0
    fi
  fi
  
  show_duplicate_details
  show_safety_summary
  delete_duplicates
  generate_html_report
  generate_csv_report
  generate_json_report
  send_email_report
  
  SCAN_END_TIME=$(date +%s)
  show_summary
  
  [[ $QUIET -eq 0 ]] && echo -e "\n${GREEN}Scan completed successfully!${NC}"
  [[ $QUIET -eq 0 ]] && echo -e "${DIM}DupeFinder Pro v$VERSION by $AUTHOR${NC}\n"
}

# ═══════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════
main "$@"
exit 0
