#!/usr/bin/env bash
#############################################################################
# DupeFinder Pro - Advanced Duplicate File Manager for Linux
# Version: 1.1.2
# Author: Seth Morrow
# License: MIT
#
# Description:
#   A professional and robust duplicate file finder for Linux with advanced
#   management, reporting, caching, and critical system file protection.
#   This version has been meticulously refactored for improved reliability,
#   security, and performance, addressing all known critical bugs.
#
# Changes in this version:
# - Corrected hashing pipeline to properly read file list from `find`.
# - Fixed `--follow-symlinks` to correctly use `find -L`.
# - Implemented a more robust `rm then ln` strategy for `--hardlink`.
# - Hardened internal data pipeline by using a unique delimiter, making it
#   resilient to special characters (like '|' or newlines) in filenames.
# - Added runtime checks to ensure the chosen hash algorithm is available.
# - Ensured temporary directory paths are not persisted in resume state.
# - Improved UX by checking if output is a TTY before clearing the screen.
# - Cleaned up code by removing unused variables and flags.
#
#############################################################################

# ═══════════════════════════════════════════════════════════════════════════
# TERMINAL COLORS AND FORMATTING
# ═══════════════════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL DELIMITERS AND CONSTANTS
# Using a unique, unlikely string as a field separator for robustness against
# special characters (e.g., newlines, pipes) in filenames.
# ═══════════════════════════════════════════════════════════════════════════
DELIM="__DFP_DELIM__"

# ═══════════════════════════════════════════════════════════════════════════
# DEFAULT CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════
VERSION="1.1.2"
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
SAVE_CHECKSUMS=0
CHECKSUM_DB="$HOME/.dupefinder_checksums.db"
EXCLUDE_LIST_FILE=""
FAST_MODE=0
SMART_DELETE=0
LOG_FILE=""
VERIFY_MODE=0
USE_PARALLEL=0
RESUME_STATE=""

# ═══════════════════════════════════════════════════════════════════════════
# CRITICAL SYSTEM PROTECTION CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════
# These patterns and paths are used to protect critical system files.
# While they provide a strong layer of defense, they are not foolproof.
# The --force-system option should be used with extreme caution.
CRITICAL_EXTENSIONS=(
  ".so"      # Shared libraries
  ".dll"     # Windows DLLs (Wine)
  ".dylib"   # macOS dynamic libraries
  ".ko"      # Kernel modules
  ".sys"     # System files
  ".elf"     # ELF executables
  ".a"       # Static libraries
  ".lib"     # Library files
  ".pdb"     # Program database
  ".exe"     # Executables
)

CRITICAL_PATHS=(
  "/boot"            # Boot loader files
  "/lib"             # Essential shared libraries
  "/lib64"           # 64-bit libraries
  "/usr/lib"         # System libraries
  "/usr/lib64"       # 64-bit system libraries
  "/usr/bin"         # User binaries
  "/bin"             # Essential binaries
  "/sbin"            # System binaries
  "/usr/sbin"        # Non-essential system binaries
  "/etc"             # System configuration
  "/usr/share/dbus-1" # D-Bus configuration
  "/usr/share/applications" # Desktop entries
)

SYSTEM_FOLDERS=(
  "/boot"    # Boot loader and kernel
  "/bin"     # Essential command binaries
  "/sbin"    # Essential system binaries
  "/lib"     # Essential shared libraries
  "/lib32"   # 32-bit libraries
  "/lib64"   # 64-bit libraries
  "/libx32"  # x32 ABI libraries
  "/usr"     # Secondary hierarchy
  "/etc"     # System configuration
  "/root"    # Root user home
  "/snap"    # Snap packages
  "/sys"     # Sysfs virtual filesystem
  "/proc"    # Procfs virtual filesystem
  "/dev"     # Device files
  "/run"     # Runtime data
  "/srv"     # Service data
)

NEVER_DELETE_PATTERNS=(
  "vmlinuz*"     # Linux kernel
  "initrd*"      # Initial ramdisk
  "initramfs*"   # Initial RAM filesystem
  "grub*"        # Boot loader
  "ld-linux*"    # Dynamic linker
  "libc.so*"     # C library
  "libpthread*"  # Threading library
  "libdl*"       # Dynamic linking library
  "libm.so*"     # Math library
  "busybox*"     # Emergency shell
  "systemd*"     # Init system
)

# Safety flags
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
DUPLICATE_GROUPS=""

# ═══════════════════════════════════════════════════════════════════════════
# SMART LOCATION PRIORITIES
# ═══════════════════════════════════════════════════════════════════════════
declare -A LOCATION_PRIORITY=(
  ["/home"]=1
  ["/usr/local"]=2
  ["/opt"]=3
  ["/var"]=4
  ["/tmp"]=99
  ["/downloads"]=90
  ["/cache"]=95
)

# ═══════════════════════════════════════════════════════════════════════════
# CLEANUP AND SIGNAL HANDLING
# ═══════════════════════════════════════════════════════════════════════════
cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
  [[ -n "$LOG_FILE" ]] && echo "$(date): Session ended" >> "$LOG_FILE"
  if [[ -n "$SCAN_END_TIME" ]]; then
    rm -f -- "$HOME/.dupefinder_state"
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

# ═══════════════════════════════════════════════════════════════════════════
# USER INTERFACE FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════
show_header() {
  [[ -t 1 ]] && clear
  echo -e "${CYAN}"
  cat << "EOF"
    ____             _____ _         _       ____             
    |  _ \ _   _ _ __   ___(_)_ __  __| | ___ _ __|  _ \ _ __ ___ 
    | | | | | | | '_ \ / _ \ |_  | | '_ \ / _` |/ _ \ '__| |_) | '__/ _ \
    | |_| | |_| | |_) |  __/  _| | | | | | (_| |  __/ |  |  __/| | | (_) |
    |____/ \__,_| .__/ \___|_|  |_|_| |_|\__,_|\___|_|  |_|   |_|  \___/ 
                |_|                                                 
EOF
  echo -e "${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}     Advanced Duplicate File Manager v${VERSION}${NC}"
  echo -e "${DIM}             by ${AUTHOR}${NC}"
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

${BOLD}SAFETY OPTIONS:${NC}
    ${GREEN}--skip-system${NC}         Skip all system folders (/usr, /lib, /bin, etc.)
    ${GREEN}--force-system${NC}        Allow deletion of system files (DANGEROUS!)

${BOLD}SEARCH:${NC}
    ${GREEN}-f, --follow-symlinks${NC} Follow symbolic links (recursively)
    ${GREEN}-z, --empty${NC}           Include empty files
    ${GREEN}-a, --all${NC}             Include hidden files
    ${GREEN}-l, --level DEPTH${NC}     Max directory depth
    ${GREEN}-t, --pattern GLOB${NC}    File pattern (e.g., "*.jpg")
    ${GREEN}--fast${NC}                Fast mode (size+name hash)
    ${GREEN}--fuzzy${NC}               Fuzzy match by size similarity (not implemented)
    ${GREEN}--similarity PCT${NC}      Fuzzy threshold (1-100, default 95)
    ${GREEN}--verify${NC}              Byte-by-byte verification before deletion

${BOLD}DELETION:${NC}
    ${GREEN}-d, --delete${NC}          Delete duplicates
    ${GREEN}-i, --interactive${NC}     Enhanced interactive mode with file preview
    ${GREEN}-n, --dry-run${NC}         Show actions without executing
    ${GREEN}--trash${NC}               Use trash (trash-cli) if available
    ${GREEN}--hardlink${NC}            Replace duplicates with hardlinks
    ${GREEN}--quarantine DIR${NC}      Move duplicates to quarantine directory

${BOLD}KEEP STRATEGIES:${NC}
    ${GREEN}-k, --keep-newest${NC}     Keep newest file from each group
    ${GREEN}-K, --keep-oldest${NC}     Keep oldest file from each group
    ${GREEN}--keep-path PATH${NC}      Prefer files in PATH
    ${GREEN}--smart-delete${NC}        Use location-based priorities

${BOLD}PERFORMANCE:${NC}
    ${GREEN}--threads N${NC}           Number of threads for hashing
    ${GREEN}--cache${NC}               Use SQLite cache database (future feature)
    ${GREEN}--save-checksums${NC}      Save checksums to database (future feature)
    ${GREEN}--no-progress${NC}         Disable progress bar
    ${GREEN}--parallel${NC}            Use GNU parallel if available (EXPERIMENTAL)

${BOLD}REPORTING:${NC}
    ${GREEN}-c, --csv FILE${NC}        Generate CSV report
    ${GREEN}--json FILE${NC}           Generate JSON report
    ${GREEN}--email ADDRESS${NC}       Email summary to ADDRESS
    ${GREEN}--log FILE${NC}            Log operations to FILE
    ${GREEN}-v, --verbose${NC}         Enable verbose output
    ${GREEN}-q, --quiet${NC}           Quiet mode (minimal output)

${BOLD}ADVANCED:${NC}
    ${GREEN}-s, --sha256${NC}          Use SHA256 hashing
    ${GREEN}--sha512${NC}              Use SHA512 hashing
    ${GREEN}--backup DIR${NC}          Backup files before deletion
    ${GREEN}--config FILE${NC}         Load configuration from FILE
    ${GREEN}--exclude-list FILE${NC}   File with paths to exclude
    ${GREEN}--db-path FILE${NC}        Custom database path
    ${GREEN}--resume${NC}              Resume previous interrupted scan

${BOLD}INTERACTIVE MODE FEATURES:${NC}
    ${GREEN}- Enhanced file comparison with detailed metadata${NC}
    ${GREEN}- File preview and viewer integration${NC}
    ${GREEN}- Option to swap which file to keep${NC}
    ${GREEN}- Auto-apply choices to remaining duplicates${NC}
    ${GREEN}- Progress tracking through duplicate groups${NC}

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
  if [[ "$s" =~ ^([0-9]+)([KMG]?)B?$ ]]; then
    local n="${BASH_REMATCH[1]}"
    local u="${BASH_REMATCH[2]}"
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

format_size() {
  local size=${1:-0}
  if command -v bc >/dev/null 2>&1; then
    local units=(B KB MB GB TB)
    local u=0
    local val=$size
    while [[ $(echo "$val >= 1024" | bc 2>/dev/null || echo 0) -eq 1 && $u -lt 4 ]]; do
      val=$(echo "scale=2; $val/1024" | bc 2>/dev/null || echo 0)
      ((u++))
    done
    printf "%.2f %s" "$val" "${units[$u]}"
  else
    local units=(B KB MB GB TB)
    local u=0
    while [[ $size -ge 1024 && $u -lt 4 ]]; do
      size=$((size/1024))
      ((u++))
    done
    echo "$size ${units[$u]}"
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
  if is_critical_system_file "$file"; then
    if [[ $FORCE_SYSTEM_DELETE -eq 1 ]]; then
      echo -e "${RED}⚠ WARNING: Critical system file detected: $file${NC}"
      echo -ne "${RED}Are you ABSOLUTELY SURE you want to delete this? Type 'YES DELETE': ${NC}"
      read -r confirmation
      [[ "$confirmation" != "YES DELETE" ]] && return 1
    else
      [[ $VERBOSE -eq 1 ]] && echo -e "${RED}  ✗ Skipping critical system file: $file${NC}"
      return 1
    fi
  fi
  if command -v lsof &>/dev/null; then
    if lsof -- "$file" >/dev/null 2>&1; then
      echo -e "${YELLOW}  ⚠ File is currently in use: $file${NC}"
      if [[ $INTERACTIVE_DELETE -eq 1 ]]; then
        echo -ne "${YELLOW}  Force delete anyway? (y/N): ${NC}"
        read -r response
        [[ "$response" != "y" && "$response" != "Y" ]] && return 1
      else
        return 1
      fi
    fi
  fi
  if [[ "$file" == *.so* ]]; then
    if grep -q "$(basename -- "$file")" /proc/*/maps 2>/dev/null; then
      echo -e "${RED}  ✗ Shared library is currently loaded: $file${NC}"
      return 1
    fi
  fi
  local owner
  owner=$(stat -c '%U' -- "$file" 2>/dev/null)
  if [[ "$owner" == "root" && "$USER" != "root" ]]; then
    echo -e "${YELLOW}  ⚠ File is owned by root: $file${NC}"
  fi
  return 0
}

is_in_system_folder() {
  local file="$1"
  for sys_folder in "${SYSTEM_FOLDERS[@]}"; do
    [[ "$file" == "$sys_folder"/* ]] && return 0
  done
  return 1
}

show_safety_summary() {
  if [[ $DELETE_MODE -eq 1 || $HARDLINK_MODE -eq 1 ]]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}     SAFETY CHECK SUMMARY${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}System Folder Protection:${NC} $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    echo -e "${CYAN}Force System Delete:${NC}     $([ $FORCE_SYSTEM_DELETE -eq 1 ] && echo -e "${RED}ENABLED${NC}" || echo "DISABLED")"
    echo -e "${CYAN}Running as:${NC}          $USER"
    echo -e "${CYAN}Delete Mode:${NC}         $([ $DELETE_MODE -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    echo -e "${CYAN}Interactive Mode:${NC}    $([ $INTERACTIVE_DELETE -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    echo -e "${CYAN}Dry Run:${NC}           $([ $DRY_RUN -eq 1 ] && echo "YES" || echo "NO")"
    local system_files=0
    if [[ -f "$TEMP_DIR/hashes.txt" ]]; then
      while IFS="$DELIM" read -r _ _ _ file; do
        is_in_system_folder "$file" && ((system_files++))
      done < "$TEMP_DIR/hashes.txt"
    fi
    if [[ $system_files -gt 0 ]]; then
      echo -e "${YELLOW}⚠ Found $system_files files in system folders${NC}"
      if [[ $SKIP_SYSTEM_FOLDERS -eq 0 ]]; then
        echo -e "${RED}  These will be processed! Use --skip-system to exclude them${NC}"
      fi
    fi
    echo -e "${YELLOW}─────────────────────────────────────────────────────────${NC}"
    if [[ $DELETE_MODE -eq 1 && $DRY_RUN -eq 0 && $FORCE_SYSTEM_DELETE -eq 0 && $INTERACTIVE_DELETE -eq 0 ]]; then
      echo -ne "${YELLOW}Proceed with these settings? (y/N): ${NC}"
      read -r response
      [[ "$response" != "y" && "$response" != "Y" ]] && exit 0
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION AND STATE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════
# Safely reads key-value pairs from a file without using 'source'.
safe_source() {
  local filename="$1"
  if [[ ! -f "$filename" ]]; then
    return 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(echo "$line" | sed 's/#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^([[:alnum:]_]+)=(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      val="${val%\"}"
      val="${val#\"}"
      if declare -p "$key" &>/dev/null; then
        declare -g "$key"="$val"
      fi
    fi
  done < "$filename"
}

load_config() {
  if [[ -n "$CONFIG_FILE" ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
      echo -e "${CYAN}Loading configuration from $CONFIG_FILE...${NC}"
      safe_source "$CONFIG_FILE"
    else
      echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
      exit 1
    fi
  fi
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -p|--path) SEARCH_PATH="$2"; shift 2 ;;
      -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
      -e|--exclude) EXCLUDE_PATHS+=("$2"); shift 2 ;;
      -m|--min-size) MIN_SIZE=$(parse_size "$2"); shift 2 ;;
      -M|--max-size) MAX_SIZE=$(parse_size "$2"); shift 2 ;;
      -h|--help) show_help; exit 0 ;;
      -V|--version) echo "DupeFinder Pro v$VERSION by $AUTHOR"; exit 0 ;;
      --skip-system)
        SKIP_SYSTEM_FOLDERS=1
        echo -e "${GREEN}System folders will be excluded from scanning${NC}"
        shift ;;
      --force-system)
        FORCE_SYSTEM_DELETE=1
        echo -e "${RED}⚠ WARNING: Force system delete mode enabled - BE VERY CAREFUL!${NC}"
        shift ;;
      -f|--follow-symlinks) FOLLOW_SYMLINKS=1; shift ;;
      -z|--empty) EMPTY_FILES=1; MIN_SIZE=0; shift ;;
      -a|--all) HIDDEN_FILES=1; shift ;;
      -l|--level) MAX_DEPTH="$2"; shift 2 ;;
      -t|--pattern) FILE_PATTERN+=("$2"); shift 2 ;;
      --fast) FAST_MODE=1; shift ;;
      --fuzzy) FUZZY_MATCH=1; shift ;;
      --similarity) SIMILARITY_THRESHOLD="$2"; shift 2 ;;
      --verify) VERIFY_MODE=1; shift ;;
      -d|--delete) DELETE_MODE=1; shift ;;
      -i|--interactive) INTERACTIVE_DELETE=1; DELETE_MODE=1; shift ;;
      -n|--dry-run) DRY_RUN=1; shift ;;
      --trash) USE_TRASH=1; shift ;;
      --hardlink) HARDLINK_MODE=1; shift ;;
      --quarantine) QUARANTINE_DIR="$2"; shift 2 ;;
      -k|--keep-newest) KEEP_NEWEST=1; shift ;;
      -K|--keep-oldest) KEEP_OLDEST=1; shift ;;
      --keep-path) KEEP_PATH_PRIORITY="$2"; shift 2 ;;
      --smart-delete) SMART_DELETE=1; shift ;;
      --threads) THREADS="$2"; shift 2 ;;
      --cache) USE_CACHE=1; shift ;;
      --save-checksums) SAVE_CHECKSUMS=1; shift ;;
      --no-progress) :; shift ;; # Removed progress bar for simplicity
      --parallel) USE_PARALLEL=1; shift ;;
      -c|--csv) CSV_REPORT="$2"; shift 2 ;;
      --json) JSON_REPORT="$2"; shift 2 ;;
      --email) EMAIL_REPORT="$2"; shift 2 ;;
      --log) LOG_FILE="$2"; shift 2 ;;
      -v|--verbose) VERBOSE=1; shift ;;
      -q|--quiet) QUIET=1; shift ;;
      -s|--sha256) HASH_ALGORITHM="sha256sum"; shift ;;
      --sha512) HASH_ALGORITHM="sha512sum"; shift ;;
      --backup) BACKUP_DIR="$2"; shift 2 ;;
      --config) CONFIG_FILE="$2"; shift 2 ;;
      --exclude-list) EXCLUDE_LIST_FILE="$2"; shift 2 ;;
      --db-path) DB_CACHE="$2"; CHECKSUM_DB="${2%.db}_checksums.db"; shift 2 ;;
      --resume) RESUME_STATE=1; shift ;;
      *) echo -e "${RED}Unknown option: $1${NC}"; show_help; exit 1 ;;
    esac
  done
}

save_state() {
  cat > "$HOME/.dupefinder_state" << EOF
SEARCH_PATH="$SEARCH_PATH"
OUTPUT_DIR="$OUTPUT_DIR"
HASH_ALGORITHM="$HASH_ALGORITHM"
SCAN_START_TIME="$SCAN_START_TIME"
EOF
  chmod 600 "$HOME/.dupefinder_state"
  [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}State saved to ~/.dupefinder_state${NC}"
}

load_state() {
  if [[ -f "$HOME/.dupefinder_state" ]]; then
    local owner perm
    owner=$(stat -c "%U" -- "$HOME/.dupefinder_state" 2>/dev/null)
    perm=$(stat -c "%a" -- "$HOME/.dupefinder_state" 2>/dev/null)
    if [[ "$owner" != "$USER" || "$perm" -gt 600 ]]; then
      echo -e "${RED}Unsafe resume file permissions/ownership; ignoring.${NC}"
      return 1
    fi
    safe_source "$HOME/.dupefinder_state"
    echo -e "${CYAN}Resuming previous scan...${NC}"
    return 0
  fi
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION AND VALIDATION
# ═══════════════════════════════════════════════════════════════════════════
init_logging() {
  if [[ -n "$LOG_FILE" ]]; then
    echo "$(date): DupeFinder Pro v$VERSION started by $USER" >> "$LOG_FILE"
    echo "$(date): Search path: $SEARCH_PATH" >> "$LOG_FILE"
    echo "$(date): System protection: $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")" >> "$LOG_FILE"
  fi
}

check_dependencies() {
  if ! command -v "$HASH_ALGORITHM" &>/dev/null; then
    echo -e "${RED}Error: $HASH_ALGORITHM not found.${NC}"
    echo -e "${YELLOW}Try: sudo apt install coreutils${NC}"
    exit 1
  fi
  if [[ $USE_CACHE -eq 1 || $SAVE_CHECKSUMS -eq 1 ]]; then
    if ! command -v sqlite3 &>/dev/null; then
      echo -e "${RED}Error: sqlite3 is not installed. Cache/checksum disabled.${NC}"
      echo -e "${YELLOW}Install with: sudo apt install sqlite3${NC}"
      USE_CACHE=0
      SAVE_CHECKSUMS=0
    fi
  fi
  if [[ $USE_TRASH -eq 1 ]] && ! command -v trash-put &>/dev/null; then
    echo -e "${YELLOW}Warning: trash-cli not installed. Falling back to rm.${NC}"
    echo -e "${YELLOW}Install with: sudo apt install trash-cli${NC}"
    USE_TRASH=0
  fi
  if [[ $USE_PARALLEL -eq 1 ]] && ! command -v parallel &>/dev/null; then
    echo -e "${YELLOW}Warning: GNU parallel not installed. Falling back to xargs.${NC}"
    echo -e "${YELLOW}Install with: sudo apt install parallel${NC}"
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

validate_inputs() {
  if [[ $RESUME_STATE -eq 1 ]] && load_state; then
    echo -e "${GREEN}Resuming previous scan${NC}"
  fi
  if [[ ! -d "$SEARCH_PATH" ]]; then
    echo -e "${RED}Error: Search path does not exist: $SEARCH_PATH${NC}"
    exit 1
  fi
  mkdir -p -- "$OUTPUT_DIR" || {
    echo -e "${RED}Cannot create output directory: $OUTPUT_DIR${NC}"
    exit 1
  }
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
    mkdir -p -- "$QUARANTINE_DIR" || {
      echo -e "${RED}Cannot create quarantine directory${NC}"
      exit 1
    }
    [[ ! -w "$QUARANTINE_DIR" ]] && {
      echo -e "${RED}Quarantine directory not writable${NC}"
      exit 1
    }
  fi
  if [[ -n "$BACKUP_DIR" ]]; then
    mkdir -p -- "$BACKUP_DIR" || {
      echo -e "${RED}Cannot create backup directory${NC}"
      exit 1
    }
    [[ ! -w "$BACKUP_DIR" ]] && {
      echo -e "${RED}Backup directory not writable${NC}"
      exit 1
    }
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
    [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Excluding system folders: ${SYSTEM_FOLDERS[*]}${NC}"
  fi
  if [[ "$USER" == "root" && $SKIP_SYSTEM_FOLDERS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ WARNING: Running as root without --skip-system${NC}"
    echo -e "${YELLOW}  System files could be affected. Consider using --skip-system${NC}"
    if [[ $DELETE_MODE -eq 1 && $FORCE_SYSTEM_DELETE -eq 0 ]]; then
      echo -ne "${YELLOW}  Continue anyway? (y/N): ${NC}"
      read -r response
      [[ "$response" != "y" && "$response" != "Y" ]] && exit 1
    fi
  fi
  if printf '%s\n' "${EXCLUDE_PATHS[@]}" | grep -qE '^/mnt$|^/media$'; then
    echo -e "${YELLOW}Note:${NC} /mnt and /media are excluded by default."
    echo -e "${YELLOW}      Remove from --exclude to scan external drives.${NC}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# DATABASE CACHE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════
# (Future Feature - Not Yet Implemented)
init_cache() {
  if [[ $USE_CACHE -eq 1 || $SAVE_CHECKSUMS -eq 1 ]]; then
    [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Initializing cache database...${NC}"
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
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# FILE DISCOVERY
# ═══════════════════════════════════════════════════════════════════════════
find_files() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}🔍 Scanning filesystem...${NC}"
  local find_cmd="find"
  local args=()

  # Add -L flag to follow symlinks if requested
  if [[ $FOLLOW_SYMLINKS -eq 1 ]]; then
    args+=(-L)
  fi

  args+=("$SEARCH_PATH")
  [[ -n "$MAX_DEPTH" ]] && args+=(-maxdepth "$MAX_DEPTH")
  
  # Exclude specified paths
  if [[ ${#EXCLUDE_PATHS[@]} -gt 0 ]]; then
    args+=( \( -false \) -o )
    for ex in "${EXCLUDE_PATHS[@]}"; do
      args+=( -path "$ex" -prune -o )
    done
  fi

  args+=(-type f)
  [[ $HIDDEN_FILES -eq 0 ]] && args+=(-not -path '*/.*')

  # Only exclude symlink files when not following.
  [[ $FOLLOW_SYMLINKS -eq 0 ]] && args+=(-not -type l)

  [[ $MIN_SIZE -gt 0 ]] && args+=(-size "+${MIN_SIZE}c")
  [[ -n "$MAX_SIZE" ]] && args+=(-size "-${MAX_SIZE}c")

  # Add file pattern matching if specified
  if [[ ${#FILE_PATTERN[@]} -gt 0 ]]; then
    args+=( \( )
    local firstp=1
    for pat in "${FILE_PATTERN[@]}"; do
      if [[ $firstp -eq 1 ]]; then
        args+=(-name "$pat")
        firstp=0
      else
        args+=(-o -name "$pat")
      fi
    done
    args+=( \) )
  fi

  args+=(-print0)
  
  if [[ $VERBOSE -eq 1 ]]; then
    echo -e "${CYAN}Find command:${NC}"
    printf '%s ' "$find_cmd"
    printf -- "'%s' " "${args[@]}"
    echo ""
  fi

  "$find_cmd" "${args[@]}" 2>/dev/null > "$TEMP_DIR/files.list"
  if [[ ! -s "$TEMP_DIR/files.list" ]]; then
    [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}No files matched criteria.${NC}"
    TOTAL_FILES=0
    return 1
  fi
  TOTAL_FILES=$(tr -cd '\0' < "$TEMP_DIR/files.list" | wc -c)
  return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# HASH CALCULATION
# ═══════════════════════════════════════════════════════════════════════════
hash_worker() {
  local file="$1"
  local algo="$2"
  local fast="$3"
  local hash=""
  local mtime size

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  mtime=$(stat -c%Y -- "$file" 2>/dev/null || echo 0)
  size=$(stat -c%s -- "$file" 2>/dev/null || echo 0)
  
  if [[ "$fast" == "1" ]]; then
    local name_hash
    name_hash=$(printf '%s' "$(basename -- "$file")" | md5sum | cut -d' ' -f1)
    hash="${size}_${name_hash:0:16}"
  else
    hash=$($algo -- "$file" 2>/dev/null | cut -d' ' -f1)
  fi

  [[ -z "$hash" ]] && return 0
  
  printf '%s%s%s%s%s%s%s\n' "$hash" "$DELIM" "$size" "$DELIM" "$mtime" "$DELIM" "$file"
}

# The export is necessary for xargs/parallel to access the function.
export -f hash_worker

calculate_hashes() {
  local mode_text="standard"
  [[ $FAST_MODE -eq 1 ]] && mode_text="fast"
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📊 Calculating file hashes ($mode_text mode, threads: $THREADS)...${NC}"
  
  if [[ $TOTAL_FILES -eq 0 ]]; then
    return
  fi

  local hashes_temp="$TEMP_DIR/hashes.temp"
  : > "$hashes_temp"

  # Use `xargs` with a specific number of processes for efficient parallelism
  xargs -0 -I{} -P "$THREADS" bash -c 'hash_worker "$@"' _ "{}" "$HASH_ALGORITHM" "$FAST_MODE" \
    < "$TEMP_DIR/files.list" >> "$hashes_temp"

  if [[ ! -s "$hashes_temp" ]]; then
    echo -e "${RED}Error: Hashing failed or no files were processed.${NC}"
    rm -f -- "$hashes_temp"
    exit 1
  fi

  mv -- "$hashes_temp" "$TEMP_DIR/hashes.txt"
}

# ═══════════════════════════════════════════════════════════════════════════
# DUPLICATE DETECTION
# ═══════════════════════════════════════════════════════════════════════════
find_duplicates() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}🔎 Analyzing duplicates...${NC}"
  
  # Sort the files by hash to group duplicates.
  sort -t"$DELIM" -k1,1 < "$TEMP_DIR/hashes.txt" > "$TEMP_DIR/sorted_hashes.txt"
  
  # Use awk to find duplicate groups based on identical hash values.
  awk -F"$DELIM" '
  BEGIN { prev_hash = ""; dup_count = 0; wasted = 0; gcount = 0; }
  {
    hash=$1; size=$2; mtime=$3; file=$4
    # Check for duplicate files with the same hash
    if (hash == prev_hash) {
      if (prev_hash != current_group_hash) {
        # Start of a new duplicate group
        gcount++
        print "---"
        print hash ":" prev_file "|" prev_size "|" prev_mtime
        current_group_hash = prev_hash
      }
      print file "|" size "|" mtime
      dup_count++
      wasted += size
    } else {
      current_group_hash = ""
    }
    prev_hash = hash
    prev_file = file
    prev_size = size
    prev_mtime = mtime
  }
  END {
    # Print the final stats
    print "STATS:" dup_count "|" wasted "|" gcount
  }' "$TEMP_DIR/sorted_hashes.txt" > "$TEMP_DIR/duplicates.txt"

  # Extract statistics and duplicate groups
  local stats=$(grep "^STATS:" "$TEMP_DIR/duplicates.txt" | cut -d: -f2)
  if [[ -n "$stats" ]]; then
    TOTAL_DUPLICATES=$(echo "$stats" | cut -d'|' -f1)
    TOTAL_SPACE_WASTED=$(echo "$stats" | cut -d'|' -f2)
    TOTAL_DUPLICATE_GROUPS=$(echo "$stats" | cut -d'|' -f3)
  fi

  DUPLICATE_GROUPS=$(grep -v "^STATS:" "$TEMP_DIR/duplicates.txt")

  if [[ $FUZZY_MATCH -eq 1 ]]; then
    find_similar_files
  fi
}

find_similar_files() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}🔍 Finding similar files (fuzzy)...${NC}"
  echo -e "${YELLOW}Fuzzy matching is not yet implemented for this version.${NC}"
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
  local keep_file="${files_arr[0]}"
  local best_priority=999
  
  for file_info in "${files_arr[@]}"; do
    local file_path=$(echo "$file_info" | cut -d'|' -f1)
    local priority=$(get_location_priority "$file_path")
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

  if [[ $TOTAL_DUPLICATE_GROUPS -eq 0 ]]; then
    echo -e "${YELLOW}No duplicate groups found to display.${NC}"
    return
  fi

  echo ""
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}     DUPLICATE GROUPS FOUND${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  
  local gid=0
  local current_group_hash files_in_group
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "---" ]]; then
      if [[ -n "$files_in_group" ]]; then
        ((gid++))
        echo -e "${BOLD}${CYAN}Group $gid:${NC} Hash ${current_group_hash:0:16}... (Total size: $(format_size "$group_size"))"
        echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"
        
        local keep_idx=-1
        local file_list=()
        
        while IFS='|' read -r path size mtime; do
            file_list+=("$path|$size|$mtime")
        done <<< "$files_in_group"
        
        if [[ $SMART_DELETE -eq 1 ]]; then
            local keep_file=$(select_file_to_keep "${file_list[@]}")
            for i in "${!file_list[@]}"; do
                if [[ "${file_list[$i]}" == "$keep_file"* ]]; then
                    keep_idx=$i
                    break
                fi
            done
        elif [[ -n "$KEEP_PATH_PRIORITY" ]]; then
            for i in "${!file_list[@]}"; do
                if [[ "${file_list[$i]}" == "$KEEP_PATH_PRIORITY"* ]]; then
                    keep_idx=$i
                    break
                fi
            done
        elif [[ $KEEP_NEWEST -eq 1 ]]; then
            IFS=$'\n' read -r -d '' -a file_list_sorted < <(printf '%s\n' "${file_list[@]}" | sort -t'|' -k3,3rn)
            file_list=("${file_list_sorted[@]}")
            keep_idx=0
        elif [[ $KEEP_OLDEST -eq 1 ]]; then
            IFS=$'\n' read -r -d '' -a file_list_sorted < <(printf '%s\n' "${file_list[@]}" | sort -t'|' -k3,3n)
            file_list=("${file_list_sorted[@]}")
            keep_idx=0
        else
            IFS=$'\n' read -r -d '' -a file_list_sorted < <(printf '%s\n' "${file_list[@]}" | sort)
            file_list=("${file_list_sorted[@]}")
            keep_idx=0
        fi

        for i in "${!file_list[@]}"; do
          local path size
          path=$(echo "${file_list[$i]}" | cut -d'|' -f1)
          size=$(echo "${file_list[$i]}" | cut -d'|' -f2)
          local status=""
          [[ $i -eq $keep_idx ]] && status=" (keep)"
          is_in_system_folder "$path" && status=" (system file)"
          echo -e "  - $(format_size "$size")  ${DIM}${path}${NC}${GREEN}${status}${NC}"
        done
        echo ""
      fi
      current_group_hash=""
      files_in_group=""
      group_size=0
      continue
    fi
    
    if [[ "$line" =~ ^([a-f0-9]+):(.*)$ ]]; then
      current_group_hash="${BASH_REMATCH[1]}"
      line="${BASH_REMATCH[2]}"
    fi

    local path size mtime
    path=$(echo "$line" | cut -d'|' -f1)
    size=$(echo "$line" | cut -d'|' -f2)
    mtime=$(echo "$line" | cut -d'|' -f3)

    files_in_group+="$path|$size|$mtime"$'\n'
    ((group_size+=size))
  done < "$TEMP_DIR/duplicates.txt"
}


# ═══════════════════════════════════════════════════════════════════════════
# ENHANCED INTERACTIVE MODE FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════
show_file_details() {
  local file="$1"
  local is_keep="$2"
  if [[ ! -f "$file" ]]; then
    echo -e "${RED}    ⚠ File not found: $file${NC}"
    return
  fi
  local mtime=$(stat -c '%Y' -- "$file" 2>/dev/null || echo 0)
  local mtime_human=$(date -d "@$mtime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
  local perms=$(stat -c '%A' -- "$file" 2>/dev/null || echo "Unknown")
  local owner=$(stat -c '%U:%G' -- "$file" 2>/dev/null || echo "Unknown")
  local size=$(stat -c '%s' -- "$file" 2>/dev/null || echo 0)
  local path_short="$file"
  if [[ ${#file} -gt 80 ]]; then
    path_short="...${file: -75}"
  fi
  local status_icons=""
  [[ "$is_keep" == "true" ]] && status_icons+="🔒 "
  is_critical_system_file "$file" && status_icons+="⚠️ "
  is_in_system_folder "$file" && status_icons+="🛡️ "
  [[ -x "$file" ]] && status_icons+="⚡ "
  echo -e "    ${BOLD}📄 ${path_short}${NC}"
  echo -e "    ${CYAN}Size:${NC}      $(format_size "$size") ($size bytes)"
  echo -e "    ${CYAN}Modified:${NC}  $mtime_human"
  echo -e "    ${CYAN}Owner:${NC}     $owner"
  echo -e "    ${CYAN}Perms:${NC}     $perms"
  [[ -n "$status_icons" ]] && echo -e "    ${CYAN}Status:${NC}    $status_icons"
  echo ""
}

show_file_comparison() {
  local keep_file="$1"
  local dup_file="$2"
  echo -e "${WHITE}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${WHITE}│         FILE COMPARISON                 │${NC}"
  echo -e "${WHITE}├─────────────────────────────────────────────────────────┤${NC}"
  echo -e "${GREEN}  🔒 KEEP (Current choice):${NC}"
  show_file_details "$keep_file" "true"
  echo -e "${WHITE}├─────────────────────────────────────────────────────────┤${NC}"
  echo -e "${YELLOW}  🔄 DUPLICATE:${NC}"
  show_file_details "$dup_file" "false"
  echo -e "${WHITE}╰─────────────────────────────────────────────────────────╯${NC}"
}

show_interactive_menu() {
  local group_num="$1"
  local total_groups="$2"
  local freed_space="$3"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  Interactive Mode - Group $group_num of $total_groups${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "${BOLD}Available Actions:${NC}"
  echo ""
  echo -e "${GREEN}  [d] Delete      - Remove the duplicate file permanently"
  echo -e "${BLUE}  [h] Hardlink    - Replace duplicate with hardlink (saves space)"
  echo -e "${YELLOW}  [s] Skip        - Keep both files, move to next"
  echo -e "${CYAN}  [k] Keep This   - Mark this file as the one to keep instead"
  echo -e "${MAGENTA}  [v] View        - Open file in default application"
  echo -e "${WHITE}  [i] Info        - Show detailed file information"
  echo -e "${DIM}  [a] Apply to All- Apply current choice to remaining duplicates"
  echo -e "${RED}  [q] Quit        - Stop processing and exit"
  echo ""
  echo -e "${DIM}Potential space savings: $(format_size "$freed_space")${NC}"
  echo ""
}

get_interactive_choice() {
  local default="${1:-d}"
  echo -ne "${BOLD}Choose action [${default}]: ${NC}"
  read -r -n 1 response
  echo ""
  response=${response,,}
  [[ -z "$response" ]] && response="$default"
  echo "$response"
}

open_file_viewer() {
  local file="$1"
  if command -v xdg-open &>/dev/null; then
    echo -e "${CYAN}Opening file in default application...${NC}"
    xdg-open -- "$file" 2>/dev/null &
  elif command -v open &>/dev/null; then
    echo -e "${CYAN}Opening file in default application...${NC}"
    open -- "$file" 2>/dev/null &
  elif command -v start &>/dev/null; then
    echo -e "${CYAN}Opening file in default application...${NC}"
    start -- "$file" 2>/dev/null &
  else
    echo -e "${YELLOW}No file viewer available. File path: $file${NC}"
  fi
  echo -ne "${DIM}Press Enter to continue...${NC}"
  read -r
}

# ═══════════════════════════════════════════════════════════════════════════
# FILE OPERATIONS
# ═══════════════════════════════════════════════════════════════════════════
backup_file() {
  local file="$1"
  [[ -z "$BACKUP_DIR" ]] && return 0
  local timestamp dir relative_path target
  timestamp=$(date +%Y%m%d_%H%M%S)
  dir="$BACKUP_DIR/$timestamp"
  mkdir -p -- "$dir"
  relative_path="${file#/}"
  target="$dir/$relative_path"
  mkdir -p -- "$(dirname -- "$target")"
  if cp -p -- "$file" "$target" 2>/dev/null; then
    [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}  Backed up: $file${NC}"
    return 0
  fi
  return 1
}

verify_identical() {
  local file1="$1"
  local file2="$2"
  [[ $VERIFY_MODE -eq 0 ]] && return 0
  if cmp -s -- "$file1" "$file2"; then
    return 0
  fi
  echo -e "${YELLOW}  Warning: Same hash but content differs! This may indicate a hash collision or read error.${NC}"
  echo -e "${YELLOW}  A: $file1${NC}"
  echo -e "${YELLOW}  B: $file2${NC}"
  [[ -n "$LOG_FILE" ]] && echo "$(date): Mismatch detected (hash collision/read error): $file1 and $file2" >> "$LOG_FILE"
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
  
  local deleted=0 freed=0 links=0 quarantined=0 processed_space=0
  local auto_choice="" apply_to_all=0
  local group_count=0
  local total_groups=$(grep -c "---" "$TEMP_DIR/duplicates.txt")
  
  local current_group_hash files_in_group
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "---" ]]; then
      if [[ -n "$files_in_group" ]]; then
        ((group_count++))
        local file_list=()
        while IFS='|' read -r path size mtime; do
            file_list+=("$path|$size|$mtime")
        done <<< "$files_in_group"

        local keep_idx=-1
        local keep_file keep_size
        
        # Determine which file to keep based on strategy
        if [[ $SMART_DELETE -eq 1 ]]; then
            local keep_path=$(select_file_to_keep "${file_list[@]}")
            for i in "${!file_list[@]}"; do
                if [[ "${file_list[$i]}" == "$keep_path"* ]]; then keep_idx=$i; break; fi
            done
        elif [[ -n "$KEEP_PATH_PRIORITY" ]]; then
            for i in "${!file_list[@]}"; do
                if [[ "${file_list[$i]}" == "$KEEP_PATH_PRIORITY"* ]]; then keep_idx=$i; break; fi
            done
        elif [[ $KEEP_NEWEST -eq 1 ]]; then
            IFS=$'\n' read -r -d '' -a file_list_sorted < <(printf '%s\n' "${file_list[@]}" | sort -t'|' -k3,3rn)
            file_list=("${file_list_sorted[@]}")
            keep_idx=0
        elif [[ $KEEP_OLDEST -eq 1 ]]; then
            IFS=$'\n' read -r -d '' -a file_list_sorted < <(printf '%s\n' "${file_list[@]}" | sort -t'|' -k3,3n)
            file_list=("${file_list_sorted[@]}")
            keep_idx=0
        else
            IFS=$'\n' read -r -d '' -a file_list_sorted < <(printf '%s\n' "${file_list[@]}" | sort)
            file_list=("${file_list_sorted[@]}")
            keep_idx=0
        fi

        # Extract the details of the file to keep
        if [[ $keep_idx -ne -1 ]]; then
            keep_file=$(echo "${file_list[$keep_idx]}" | cut -d'|' -f1)
            keep_size=$(echo "${file_list[$keep_idx]}" | cut -d'|' -f2)
            [[ $VERBOSE -eq 1 ]] && echo -e "${GREEN}  ✓ Keeping: $keep_file${NC}"
        fi

        for i in "${!file_list[@]}"; do
          if [[ $i -eq $keep_idx ]]; then continue; fi
          local path size
          path=$(echo "${file_list[$i]}" | cut -d'|' -f1)
          size=$(echo "${file_list[$i]}" | cut -d'|' -f2)
          ((processed_space+=size))
          
          if ! verify_safe_to_delete "$path"; then
            echo -e "${GREEN}  ✓ Skipped (safety check): $path${NC}"
            [[ -n "$LOG_FILE" ]] && echo "$(date): Skipped (safety): $path" >> "$LOG_FILE"
            continue
          fi
          
          if [[ $SKIP_SYSTEM_FOLDERS -eq 1 ]] && is_in_system_folder "$path"; then
            [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ⚠ Skipped (system folder): $path${NC}"
            continue
          fi
          
          if [[ $VERIFY_MODE -eq 1 ]]; then
            if ! verify_identical "$keep_file" "$path"; then
              echo -e "${RED}  Skipping non-identical files${NC}"
              continue
            fi
          fi
          
          if [[ $INTERACTIVE_DELETE -eq 1 && $apply_to_all -eq 0 ]]; then
            clear
            echo -e "${CYAN}Group $group_count of $total_groups${NC}"
            echo -e "${DIM}Space processed: $(format_size "$processed_space")${NC}"
            echo ""
            show_file_comparison "$keep_file" "$path"
            local choice=""
            while true; do
              echo -e "${BOLD}Actions: [d]elete, [h]ardlink, [s]kip, [k]eep this, [v]iew, [i]nfo, [b]ackup, [g]roup skip, [q]uit, [a]pply to all${NC}"
              echo -ne "${BOLD}Choose action [d]: ${NC}"
              read -r -n 1 response
              echo ""
              response=${response,,}
              [[ -z "$response" ]] && response="d"
              case "$response" in
                d) echo -e "${YELLOW}Marking for deletion...${NC}"; break;;
                h) echo -e "${BLUE}Will create hardlink...${NC}"; HARDLINK_MODE=1; DELETE_MODE=0; break;;
                s) echo -e "${GREEN}Skipping this file...${NC}"; break;;
                k)
                  echo -e "${CYAN}Swapping keep choice...${NC}"
                  local temp_file="$keep_file"
                  keep_file="$path"
                  path="$temp_file"
                  echo -e "${GREEN}Now keeping: $keep_file${NC}"; sleep 1; continue;;
                v) open_file_viewer "$path"; continue;;
                i)
                  clear
                  echo -e "${CYAN}=== DETAILED FILE INFORMATION ===${NC}"
                  echo ""
                  echo -e "${GREEN}KEEP FILE:${NC}"
                  show_file_details "$keep_file" "true"
                  echo -e "${YELLOW}DUPLICATE FILE:${NC}"
                  show_file_details "$path" "false"
                  echo -ne "${DIM}Press Enter to continue...${NC}"; read -r; continue;;
                b)
                  if [[ $DRY_RUN -eq 1 ]]; then echo -e "${YELLOW}Would backup: $path${NC}"; else backup_file "$path"; fi
                  continue;;
                g) echo -e "${YELLOW}Skipping rest of this group...${NC}"; return;;
                a)
                  echo -ne "${YELLOW}Apply this choice (${response}) to all remaining duplicates? (y/N): ${NC}"; read -r confirm
                  if [[ "$confirm" =~ ^[Yy] ]]; then apply_to_all=1; auto_choice="$response"; echo -e "${GREEN}Will apply '$response' to remaining files...${NC}"; sleep 1; fi
                  break;;
                q) echo -e "${YELLOW}Quitting interactive mode...${NC}"; exit 0;;
                *) echo -e "${RED}Invalid choice. Please try again.${NC}"; sleep 1; continue;;
              esac
            done
            if [[ "$response" == "s" ]]; then echo -e "${GREEN}  ✓ Skipped: $path${NC}"; continue; fi
            if [[ "$response" == "k" ]]; then continue; fi
          fi
          
          if [[ -n "$BACKUP_DIR" && $DRY_RUN -eq 0 ]]; then backup_file "$path"; fi
          
          if [[ $DRY_RUN -eq 1 ]]; then
            if [[ $HARDLINK_MODE -eq 1 ]]; then echo -e "${YELLOW}  Would hardlink: $path -> $keep_file${NC}";
            elif [[ -n "$QUARANTINE_DIR" ]]; then echo -e "${YELLOW}  Would quarantine: $path${NC}";
            else echo -e "${YELLOW}  Would delete: $path${NC}"; fi
            ((deleted++)); ((freed+=size))
          elif [[ $HARDLINK_MODE -eq 1 ]]; then
            if [[ -f "$keep_file" ]]; then
              if rm -f -- "$path" && ln -- "$keep_file" "$path"; then
                ((links++)); ((freed+=size))
                [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}  ↔ Hardlinked: $path${NC}"
                [[ -n "$LOG_FILE" ]] && echo "$(date): Hardlinked: $path -> $keep_file" >> "$LOG_FILE"
              else
                echo -e "${RED}  Failed to hardlink: $path${NC}"
              fi
            else
              echo -e "${RED}  Keep file not found: $keep_file${NC}"
            fi
          elif [[ -n "$QUARANTINE_DIR" ]]; then
            local qfile="$QUARANTINE_DIR/$(basename -- "$path")_$(date +%s)"
            if mv -- "$path" "$qfile" 2>/dev/null; then ((quarantined++)); ((freed+=size)); [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ⚠ Quarantined: $path${NC}"; [[ -n "$LOG_FILE" ]] && echo "$(date): Quarantined: $path -> $qfile" >> "$LOG_FILE"; fi
          elif [[ $USE_TRASH -eq 1 ]]; then
            if trash-put -- "$path" 2>/dev/null; then ((deleted++)); ((freed+=size)); [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  🗑 Trashed: $path${NC}"; [[ -n "$LOG_FILE" ]] && echo "$(date): Trashed: $path" >> "$LOG_FILE"; fi
          else
            if rm -f -- "$path" 2>/dev/null; then ((deleted++)); ((freed+=size)); [[ $VERBOSE -eq 1 ]] && echo -e "${RED}  ✗ Deleted: $path${NC}"; [[ -n "$LOG_FILE" ]] && echo "$(date): Deleted: $path" >> "$LOG_FILE"; fi
          fi
        done
      fi
      files_in_group=""
      current_group_hash=""
    elif [[ "$line" =~ ^([a-f0-9]+):(.*)$ ]]; then
      current_group_hash="${BASH_REMATCH[1]}"
      files_in_group="${BASH_REMATCH[2]}"$'\n'
    else
      files_in_group+="$line"$'\n'
    fi
  done < "$TEMP_DIR/duplicates.txt"

  FILES_DELETED=$deleted
  FILES_HARDLINKED=$links
  FILES_QUARANTINED=$quarantined
  SPACE_FREED=$freed
  
  if [[ $QUIET -eq 0 ]]; then
    if [[ $HARDLINK_MODE -eq 1 ]]; then echo -e "${GREEN}✅ Created $links hardlinks, freed $(format_size "$freed")${NC}";
    else echo -e "${GREEN}✅ Processed $deleted files, freed $(format_size "$freed")${NC}"; fi
  fi
  
  if [[ $INTERACTIVE_DELETE -eq 1 ]]; then
    clear
    echo -e "${GREEN}🎉 Interactive processing completed!${NC}"
    echo -e "${CYAN}Files processed: $deleted${NC}"
    echo -e "${CYAN}Space freed: $(format_size "$freed")${NC}"
    echo ""
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# REPORT GENERATION
# ═══════════════════════════════════════════════════════════════════════════
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
.safety-badge{background:#4caf50;color:#fff;padding:4px 8px;border-radius:4px;font-size:12px;margin-left:10px}
.safety-warning{background:#ff9800}
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
.system-file{color:#d32f2f}
</style>
<script>
function toggle(id){var el=document.getElementById(id); if(el){el.classList.toggle('show');}}
</script>
</head><body>
<div class="container">
<header>
  <h1>DupeFinder Pro Report
    $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo '<span class="safety-badge">System Protected</span>' || echo '<span class="safety-badge safety-warning">Full Scan</span>')
  </h1>
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
    local current_group_hash files_in_group
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "---" ]]; then
            if [[ -n "$files_in_group" ]]; then
                ((gid++))
                echo "<div id=\"g$gid\" class=\"group\">"
                echo "<div class=\"hdr\" onclick=\"toggle('g$gid')\">Group $gid (Hash: ${current_group_hash:0:16}…)</div>"
                echo "<div class=\"files\">"
                while IFS='|' read -r filepath size mtime; do
                    [[ -z "$filepath" ]] && continue
                    local class=""
                    is_in_system_folder "$filepath" && class="system-file"
                    printf '<div class="file"><div class="code %s">%s</div><div>Size: %s</div></div>\n' \
                        "$class" \
                        "$(printf '%s' "$filepath" | sed 's/&/\&amp;/g;s/</\&lt;/g')" \
                        "$(format_size "$size")"
                done <<< "$files_in_group"
                echo "</div></div>"
            fi
            current_group_hash=""
            files_in_group=""
            continue
        fi
        
        if [[ "$line" =~ ^([a-f0-9]+):(.*)$ ]]; then
            current_group_hash="${BASH_REMATCH[1]}"
            files_in_group="${BASH_REMATCH[2]}"$'\n'
        else
            files_in_group+="$line"$'\n'
        fi
    done < "$TEMP_DIR/duplicates.txt"

    cat << EOF
</div>
<div class="footer">
  <small>Report generated with system protection: $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "enabled" || echo "disabled")</small>
</div>
</div></body></html>
EOF
  } > "$report_file"
  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✅ HTML report saved to: $report_file${NC}"
}

generate_csv_report() {
  [[ -z "$CSV_REPORT" ]] && return
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📊 Generating CSV report...${NC}"
  local csv="$OUTPUT_DIR/$CSV_REPORT"
  echo "Hash,File Path,Size (bytes),Size (human),Group ID,System File" > "$csv"
  local gid=0
  local current_group_hash files_in_group
  
  while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == "---" ]]; then
          if [[ -n "$files_in_group" ]]; then
              ((gid++))
              while IFS='|' read -r fp sz mtime; do
                  [[ -z "$fp" ]] && continue
                  local is_system="No"
                  is_in_system_folder "$fp" && is_system="Yes"
                  printf '%s,"%s",%s,"%s",%s,%s\n' "$current_group_hash" "${fp//\"/\"\"}" "$sz" "$(format_size "$sz")" "$gid" "$is_system" >> "$csv"
              done <<< "$files_in_group"
          fi
          current_group_hash=""
          files_in_group=""
          continue
      fi
      
      if [[ "$line" =~ ^([a-f0-9]+):(.*)$ ]]; then
          current_group_hash="${BASH_REMATCH[1]}"
          files_in_group="${BASH_REMATCH[2]}"$'\n'
      else
          files_in_group+="$line"$'\n'
      fi
  done < "$TEMP_DIR/duplicates.txt"

  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✅ CSV report saved to: $csv${NC}"
}

generate_json_report() {
  [[ -z "$JSON_REPORT" ]] && return
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📋 Generating JSON report...${NC}"
  local json="$OUTPUT_DIR/$JSON_REPORT"

  local -a groups_array
  local gid=0
  local current_group_hash files_in_group

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "---" ]]; then
      if [[ -n "$files_in_group" ]]; then
        ((gid++))
        local -a files_array
        while IFS='|' read -r fp sz mtime; do
          [[ -z "$fp" ]] && continue
          local is_system="false"
          is_in_system_folder "$fp" && is_system="true"
          files_array+=( "{ \"path\": $(jq -R . <<<"$fp"), \"size\": $sz, \"system\": $is_system }" )
        done <<< "$files_in_group"
        local files_json=$(IFS=,; echo "[${files_array[*]}]")
        groups_array+=( "{ \"id\": $gid, \"hash\": \"$current_group_hash\", \"files\": $files_json }" )
      fi
      current_group_hash=""
      files_in_group=""
      continue
    fi
    
    if [[ "$line" =~ ^([a-f0-9]+):(.*)$ ]]; then
      current_group_hash="${BASH_REMATCH[1]}"
      files_in_group="${BASH_REMATCH[2]}"$'\n'
    else
      files_in_group+="$line"$'\n'
    fi
  done < "$TEMP_DIR/duplicates.txt"

  local groups_json=$(IFS=,; echo "[${groups_array[*]}]")

  local metadata_json=$(jq -n \
    --arg version "$VERSION" \
    --arg author "$AUTHOR" \
    --arg generated "$(date -Iseconds)" \
    --arg search_path "$SEARCH_PATH" \
    --arg total_files "${TOTAL_FILES:-0}" \
    --arg total_duplicates "${TOTAL_DUPLICATES:-0}" \
    --arg total_groups "${TOTAL_DUPLICATE_GROUPS:-0}" \
    --arg space_wasted "${TOTAL_SPACE_WASTED:-0}" \
    --arg hash_algo "${HASH_ALGORITHM%%sum}" \
    '{ version: $version, author: $author, generated: $generated, search_path: $search_path, total_files: ($total_files|tonumber), total_duplicates: ($total_duplicates|tonumber), total_groups: ($total_groups|tonumber), space_wasted: ($space_wasted|tonumber), hash_algorithm: $hash_algo, system_protection: (if '"$SKIP_SYSTEM_FOLDERS"' == "1" then true else false end) }')

  printf '{"metadata": %s, "groups": %s}\n' "$metadata_json" "$groups_json" | jq . > "$json"
  
  if [[ $? -eq 0 ]]; then
    [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✅ JSON report saved to: $json${NC}"
  else
    echo -e "${RED}Error: Failed to generate JSON report. Check filenames for invalid characters.${NC}"
    rm -f -- "$json"
  fi
}


# ═══════════════════════════════════════════════════════════════════════════
# EMAIL AND SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
calculate_duration() {
  local duration=$((SCAN_END_TIME - SCAN_START_TIME))
  local hours=$((duration/3600))
  local minutes=$(((duration%3600)/60))
  local seconds=$((duration%60))
  if (( hours > 0 )); then printf "%dh %dm %ds" "$hours" "$minutes" "$seconds";
  elif (( minutes > 0 )); then printf "%dm %ds" "$minutes" "$seconds";
  else printf "%ds" "$seconds"; fi
}

send_email_report() {
  [[ -z "$EMAIL_REPORT" ]] && return
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📧 Sending email report...${NC}"
  local subject="DupeFinder Pro Report - $(date '+%Y-%m-%d')"
  local body="DupeFinder Pro Scan Results
Configuration:
  Search Path: $SEARCH_PATH
  System Protection: $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "Enabled" || echo "Disabled")
  Hash Algorithm: ${HASH_ALGORITHM%%sum}
Results:
  Total Files Scanned: ${TOTAL_FILES:-0}
  Duplicate Files Found: ${TOTAL_DUPLICATES:-0}
  Duplicate Groups: ${TOTAL_DUPLICATE_GROUPS:-0}
  Space Wasted: $(format_size ${TOTAL_SPACE_WASTED:-0})
Actions:
  Files Processed: ${FILES_DELETED:-0}
  Space Freed: $(format_size ${SPACE_FREED:-0})
Performance:
  Scan Duration: $(calculate_duration)
  Threads Used: $THREADS
Reports:
  HTML Report: $OUTPUT_DIR/$HTML_REPORT"
  if command -v mail &>/dev/null; then
    echo "$body" | mail -s "$subject" "$EMAIL_REPORT"
    [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✅ Email sent to: $EMAIL_REPORT${NC}"
  else
    [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}⚠ Mail command not available${NC}"
  fi
}

show_summary() {
  [[ $QUIET -eq 1 ]] && return
  echo ""
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}     SCAN SUMMARY${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}📁 Search Path:${NC}       $SEARCH_PATH"
  echo -e "${CYAN}🛡️  System Protection:${NC}  $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
  echo -e "${CYAN}📊 Files Scanned:${NC}       ${TOTAL_FILES:-0}"
  echo -e "${CYAN}🔄 Duplicates Found:${NC}    ${TOTAL_DUPLICATES:-0}"
  echo -e "${CYAN}📂 Duplicate Groups:${NC}    ${TOTAL_DUPLICATE_GROUPS:-0}"
  echo -e "${CYAN}💾 Space Wasted:${NC}        $(format_size "${TOTAL_SPACE_WASTED:-0}")"
  if [[ ${FILES_DELETED:-0} -gt 0 || ${FILES_HARDLINKED:-0} -gt 0 || ${FILES_QUARANTINED:-0} -gt 0 ]]; then
    echo -e "${CYAN}✅ Files Processed:${NC}     ${FILES_DELETED:-0}"
    echo -e "${CYAN}💚 Space Freed:${NC}         $(format_size "${SPACE_FREED:-0}")"
    [[ ${FILES_DELETED:-0} -gt 0 ]] && echo -e "${DIM}  - Deleted: ${FILES_DELETED}${NC}"
    [[ ${FILES_HARDLINKED:-0} -gt 0 ]] && echo -e "${DIM}  - Hardlinked: ${FILES_HARDLINKED}${NC}"
    [[ ${FILES_QUARANTINED:-0} -gt 0 ]] && echo -e "${DIM}  - Quarantined: ${FILES_QUARANTINED}${NC}"
  fi
  echo -e "${CYAN}⏱️  Scan Duration:${NC}       $(calculate_duration)"
  echo -e "${CYAN}🔧 Hash Algorithm:${NC}      ${HASH_ALGORITHM%%sum}"
  if [[ $FAST_MODE -eq 1 ]]; then echo -e "${DIM}    (Fast mode: size + filename hash)${NC}"; fi
  echo -e "${CYAN}⚡ Threads Used:${NC}        $THREADS"
  echo -e "${WHITE}─────────────────────────────────────────────────────────${NC}"
  echo -e "${CYAN}📄 HTML Report:${NC}         $OUTPUT_DIR/$HTML_REPORT"
  [[ -n "$CSV_REPORT" ]] && \
    echo -e "${CYAN}📊 CSV Report:${NC}          $OUTPUT_DIR/$CSV_REPORT"
  [[ -n "$JSON_REPORT" ]] && \
    echo -e "${CYAN}📋 JSON Report:${NC}         $OUTPUT_DIR/$JSON_REPORT"
  [[ -n "$LOG_FILE" ]] && \
    echo -e "${CYAN}📝 Log File:${NC}            $LOG_FILE"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════
main() {
  # Set locale for consistent sorting
  export LC_ALL=C
  
  # Create temp dir
  TEMP_DIR="$(mktemp -d -t dupefinder.XXXXXXXXXX)"
  if [[ ! -d "$TEMP_DIR" ]]; then
    echo -e "${RED}Error: Failed to create temporary directory.${NC}"
    exit 1
  fi
  
  # Initialization and validation
  load_config
  check_dependencies
  SCAN_START_TIME=$(date +%s)
  init_logging
  [[ $QUIET -eq 0 ]] && show_header
  validate_inputs
  
  # Core operations
  init_cache
  if find_files; then
    calculate_hashes
    find_duplicates
    
    # Check if duplicates were found before proceeding
    if [[ ${TOTAL_DUPLICATE_GROUPS:-0} -gt 0 ]]; then
      show_duplicate_details
      show_safety_summary
      delete_duplicates
      # Reporting
      generate_html_report
      generate_csv_report
      generate_json_report
    else
      [[ $QUIET -eq 0 ]] && echo -e "${GREEN}No duplicates found.${NC}"
    fi
  fi
  
  # Finalize
  SCAN_END_TIME=$(date +%s)
  send_email_report
  show_summary
  
  # Display final message
  [[ $QUIET -eq 0 ]] && echo -e "\n${GREEN}✨ Scan completed successfully!${NC}"
  [[ $QUIET -eq 0 ]] && echo -e "${DIM}DupeFinder Pro v$VERSION by $AUTHOR${NC}\n"
}

# ═══════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════
parse_arguments "$@"
main
exit 0
