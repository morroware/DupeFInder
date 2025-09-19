#!/usr/bin/env bash
#############################################################################
# DupeFinder Pro - Advanced Duplicate File Manager for Linux
# Version: 1.1.4 (Final)
# Author: Seth Morrow, with contributions by Gemini and Claude
# License: MIT
#
# Description:
#   Production-ready duplicate file finder with comprehensive safety checks,
#   robust error handling, and reliable operation for large-scale deployments.
#
# Major improvements in v1.1.0:
# - Truly atomic parallel hashing with named pipes
# - GNU tool detection and verification
# - Atomic hardlink operations (no rm/ln race)
# - Proper hidden directory pruning
# - Non-interactive mode safety checks
# - Enhanced root ownership detection
# - Improved memory checking with /proc fallback
# - Better quarantine collision avoidance
#
# v1.1.4 Patch Notes:
# - FIXED: Missing color constants, which caused crashes with nounset.
# - FIXED: Broken `safe_source` loop logic to correctly parse config files.
# - FIXED: GNU `awk` detection logic to correctly identify default `awk`.
# - FIXED: JSON report generation to produce valid output with proper group closing.
# - HARDENED: `find` command now explicitly prunes excluded directories and their children.
# - HARDENED: JSON output now safely escapes backslashes in file paths.
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
LSOF_CHECKS=1
TEMP_DIR=""
MEMORY_CHECK_INTERVAL=100  # Check memory every N files
readonly VERSION="1.1.4"
readonly AUTHOR="Seth Morrow"
readonly MAX_MEMORY_MB=2048 # Maximum memory usage in MB
readonly HASH_TIMEOUT=30    # Timeout for hash calculation per file
readonly MAX_RETRIES=3      # Maximum retries for failed operations
AWK_BIN="awk"               # Will be set to gawk if available


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
  
  if [[ ! -f "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || return
    touch "$LOG_FILE" 2>/dev/null || return
  fi
  
  # HARDENED: Sanitize log entries to prevent log injection
  local msg
  printf -v msg "%q" "$2"
  echo "$(date +'%Y-%m-%d %H:%M:%S') [${level^^}] $msg" >> "$LOG_FILE"
}

check_memory_usage() {
  local available_mb=""
  if command -v free >/dev/null 2>&1; then
    available_mb=$(free -m | awk '/^Mem:/ {print $7}')
  elif [[ -r /proc/meminfo ]]; then
    # MemAvailable in kB
    local kb
    kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
    [[ -n "$kb" ]] && available_mb=$(( kb / 1024 ))
  fi
  
  if [[ -n "$available_mb" ]] && [[ "$available_mb" -lt 100 ]]; then
    log_action "warning" "Low memory: ${available_mb}MB available"
    echo -e "${YELLOW}Warning: Low memory (${available_mb}MB available)${NC}" >&2
    return 1
  fi
  
  return 0
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

  # Ensure all background jobs are terminated
  local pids
  pids=$(jobs -p)
  if [[ -n "$pids" ]]; then
    kill $pids 2>/dev/null || true
  fi
  wait 2>/dev/null || true

  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR" 2>/dev/null || true
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
# HARDENED: Add trap to kill all background processes on EXIT
trap "cleanup; kill 0" EXIT

# ═══════════════════════════════════════════════════════════════════════════
# SECURE TEMPORARY DIRECTORY CREATION (FIXED for atomic mv)
# ═══════════════════════════════════════════════════════════════════════════
create_temp_dir() {
  local temp_base="$OUTPUT_DIR"
  local attempt=0
  
  # Ensure the base directory exists and is writable
  mkdir -p -- "$temp_base" 2>/dev/null || error_exit "Cannot create or access output directory: $temp_base"

  # HARDENED: Tighten output dir permission check (don’t allow group/other write)
  local perms owner p_group p_other
  perms=$(stat -c "%a" "$OUTPUT_DIR")
  owner=$(stat -c "%U" "$OUTPUT_DIR")
  p_group=${perms:1:1}
  p_other=${perms:2:1}
  if [[ "$owner" != "$USER" || "$p_group" =~ [2367] || "$p_other" =~ [2367] ]]; then
    error_exit "Output directory '$OUTPUT_DIR' is unsafe (must be owned by user and not group/other-writable)"
  fi
  
  while [[ $attempt -lt 5 ]]; do
    TEMP_DIR=$(mktemp -d -p "$temp_base" dupefinder.XXXXXXXXXX 2>/dev/null) || {
      ((attempt++))
      sleep 1
      continue
    }
    
    if [[ -d "$TEMP_DIR" ]]; then
      chmod 700 "$TEMP_DIR" || {
        rm -rf -- "$TEMP_DIR"
        error_exit "Failed to secure temporary directory"
      }
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
    ____         _____ _        _         ____                 
   |  _ \ _   _ _ __ ___| ___(_)_ __   __| | ___ _ __ |  _ \ _ __ ___  
   | | | | | | | '_ \/ _ \ |_  | | '_ \ / _` |/ _ \ '__|| |_) | '__/ _ \ 
   | |_| | |_| | |_)|  __/  _| | | | | | (_| |  __/ |  |  __/| | | (_) |
   |____/ \__,_| .__/\___|_|   |_|_| |_|\__,_|\___|_|  |_|   |_|  \___/ 
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
    ${GREEN}-p, --path PATH${NC}      Search path (default: current directory)
    ${GREEN}-o, --output DIR${NC}     Output directory for reports
    ${GREEN}-e, --exclude PATH${NC}   Exclude path (can be used multiple times)
    ${GREEN}-m, --min-size SIZE${NC}  Min size (e.g., 100, 10K, 5M, 1G)
    ${GREEN}-M, --max-size SIZE${NC}  Max size (e.g., 100, 10K, 5M, 1G)
    ${GREEN}-h, --help${NC}           Show this help
    ${GREEN}-V, --version${NC}        Show version

${BOLD}SAFETY OPTIONS:${NC}
    ${GREEN}--skip-system${NC}        Skip all system folders (/usr, /lib, /bin, etc.)
    ${GREEN}--force-system${NC}       Allow deletion of system files (DANGEROUS!)

${BOLD}SEARCH:${NC}
    ${GREEN}-f, --follow-symlinks${NC} Follow symbolic links (recursively)
    ${GREEN}-z, --empty${NC}          Include empty files
    ${GREEN}-a, --all${NC}            Include hidden files
    ${GREEN}-l, --level DEPTH${NC}    Max directory depth
    ${GREEN}-t, --pattern GLOB${NC}   File pattern (e.g., "*.jpg")
    ${GREEN}--fast${NC}               Fast mode (size+name hash)
    ${GREEN}--verify${NC}             Byte-by-byte verification before deletion

${BOLD}DELETION:${NC}
    ${GREEN}-d, --delete${NC}         Delete duplicates
    ${GREEN}-i, --interactive${NC}    Enhanced interactive mode with file preview
    ${GREEN}-n, --dry-run${NC}        Show actions without executing
    ${GREEN}--trash${NC}              Use trash (trash-cli) if available
    ${GREEN}--hardlink${NC}           Replace duplicates with hardlinks
    ${GREEN}--quarantine DIR${NC}     Move duplicates to quarantine directory

${BOLD}KEEP STRATEGIES:${NC}
    ${GREEN}-k, --keep-newest${NC}    Keep newest file from each group
    ${GREEN}-K, --keep-oldest${NC}    Keep oldest file from each group
    ${GREEN}--keep-path PATH${NC}     Prefer files in PATH
    ${GREEN}--smart-delete${NC}       Use location-based priorities

${BOLD}PERFORMANCE:${NC}
    ${GREEN}--threads N${NC}          Number of threads for hashing

${BOLD}REPORTING:${NC}
    ${GREEN}-c, --csv FILE${NC}       Generate CSV report
    ${GREEN}--json FILE${NC}          Generate JSON report
    ${GREEN}--log FILE${NC}           Log operations to FILE
    ${GREEN}-v, --verbose${NC}        Enable verbose output
    ${GREEN}-q, --quiet${NC}          Quiet mode (minimal output)

${BOLD}ADVANCED:${NC}
    ${GREEN}-s, --sha256${NC}         Use SHA256 hashing
    ${GREEN}--sha512${NC}             Use SHA512 hashing
    ${GREEN}--backup DIR${NC}         Backup files before deletion
    ${GREEN}--exclude-list FILE${NC}  File with paths to exclude

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
  
  # HARDENED: Defend against symlink attacks
  local real_file
  real_file=$(realpath -e "$file") || return 1
  
  if is_critical_system_file "$real_file"; then
    if [[ $FORCE_SYSTEM_DELETE -eq 1 ]]; then
      echo -e "${RED}WARNING: Critical system file detected: $real_file${NC}"
      echo -ne "${RED}Are you ABSOLUTELY SURE you want to delete this? Type 'YES DELETE': ${NC}"
      read -r confirmation
      [[ "$confirmation" != "YES DELETE" ]] && return 1
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
  if [[ "$owner" == "root" && "${USER:-}" != "root" ]]; then
    echo -e "${YELLOW}  ! File is owned by root: $file${NC}"
    log_action "warning" "File is owned by root: $file"
    return 1
  fi
  
  return 0
}

# HARDENED: Resolve symlinks in "system folder" checks too
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
    echo -e "${CYAN}System Folder Protection:${NC} $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    echo -e "${CYAN}Force System Delete:${NC}       $([ $FORCE_SYSTEM_DELETE -eq 1 ] && echo -e "${RED}ENABLED${NC}" || echo "DISABLED")"
    echo -e "${CYAN}Running as:${NC}              $USER"
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
  
  # List of variables allowed to be set from the config file
  local -a allowed_vars=("SEARCH_PATH" "OUTPUT_DIR" "HASH_ALGORITHM" "SCAN_START_TIME" "STATE_DUPS_FILE" "FILES_PROCESSED" "EXCLUDE_PATHS" "MIN_SIZE" "MAX_SIZE" "DELETE_MODE" "DRY_RUN" "VERBOSE" "QUIET" "FOLLOW_SYMLINKS" "EMPTY_FILES" "HIDDEN_FILES" "MAX_DEPTH" "FILE_PATTERN" "INTERACTIVE_DELETE" "KEEP_NEWEST" "KEEP_OLDEST" "KEEP_PATH_PRIORITY" "BACKUP_DIR" "USE_TRASH" "HARDLINK_MODE" "QUARANTINE_DIR" "USE_CACHE" "THREADS" "EMAIL_REPORT" "FUZZY_MATCH" "SIMILARITY_THRESHOLD" "SAVE_CHECKSUMS" "CHECKSUM_DB" "EXCLUDE_LIST_FILE" "FAST_MODE" "SMART_DELETE" "LOG_FILE" "VERIFY_MODE" "USE_PARALLEL" "RESUME_STATE" "LSOF_CHECKS")

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip comments and trim
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    
    [[ -z "$line" ]] && continue
    
    if [[ "$line" =~ ^([[:alnum:]_]+)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"

      # HARDENED: Reject dangerous content like ` $(;)`
      if [[ "$val" =~ [\`\$\(;\)] ]]; then
          log_action "error" "Unsafe value rejected for $key in $1"
          continue
      fi

      # Strip one layer of surrounding double quotes if present
      [[ "$val" == \"*\" ]] && val="${val%\"}" && val="${val#\"}"

      local is_allowed=0
      for var_name in "${allowed_vars[@]}"; do
        if [[ "$key" == "$var_name" ]]; then
          is_allowed=1
          break
        fi
      done
      if [[ $is_allowed -eq 1 ]]; then
        # HARDENED: Assign without evaluation
        printf -v "$key" "%s" "$val"
      fi
    fi
  done < "$filename"
}

parse_arguments() {
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
      -s|--sha256) HASH_ALGORITHM="sha256sum"; shift ;;
      --sha512) HASH_ALGORITHM="sha512sum"; shift ;;
      --backup)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a directory path"
        BACKUP_DIR="$2"; shift 2 ;;
      --exclude-list)
        [[ $# -lt 2 || "$2" == -* ]] && error_exit "$arg requires a filename"
        EXCLUDE_LIST_FILE="$2"; shift 2 ;;
      *)
        echo -e "${RED}Unknown option: $arg${NC}"; show_help; exit 1 ;;
    esac
  done
}

save_state() {
  local state_file="$HOME/.dupefinder_state"
  local state_dups="$HOME/.dupefinder_state.dups"
  local state_checksum_file="$HOME/.dupefinder_state.cksum"
  
  [[ ! -f "$TEMP_DIR/duplicates.txt" ]] && {
    log_action "warning" "No duplicates file found to save state"
    return 1
  }
  
  cp -- "$TEMP_DIR/duplicates.txt" "$state_dups" 2>/dev/null || {
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
  
  if [[ "$owner" != "$USER" || "$perm" != "600" ]]; then
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
  
  cp -- "$STATE_DUPS_FILE" "$TEMP_DIR/duplicates.txt"
  echo -e "${GREEN}Resuming previous scan...${NC}"
  log_action "info" "Resume state loaded successfully"
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION AND VALIDATION
# ═══════════════════════════════════════════════════════════════════════════
init_logging() {
  if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || LOG_FILE="$HOME/.dupefinder.log"
    {
      echo "$(date): DupeFinder Pro v$VERSION started by $USER"
      echo "$(date): Search path: $SEARCH_PATH"
      echo "$(date): System protection: $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    } >> "$LOG_FILE" 2>/dev/null || true
  fi
}

check_dependencies() {
  if ! command -v "$HASH_ALGORITHM" &>/dev/null; then
    error_exit "$HASH_ALGORITHM not found. Try: sudo apt install coreutils"
  fi
  
  for cmd in find stat sort awk; do
    if ! command -v "$cmd" &>/dev/null; then
      error_exit "$cmd command not found"
    fi
  done
  
  # Corrected GNU awk detection logic
  if awk --version 2>&1 | grep -qi 'GNU Awk'; then
    AWK_BIN="awk"
  elif command -v gawk >/dev/null 2>&1; then
    AWK_BIN="gawk"
  else
    error_exit "GNU awk required (supports RS='\\0'). Install 'gawk'."
  fi
  
  # Tools used elsewhere
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
  
  # Add search path with proper quoting
  args+=("$SEARCH_PATH")
  
  [[ -n "$MAX_DEPTH" ]] && args+=(-maxdepth "$MAX_DEPTH")
  
  # Build exclude arguments properly (FIXED HIDDEN DIRECTORY PRUNING)
  if [[ ${#EXCLUDE_PATHS[@]} -gt 0 || $HIDDEN_FILES -eq 0 ]]; then
    args+=( \( )
    local first=1
    if [[ $HIDDEN_FILES -eq 0 ]]; then
      args+=( -path '*/.*' ) # Correctly prune hidden directories
      first=0
    fi
    # HARDENED: Stronger find pruning for explicit paths
    for ex in "${EXCLUDE_PATHS[@]}"; do
      if [[ $first -eq 1 ]]; then
        args+=( -path "$ex" -o -path "$ex/*" )
        first=0
      else
        args+=( -o -path "$ex" -o -path "$ex/*" )
      fi
    done
    args+=( \) -prune -o )
  fi

  args+=(-type f)
  [[ $MIN_SIZE -gt 0 ]] && args+=(-size "+${MIN_SIZE}c")
  [[ -n "$MAX_SIZE" ]] && args+=(-size "-${MAX_SIZE}c")

  # Build pattern arguments properly
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
  
  # Execute find with error handling
  # Quote array expansion to prevent globbing/injection
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
# HASH CALCULATION (IMPROVED WITH RACE-CONDITION FIX)
# ═══════════════════════════════════════════════════════════════════════════
hash_file_with_timeout() {
  local file="$1"
  local algo="$2"
  local fast="$3"
  local result=""
  
  if [[ ! -f "$file" ]]; then
    ((HASH_ERRORS++))
    return 1
  fi
  
  local mtime size
  mtime=$(safe_stat "$file" "%Y")
  size=$(safe_stat "$file" "%s")
  
  if [[ "$fast" == "1" ]]; then
    local name_hash
    name_hash=$(printf '%s' "$(basename -- "$file")" | md5sum | cut -d' ' -f1)
    result="${size}_${name_hash:0:16}${DELIM}${size}${DELIM}${mtime}${DELIM}${file}"
  else
    local hash
    if hash=$(timeout "$HASH_TIMEOUT" "$algo" -- "$file" 2>/dev/null | cut -d' ' -f1); then
      [[ -n "$hash" ]] && result="${hash}${DELIM}${size}${DELIM}${mtime}${DELIM}${file}"
    else
      ((HASH_ERRORS++))
      log_action "warning" "Failed to hash: $file"
      return 1
    fi
  fi
  
  [[ -n "$result" ]] && printf '%s\0' "$result"
}

calculate_hashes() {
  local mode_text="standard"
  [[ $FAST_MODE -eq 1 ]] && mode_text="fast"
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Calculating file hashes ($mode_text mode, threads: $THREADS)...${NC}"
  
  [[ $TOTAL_FILES -eq 0 ]] && return
  
  local hashes_temp="$TEMP_DIR/hashes.temp"
  : > "$hashes_temp"
  
  # Named pipe to serialize writes safely
  local pipe="$TEMP_DIR/hashpipe"
  mkfifo "$pipe"
  # Single consumer writing to the file
  ( cat < "$pipe" > "$hashes_temp" ) &
  local cat_pid=$!
  
  local file_count=0
  local active_jobs=0
  
  while IFS= read -r -d '' file; do
    ((file_count++))
    ((FILES_PROCESSED++))
    
    # Check memory periodically
    if [[ $((file_count % MEMORY_CHECK_INTERVAL)) -eq 0 ]]; then
      if ! check_memory_usage; then
        echo -e "${YELLOW}Waiting for memory to free up...${NC}"
        wait
        active_jobs=0
      fi
    fi
    
    # Show progress
    if [[ $VERBOSE -eq 1 ]] && [[ $((file_count % 100)) -eq 0 ]]; then
      echo -e "${DIM}Processed $file_count/$TOTAL_FILES files...${NC}"
    fi
    
    # Launch hash calculation in background with job control
    {
      hash_file_with_timeout "$file" "$HASH_ALGORITHM" "$FAST_MODE"
    } > "$pipe" &
    
    ((active_jobs++))
    
    # Wait for jobs to complete if we hit thread limit
    if [[ $active_jobs -ge $THREADS ]]; then
      wait -n 2>/dev/null || true
      ((active_jobs--))
    fi
  done < "$TEMP_DIR/files.list"
  
  # Wait for remaining jobs and the cat consumer
  wait
  wait "$cat_pid" 2>/dev/null || true
  rm -f -- "$pipe"
  
  if [[ ! -s "$hashes_temp" ]]; then
    echo -e "${RED}Error: No files were successfully hashed.${NC}"
    [[ $HASH_ERRORS -gt 0 ]] && echo -e "${YELLOW}Hash errors: $HASH_ERRORS${NC}"
    return 1
  fi
  
  mv -- "$hashes_temp" "$TEMP_DIR/hashes.txt"
  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}Hash calculation completed${NC}"
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
  
  # Sort and process with improved AWK script
  sort -z -t"$DELIM" -k1,1 < "$TEMP_DIR/hashes.txt" | \
  "$AWK_BIN" -v DELIM="$DELIM" -v RS='\0' -v ORS='\0' '
  BEGIN { 
    prev_hash = ""; 
    dup_count = 0; 
    wasted = 0; 
    gcount = 0;
    group_files = "";
    in_group = 0;
  }
  
  function print_group() {
    if (group_files != "") {
      print "---" ORS;
      print group_files;
      group_files = "";
    }
  }
  
  {
    # Skip empty records
    if (length($0) == 0) next;
    
    # Parse the record
    split($0, a, DELIM);
    if (length(a) < 4) next;
    
    hash = a[1];
    size = a[2];
    mtime = a[3];
    file = a[4];
    
    # Validate fields
    if (length(hash) == 0 || length(file) == 0) next;
    if (size !~ /^[0-9]+$/) next;
    
    if (hash == prev_hash && prev_hash != "") {
      # Found duplicate
      if (in_group == 0) {
        # First duplicate in group
        gcount++;
        in_group = 1;
        group_files = hash ":" prev_file "|" prev_size "|" prev_mtime ORS;
      }
      group_files = group_files file "|" size "|" mtime ORS;
      dup_count++;
      wasted += size;
    } else {
      # Different hash - print previous group if exists
      print_group();
      in_group = 0;
    }
    
    prev_hash = hash;
    prev_file = file;
    prev_size = size;
    prev_mtime = mtime;
  }
  
  END {
    print_group();
    print "STATS:" dup_count "|" wasted "|" gcount ORS;
  }' | tr '\0' '\n' > "$TEMP_DIR/duplicates.txt"
  
  # Extract statistics
  local stats
  stats=$(grep "^STATS:" "$TEMP_DIR/duplicates.txt" 2>/dev/null | tail -1 | cut -d: -f2)
  
  if [[ -n "$stats" ]]; then
    TOTAL_DUPLICATES=$(echo "$stats" | cut -d'|' -f1)
    TOTAL_SPACE_WASTED=$(echo "$stats" | cut -d'|' -f2)
    TOTAL_DUPLICATE_GROUPS=$(echo "$stats" | cut -d'|' -f3)
    
    # Validate statistics
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
  [[ $VERBOSE -eq 0 ]] && return
  [[ $QUIET -eq 1 ]] && return

  if [[ ${TOTAL_DUPLICATE_GROUPS:-0} -eq 0 ]]; then
    echo -e "${YELLOW}No duplicate groups found to display.${NC}"
    return
  fi

  echo ""
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}      DUPLICATE GROUPS FOUND${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  
  local gid=0
  local in_group=0
  local current_hash=""
  
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      in_group=1
      continue
    elif [[ "$line" =~ ^STATS: ]]; then
      break
    elif [[ $in_group -eq 1 && "$line" =~ ^([a-f0-9]+):(.*)$ ]]; then
      ((gid++))
      current_hash="${BASH_REMATCH[1]}"
      local first_file="${BASH_REMATCH[2]}"
      echo -e "${BOLD}${CYAN}Group $gid:${NC} Hash ${current_hash:0:16}..."
      echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
      
      local path size mtime
      IFS='|' read -r path size mtime <<< "$first_file"
      local status=""
      is_in_system_folder "$path" && status=" (system file)"
      echo -e "  - $(format_size "$size")  ${DIM}${path}${NC}${YELLOW}${status}${NC}"
    elif [[ $in_group -eq 1 && -n "$line" ]]; then
      local path size mtime
      IFS='|' read -r path size mtime <<< "$line"
      local status=""
      is_in_system_folder "$path" && status=" (system file)"
      echo -e "  - $(format_size "$size")  ${DIM}${path}${NC}${YELLOW}${status}${NC}"
    fi
  done < "$TEMP_DIR/duplicates.txt"
  
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

  # Determine which file to keep based on strategy
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
  
  # Process duplicates
  for i in "${!files[@]}"; do
    [[ $i -eq $keep_idx ]] && continue
    
    local path size mtime
    IFS='|' read -r path size mtime <<< "${files[$i]}"
    
    # Safety checks
    if ! verify_safe_to_delete "$path"; then
      [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ! Skipped (safety): $path${NC}"
      continue
    fi
    
    if [[ $SKIP_SYSTEM_FOLDERS -eq 1 ]] && is_in_system_folder "$path"; then
      [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ! Skipped (system): $path${NC}"
      continue
    fi
    
    if [[ $VERIFY_MODE -eq 1 ]] && ! verify_identical "$keep_file" "$path"; then
      [[ $VERBOSE -eq 1 ]] && echo -e "${RED}  ! Skipped (not identical): $path${NC}"
      continue
    fi
    
    # Interactive mode
    if [[ $INTERACTIVE_DELETE -eq 1 ]]; then
      # HARDENED: Safer default in interactive mode (default -> skip)
      echo -ne "${BOLD}[d]elete, [h]ardlink, [s]kip, [q]uit? [s]: ${NC}"
      read -r -n 1 response
      echo ""
      response=${response,,}
      [[ -z "$response" ]] && response="s" # Safer default
      
      case "$response" in
        s) continue ;;
        q) exit 0 ;;
        h) HARDLINK_MODE=1; DELETE_MODE=0 ;;
      esac
    fi
    
    # Backup if requested
    if [[ -n "$BACKUP_DIR" && $DRY_RUN -eq 0 ]]; then
      backup_file "$path"
    fi
    
    # Perform action
    if [[ $DRY_RUN -eq 1 ]]; then
      if [[ $HARDLINK_MODE -eq 1 ]]; then
        echo -e "${YELLOW}  Would hardlink: $path -> $keep_file${NC}"
        ((FILES_HARDLINKED++))
      elif [[ -n "$QUARANTINE_DIR" ]]; then
        echo -e "${YELLOW}  Would quarantine: $path${NC}"
        ((FILES_QUARANTINED++))
      else
        echo -e "${YELLOW}  Would delete: $path${NC}"
        ((FILES_DELETED++))
      fi
      ((SPACE_FREED+=size))
    else
      if [[ $HARDLINK_MODE -eq 1 ]]; then
        local keep_dev dup_dev
        keep_dev=$(safe_stat "$keep_file" "%d")
        dup_dev=$(safe_stat "$path" "%d")
        if [[ "$keep_dev" == "$dup_dev" ]]; then
          # FIXED: Replaced non-atomic `rm` and `ln` with atomic `ln -f`.
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
      elif [[ -n "$QUARANTINE_DIR" ]]; then
        local qfile="$QUARANTINE_DIR/$(basename -- "$path")_$(date +%s)_$(printf '%s' "$path" | sha256sum | cut -c1-8)"
        if mv -- "$path" "$qfile" 2>/dev/null; then
          ((FILES_QUARANTINED++))
          ((SPACE_FREED+=size))
          [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  - Quarantined: $path${NC}"
          log_action "info" "Quarantined: $path -> $qfile"
        fi
      elif [[ $DELETE_MODE -eq 1 ]]; then
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

  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Processing duplicate files...${NC}"
  
  local in_group=0
  local -a current_group=()
  local group_count=0
  
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if [[ ${#current_group[@]} -gt 0 ]]; then
        ((group_count++))
        [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Processing group $group_count...${NC}"
        process_duplicate_group "${current_group[@]}"
      fi
      in_group=1
      current_group=()
      continue
    elif [[ "$line" =~ ^STATS: ]]; then
      break
    elif [[ $in_group -eq 1 && "$line" =~ ^([a-f0-9]+):(.*)$ ]]; then
      current_group+=("${BASH_REMATCH[2]}")
    elif [[ $in_group -eq 1 && -n "$line" ]]; then
      current_group+=("$line")
    fi
  done < "$TEMP_DIR/duplicates.txt"
  
  # Process final group
  if [[ ${#current_group[@]} -gt 0 ]]; then
    ((group_count++))
    [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Processing group $group_count...${NC}"
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
  local in_group=0
  local first_group=1
  
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      [[ $in_group -eq 1 && $gid -gt 0 ]] && echo "</div></div>" >> "$report_file"
      in_group=1
      continue
    elif [[ "$line" =~ ^STATS: ]]; then
      [[ $in_group -eq 1 && $gid -gt 0 ]] && echo "</div></div>" >> "$report_file"
      break
    elif [[ $in_group -eq 1 && "$line" =~ ^([a-f0-9]+):(.*)$ ]]; then
      ((gid++))
      current_hash="${BASH_REMATCH[1]}"
      local first_file="${BASH_REMATCH[2]}"
      echo "<div id=\"g$gid\" class=\"group\" onclick=\"toggle('g$gid')\">" >> "$report_file"
      echo "<div class=\"hdr\">Group $gid (Hash: ${current_hash:0:16}...)</div>" >> "$report_file"
      echo "<div class=\"files\">" >> "$report_file"
      
      local path size mtime
      IFS='|' read -r path size mtime <<< "$first_file"
      local class=""
      is_in_system_folder "$path" && class="system-file"
      # HARDENED: Correctly escape single quotes in HTML output
      printf '<div class="file %s">%s<br>Size: %s</div>\n' \
        "$class" \
        "$(printf '%s' "$path" | sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/"/\&quot;/g;s/'"'"'/\&#39;/g')" \
        "$(format_size "$size")" >> "$report_file"
    elif [[ $in_group -eq 1 && -n "$line" ]]; then
      local path size mtime
      IFS='|' read -r path size mtime <<< "$line"
      local class=""
      is_in_system_folder "$path" && class="system-file"
      # HARDENED: Correctly escape single quotes in HTML output
      printf '<div class="file %s">%s<br>Size: %s</div>\n' \
        "$class" \
        "$(printf '%s' "$path" | sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/"/\&quot;/g;s/'"'"'/\&#39;/g')" \
        "$(format_size "$size")" >> "$report_file"
    fi
  done < "$TEMP_DIR/duplicates.txt"

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
  local in_group=0
  local current_hash=""
  
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      in_group=1
      continue
    elif [[ "$line" =~ ^STATS: ]]; then
      break
    elif [[ $in_group -eq 1 && "$line" =~ ^([a-f0-9]+):(.*)$ ]]; then
      ((gid++))
      current_hash="${BASH_REMATCH[1]}"
      local first_file="${BASH_REMATCH[2]}"
      
      local path size mtime
      IFS='|' read -r path size mtime <<< "$first_file"
      local is_system="No"
      is_in_system_folder "$path" && is_system="Yes"
      printf '%s,"%s",%s,"%s",%s,%s\n' "$current_hash" "${path//\"/\"\"}" "$size" "$(format_size "$size")" "$gid" "$is_system" >> "$csv"
    elif [[ $in_group -eq 1 && -n "$line" ]]; then
      local path size mtime
      IFS='|' read -r path size mtime <<< "$line"
      local is_system="No"
      is_in_system_folder "$path" && is_system="Yes"
      printf '%s,"%s",%s,"%s",%s,%s\n' "$current_hash" "${path//\"/\"\"}" "$size" "$(format_size "$size")" "$gid" "$is_system" >> "$csv"
    fi
  done < "$TEMP_DIR/duplicates.txt"

  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✓ CSV report saved: $csv${NC}"
}

generate_json_report() {
  [[ -z "$JSON_REPORT" ]] && return
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}Generating JSON report...${NC}"
  
  local json="$OUTPUT_DIR/$JSON_REPORT"
  
  cat > "$json" << EOF
{
  "metadata": {
    "version": "$VERSION",
    "author": "$AUTHOR",
    "generated": "$(date -Iseconds 2>/dev/null || date)",
    "search_path": "$SEARCH_PATH",
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
  local in_group=0
  local first_group=1
  local need_comma=0
  
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if [[ $first_group -eq 0 ]]; then
        echo "      ]" >> "$json"
        echo "    }" >> "$json"
        need_comma=1
      fi
      first_group=0
      in_group=1
      # Start a new group; print comma if needed
      if [[ $need_comma -eq 1 ]]; then
        echo "    ," >> "$json"
        need_comma=0
      fi
      continue
    elif [[ "$line" =~ ^STATS: ]]; then
      break
    elif [[ $in_group -eq 1 && "$line" =~ ^([a-f0-9]+):(.*)$ ]]; then
      ((gid++))
      local hash="${BASH_REMATCH[1]}"
      local first_file="${BASH_REMATCH[2]}"
      
      echo "    {" >> "$json"
      echo "      \"id\": $gid," >> "$json"
      echo "      \"hash\": \"$hash\"," >> "$json"
      echo "      \"files\": [" >> "$json"
      
      local path size mtime
      IFS='|' read -r path size mtime <<< "$first_file"
      local is_system="false"
      is_in_system_folder "$path" && is_system="true"
      local jpath="${path//\\/\\\\}"; jpath="${jpath//\"/\\\"}"
      printf '        {"path": "%s", "size": %s, "system": %s}' "$jpath" "$size" "$is_system" >> "$json"
    elif [[ $in_group -eq 1 && -n "$line" ]]; then
      local path size mtime
      IFS='|' read -r path size mtime <<< "$line"
      local is_system="false"
      is_in_system_folder "$path" && is_system="true"
      local jpath2="${path//\\/\\\\}"; jpath2="${jpath2//\"/\\\"}"
      printf ',\n        {"path": "%s", "size": %s, "system": %s}' "$jpath2" "$size" "$is_system" >> "$json"
    fi
  done < "$TEMP_DIR/duplicates.txt"
  
  # Close the last open group if any
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

show_summary() {
  [[ $QUIET -eq 1 ]] && return
  
  echo ""
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}      SCAN SUMMARY${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}Search Path:${NC}            $SEARCH_PATH"
  echo -e "${CYAN}System Protection:${NC}    $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
  echo -e "${CYAN}Files Scanned:${NC}        ${TOTAL_FILES:-0}"
  echo -e "${CYAN}Duplicates Found:${NC}     ${TOTAL_DUPLICATES:-0}"
  echo -e "${CYAN}Duplicate Groups:${NC}     ${TOTAL_DUPLICATE_GROUPS:-0}"
  echo -e "${CYAN}Space Wasted:${NC}         $(format_size "${TOTAL_SPACE_WASTED:-0}")"
  
  if [[ ${FILES_DELETED:-0} -gt 0 || ${FILES_HARDLINKED:-0} -gt 0 || ${FILES_QUARANTINED:-0} -gt 0 ]]; then
    echo -e "${CYAN}Files Processed:${NC}      $((${FILES_DELETED:-0} + ${FILES_HARDLINKED:-0} + ${FILES_QUARANTINED:-0}))"
    echo -e "${CYAN}Space Freed:${NC}          $(format_size "${SPACE_FREED:-0}")"
    [[ ${FILES_DELETED:-0} -gt 0 ]] && echo -e "${DIM}  - Deleted: ${FILES_DELETED}${NC}"
    [[ ${FILES_HARDLINKED:-0} -gt 0 ]] && echo -e "${DIM}  - Hardlinked: ${FILES_HARDLINKED}${NC}"
    [[ ${FILES_QUARANTINED:-0} -gt 0 ]] && echo -e "${DIM}  - Quarantined: ${FILES_QUARANTINED}${NC}"
  fi
  
  [[ -n "$SCAN_START_TIME" && -n "$SCAN_END_TIME" ]] && \
    echo -e "${CYAN}Scan Duration:${NC}        $(calculate_duration)"
  echo -e "${CYAN}Hash Algorithm:${NC}         ${HASH_ALGORITHM%%sum}"
  [[ $FAST_MODE -eq 1 ]] && echo -e "${DIM}    (Fast mode: size + filename hash)${NC}"
  echo -e "${CYAN}Threads Used:${NC}           $THREADS"
  [[ $HASH_ERRORS -gt 0 ]] && echo -e "${YELLOW}Hash Errors:${NC}            $HASH_ERRORS"
  echo -e "${WHITE}─────────────────────────────────────────────────────────${NC}"
  echo -e "${CYAN}HTML Report:${NC}          $OUTPUT_DIR/$HTML_REPORT"
  [[ -n "$CSV_REPORT" ]] && \
    echo -e "${CYAN}CSV Report:${NC}           $OUTPUT_DIR/$CSV_REPORT"
  [[ -n "$JSON_REPORT" ]] && \
    echo -e "${CYAN}JSON Report:${NC}          $OUTPUT_DIR/$JSON_REPORT"
  [[ -n "$LOG_FILE" ]] && \
    echo -e "${CYAN}Log File:${NC}             $LOG_FILE"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════
main() {
  # Set locale for consistent sorting
  export LC_ALL=C
  
  # Parse arguments and initialize
  parse_arguments "$@"
  check_dependencies
  
  # Create secure temp dir
  create_temp_dir
  
  SCAN_START_TIME=$(date +%s)
  init_logging
  
  [[ $QUIET -eq 0 ]] && show_header
  
  # Validate inputs
  validate_inputs
  
  # Check if resuming
  if [[ $RESUME_STATE -eq 1 ]] && load_state; then
    echo -e "${GREEN}Resuming from saved state...${NC}"
  else
    # Main execution flow
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
  
  # Process results
  show_duplicate_details
  show_safety_summary
  delete_duplicates
  generate_html_report
  generate_csv_report
  generate_json_report
  
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
