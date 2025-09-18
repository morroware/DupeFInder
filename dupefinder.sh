#!/usr/bin/env bash
#############################################################################
# DupeFinder Pro - Advanced Duplicate File Manager for Linux
# Version: 0.0.1
# Author: Seth Morrow
# License: MIT
#
# Description:
#   Professional duplicate file finder with advanced management, reporting,
#   caching, smart deletion strategies, and critical system file protection.
#   This version includes comprehensive safety features to prevent accidental
#   deletion of system-critical files and libraries.
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
# DEFAULT CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════
VERSION="0.0.1"
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

# ═══════════════════════════════════════════════════════════════════════════
# CRITICAL SYSTEM PROTECTION CONFIGURATION
# These arrays define files and paths that should never be deleted to prevent
# system damage. The protection can be overridden with --force-system flag.
# ═══════════════════════════════════════════════════════════════════════════
CRITICAL_EXTENSIONS=(
  ".so"     # Shared libraries
  ".dll"    # Windows DLLs (Wine)
  ".dylib"  # macOS dynamic libraries
  ".ko"     # Kernel modules
  ".sys"    # System files
  ".elf"    # ELF executables
  ".a"      # Static libraries
  ".lib"    # Library files
  ".pdb"    # Program database
  ".exe"    # Executables
)

CRITICAL_PATHS=(
  "/boot"                     # Boot loader files
  "/lib"                      # Essential shared libraries
  "/lib64"                    # 64-bit libraries
  "/usr/lib"                  # System libraries
  "/usr/lib64"                # 64-bit system libraries
  "/usr/bin"                  # User binaries
  "/bin"                      # Essential binaries
  "/sbin"                     # System binaries
  "/usr/sbin"                 # Non-essential system binaries
  "/etc"                      # System configuration
  "/usr/share/dbus-1"         # D-Bus configuration
  "/usr/share/applications"   # Desktop entries
)

SYSTEM_FOLDERS=(
  "/boot"     # Boot loader and kernel
  "/bin"      # Essential command binaries
  "/sbin"     # Essential system binaries
  "/lib"      # Essential shared libraries
  "/lib32"    # 32-bit libraries
  "/lib64"    # 64-bit libraries
  "/libx32"   # x32 ABI libraries
  "/usr"      # Secondary hierarchy
  "/etc"      # System configuration
  "/root"     # Root user home
  "/snap"     # Snap packages
  "/sys"      # Sysfs virtual filesystem
  "/proc"     # Procfs virtual filesystem
  "/dev"      # Device files
  "/run"      # Runtime data
  "/srv"      # Service data
)

NEVER_DELETE_PATTERNS=(
  "vmlinuz*"      # Linux kernel
  "initrd*"       # Initial ramdisk
  "initramfs*"    # Initial RAM filesystem
  "grub*"         # Boot loader
  "ld-linux*"     # Dynamic linker
  "libc.so*"      # C library
  "libpthread*"   # Threading library
  "libdl*"        # Dynamic linking library
  "libm.so*"      # Math library
  "busybox*"      # Emergency shell
  "systemd*"      # Init system
)

# Safety flags
SKIP_SYSTEM_FOLDERS=0    # When enabled, excludes all system folders
FORCE_SYSTEM_DELETE=0    # Dangerous flag, requires explicit confirmation

# ═══════════════════════════════════════════════════════════════════════════
# STATISTICS COUNTERS
# Track scan progress and results for reporting
# ═══════════════════════════════════════════════════════════════════════════
TOTAL_FILES=0
TOTAL_DUPLICATES=0
TOTAL_DUPLICATE_GROUPS=0
TOTAL_SPACE_WASTED=0
FILES_DELETED=0
SPACE_FREED=0
SCAN_START_TIME=""
SCAN_END_TIME=""
DUPLICATE_GROUPS=""

# ═══════════════════════════════════════════════════════════════════════════
# SMART LOCATION PRIORITIES
# Lower number = higher priority for keeping files
# Used with --smart-delete to intelligently choose which duplicate to keep
# ═══════════════════════════════════════════════════════════════════════════
declare -A LOCATION_PRIORITY=(
  ["/home"]=1          # User files - highest priority
  ["/usr/local"]=2     # Local installations
  ["/opt"]=3           # Optional software
  ["/var"]=4           # Variable data
  ["/tmp"]=99          # Temporary files - lowest priority
  ["/downloads"]=90    # Downloads folder
  ["/cache"]=95        # Cache directories
)

# ═══════════════════════════════════════════════════════════════════════════
# CLEANUP AND SIGNAL HANDLING
# Ensures proper cleanup of temporary files and state management
# ═══════════════════════════════════════════════════════════════════════════
cleanup() {
  # Remove temporary directory if it exists
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
  
  # Log session end
  [[ -n "$LOG_FILE" ]] && echo "$(date): Session ended" >> "$LOG_FILE"
  
  # Remove resume state only if scan completed successfully
  if [[ -n "$SCAN_END_TIME" && "$SCAN_END_TIME" -gt 0 ]]; then
    rm -f "$HOME/.dupefinder_state"
  fi
}

handle_interrupt() {
  echo -e "\n${YELLOW}Interrupted!${NC}"
  
  # Offer to save state for later resume
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

# Set up signal handlers
trap handle_interrupt INT TERM
trap cleanup EXIT

# Create temporary directory for work files
TEMP_DIR="/tmp/dupefinder_$$"
mkdir -p "$TEMP_DIR"

# ═══════════════════════════════════════════════════════════════════════════
# USER INTERFACE FUNCTIONS
# Display header, help information, and usage instructions
# ═══════════════════════════════════════════════════════════════════════════
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

${BOLD}SAFETY OPTIONS:${NC}
    ${GREEN}--skip-system${NC}            Skip all system folders (/usr, /lib, /bin, etc.)
    ${GREEN}--force-system${NC}           Allow deletion of system files (DANGEROUS!)

${BOLD}SEARCH:${NC}
    ${GREEN}-f, --follow-symlinks${NC}    Follow symbolic links
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
    ${GREEN}-n, --dry-run${NC}            Show actions without executing
    ${GREEN}--trash${NC}                  Use trash (trash-cli) if available
    ${GREEN}--hardlink${NC}               Replace duplicates with hardlinks
    ${GREEN}--quarantine DIR${NC}         Move duplicates to quarantine directory

${BOLD}KEEP STRATEGIES:${NC}
    ${GREEN}-k, --keep-newest${NC}        Keep newest file from each group
    ${GREEN}-K, --keep-oldest${NC}        Keep oldest file from each group
    ${GREEN}--keep-path PATH${NC}         Prefer files in PATH
    ${GREEN}--smart-delete${NC}           Use location-based priorities
    ${GREEN}--auto-select LOC${NC}        Auto-select by location priority

${BOLD}PERFORMANCE:${NC}
    ${GREEN}--threads N${NC}              Number of threads for hashing
    ${GREEN}--cache${NC}                  Use SQLite cache database
    ${GREEN}--save-checksums${NC}         Save checksums to database
    ${GREEN}--no-progress${NC}            Disable progress bar
    ${GREEN}--parallel${NC}               Use GNU parallel if available

${BOLD}REPORTING:${NC}
    ${GREEN}-c, --csv FILE${NC}           Generate CSV report
    ${GREEN}--json FILE${NC}              Generate JSON report
    ${GREEN}--email ADDRESS${NC}          Email summary to ADDRESS
    ${GREEN}--log FILE${NC}               Log operations to FILE
    ${GREEN}-v, --verbose${NC}            Enable verbose output
    ${GREEN}-q, --quiet${NC}              Quiet mode (minimal output)

${BOLD}ADVANCED:${NC}
    ${GREEN}-s, --sha256${NC}             Use SHA256 hashing
    ${GREEN}--sha512${NC}                 Use SHA512 hashing
    ${GREEN}--backup DIR${NC}             Backup files before deletion
    ${GREEN}--config FILE${NC}            Load configuration from FILE
    ${GREEN}--exclude-list FILE${NC}      File with paths to exclude
    ${GREEN}--db-path FILE${NC}           Custom database path
    ${GREEN}--resume${NC}                 Resume previous interrupted scan

${BOLD}EXAMPLES:${NC}
    # Safe system-wide scan
    $0 --path / --skip-system --delete --dry-run
    
    # Clean downloads folder
    $0 --path ~/Downloads --min-size 1M --trash
    
    # Find duplicate photos
    $0 --path ~/Pictures --pattern "*.jpg" --pattern "*.png" --smart-delete

EOF
}

# ═══════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# Helper functions for size parsing, SQL escaping, and data formatting
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

# Format bytes into human-readable sizes
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
    # Fallback for systems without bc
    local units=(B KB MB GB TB)
    local u=0
    while [[ $size -ge 1024 && $u -lt 4 ]]; do
      size=$((size/1024))
      ((u++))
    done
    echo "$size ${units[$u]}"
  fi
}

# Escape strings for safe SQL insertion
sql_escape() {
  # Properly escape single quotes and backslashes for SQL
  echo "$1" | sed "s/'/''/g; s/\\/\\\\/g"
}

# ═══════════════════════════════════════════════════════════════════════════
# CRITICAL SAFETY VERIFICATION FUNCTIONS
# Multi-layer protection against accidental deletion of system files
# ═══════════════════════════════════════════════════════════════════════════

# Check if a file is a critical system file that should never be deleted
is_critical_system_file() {
  local file="$1"
  local basename_file
  basename_file=$(basename "$file")
  
  # Check against critical file extensions
  for ext in "${CRITICAL_EXTENSIONS[@]}"; do
    [[ "$file" == *"$ext" ]] && return 0
  done
  
  # Check if file is in a critical system path
  for path in "${CRITICAL_PATHS[@]}"; do
    [[ "$file" == "$path"/* ]] && return 0
  done
  
  # Check against never-delete filename patterns
  for pattern in "${NEVER_DELETE_PATTERNS[@]}"; do
    # Use bash pattern matching for wildcards
    if [[ "$basename_file" == $pattern ]]; then
      return 0
    fi
  done
  
  # Check if it's a system binary in critical locations
  if [[ -x "$file" ]]; then
    case "$(dirname "$file")" in
      /bin|/sbin|/usr/bin|/usr/sbin|/usr/local/bin|/usr/local/sbin)
        return 0
        ;;
    esac
  fi
  
  return 1
}

# Comprehensive safety verification before deletion
verify_safe_to_delete() {
  local file="$1"
  
  # First check: Is this a critical system file?
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
  
  # Second check: Is the file currently in use?
  if command -v lsof &>/dev/null; then
    if lsof "$file" >/dev/null 2>&1; then
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
  
  # Third check: Is this a loaded shared library?
  if [[ "$file" == *.so* ]]; then
    if grep -q "$(basename "$file")" /proc/*/maps 2>/dev/null; then
      echo -e "${RED}  ✗ Shared library is currently loaded: $file${NC}"
      return 1
    fi
  fi
  
  # Fourth check: Warn if file is owned by root
  local owner
  owner=$(stat -c '%U' "$file" 2>/dev/null)
  if [[ "$owner" == "root" && "$USER" != "root" ]]; then
    echo -e "${YELLOW}  ⚠ File is owned by root: $file${NC}"
    # Don't prevent deletion, just warn
  fi
  
  return 0
}

# Check if a file resides in a system folder
is_in_system_folder() {
  local file="$1"
  for sys_folder in "${SYSTEM_FOLDERS[@]}"; do
    [[ "$file" == "$sys_folder"/* ]] && return 0
  done
  return 1
}

# Display safety summary before destructive operations
show_safety_summary() {
  if [[ $DELETE_MODE -eq 1 || $HARDLINK_MODE -eq 1 ]]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                 SAFETY CHECK SUMMARY${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}System Folder Protection:${NC} $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    echo -e "${CYAN}Force System Delete:${NC}     $([ $FORCE_SYSTEM_DELETE -eq 1 ] && echo -e "${RED}ENABLED${NC}" || echo "DISABLED")"
    echo -e "${CYAN}Running as:${NC}              $USER"
    echo -e "${CYAN}Delete Mode:${NC}             $([ $DELETE_MODE -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
    echo -e "${CYAN}Dry Run:${NC}                 $([ $DRY_RUN -eq 1 ] && echo "YES" || echo "NO")"
    
    # Count files in system locations
    if [[ -f "$TEMP_DIR/hashes.txt" ]]; then
      local system_files=0
      while IFS='|' read -r hash size file; do
        is_in_system_folder "$file" && ((system_files++))
      done < "$TEMP_DIR/hashes.txt"
      
      if [[ $system_files -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Found $system_files files in system folders${NC}"
        if [[ $SKIP_SYSTEM_FOLDERS -eq 0 ]]; then
          echo -e "${RED}  These will be processed! Use --skip-system to exclude them${NC}"
        fi
      fi
    fi
    
    echo -e "${YELLOW}─────────────────────────────────────────────────────────${NC}"
    
    # Request confirmation for potentially dangerous operations
    if [[ $DELETE_MODE -eq 1 && $DRY_RUN -eq 0 && $FORCE_SYSTEM_DELETE -eq 0 ]]; then
      echo -ne "${YELLOW}Proceed with these settings? (y/N): ${NC}"
      read -r response
      [[ "$response" != "y" && "$response" != "Y" ]] && exit 0
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# STATE MANAGEMENT FUNCTIONS
# Save and restore scan state for resumable operations
# ═══════════════════════════════════════════════════════════════════════════
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
    # Security check: verify file ownership and permissions
    local owner perm
    owner=$(stat -c "%U" "$HOME/.dupefinder_state" 2>/dev/null)
    perm=$(stat -c "%a" "$HOME/.dupefinder_state" 2>/dev/null)
    
    if [[ "$owner" != "$USER" || "$perm" -gt 600 ]]; then
      echo -e "${RED}Unsafe resume file permissions/ownership; ignoring.${NC}"
      return 1
    fi
    
    # Source the state file
    # shellcheck disable=SC1090
    source "$HOME/.dupefinder_state"
    echo -e "${CYAN}Resuming previous scan...${NC}"
    return 0
  fi
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION MANAGEMENT
# Load external configuration files and process command-line arguments
# ═══════════════════════════════════════════════════════════════════════════
load_config() {
  if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    echo -e "${CYAN}Loading configuration from $CONFIG_FILE...${NC}"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      # Basic options
      -p|--path) SEARCH_PATH="$2"; shift 2 ;;
      -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
      -e|--exclude) EXCLUDE_PATHS+=("$2"); shift 2 ;;
      -m|--min-size) MIN_SIZE=$(parse_size "$2"); shift 2 ;;
      -M|--max-size) MAX_SIZE=$(parse_size "$2"); shift 2 ;;
      -h|--help) show_help; exit 0 ;;
      -V|--version) echo "DupeFinder Pro v$VERSION by $AUTHOR"; exit 0 ;;
      
      # Safety options
      --skip-system)
        SKIP_SYSTEM_FOLDERS=1
        echo -e "${GREEN}System folders will be excluded from scanning${NC}"
        shift ;;
      --force-system)
        FORCE_SYSTEM_DELETE=1
        echo -e "${RED}⚠ WARNING: Force system delete mode enabled - BE VERY CAREFUL!${NC}"
        shift ;;
      
      # Search options
      -f|--follow-symlinks) FOLLOW_SYMLINKS=1; shift ;;
      -z|--empty) EMPTY_FILES=1; MIN_SIZE=0; shift ;;
      -a|--all) HIDDEN_FILES=1; shift ;;
      -l|--level) MAX_DEPTH="$2"; shift 2 ;;
      -t|--pattern) FILE_PATTERN+=("$2"); shift 2 ;;
      --fast) FAST_MODE=1; shift ;;
      --fuzzy) FUZZY_MATCH=1; shift ;;
      --similarity) SIMILARITY_THRESHOLD="$2"; shift 2 ;;
      --verify) VERIFY_MODE=1; shift ;;
      
      # Deletion options
      -d|--delete) DELETE_MODE=1; shift ;;
      -i|--interactive) INTERACTIVE_DELETE=1; DELETE_MODE=1; shift ;;
      -n|--dry-run) DRY_RUN=1; shift ;;
      --trash) USE_TRASH=1; shift ;;
      --hardlink) HARDLINK_MODE=1; shift ;;
      --quarantine) QUARANTINE_DIR="$2"; shift 2 ;;
      
      # Keep strategies
      -k|--keep-newest) KEEP_NEWEST=1; shift ;;
      -K|--keep-oldest) KEEP_OLDEST=1; shift ;;
      --keep-path) KEEP_PATH_PRIORITY="$2"; shift 2 ;;
      --smart-delete) SMART_DELETE=1; shift ;;
      --auto-select) AUTO_SELECT_LOCATION="$2"; shift 2 ;;
      
      # Performance options
      --threads) THREADS="$2"; shift 2 ;;
      --cache) USE_CACHE=1; shift ;;
      --save-checksums) SAVE_CHECKSUMS=1; shift ;;
      --no-progress) PROGRESS_BAR=0; shift ;;
      --parallel) USE_PARALLEL=1; shift ;;
      
      # Reporting options
      -c|--csv) CSV_REPORT="$2"; shift 2 ;;
      --json) JSON_REPORT="$2"; shift 2 ;;
      --email) EMAIL_REPORT="$2"; shift 2 ;;
      --log) LOG_FILE="$2"; shift 2 ;;
      -v|--verbose) VERBOSE=1; shift ;;
      -q|--quiet) QUIET=1; PROGRESS_BAR=0; shift ;;
      
      # Advanced options
      -s|--sha256) HASH_ALGORITHM="sha256sum"; shift ;;
      --sha512) HASH_ALGORITHM="sha512sum"; shift ;;
      --backup) BACKUP_DIR="$2"; shift 2 ;;
      --config) CONFIG_FILE="$2"; shift 2 ;;
      --exclude-list) EXCLUDE_LIST_FILE="$2"; shift 2 ;;
      --db-path) DB_CACHE="$2"; CHECKSUM_DB="${2%.db}_checksums.db"; shift 2 ;;
      --resume) RESUME_STATE=1; shift ;;
      
      # Unknown option
      *) echo -e "${RED}Unknown option: $1${NC}"; show_help; exit 1 ;;
    esac
  done
}

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION AND VALIDATION
# Check dependencies, validate inputs, and set up the environment
# ═══════════════════════════════════════════════════════════════════════════
init_logging() {
  if [[ -n "$LOG_FILE" ]]; then
    echo "$(date): DupeFinder Pro v$VERSION started by $USER" >> "$LOG_FILE"
    echo "$(date): Search path: $SEARCH_PATH" >> "$LOG_FILE"
    echo "$(date): System protection: $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")" >> "$LOG_FILE"
  fi
}

check_dependencies() {
  # Check for SQLite3 if caching is requested
  if [[ $USE_CACHE -eq 1 || $SAVE_CHECKSUMS -eq 1 ]]; then
    if ! command -v sqlite3 &>/dev/null; then
      echo -e "${RED}Error: sqlite3 is not installed. Cache/checksum disabled.${NC}"
      echo -e "${YELLOW}Install with: sudo apt install sqlite3${NC}"
      USE_CACHE=0
      SAVE_CHECKSUMS=0
    fi
  fi
  
  # Check for trash-cli if trash mode is requested
  if [[ $USE_TRASH -eq 1 ]] && ! command -v trash-put &>/dev/null; then
    echo -e "${YELLOW}Warning: trash-cli not installed. Falling back to rm.${NC}"
    echo -e "${YELLOW}Install with: sudo apt install trash-cli${NC}"
    USE_TRASH=0
  fi
  
  # Check for GNU parallel if requested
  if [[ $USE_PARALLEL -eq 1 ]] && ! command -v parallel &>/dev/null; then
    echo -e "${YELLOW}Warning: GNU parallel not installed. Using xargs.${NC}"
    echo -e "${YELLOW}Install with: sudo apt install parallel${NC}"
    USE_PARALLEL=0
  fi
  
  # Check for mail command if email reporting is requested
  if [[ -n "$EMAIL_REPORT" ]] && ! command -v mail &>/dev/null; then
    echo -e "${YELLOW}Warning: 'mail' command not found. Email disabled.${NC}"
    EMAIL_REPORT=""
  fi
  
  # Check for jq if JSON reporting is requested
  if [[ -n "$JSON_REPORT" ]] && ! command -v jq &>/dev/null; then
    echo -e "${RED}Error: jq is not installed. JSON report disabled.${NC}"
    echo -e "${YELLOW}Install with: sudo apt install jq${NC}"
    JSON_REPORT=""
  fi
}

validate_inputs() {
  # Try to resume previous scan if requested
  if [[ $RESUME_STATE -eq 1 ]] && load_state; then
    echo -e "${GREEN}Resuming previous scan${NC}"
  fi
  
  # Validate search path
  if [[ ! -d "$SEARCH_PATH" ]]; then
    echo -e "${RED}Error: Search path does not exist: $SEARCH_PATH${NC}"
    exit 1
  fi
  
  # Create and validate output directory
  mkdir -p "$OUTPUT_DIR" || {
    echo -e "${RED}Cannot create output directory: $OUTPUT_DIR${NC}"
    exit 1
  }
  
  if [[ ! -w "$OUTPUT_DIR" ]]; then
    echo -e "${RED}Error: Cannot write to output directory: $OUTPUT_DIR${NC}"
    exit 1
  fi
  
  # Validate thread count
  if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || [[ "$THREADS" -lt 1 ]]; then
    THREADS=$(nproc)
    [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}Invalid thread count, using $THREADS threads${NC}"
  fi
  
  # Check for conflicting keep strategies
  if [[ $KEEP_NEWEST -eq 1 && $KEEP_OLDEST -eq 1 ]]; then
    echo -e "${RED}Error: Cannot use both --keep-newest and --keep-oldest${NC}"
    exit 1
  fi
  
  # Validate and create quarantine directory if specified
  if [[ -n "$QUARANTINE_DIR" ]]; then
    mkdir -p "$QUARANTINE_DIR" || {
      echo -e "${RED}Cannot create quarantine directory${NC}"
      exit 1
    }
    [[ ! -w "$QUARANTINE_DIR" ]] && {
      echo -e "${RED}Quarantine directory not writable${NC}"
      exit 1
    }
  fi
  
  # Validate and create backup directory if specified
  if [[ -n "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR" || {
      echo -e "${RED}Cannot create backup directory${NC}"
      exit 1
    }
    [[ ! -w "$BACKUP_DIR" ]] && {
      echo -e "${RED}Backup directory not writable${NC}"
      exit 1
    }
  fi
  
  # Process exclude list file if provided
  if [[ -n "$EXCLUDE_LIST_FILE" && -f "$EXCLUDE_LIST_FILE" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" && ! "$line" =~ ^# ]] && EXCLUDE_PATHS+=("$line")
    done < "$EXCLUDE_LIST_FILE"
  fi
  
  # Add system folders to exclude list if requested
  if [[ $SKIP_SYSTEM_FOLDERS -eq 1 ]]; then
    for sys_folder in "${SYSTEM_FOLDERS[@]}"; do
      # Only add if it exists and isn't already excluded
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
  
  # Safety warning for root execution without system protection
  if [[ "$USER" == "root" && $SKIP_SYSTEM_FOLDERS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ WARNING: Running as root without --skip-system${NC}"
    echo -e "${YELLOW}  System files could be affected. Consider using --skip-system${NC}"
    if [[ $DELETE_MODE -eq 1 && $FORCE_SYSTEM_DELETE -eq 0 ]]; then
      echo -ne "${YELLOW}  Continue anyway? (y/N): ${NC}"
      read -r response
      [[ "$response" != "y" && "$response" != "Y" ]] && exit 1
    fi
  fi
  
  # Display warning about excluded external media
  if printf '%s\n' "${EXCLUDE_PATHS[@]}" | grep -qE '^/mnt$|^/media$'; then
    echo -e "${YELLOW}Note:${NC} /mnt and /media are excluded by default."
    echo -e "${YELLOW}      Remove from --exclude to scan external drives.${NC}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# DATABASE CACHE MANAGEMENT
# SQLite-based caching for improved performance on repeated scans
# ═══════════════════════════════════════════════════════════════════════════
init_cache() {
  if [[ $USE_CACHE -eq 1 || $SAVE_CHECKSUMS -eq 1 ]]; then
    [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Initializing cache database...${NC}"
    
    # Create database schema if it doesn't exist
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
    
    # Clean old entries (older than 30 days)
    local cutoff=$(($(date +%s) - 2592000))
    sqlite3 "$DB_CACHE" "DELETE FROM file_hashes WHERE last_scan < $cutoff;" >/dev/null 2>&1
    
    # Initialize SQL buffer for batch operations
    : > "$TEMP_DIR/sql_buffer.sql"
  fi
}

# Flush batched SQL operations for better performance
flush_cache_batch() {
  if [[ $USE_CACHE -eq 1 || $SAVE_CHECKSUMS -eq 1 ]]; then
    if [[ -s "$TEMP_DIR/sql_buffer.sql" ]]; then
      [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Flushing batched SQLite writes...${NC}"
      
      # Wrap all operations in a single transaction
      printf 'BEGIN IMMEDIATE;\n' > "$TEMP_DIR/sql_txn.sql"
      cat "$TEMP_DIR/sql_buffer.sql" >> "$TEMP_DIR/sql_txn.sql"
      printf 'COMMIT;\n' >> "$TEMP_DIR/sql_txn.sql"
      
      sqlite3 "$DB_CACHE" < "$TEMP_DIR/sql_txn.sql" >/dev/null 2>&1
      
      # Clear buffer for next batch
      : > "$TEMP_DIR/sql_buffer.sql"
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# FILE DISCOVERY
# Find all files matching the specified criteria
# ═══════════════════════════════════════════════════════════════════════════
find_files() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}🔍 Scanning filesystem...${NC}"
  
  # Build find command with appropriate options
  local find_cmd="find"
  local args=("$SEARCH_PATH")
  
  # Add max depth if specified
  [[ -n "$MAX_DEPTH" ]] && args+=(-maxdepth "$MAX_DEPTH")
  
  # Add exclude paths with proper pruning
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
  
  # Add file type and other filters
  args+=(-type f)
  [[ $HIDDEN_FILES -eq 0 ]] && args+=(-not -path '*/.*')
  [[ $FOLLOW_SYMLINKS -eq 0 ]] && args+=(-not -type l)
  [[ $MIN_SIZE -gt 0 ]] && args+=(-size "+${MIN_SIZE}c")
  [[ -n "$MAX_SIZE" ]] && args+=(-size "-${MAX_SIZE}c")
  
  # Add file pattern filters if specified
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
  
  # Output null-delimited for safety
  args+=(-print0)
  
  [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Find command:${NC} $find_cmd ${args[*]}"
  
  # Execute find and save results
  "$find_cmd" "${args[@]}" 2>/dev/null > "$TEMP_DIR/files.list"
}

# ═══════════════════════════════════════════════════════════════════════════
# HASH CALCULATION
# Calculate checksums for all discovered files
# ═══════════════════════════════════════════════════════════════════════════

# Worker function for parallel hash calculation
# Each worker writes to its own temporary file to avoid race conditions
hash_worker() {
  local file="$1"
  local algo="$2"
  local fast="$3"
  local worker_id="$4"  # Unique identifier for this worker
  
  # Skip unreadable files
  [[ ! -r "$file" ]] && return 0
  
  local mtime size hash
  mtime=$(stat -c%Y "$file" 2>/dev/null) || mtime=0
  size=$(stat -c%s "$file" 2>/dev/null) || size=0
  
  if [[ "$fast" == "1" ]]; then
    # Fast mode: use size and partial name hash
    local name_hash
    name_hash=$(basename "$file" | md5sum | cut -d' ' -f1)
    hash="${size}_${name_hash:0:16}"
  else
    # Full file hash
    hash=$($algo "$file" 2>/dev/null | cut -d' ' -f1)
  fi
  
  [[ -z "$hash" ]] && return 0
  
  # Output result to worker-specific file
  printf '%s|%s|%s\n' "$hash" "$size" "$file"
  
  # Also prepare SQL for caching if enabled (written to worker-specific SQL file)
  if [[ "$USE_CACHE" == "1" || "$SAVE_CHECKSUMS" == "1" ]]; then
    local esc
    esc=$(sql_escape "$file")
    printf "INSERT OR REPLACE INTO file_hashes VALUES ('%s','%s',%s,%s,%s);\n" \
      "$esc" "$hash" "$size" "$mtime" "$(date +%s)" >> "$TEMP_DIR/sql_${worker_id}.sql"
  fi
}

# Export function and variables for parallel execution
export -f hash_worker sql_escape
export HASH_ALGORITHM FAST_MODE USE_CACHE DB_CACHE SAVE_CHECKSUMS TEMP_DIR

# Show progress during hash calculation
show_progress() {
  local current=$1
  local total=$2
  
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

# Main hash calculation driver with thread-safe file writing
calculate_hashes() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📊 Calculating file hashes (threads: $THREADS)...${NC}"
  
  # Count total files
  local total
  total=$(tr -cd '\0' < "$TEMP_DIR/files.list" | wc -c)
  TOTAL_FILES=$total
  
  # Initialize output files
  : > "$TEMP_DIR/hashes.txt"
  : > "$TEMP_DIR/prog.count"
  
  if [[ $total -eq 0 ]]; then
    [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}No files matched criteria.${NC}"
    return
  fi
  
  # Create directory for worker output files
  mkdir -p "$TEMP_DIR/workers"
  
  # Execute hash calculation in parallel with per-worker output files
  if [[ $USE_PARALLEL -eq 1 ]]; then
    # Use GNU parallel with results management
    < "$TEMP_DIR/files.list" parallel -0 -j "$THREADS" --no-notice --results "$TEMP_DIR/workers" \
      "worker_id=\$PARALLEL_SEQ; hash_worker {} '$HASH_ALGORITHM' '$FAST_MODE' \$worker_id; echo 1 >> '$TEMP_DIR/prog.count'" &
  else
    # Use xargs with individual output files per job
    local job_num=0
    while IFS= read -r -d '' filepath; do
      ((job_num++))
      local worker_id="worker_${job_num}"
      
      # Start job in background, writing to its own file
      (
        hash_worker "$filepath" "$HASH_ALGORITHM" "$FAST_MODE" "$worker_id" >> "$TEMP_DIR/workers/hash_${worker_id}.txt"
        echo 1 >> "$TEMP_DIR/prog.count"
      ) &
      
      # Control parallelism
      while [[ $(jobs -r | wc -l) -ge $THREADS ]]; do
        sleep 0.05
      done
    done < "$TEMP_DIR/files.list"
    
    # Wait for all remaining background jobs
    wait
  fi
  
  # Show progress (for parallel mode)
  if [[ $USE_PARALLEL -eq 1 ]]; then
    local pid=$!
    while kill -0 $pid 2>/dev/null; do
      local processed
      processed=$(wc -l < "$TEMP_DIR/prog.count" 2>/dev/null || echo 0)
      show_progress "$processed" "$total"
      sleep 0.3
    done
    wait $pid
  fi
  
  # Final progress update
  show_progress "$total" "$total"
  [[ $PROGRESS_BAR -eq 1 && $QUIET -eq 0 ]] && echo ""
  
  # Safely aggregate all worker output files
  [[ $VERBOSE -eq 1 ]] && echo -e "${CYAN}Aggregating hash results...${NC}"
  
  # Concatenate all hash files
  if [[ -d "$TEMP_DIR/workers" ]]; then
    # GNU parallel results structure
    if [[ $USE_PARALLEL -eq 1 ]]; then
      find "$TEMP_DIR/workers" -name stdout -type f -exec cat {} \; >> "$TEMP_DIR/hashes.txt"
    else
      # Standard worker files
      cat "$TEMP_DIR/workers"/hash_*.txt >> "$TEMP_DIR/hashes.txt" 2>/dev/null
    fi
  fi
  
  # Aggregate SQL commands if caching is enabled
  if [[ $USE_CACHE -eq 1 || $SAVE_CHECKSUMS -eq 1 ]]; then
    : > "$TEMP_DIR/sql_buffer.sql"
    
    # Collect all SQL files from workers
    if [[ $USE_PARALLEL -eq 1 ]]; then
      find "$TEMP_DIR/workers" -name "sql_*.sql" -type f -exec cat {} \; >> "$TEMP_DIR/sql_buffer.sql" 2>/dev/null
    else
      cat "$TEMP_DIR"/sql_*.sql >> "$TEMP_DIR/sql_buffer.sql" 2>/dev/null
    fi
    
    # Flush cache in a single transaction
    flush_cache_batch
  fi
  
  # Clean up worker files
  rm -rf "$TEMP_DIR/workers" "$TEMP_DIR"/sql_*.sql 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════
# DUPLICATE DETECTION
# Analyze hashes to find duplicate files
# ═══════════════════════════════════════════════════════════════════════════
find_duplicates() {
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}🔎 Analyzing duplicates...${NC}"
  
  # Sort by hash for grouping
  sort -t'|' -k1,1 "$TEMP_DIR/hashes.txt" > "$TEMP_DIR/sorted_hashes.txt"
  
  # Group duplicates and calculate statistics
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
  
  # Extract statistics
  local stats
  stats=$(grep "^STATS:" "$TEMP_DIR/duplicates.txt" | cut -d: -f2)
  if [[ -n "$stats" ]]; then
    TOTAL_DUPLICATES=$(echo "$stats" | cut -d'|' -f1)
    TOTAL_SPACE_WASTED=$(echo "$stats" | cut -d'|' -f2)
    TOTAL_DUPLICATE_GROUPS=$(echo "$stats" | cut -d'|' -f3)
  fi
  
  # Store duplicate groups for processing
  DUPLICATE_GROUPS=$(grep -v "^STATS:" "$TEMP_DIR/duplicates.txt")
  
  # Perform fuzzy matching if requested
  [[ $FUZZY_MATCH -eq 1 ]] && find_similar_files
}

# Find similar files based on size similarity
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
        if (pct >= threshold) {
          print "SIMILAR:" file "|" sizes[s] "|" pct "%"
        }
      }
    }
    sizes[size] = file
  }' "$TEMP_DIR/sorted_hashes.txt" >> "$TEMP_DIR/duplicates.txt"
}

# ═══════════════════════════════════════════════════════════════════════════
# SMART DELETION STRATEGIES
# Intelligent selection of which duplicates to keep
# ═══════════════════════════════════════════════════════════════════════════

# Get priority score for a file based on its location
get_location_priority() {
  local path="$1"
  local priority=50  # Default priority
  
  for loc in "${!LOCATION_PRIORITY[@]}"; do
    if [[ "$path" == *"$loc"* ]]; then
      priority=${LOCATION_PRIORITY[$loc]}
      break
    fi
  done
  
  echo "$priority"
}

# Select the best file to keep from a group
select_file_to_keep() {
  local files=("$@")
  local keep_index=0
  local best_priority=999
  
  for i in "${!files[@]}"; do
    local path="${files[$i]}"
    local priority
    priority=$(get_location_priority "$path")
    
    if (( priority < best_priority )); then
      best_priority=$priority
      keep_index=$i
    fi
  done
  
  echo "$keep_index"
}

# ═══════════════════════════════════════════════════════════════════════════
# FILE OPERATIONS
# Backup, verification, and deletion operations
# ═══════════════════════════════════════════════════════════════════════════

# Create backup of file before deletion
backup_file() {
  local file="$1"
  [[ -z "$BACKUP_DIR" ]] && return 0
  
  local timestamp dir relative_path target
  timestamp=$(date +%Y%m%d_%H%M%S)
  dir="$BACKUP_DIR/$timestamp"
  mkdir -p "$dir"
  
  relative_path="${file#/}"
  target="$dir/$relative_path"
  mkdir -p "$(dirname "$target")"
  
  if cp -p -- "$file" "$target" 2>/dev/null; then
    [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}  Backed up: $file${NC}"
    return 0
  fi
  
  return 1
}

# Verify two files are identical byte-for-byte
verify_identical() {
  local file1="$1"
  local file2="$2"
  
  [[ $VERIFY_MODE -eq 0 ]] && return 0
  
  if cmp -s -- "$file1" "$file2"; then
    return 0
  fi
  
  echo -e "${YELLOW}  Warning: Same hash but content differs!${NC}"
  echo -e "${YELLOW}  A: $file1${NC}"
  echo -e "${YELLOW}  B: $file2${NC}"
  return 1
}

# Process duplicate files for deletion/hardlinking/quarantine
delete_duplicates() {
  if [[ $DELETE_MODE -eq 0 && $HARDLINK_MODE -eq 0 && -z "$QUARANTINE_DIR" ]]; then
    return
  fi
  
  # Determine action type for display
  local action="Processing"
  [[ $DELETE_MODE -eq 1 ]] && action="Deleting"
  [[ $HARDLINK_MODE -eq 1 ]] && action="Hardlinking"
  [[ -n "$QUARANTINE_DIR" ]] && action="Quarantining"
  [[ $DRY_RUN -eq 1 ]] && action="Would $action"
  
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}🗑️  $action duplicate files...${NC}"
  
  local deleted=0 freed=0 links=0
  
  # Process each duplicate group
  while IFS= read -r line; do
    if [[ "$line" =~ ^([a-f0-9]+):(.+)$ ]]; then
      local files="${BASH_REMATCH[2]}"
      local arr=()
      
      # Parse files in group
      while IFS='|' read -r filepath size; do
        [[ -n "$filepath" ]] && arr+=("$filepath|$size")
      done <<< "$files"
      
      # Skip groups with only one file
      (( ${#arr[@]} < 2 )) && continue
      
      # Determine which file to keep
      local keep_idx=0
      
      if [[ $SMART_DELETE -eq 1 ]]; then
        # Use smart location-based selection
        local only_paths=()
        for f in "${arr[@]}"; do
          only_paths+=("$(echo "$f" | cut -d'|' -f1)")
        done
        keep_idx=$(select_file_to_keep "${only_paths[@]}")
        
      elif [[ -n "$KEEP_PATH_PRIORITY" ]]; then
        # Keep files in specified path
        for i in "${!arr[@]}"; do
          local p
          p=$(echo "${arr[$i]}" | cut -d'|' -f1)
          if [[ "$p" == "$KEEP_PATH_PRIORITY"* ]]; then
            keep_idx=$i
            break
          fi
        done
        
      elif [[ $KEEP_NEWEST -eq 1 || $KEEP_OLDEST -eq 1 ]]; then
        # Sort by modification time
        IFS=$'\n' read -r -d '' -a arr < <(
          for f in "${arr[@]}"; do
            local p m
            p=$(echo "$f" | cut -d'|' -f1)
            m=$(stat -c '%Y' -- "$p" 2>/dev/null || echo 0)
            echo "$m|$f"
          done | {
            [[ $KEEP_NEWEST -eq 1 ]] && sort -rn || sort -n
          } | cut -d'|' -f2- && printf '\0'
        )
        keep_idx=0
        
      else
        # Default: keep first alphabetically
        IFS=$'\n' read -r -d '' -a arr < <(
          printf '%s\n' "${arr[@]}" | sort && printf '\0'
        )
        keep_idx=0
      fi
      
      # Get the file to keep
      local keep_file
      keep_file=$(echo "${arr[$keep_idx]}" | cut -d'|' -f1)
      [[ $VERBOSE -eq 1 ]] && echo -e "${GREEN}  ✓ Keeping: $keep_file${NC}"
      
      # Process duplicates
      for i in "${!arr[@]}"; do
        [[ $i -eq $keep_idx ]] && continue
        
        local path size
        path=$(echo "${arr[$i]}" | cut -d'|' -f1)
        size=$(echo "${arr[$i]}" | cut -d'|' -f2)
        
        # CRITICAL SAFETY CHECK
        if ! verify_safe_to_delete "$path"; then
          echo -e "${GREEN}  ✓ Skipped (safety check): $path${NC}"
          [[ -n "$LOG_FILE" ]] && echo "$(date): Skipped (safety): $path" >> "$LOG_FILE"
          continue
        fi
        
        # Additional system folder check
        if [[ $SKIP_SYSTEM_FOLDERS -eq 1 ]] && is_in_system_folder "$path"; then
          [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ⚠ Skipped (system folder): $path${NC}"
          continue
        fi
        
        # Verify files are identical if requested
        if [[ $VERIFY_MODE -eq 1 ]]; then
          if ! verify_identical "$keep_file" "$path"; then
            echo -e "${RED}  Skipping non-identical files${NC}"
            continue
          fi
        fi
        
        # Interactive confirmation if requested
        if [[ $INTERACTIVE_DELETE -eq 1 ]]; then
          echo -e "${CYAN}Duplicate:${NC}"
          echo -e "  Keep: $keep_file"
          echo -e "  File: $path"
          echo -e "  Size: $(format_size "$size")"
          echo -ne "${YELLOW}Action? (d)elete/(s)kip/(h)ardlink/(q)uit [d]: ${NC}"
          read -r resp
          
          case "${resp:-d}" in
            d|D) : ;;  # Continue with deletion
            h|H) HARDLINK_MODE=1; DELETE_MODE=0 ;;
            q|Q) echo -e "${YELLOW}Quitting...${NC}"; break 2 ;;
            *) echo -e "${GREEN}  Skipped: $path${NC}"; continue ;;
          esac
        fi
        
        # Backup file if requested
        if [[ -n "$BACKUP_DIR" && $DRY_RUN -eq 0 ]]; then
          backup_file "$path"
        fi
        
        # Perform the action
        if [[ $DRY_RUN -eq 1 ]]; then
          # Dry run - just show what would be done
          if [[ $HARDLINK_MODE -eq 1 ]]; then
            echo -e "${YELLOW}  Would hardlink: $path -> $keep_file${NC}"
          elif [[ -n "$QUARANTINE_DIR" ]]; then
            echo -e "${YELLOW}  Would quarantine: $path${NC}"
          else
            echo -e "${YELLOW}  Would delete: $path${NC}"
          fi
          ((deleted++))
          ((freed+=size))
          
        elif [[ $HARDLINK_MODE -eq 1 ]]; then
          # Create hardlink
          if ln -f -- "$keep_file" "$path" 2>/dev/null; then
            ((links++))
            ((freed+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}  ↔ Hardlinked: $path${NC}"
            [[ -n "$LOG_FILE" ]] && echo "$(date): Hardlinked: $path -> $keep_file" >> "$LOG_FILE"
          else
            echo -e "${RED}  Failed to hardlink: $path${NC}"
          fi
          
        elif [[ -n "$QUARANTINE_DIR" ]]; then
          # Move to quarantine
          local qfile="$QUARANTINE_DIR/$(basename "$path")_$(date +%s)"
          if mv -- "$path" "$qfile" 2>/dev/null; then
            ((deleted++))
            ((freed+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  ⚠ Quarantined: $path${NC}"
            [[ -n "$LOG_FILE" ]] && echo "$(date): Quarantined: $path -> $qfile" >> "$LOG_FILE"
          fi
          
        elif [[ $USE_TRASH -eq 1 ]]; then
          # Move to trash
          if trash-put -- "$path" 2>/dev/null; then
            ((deleted++))
            ((freed+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${YELLOW}  🗑 Trashed: $path${NC}"
            [[ -n "$LOG_FILE" ]] && echo "$(date): Trashed: $path" >> "$LOG_FILE"
          fi
          
        else
          # Permanent deletion
          if rm -f -- "$path" 2>/dev/null; then
            ((deleted++))
            ((freed+=size))
            [[ $VERBOSE -eq 1 ]] && echo -e "${RED}  ✗ Deleted: $path${NC}"
            [[ -n "$LOG_FILE" ]] && echo "$(date): Deleted: $path" >> "$LOG_FILE"
          fi
        fi
      done
    fi
  done <<< "$DUPLICATE_GROUPS"
  
  # Update statistics
  FILES_DELETED=$deleted
  SPACE_FREED=$freed
  
  # Show summary
  if [[ $QUIET -eq 0 ]]; then
    if [[ $HARDLINK_MODE -eq 1 ]]; then
      echo -e "${GREEN}✅ Created $links hardlinks, freed $(format_size $freed)${NC}"
    else
      echo -e "${GREEN}✅ Processed $deleted files, freed $(format_size $freed)${NC}"
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# REPORT GENERATION
# Create detailed reports in various formats
# ═══════════════════════════════════════════════════════════════════════════

# Generate HTML report with interactive interface
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
    
    # Generate duplicate group entries
    local gid=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^([a-f0-9]+):(.+)$ ]]; then
        ((gid++))
        local hash="${BASH_REMATCH[1]}"
        local files="${BASH_REMATCH[2]}"
        
        echo "<div id=\"g$gid\" class=\"group\">"
        echo "<div class=\"hdr\" onclick=\"toggle('g$gid')\">Group $gid (Hash: ${hash:0:16}…)</div>"
        echo "<div class=\"files\">"
        
        while IFS='|' read -r filepath size; do
          [[ -z "$filepath" ]] && continue
          
          # Check if it's a system file
          local class=""
          is_in_system_folder "$filepath" && class="system-file"
          
          printf '<div class="file"><div class="code %s">%s</div><div>Size: %s</div></div>\n' \
            "$class" \
            "$(printf '%s' "$filepath" | sed 's/&/\&amp;/g;s/</\&lt;/g')" \
            "$(format_size "$size")"
        done <<< "$files"
        
        echo "</div></div>"
      fi
    done <<< "$DUPLICATE_GROUPS"
    
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

# Generate CSV report for data analysis
generate_csv_report() {
  [[ -z "$CSV_REPORT" ]] && return
  
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📊 Generating CSV report...${NC}"
  
  local csv="$OUTPUT_DIR/$CSV_REPORT"
  echo "Hash,File Path,Size (bytes),Size (human),Group ID,System File" > "$csv"
  
  local gid=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^([a-f0-9]+):(.+)$ ]]; then
      ((gid++))
      local hash="${BASH_REMATCH[1]}"
      local files="${BASH_REMATCH[2]}"
      
      while IFS='|' read -r fp sz; do
        [[ -z "$fp" ]] && continue
        
        local is_system="No"
        is_in_system_folder "$fp" && is_system="Yes"
        
        printf '%s,"%s",%s,"%s",%s,%s\n' \
          "$hash" "$fp" "$sz" "$(format_size "$sz")" "$gid" "$is_system" >> "$csv"
      done <<< "$files"
    fi
  done <<< "$DUPLICATE_GROUPS"
  
  [[ $QUIET -eq 0 ]] && echo -e "${GREEN}✅ CSV report saved to: $csv${NC}"
}

# Generate JSON report for programmatic processing
generate_json_report() {
  [[ -z "$JSON_REPORT" ]] && return
  
  [[ $QUIET -eq 0 ]] && echo -e "${YELLOW}📋 Generating JSON report...${NC}"
  
  local json="$OUTPUT_DIR/$JSON_REPORT"
  
  {
    echo '{'
    echo '  "metadata": {'
    printf '    "version": "%s", "author": "%s", "generated": "%s", ' \
      "$VERSION" "$AUTHOR" "$(date -Iseconds)"
    printf '"search_path": "%s", "system_protection": %s, ' \
      "$SEARCH_PATH" "$([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "true" || echo "false")"
    printf '"total_files": %s, "total_duplicates": %s, ' \
      "${TOTAL_FILES:-0}" "${TOTAL_DUPLICATES:-0}"
    printf '"total_groups": %s, "space_wasted": %s, ' \
      "${TOTAL_DUPLICATE_GROUPS:-0}" "${TOTAL_SPACE_WASTED:-0}"
    printf '"hash_algorithm": "%s"\n' "${HASH_ALGORITHM%%sum}"
    echo '  },'
    echo '  "groups": ['
    
    local first_group=1
    local gid=0
    
    while IFS= read -r line; do
      if [[ "$line" =~ ^([a-f0-9]+):(.+)$ ]]; then
        ((gid++))
        local hash="${BASH_REMATCH[1]}"
        local files="${BASH_REMATCH[2]}"
        
        [[ $first_group -eq 0 ]] && echo ','
        echo '    {'
        printf '      "id": %s, "hash": "%s", "files": [' "$gid" "$hash"
        
        local first_file=1
        while IFS='|' read -r fp sz; do
          [[ -z "$fp" ]] && continue
          [[ $first_file -eq 0 ]] && echo -n ','
          
          local is_system="false"
          is_in_system_folder "$fp" && is_system="true"
          
          printf '\n        {"path": %s, "size": %s, "system": %s}' \
            "$(printf '%s' "$fp" | jq -Rsa . | sed 's/^"//;s/"$//')" \
            "$sz" "$is_system"
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

# ═══════════════════════════════════════════════════════════════════════════
# EMAIL AND SUMMARY
# Send email notifications and display final summary
# ═══════════════════════════════════════════════════════════════════════════

# Calculate scan duration in human-readable format
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

# Send email report summary
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
  Total Files Scanned: $TOTAL_FILES
  Duplicate Files Found: $TOTAL_DUPLICATES
  Duplicate Groups: $TOTAL_DUPLICATE_GROUPS
  Space Wasted: $(format_size ${TOTAL_SPACE_WASTED:-0})
  
Actions:
  Files Processed: $FILES_DELETED
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

# Display final summary
show_summary() {
  [[ $QUIET -eq 1 ]] && return
  
  echo ""
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}                    SCAN SUMMARY${NC}"
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}📁 Search Path:${NC}          $SEARCH_PATH"
  echo -e "${CYAN}🛡️  System Protection:${NC}    $([ $SKIP_SYSTEM_FOLDERS -eq 1 ] && echo "ENABLED" || echo "DISABLED")"
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
  
  [[ -n "$CSV_REPORT" ]] && \
    echo -e "${CYAN}📊 CSV Report:${NC}           $OUTPUT_DIR/$CSV_REPORT"
  [[ -n "$JSON_REPORT" ]] && \
    echo -e "${CYAN}📋 JSON Report:${NC}          $OUTPUT_DIR/$JSON_REPORT"
  [[ -n "$LOG_FILE" ]] && \
    echo -e "${CYAN}📝 Log File:${NC}             $LOG_FILE"
  
  echo -e "${WHITE}═══════════════════════════════════════════════════════════${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# Orchestrate all operations in the correct sequence
# ═══════════════════════════════════════════════════════════════════════════
main() {
  # Initialize and validate
  load_config
  check_dependencies
  SCAN_START_TIME=$(date +%s)
  init_logging
  [[ $QUIET -eq 0 ]] && show_header
  validate_inputs
  
  # Core operations
  init_cache
  find_files
  calculate_hashes
  find_duplicates
  
  # Generate reports
  generate_html_report
  generate_csv_report
  generate_json_report
  
  # Show safety summary before destructive operations
  show_safety_summary
  
  # Process duplicates
  delete_duplicates
  
  # Finalize
  SCAN_END_TIME=$(date +%s)
  send_email_report
  show_summary
  
  # Success message
  [[ $QUIET -eq 0 ]] && echo -e "\n${GREEN}✨ Scan completed successfully!${NC}"
  [[ $QUIET -eq 0 ]] && echo -e "${DIM}DupeFinder Pro v$VERSION by $AUTHOR${NC}\n"
}

# ═══════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# Parse arguments and execute main function
# ═══════════════════════════════════════════════════════════════════════════
parse_arguments "$@"
main
exit 0
