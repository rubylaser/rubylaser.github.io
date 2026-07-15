#!/usr/bin/env bash
# shellcheck shell=bash
#
#
# Copyright (c) 2026 Zack Reed
#
# Licensed under the MIT License.
#
# This software is provided "as is", without warranty of any kind.
# Use it at your own risk. Review and test the script before scheduling it,
# verify all mountpoints and settings, and maintain independent backups.
#
# See the LICENSE file for the complete license terms.
#
# snapraid-helper.sh
#
# A defensive SnapRAID maintenance orchestrator with support for one or more
# SnapRAID configuration files.
#
# Design overview
# ---------------
# * Orchestrator mode owns the global lock and shared Docker service lifecycle.
# * Worker mode handles exactly one SnapRAID configuration in a fresh process.
# * Per-config state, logs, locks, and Healthchecks IDs are isolated.
# * SnapRAID `diff` exit code 2 is treated as normal (differences found).
# * Safety-threshold blocks return exit code 2; operational failures return 1.
# * Persistent warning counters live under /var/lib, not /tmp.
# * Temporary files are always removed by an EXIT trap.
# * Mount validation can verify mountpoints and optional expected source devices.
#
# Exit codes
# ----------
#   0  Completed successfully.
#   1  Operational failure (SnapRAID, Docker, mail, preflight, etc.).
#   2  Sync intentionally blocked by deletion/update safety thresholds.
# 130  Interrupted with SIGINT.
# 143  Terminated with SIGTERM.

set -uo pipefail
IFS=$'\n\t'

###############################################################################
# GLOBAL DEFAULTS
#
# These may be overridden by a trusted profile file passed with --profile.
# A profile is sourced as Bash and therefore MUST be root-owned and not writable
# by untrusted users.
###############################################################################

PROGRAM_NAME="${0##*/}"
VERSION="2.1.6"

SNAPRAID_BIN="/usr/local/bin/snapraid"
MAIL_BIN="/usr/bin/mutt"
DOCKER_BIN="/usr/bin/docker"

EMAIL_ADDRESS="yourusername@gmail.com"
EMAIL_SUBJECT_PREFIX=""

DEL_THRESHOLD=100
UP_THRESHOLD=500

#  0  = force sync immediately when thresholds are breached.
# -1  = never force sync; manual intervention is required.
#  N  = force sync on the Nth consecutive threshold-breaching run.
#       Example: 1 forces on the first breach; 2 blocks once and forces next run.
SYNC_WARN_THRESHOLD=-1

SCRUB_PERCENT=3
SCRUB_AGE=10
SMART_LOG=1
SPINDOWN_DISKS=0

# A failed write-producing service pause blocks maintenance by default.
MANAGE_SERVICES=1
REQUIRE_ALL_SERVICES_PAUSED=1
SERVICES=(sabnzbd sonarr radarr lidarr)

FAIL_FAST=1

SUMMARIZE_DIFF_EMAIL=1
DIFF_LIST_HEAD=20
DIFF_LIST_TAIL=20

# Email detail controls:
#   summary    = health dashboard only
#   changes    = dashboard plus changed file paths
#   diagnostic = dashboard plus a filtered diagnostic excerpt
#   full       = dashboard plus the complete raw command log
EMAIL_DETAIL_LEVEL="summary"
EMAIL_DETAIL_ON_WARNING="changes"
EMAIL_DETAIL_ON_FAILURE="diagnostic"

# Email rendering format:
#   html = responsive, table-based dashboard (recommended)
#   text = plain-text fallback for minimal mail clients
EMAIL_FORMAT="html"

# Capacity health policy. This affects report severity only; it never
# authorizes or blocks a SnapRAID sync.
#
#   disk = individual SnapRAID data-disk utilization affects health
#   pool = only the configured mergerfs/pool path affects health
#   both = individual disks and the configured pool affect health
#   off  = capacity is reported but never changes overall health
#
# mergerfs users will usually want "pool" because individual branches may be
# intentionally full while the combined pool still has plenty of free space.
CAPACITY_HEALTH_SOURCE="disk"

# Individual SnapRAID data-disk thresholds. These are still displayed when
# REPORT_DISK_CAPACITY_WARNINGS=1, even when they do not affect health.
DISK_USAGE_WARN_PERCENT=85
DISK_USAGE_CRITICAL_PERCENT=95
REPORT_DISK_CAPACITY_WARNINGS=1

# Optional mergerfs or other pooled filesystem. Required when
# CAPACITY_HEALTH_SOURCE is "pool" or "both".
MERGERFS_POOL_PATH=""
POOL_USAGE_WARN_PERCENT=85
POOL_USAGE_CRITICAL_PERCENT=95

DISK_TEMP_WARN_C=40
DISK_TEMP_CRITICAL_C=50
SCRUB_AGE_WARN_DAYS=30
SCRUB_AGE_CRITICAL_DAYS=60
UNSCRUBBED_WARN_PERCENT=50
UNSCRUBBED_CRITICAL_PERCENT=80
# SMART error counters are cumulative on many drives and can remain non-zero
# indefinitely. Choose how those counters affect overall health:
#   delta     = warn only when a disk count increases since the prior run
#   threshold = warn whenever the current count is >= SMART_ERROR_WARN_COUNT
#   off       = display counts but never change overall health
SMART_ERROR_HEALTH_MODE="delta"
SMART_ERROR_WARN_COUNT=1
SMART_ERROR_DELTA_WARN_COUNT=1

# Individual SnapRAID failure-probability estimates can be noisy and should not
# normally change the subject on their own. Choose how they affect health:
#   failure-only = critical only when the estimate reaches SMART_FAILED_FP_PERCENT
#   warning      = attention at SMART_FP_WARN_PERCENT; critical at failed threshold
#   off          = display only; never affects health
SMART_FP_HEALTH_MODE="failure-only"
SMART_FP_WARN_PERCENT=10
SMART_FAILED_FP_PERCENT=100

# Show unchanged historical SMART error counts in the Drive Health summary.
# They are intentionally omitted from the Drive Overview table so the same
# cumulative counter is not repeated throughout the report.
REPORT_HISTORICAL_SMART_ERRORS=1

# SnapRAID's aggregate probability naturally rises with array size. Keep it
# informational unless you explicitly want it to affect report severity.
AGGREGATE_FP_IS_WARNING=0

# When enabled, a health warning sends a non-success Healthchecks ping while
# the script itself still exits 0 if all automation completed successfully.
HEALTH_WARNINGS_FAIL_HEALTHCHECK=1

LOG_DIR="/var/log/snapraid-helper"
STATE_DIR="/var/lib/snapraid-helper"
LOCK_DIR="/run/lock/snapraid-helper"

# Optional log retention. 0 disables automatic deletion.
LOG_RETENTION_DAYS=90

HEALTHCHECKS_ALERTS=1
HEALTHCHECKS_URL="https://healthchecks.yourdomain.com/ping/"
HEALTHCHECKS_ID=""
HC_TIMEOUT_SECS=10
HC_RETRIES=3

# Optional mount safety validation.
# REQUIRED_MOUNTS entries must be mounted. Example:
#   REQUIRED_MOUNTS=(/mnt/disk1 /mnt/disk2 /mnt/parity)
REQUIRED_MOUNTS=()

# OPTIONAL expected mount sources. The key is a mountpoint and the value is the
# expected block device or /dev/disk/by-* symlink. Example profile entry:
#   declare -A EXPECTED_MOUNT_SOURCES=(
#     ["/mnt/parity"]="/dev/disk/by-uuid/AAAA-BBBB"
#   )
declare -A EXPECTED_MOUNT_SOURCES=()

# In orchestrator mode, services are paused once around all array workers.
# Set to 0 only when each array has completely independent services and disks.
GLOBAL_SERIAL_EXECUTION=1

###############################################################################
# RUNTIME GLOBALS
###############################################################################

MODE="orchestrator"
RUN_ALL=0
CONFIG_DIR="/etc/snapraid.d"
PROFILE_FILE=""
WORKER_CONFIG=""
NO_EMAIL=0
NO_SERVICES=0
DRY_RUN=0
VERBOSE=0

CONFIGS=()
PROFILES=()
PASSTHROUGH_ARGS=()

GLOBAL_LOCK_FD=""
ARRAY_LOCK_FD=""

TMP_OUTPUT=""
EMAIL_OUTPUT=""
FULL_LOG_FILE=""
SUMMARY_FILE=""

SNAPRAID_CONF=""
SNAPRAID_CANONICAL_CONF=""
SNAPRAID_TAG=""
CONFIG_ID=""
CONFIG_STATE_DIR=""
SYNC_WARN_FILE=""
ARRAY_LOCK_FILE=""

PAUSED_SERVICES=()
SERVICES_RESTORED=0
SERVICES_PAUSED_COUNT=0
SERVICES_RESTORED_COUNT=0
SERVICES_FAILED_PAUSE=0
SERVICES_FAILED_RESTORE=0
SERVICE_RC=0

SECONDS=0
HAD_FAILURE=0
CHK_FAIL=0
DO_SYNC=0
SYNC_FORCED=0
JOBS_DONE=""
SUBJECT=""

DEL_COUNT=0
ADD_COUNT=0
MOVE_COUNT=0
COPY_COUNT=0
UPDATE_COUNT=0
RESTORED_COUNT=0
SYNC_WARN_COUNT=0

DIFF_RC=0
SYNC_RC=0
SCRUB_RC=0
SMART_RC=0
DOWN_RC=0
TOUCH_RC=0

HC_ENABLED=0
HC_TOOL=""

# Structured health state. Execution success and array health are intentionally
# tracked separately so a successful command run can still report attention.
HEALTH_LEVEL=0              # 0=healthy, 1=notice, 2=warning, 3=critical
HEALTH_LABEL="HEALTHY"
HEALTH_REASONS=()
HEALTH_NOTES=()
REPORT_DETAIL_EFFECTIVE="summary"
PARITY_STATE="UNKNOWN"
ZERO_TIMESTAMP_FOUND=0
ZERO_TIMESTAMP_CORRECTED=0
SCRUB_OLDEST_DAYS=-1
SCRUB_MEDIAN_DAYS=-1
SCRUB_NEWEST_DAYS=-1
UNSCRUBBED_PERCENT=-1
SCRUB_DATA_ERRORS=0
SMART_PARSE_OK=0
SMART_DISK_COUNT=0
SMART_DATA_COUNT=0
SMART_PARITY_COUNT=0
SMART_ERROR_DISKS=0
SMART_MAX_TEMP=-1
SMART_MAX_TEMP_DISK=""
SMART_OVERALL_FP=-1
SMART_WARNING_ROWS=()
SMART_INFO_ROWS=()
SMART_BASELINE_ROWS=()
SMART_NEW_ERROR_DISKS=0
SMART_ERROR_BASELINE_FILE=""
CAPACITY_WARNING_ROWS=()
MAX_DISK_USAGE=-1
MAX_DISK_USAGE_DISK=""
POOL_USAGE_PERCENT=-1
POOL_TOTAL_KB=-1
POOL_USED_KB=-1
POOL_FREE_KB=-1
POOL_FILESYSTEM=""
POOL_FSTYPE=""

###############################################################################
# BASIC UTILITIES
###############################################################################

log() {
  printf '%s\n' "$*"
}

vlog() {
  (( VERBOSE == 1 )) && log "DEBUG: $*"
  return 0
}

warn() {
  log "WARNING: $*" >&2
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

usage() {
  cat <<EOF
${PROGRAM_NAME} ${VERSION}

Usage:
  ${PROGRAM_NAME} --config FILE [--config FILE ...] [options]
  ${PROGRAM_NAME} --all [--config-dir DIR] [options]
  ${PROGRAM_NAME} --profile FILE [options]

Selection:
  -c, --config FILE       Add a SnapRAID config file. Repeatable.
      --all               Run every *.conf file in --config-dir.
      --config-dir DIR    Directory scanned by --all (default: ${CONFIG_DIR}).
  -p, --profile FILE      Source a trusted Bash profile. Repeatable. A profile
                          can define SNAPRAID_CONF and per-array settings.

Behavior:
      --no-email          Disable email for this invocation.
      --no-services       Do not pause or restore Docker services.
      --dry-run           Print selected configs/profiles without running jobs.
  -v, --verbose           Enable diagnostic logging.
  -h, --help              Show this help.
      --version           Show version.

Examples:
  ${PROGRAM_NAME} --config /etc/snapraid.conf
  ${PROGRAM_NAME} --config /etc/snapraid-media.conf \\
                  --config /etc/snapraid-archive.conf
  ${PROGRAM_NAME} --all --config-dir /etc/snapraid.d
  ${PROGRAM_NAME} --profile /etc/snapraid-helper.d/media.env
EOF
}

format_duration() {
  local total_seconds=${1:-0}
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  if (( hours > 0 )); then
    printf '%dh %dm %ds' "$hours" "$minutes" "$seconds"
  elif (( minutes > 0 )); then
    printf '%dm %ds' "$minutes" "$seconds"
  else
    printf '%ds' "$seconds"
  fi
}

canonical_path() {
  local path=$1
  if have_cmd realpath; then
    realpath -- "$path"
  elif have_cmd readlink; then
    readlink -f -- "$path"
  else
    printf '%s\n' "$path"
  fi
}

sanitize_tag() {
  local value=$1
  value=${value//[^a-zA-Z0-9_.-]/_}
  printf '%s\n' "$value"
}

short_hash() {
  local value=$1
  if have_cmd sha256sum; then
    printf '%s' "$value" | sha256sum | awk '{print substr($1,1,10)}'
  elif have_cmd shasum; then
    printf '%s' "$value" | shasum -a 256 | awk '{print substr($1,1,10)}'
  else
    # cksum is less collision-resistant but remains a deterministic fallback.
    printf '%s' "$value" | cksum | awk '{print $1}'
  fi
}

append_job() {
  local job=$1
  JOBS_DONE="${JOBS_DONE:+${JOBS_DONE} + }${job}"
}

###############################################################################
# ARGUMENT AND PROFILE HANDLING
###############################################################################

parse_args() {
  while (($#)); do
    case "$1" in
      -c|--config)
        (($# >= 2)) || die "$1 requires a file"
        CONFIGS+=("$2")
        shift 2
        ;;
      -p|--profile)
        (($# >= 2)) || die "$1 requires a file"
        PROFILES+=("$2")
        shift 2
        ;;
      --all)
        RUN_ALL=1
        shift
        ;;
      --config-dir)
        (($# >= 2)) || die "$1 requires a directory"
        CONFIG_DIR=$2
        shift 2
        ;;
      --no-email)
        NO_EMAIL=1
        shift
        ;;
      --no-services)
        NO_SERVICES=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -v|--verbose)
        VERBOSE=1
        shift
        ;;
      --worker)
        MODE="worker"
        shift
        ;;
      --worker-config)
        (($# >= 2)) || die "$1 requires a file"
        WORKER_CONFIG=$2
        shift 2
        ;;
      --worker-profile)
        (($# >= 2)) || die "$1 requires a file"
        PROFILE_FILE=$2
        shift 2
        ;;
      --version)
        printf '%s %s\n' "$PROGRAM_NAME" "$VERSION"
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

# Validate a sourced profile before executing it. This protects against an
# accidentally user-writable profile becoming arbitrary root code.
validate_profile_security() {
  local profile=$1
  local owner_uid mode

  [[ -f "$profile" ]] || die "Profile not found: $profile"

  if have_cmd stat; then
    owner_uid=$(stat -c '%u' "$profile" 2>/dev/null || stat -f '%u' "$profile")
    mode=$(stat -c '%a' "$profile" 2>/dev/null || stat -f '%Lp' "$profile")

    if (( EUID == 0 )) && [[ "$owner_uid" != "0" ]]; then
      die "Profile must be owned by root when running as root: $profile"
    fi

    # Reject group- or world-writable files. Decimal mode digits are sufficient
    # here because we only inspect the last two octal permission digits.
    local group_digit=${mode: -2:1}
    local other_digit=${mode: -1}
    if (( (10#$group_digit & 2) != 0 || (10#$other_digit & 2) != 0 )); then
      die "Profile must not be group/world writable: $profile (mode $mode)"
    fi
  fi
}

load_profile() {
  local profile=$1
  validate_profile_security "$profile"
  # shellcheck source=/dev/null
  source "$profile"
}

discover_all_configs() {
  [[ -d "$CONFIG_DIR" ]] || die "Config directory not found: $CONFIG_DIR"

  local found=0 conf
  while IFS= read -r -d '' conf; do
    CONFIGS+=("$conf")
    found=1
  done < <(find "$CONFIG_DIR" -maxdepth 1 -type f -name '*.conf' -print0 | sort -z)

  (( found == 1 )) || die "No *.conf files found in: $CONFIG_DIR"
}

###############################################################################
# DEPENDENCY AND DIRECTORY SETUP
###############################################################################

require_common_bins() {
  local b
  for b in awk sed grep hostname date tee mkdir mktemp basename cp mv rm flock find sort stat; do
    have_cmd "$b" || die "Required command not found: $b"
  done
}

require_worker_bins() {
  [[ -x "$SNAPRAID_BIN" ]] || die "SnapRAID binary not executable: $SNAPRAID_BIN"
  [[ -f "$SNAPRAID_CONF" ]] || die "SnapRAID config not found: $SNAPRAID_CONF"

  if [[ -n "${EMAIL_ADDRESS:-}" ]] && (( NO_EMAIL == 0 )); then
    [[ -x "$MAIL_BIN" ]] || die "Mail binary not executable: $MAIL_BIN"
  fi

  if (( MANAGE_SERVICES == 1 && NO_SERVICES == 0 )); then
    [[ -x "$DOCKER_BIN" ]] || die "Docker binary not executable: $DOCKER_BIN"
  fi
}

initialize_directories() {
  mkdir -p -- "$LOG_DIR" "$STATE_DIR" "$LOCK_DIR" ||
    die "Unable to create log/state/lock directories"

  mkdir -p -- "$CONFIG_STATE_DIR" ||
    die "Unable to create config state directory: $CONFIG_STATE_DIR"
}

###############################################################################
# LOCKING
###############################################################################

acquire_global_lock() {
  local global_lock_file="${LOCK_DIR}/global.lock"
  mkdir -p -- "$LOCK_DIR" || die "Unable to create lock directory: $LOCK_DIR"

  exec {GLOBAL_LOCK_FD}>"$global_lock_file" ||
    die "Unable to open global lock: $global_lock_file"

  flock -n "$GLOBAL_LOCK_FD" ||
    die "Another SnapRAID maintenance orchestration is already active."
}

acquire_array_lock() {
  exec {ARRAY_LOCK_FD}>"$ARRAY_LOCK_FILE" ||
    die "Unable to open array lock: $ARRAY_LOCK_FILE"

  flock -n "$ARRAY_LOCK_FD" ||
    die "Another job is already active for config: $SNAPRAID_CONF"
}

###############################################################################
# HEALTHCHECKS
###############################################################################

hc_init() {
  HC_ENABLED=0
  HC_TOOL=""

  (( HEALTHCHECKS_ALERTS == 1 )) || return 0

  if [[ -z "${HEALTHCHECKS_ID:-}" || -z "${HEALTHCHECKS_URL:-}" ]]; then
    warn "Healthchecks enabled but ID/URL is empty for ${SNAPRAID_TAG}; disabling."
    return 0
  fi

  if have_cmd curl; then
    HC_TOOL="curl"
  elif have_cmd wget; then
    HC_TOOL="wget"
  else
    warn "Healthchecks enabled but neither curl nor wget is installed; disabling."
    return 0
  fi

  HC_ENABLED=1
}

hc_ping_url() {
  local suffix=${1:-}
  local url="${HEALTHCHECKS_URL%/}/${HEALTHCHECKS_ID}"
  [[ -n "$suffix" ]] && url="${url}/${suffix}"
  printf '%s' "$url"
}

hc_send() {
  (( HC_ENABLED == 1 )) || return 0

  local suffix=${1:-}
  local body=${2:-}
  local url result=0
  url=$(hc_ping_url "$suffix")

  if [[ "$HC_TOOL" == "curl" ]]; then
    if [[ -n "$body" ]]; then
      curl -fsS --max-time "$HC_TIMEOUT_SECS" --retry "$HC_RETRIES" \
        --retry-delay 1 --retry-all-errors -X POST --data-raw "$body" \
        "$url" >/dev/null 2>&1 || result=$?
    else
      curl -fsS --max-time "$HC_TIMEOUT_SECS" --retry "$HC_RETRIES" \
        --retry-delay 1 --retry-all-errors "$url" >/dev/null 2>&1 || result=$?
    fi
  else
    if [[ -n "$body" ]]; then
      printf '%s' "$body" | wget -qO- --timeout="$HC_TIMEOUT_SECS" \
        --tries="$HC_RETRIES" --method=POST --body-file=- "$url" \
        >/dev/null 2>&1 || result=$?
    else
      wget -qO- --timeout="$HC_TIMEOUT_SECS" --tries="$HC_RETRIES" \
        "$url" >/dev/null 2>&1 || result=$?
    fi
  fi

  (( result == 0 )) || vlog "Healthchecks ping failed: $url (rc=$result)"
  return 0
}

hc_start() {
  hc_send "start" "SnapRAID job started on $(hostname) [${SNAPRAID_TAG}] at $(date)"
}

hc_finish_success() {
  hc_send "" "SnapRAID job succeeded on $(hostname) [${SNAPRAID_TAG}] at $(date). Jobs: ${JOBS_DONE:-none}"
}

hc_finish_fail() {
  local code=${1:-1}
  (( code >= 1 && code <= 255 )) || code=1
  hc_send "$code" "SnapRAID job failed or was blocked on $(hostname) [${SNAPRAID_TAG}] at $(date). Subject: ${SUBJECT:-unknown}"
}

###############################################################################
# LOGGING, MARKERS, AND COMMAND EXECUTION
###############################################################################

section() {
  log ""
  log "----------------------------------------"
  log "$1"
}

mark_begin() {
  local name=$1
  printf '__SNAPRAID_%s_BEGIN__ [%s]\n' "$name" "$(date)" | tee -a "$TMP_OUTPUT" >/dev/null
}

mark_end() {
  local name=$1 rc=$2
  {
    printf '__SNAPRAID_%s_END__ [%s] rc=%s\n' "$name" "$(date)" "$rc"
    printf '\n'
  } | tee -a "$TMP_OUTPUT" >/dev/null
}

extract_job_log() {
  local name=$1
  awk -v begin="__SNAPRAID_${name}_BEGIN__" \
      -v end="__SNAPRAID_${name}_END__" '
    index($0, begin) { active=1; next }
    index($0, end)   { active=0 }
    active           { print }
  ' "$TMP_OUTPUT"
}

marker_end_present() {
  local name=$1
  grep -q "__SNAPRAID_${name}_END__" "$TMP_OUTPUT"
}

snapraid_cmd() {
  "$SNAPRAID_BIN" -c "$SNAPRAID_CONF" "$@"
}

# Run a command while preserving the command's exit status through tee.
# The caller decides whether a particular nonzero status is fatal.
run_cmd() {
  local name=$1
  shift
  local rc

  mark_begin "$name"
  {
    printf '###%s [%s]\n' "$name" "$(date)"
    "$@"
  } 2>&1 | tee -a "$TMP_OUTPUT"
  rc=${PIPESTATUS[0]}
  mark_end "$name" "$rc"

  if (( rc != 0 )); then
    HAD_FAILURE=1
    warn "${name} returned exit code ${rc}"
    if (( FAIL_FAST == 1 )); then
      return "$rc"
    fi
  fi

  return "$rc"
}

is_snapraid_diff_ok() {
  local rc=$1
  [[ "$rc" -eq 0 || "$rc" -eq 2 ]]
}

###############################################################################
# DOCKER SERVICE MANAGEMENT
###############################################################################

service_pause() {
  local service status

  for service in "${SERVICES[@]}"; do
    status=$("$DOCKER_BIN" inspect -f '{{.State.Status}}' "$service" 2>/dev/null || true)

    case "$status" in
      running)
        log "Pausing service: ${service}" | tee -a "$TMP_OUTPUT"
        if "$DOCKER_BIN" pause "$service" >/dev/null 2>&1; then
          PAUSED_SERVICES+=("$service")
          ((SERVICES_PAUSED_COUNT += 1))
        else
          warn "Failed to pause service: $service"
          printf 'WARNING: failed to pause %s\n' "$service" >>"$TMP_OUTPUT"
          ((SERVICES_FAILED_PAUSE += 1))
          SERVICE_RC=1
          HAD_FAILURE=1
        fi
        ;;
      paused)
        log "Service already paused; leaving unchanged: ${service}" | tee -a "$TMP_OUTPUT"
        ;;
      exited|created|dead|restarting|removing)
        log "Service not actively running; skip pause: ${service} (${status})" | tee -a "$TMP_OUTPUT"
        ;;
      "")
        log "Service not found; skip pause: ${service}" | tee -a "$TMP_OUTPUT"
        ;;
      *)
        log "Unknown service state; skip pause: ${service} (${status})" | tee -a "$TMP_OUTPUT"
        ;;
    esac
  done

  if (( SERVICES_FAILED_PAUSE > 0 && REQUIRE_ALL_SERVICES_PAUSED == 1 )); then
    return 1
  fi

  return 0
}

service_unpause() {
  local service status rc=0

  for service in "${PAUSED_SERVICES[@]}"; do
    status=$("$DOCKER_BIN" inspect -f '{{.State.Status}}' "$service" 2>/dev/null || true)

    if [[ "$status" == "paused" ]]; then
      log "Unpausing service: ${service}" | tee -a "$TMP_OUTPUT"
      if "$DOCKER_BIN" unpause "$service" >/dev/null 2>&1; then
        ((SERVICES_RESTORED_COUNT += 1))
      else
        warn "Failed to unpause service: $service"
        printf 'WARNING: failed to unpause %s\n' "$service" >>"$TMP_OUTPUT"
        ((SERVICES_FAILED_RESTORE += 1))
        SERVICE_RC=1
        HAD_FAILURE=1
        rc=1
      fi
    else
      log "Service no longer paused; skip restore: ${service} (${status:-missing})" | tee -a "$TMP_OUTPUT"
    fi
  done

  return "$rc"
}

# Idempotent restoration: normal flow and EXIT cleanup may both call this.
restore_services() {
  (( MANAGE_SERVICES == 1 && NO_SERVICES == 0 )) || return 0
  (( SERVICES_RESTORED == 0 )) || return 0

  SERVICES_RESTORED=1

  if ((${#PAUSED_SERVICES[@]} == 0)); then
    vlog "No services were paused by this invocation."
    return 0
  fi

  service_unpause
  local rc=$?
  PAUSED_SERVICES=()
  return "$rc"
}

###############################################################################
# CLEANUP AND SIGNAL HANDLING
###############################################################################

cleanup_temp_files() {
  [[ -n "${TMP_OUTPUT:-}" ]] && rm -f -- "$TMP_OUTPUT" 2>/dev/null || true
  [[ -n "${EMAIL_OUTPUT:-}" ]] && rm -f -- "$EMAIL_OUTPUT" "${EMAIL_OUTPUT}.tmp" 2>/dev/null || true
  [[ -n "${SUMMARY_FILE:-}" ]] && rm -f -- "$SUMMARY_FILE" 2>/dev/null || true
}

on_exit() {
  local rc=$?
  trap - EXIT INT TERM

  if ! restore_services; then
    (( rc == 0 )) && rc=1
  fi

  cleanup_temp_files
  exit "$rc"
}

on_int() {
  exit 130
}

on_term() {
  exit 143
}

trap on_exit EXIT
trap on_int INT
trap on_term TERM

###############################################################################
# CONFIG IDENTITY AND MOUNT VALIDATION
###############################################################################

initialize_config_identity() {
  SNAPRAID_CANONICAL_CONF=$(canonical_path "$SNAPRAID_CONF") ||
    die "Unable to canonicalize config path: $SNAPRAID_CONF"

  local base digest
  base=$(basename "${SNAPRAID_CANONICAL_CONF%.conf}")
  SNAPRAID_TAG=$(sanitize_tag "$base")
  digest=$(short_hash "$SNAPRAID_CANONICAL_CONF")
  CONFIG_ID="${SNAPRAID_TAG}-${digest}"

  CONFIG_STATE_DIR="${STATE_DIR}/${CONFIG_ID}"
  SYNC_WARN_FILE="${CONFIG_STATE_DIR}/warning-count"
  SMART_ERROR_BASELINE_FILE="${CONFIG_STATE_DIR}/smart-error-baseline.tsv"
  ARRAY_LOCK_FILE="${LOCK_DIR}/${CONFIG_ID}.lock"
}

# Verify that a mountpoint is mounted and, when configured, that it is backed by
# the expected source device. This is stronger than merely checking for a stale
# parity/content file underneath an unmounted directory.
validate_required_mounts() {
  local target expected actual expected_resolved actual_resolved

  ((${#REQUIRED_MOUNTS[@]} > 0 || ${#EXPECTED_MOUNT_SOURCES[@]} > 0)) || return 0

  have_cmd findmnt || die "findmnt is required when mount validation is configured"

  for target in "${REQUIRED_MOUNTS[@]}"; do
    actual=$(findmnt -nro SOURCE --target "$target" 2>/dev/null || true)
    [[ -n "$actual" ]] || die "Required filesystem is not mounted: $target"
    log "Verified mount: $target <- $actual"
  done

  for target in "${!EXPECTED_MOUNT_SOURCES[@]}"; do
    expected=${EXPECTED_MOUNT_SOURCES[$target]}
    actual=$(findmnt -nro SOURCE --target "$target" 2>/dev/null || true)
    [[ -n "$actual" ]] || die "Required filesystem is not mounted: $target"

    expected_resolved=$(canonical_path "$expected" 2>/dev/null || printf '%s' "$expected")
    actual_resolved=$(canonical_path "$actual" 2>/dev/null || printf '%s' "$actual")

    [[ "$actual_resolved" == "$expected_resolved" ]] ||
      die "Unexpected source mounted at $target: got $actual, expected $expected"

    log "Verified mount source: $target <- $actual"
  done
}

# Ask SnapRAID itself to parse and validate the config instead of attempting to
# fully duplicate SnapRAID's configuration grammar in Bash/Awk.
snapraid_preflight() {
  if run_cmd "PREFLIGHT_STATUS" snapraid_cmd status; then
    return 0
  fi

  local rc=$?
  die "SnapRAID status preflight failed for $SNAPRAID_CONF (rc=$rc)"
}

###############################################################################
# DIFF ANALYSIS AND SAFETY DECISIONS
###############################################################################

get_counts() {
  local diff_block
  diff_block=$(extract_job_log DIFF)

  ADD_COUNT=$(awk '/^[[:space:]]*[0-9]+[[:space:]]+added$/       {print $1; exit}' <<<"$diff_block")
  DEL_COUNT=$(awk '/^[[:space:]]*[0-9]+[[:space:]]+removed$/     {print $1; exit}' <<<"$diff_block")
  UPDATE_COUNT=$(awk '/^[[:space:]]*[0-9]+[[:space:]]+updated$/  {print $1; exit}' <<<"$diff_block")
  MOVE_COUNT=$(awk '/^[[:space:]]*[0-9]+[[:space:]]+moved$/      {print $1; exit}' <<<"$diff_block")
  COPY_COUNT=$(awk '/^[[:space:]]*[0-9]+[[:space:]]+copied$/     {print $1; exit}' <<<"$diff_block")
  RESTORED_COUNT=$(awk '/^[[:space:]]*[0-9]+[[:space:]]+restored$/ {print $1; exit}' <<<"$diff_block")

  [[ "$ADD_COUNT" =~ ^[0-9]+$ ]] || return 1
  [[ "$DEL_COUNT" =~ ^[0-9]+$ ]] || return 1
  [[ "$UPDATE_COUNT" =~ ^[0-9]+$ ]] || return 1
  [[ "$MOVE_COUNT" =~ ^[0-9]+$ ]] || return 1
  [[ "$COPY_COUNT" =~ ^[0-9]+$ ]] || return 1
  [[ "$RESTORED_COUNT" =~ ^[0-9]+$ ]] || RESTORED_COUNT=0
}

read_warning_count() {
  SYNC_WARN_COUNT=0
  [[ -f "$SYNC_WARN_FILE" ]] || return 0

  local value
  value=$(awk 'NR==1 && /^[0-9]+$/ {print; exit}' "$SYNC_WARN_FILE")
  [[ "$value" =~ ^[0-9]+$ ]] && SYNC_WARN_COUNT=$value
}

write_warning_count() {
  local value=$1 tmp
  tmp=$(mktemp "${SYNC_WARN_FILE}.XXXXXX") || return 1
  printf '%s\n' "$value" >"$tmp" || { rm -f -- "$tmp"; return 1; }
  chmod 0640 "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$SYNC_WARN_FILE"
}

clear_warning_count() {
  rm -f -- "$SYNC_WARN_FILE"
  SYNC_WARN_COUNT=0
}

evaluate_thresholds() {
  CHK_FAIL=0
  DO_SYNC=1
  SYNC_FORCED=0

  # Threshold semantics: a count equal to the configured threshold is blocked.
  if (( DEL_COUNT >= DEL_THRESHOLD )); then
    warn "Deleted files reached/exceeded threshold: ${DEL_COUNT} >= ${DEL_THRESHOLD}"
    CHK_FAIL=1
  else
    log "Deleted files below threshold: ${DEL_COUNT} < ${DEL_THRESHOLD}"
  fi

  if (( UPDATE_COUNT >= UP_THRESHOLD )); then
    warn "Updated files reached/exceeded threshold: ${UPDATE_COUNT} >= ${UP_THRESHOLD}"
    CHK_FAIL=1
  else
    log "Updated files below threshold: ${UPDATE_COUNT} < ${UP_THRESHOLD}"
  fi

  (( CHK_FAIL == 1 )) || return 0

  if (( SYNC_WARN_THRESHOLD == 0 )); then
    log "Threshold override is immediate (SYNC_WARN_THRESHOLD=0); forcing sync."
    DO_SYNC=1
    SYNC_FORCED=1
    return 0
  fi

  if (( SYNC_WARN_THRESHOLD < 0 )); then
    warn "Forced sync is disabled; sync remains blocked for manual review."
    DO_SYNC=0
    return 0
  fi

  read_warning_count
  ((SYNC_WARN_COUNT += 1))
  write_warning_count "$SYNC_WARN_COUNT" || die "Unable to persist warning count"

  if (( SYNC_WARN_COUNT >= SYNC_WARN_THRESHOLD )); then
    log "Threshold breach count ${SYNC_WARN_COUNT}/${SYNC_WARN_THRESHOLD}; forcing sync now."
    DO_SYNC=1
    SYNC_FORCED=1
  else
    log "Threshold breach count ${SYNC_WARN_COUNT}/${SYNC_WARN_THRESHOLD}; sync remains blocked."
    DO_SYNC=0
  fi
}

chk_zero_timestamps() {
  local status_block timelog

  status_block=$(extract_job_log PREFLIGHT_STATUS)
  timelog=$(grep -E 'You have [1-9][0-9]* files with zero sub-second timestamp\.' <<<"$status_block" | tail -n 1 || true)

  if [[ -n "$timelog" ]]; then
    ZERO_TIMESTAMP_FOUND=$(awk '{print $3}' <<<"$timelog")
    [[ "$ZERO_TIMESTAMP_FOUND" =~ ^[0-9]+$ ]] || ZERO_TIMESTAMP_FOUND=1
    log "${timelog/You have/Found}"
    if run_cmd "TOUCH" snapraid_cmd touch; then
      TOUCH_RC=0
      ZERO_TIMESTAMP_CORRECTED=1
      append_job TOUCH
    else
      TOUCH_RC=$?
      return "$TOUCH_RC"
    fi
  else
    log "No files with zero sub-second timestamps found."
  fi
}

###############################################################################
# EMAIL AND LOG REPORTING
###############################################################################

persist_full_log() {
  local ts host
  ts=$(date +'%Y%m%d-%H%M%S')
  host=$(hostname)
  FULL_LOG_FILE="${LOG_DIR}/${CONFIG_ID}-${host}-${ts}.log"

  cp -f -- "$TMP_OUTPUT" "$FULL_LOG_FILE" ||
    die "Unable to persist full log: $FULL_LOG_FILE"
}

prune_old_logs() {
  (( LOG_RETENTION_DAYS > 0 )) || return 0
  find "$LOG_DIR" -type f -name "${CONFIG_ID}-*.log" \
    -mtime "+${LOG_RETENTION_DAYS}" -delete 2>/dev/null ||
    warn "Unable to prune one or more old logs"
}

health_level_name() {
  case "$1" in
    0) printf 'HEALTHY' ;;
    1) printf 'NOTICE' ;;
    2) printf 'ATTENTION' ;;
    3) printf 'CRITICAL' ;;
    *) printf 'UNKNOWN' ;;
  esac
}

raise_health() {
  local level=$1 reason=$2
  (( level > HEALTH_LEVEL )) && HEALTH_LEVEL=$level
  HEALTH_REASONS+=("$reason")
}

add_health_note() {
  HEALTH_NOTES+=("$1")
}

capacity_source_includes_disk() {
  [[ "$CAPACITY_HEALTH_SOURCE" == "disk" || "$CAPACITY_HEALTH_SOURCE" == "both" ]]
}

capacity_source_includes_pool() {
  [[ "$CAPACITY_HEALTH_SOURCE" == "pool" || "$CAPACITY_HEALTH_SOURCE" == "both" ]]
}

format_kib() {
  # `df -Pk` reports 1 KiB blocks. Convert those blocks to the displayed unit.
  # Version 2.1.4 shifted every unit label by one level, so roughly 45 TB was
  # displayed as 44.8 PB.
  local kib=${1:--1}
  if (( kib < 0 )); then
    printf 'unknown'
  elif (( kib >= 1099511627776 )); then
    awk -v v="$kib" 'BEGIN { printf "%.1f PB", v/1099511627776 }'
  elif (( kib >= 1073741824 )); then
    awk -v v="$kib" 'BEGIN { printf "%.1f TB", v/1073741824 }'
  elif (( kib >= 1048576 )); then
    awk -v v="$kib" 'BEGIN { printf "%.1f GB", v/1048576 }'
  elif (( kib >= 1024 )); then
    awk -v v="$kib" 'BEGIN { printf "%.1f MB", v/1024 }'
  else
    printf '%s KB' "$kib"
  fi
}

validate_capacity_configuration() {
  case "$CAPACITY_HEALTH_SOURCE" in
    disk|pool|both|off) ;;
    *) die "CAPACITY_HEALTH_SOURCE must be disk, pool, both, or off (got: $CAPACITY_HEALTH_SOURCE)" ;;
  esac

  if capacity_source_includes_pool; then
    [[ -n "$MERGERFS_POOL_PATH" ]] ||
      die "MERGERFS_POOL_PATH is required when CAPACITY_HEALTH_SOURCE=$CAPACITY_HEALTH_SOURCE"
    [[ -d "$MERGERFS_POOL_PATH" ]] ||
      die "Configured pool path does not exist or is not a directory: $MERGERFS_POOL_PATH"
    have_cmd df || die "df is required for pool-capacity monitoring"
  fi

  case "$SMART_ERROR_HEALTH_MODE" in
    delta|threshold|off) ;;
    *) die "SMART_ERROR_HEALTH_MODE must be delta, threshold, or off (got: $SMART_ERROR_HEALTH_MODE)" ;;
  esac

  case "$SMART_FP_HEALTH_MODE" in
    failure-only|warning|off) ;;
    *) die "SMART_FP_HEALTH_MODE must be failure-only, warning, or off (got: $SMART_FP_HEALTH_MODE)" ;;
  esac
}

parse_pool_capacity_health() {
  capacity_source_includes_pool || return 0

  local values
  values=$(df -Pk -- "$MERGERFS_POOL_PATH" 2>/dev/null | awk 'NR==2 {
    use=$5; sub(/%/,"",use)
    print $1 "|" $2 "|" $3 "|" $4 "|" use
  }')

  if [[ -z "$values" ]]; then
    raise_health 2 "Unable to read capacity for pool ${MERGERFS_POOL_PATH}"
    return 0
  fi

  IFS='|' read -r POOL_FILESYSTEM POOL_TOTAL_KB POOL_USED_KB POOL_FREE_KB POOL_USAGE_PERCENT <<<"$values"
  POOL_FSTYPE=$(findmnt -nro FSTYPE --target "$MERGERFS_POOL_PATH" 2>/dev/null || true)

  if ! [[ "$POOL_USAGE_PERCENT" =~ ^[0-9]+$ ]]; then
    POOL_USAGE_PERCENT=-1
    raise_health 2 "Unable to parse capacity for pool ${MERGERFS_POOL_PATH}"
    return 0
  fi

  if (( POOL_USAGE_PERCENT >= POOL_USAGE_CRITICAL_PERCENT )); then
    raise_health 3 "Storage pool is ${POOL_USAGE_PERCENT}% full"
  elif (( POOL_USAGE_PERCENT >= POOL_USAGE_WARN_PERCENT )); then
    raise_health 2 "Storage pool is ${POOL_USAGE_PERCENT}% full"
  fi
}

parse_status_health() {
  local block="" source_job="PREFLIGHT_STATUS"
  if marker_end_present FINAL_STATUS; then
    source_job="FINAL_STATUS"
  fi
  block=$(extract_job_log "$source_job")
  [[ -n "$block" ]] || return 0

  local values
  values=$(awk '
    /The oldest block was scrubbed [0-9]+ days ago, the median [0-9]+, the newest [0-9]+/ {
      line=$0
      sub(/^.*scrubbed /, "", line)
      split(line,a,/ days ago, the median |, the newest |\./)
      print "SCRUB " a[1] " " a[2] " " a[3]
    }
    /^[0-9]+% of the array is not scrubbed\./ {
      v=$1; sub(/%/,"",v); print "UNSCRUBBED " v
    }
    /No error detected\./ { print "ERRORS 0" }
    /[0-9]+ errors? detected\./ {
      for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) { print "ERRORS " $i; break }
    }
  ' <<<"$block")

  local kind a b c
  while read -r kind a b c; do
    case "$kind" in
      SCRUB)
        SCRUB_OLDEST_DAYS=${a:--1}
        SCRUB_MEDIAN_DAYS=${b:--1}
        SCRUB_NEWEST_DAYS=${c:--1}
        ;;
      UNSCRUBBED) UNSCRUBBED_PERCENT=${a:--1} ;;
      ERRORS) SCRUB_DATA_ERRORS=${a:-0} ;;
    esac
  done <<<"$values"

  # Parse the status capacity table. The final fields are Use and disk name.
  local row disk use free
  while IFS='|' read -r disk use free; do
    [[ -n "$disk" && "$use" =~ ^[0-9]+$ ]] || continue
    (( use > MAX_DISK_USAGE )) && { MAX_DISK_USAGE=$use; MAX_DISK_USAGE_DISK=$disk; }
    if (( use >= DISK_USAGE_CRITICAL_PERCENT )); then
      (( REPORT_DISK_CAPACITY_WARNINGS == 1 )) && CAPACITY_WARNING_ROWS+=("$disk|$use|$free|critical")
      capacity_source_includes_disk && raise_health 3 "$disk is ${use}% full"
    elif (( use >= DISK_USAGE_WARN_PERCENT )); then
      (( REPORT_DISK_CAPACITY_WARNINGS == 1 )) && CAPACITY_WARNING_ROWS+=("$disk|$use|$free|warning")
      capacity_source_includes_disk && raise_health 2 "$disk is ${use}% full"
    fi
  done < <(awk '
    /^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[-0-9.]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+%[[:space:]]+[^[:space:]]+[[:space:]]*$/ {
      use=$(NF-1); sub(/%/,"",use); print $NF "|" use "|" $(NF-2)
    }
  ' <<<"$block")

  if (( SCRUB_DATA_ERRORS > 0 )); then
    raise_health 3 "Scrub/status detected ${SCRUB_DATA_ERRORS} data error(s)"
  fi
  if (( SCRUB_OLDEST_DAYS >= SCRUB_AGE_CRITICAL_DAYS )); then
    raise_health 2 "Oldest unscrubbed data is ${SCRUB_OLDEST_DAYS} days old"
  elif (( SCRUB_OLDEST_DAYS >= SCRUB_AGE_WARN_DAYS )); then
    raise_health 1 "Oldest unscrubbed data is ${SCRUB_OLDEST_DAYS} days old"
  fi
  if (( UNSCRUBBED_PERCENT >= UNSCRUBBED_CRITICAL_PERCENT )); then
    raise_health 2 "${UNSCRUBBED_PERCENT}% of the array is not scrubbed"
  elif (( UNSCRUBBED_PERCENT >= UNSCRUBBED_WARN_PERCENT )); then
    raise_health 1 "${UNSCRUBBED_PERCENT}% of the array is not scrubbed"
  fi
}

load_smart_error_baseline() {
  declare -gA SMART_ERROR_BASELINE=()
  local serial disk errors
  [[ -f "$SMART_ERROR_BASELINE_FILE" ]] || return 0
  while IFS=$'\t' read -r serial disk errors; do
    [[ -n "$serial" && "$errors" =~ ^[0-9]+$ ]] || continue
    SMART_ERROR_BASELINE["$serial"]=$errors
  done < "$SMART_ERROR_BASELINE_FILE"
}

write_smart_error_baseline() {
  local tmp row serial disk errors
  tmp=$(mktemp "${SMART_ERROR_BASELINE_FILE}.XXXXXX") || return 1
  for row in "${SMART_BASELINE_ROWS[@]}"; do
    IFS='|' read -r serial disk errors <<<"$row"
    printf '%s\t%s\t%s\n' "$serial" "$disk" "$errors"
  done >"$tmp"
  chmod 0640 "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$SMART_ERROR_BASELINE_FILE"
}

parse_smart_health() {
  marker_end_present SMART || return 0
  local block
  block=$(extract_job_log SMART)
  [[ -n "$block" ]] || return 0

  SMART_WARNING_ROWS=()
  SMART_INFO_ROWS=()
  SMART_BASELINE_ROWS=()
  load_smart_error_baseline

  local parsed
  parsed=$(awk '
    BEGIN { in_report=0 }
    /^SnapRAID SMART report:/ { in_report=1; next }
    in_report && /^Probability that at least one disk/ {
      if (match($0, /[0-9]+%/)) { v=substr($0,RSTART,RLENGTH); sub(/%/,"",v); print "OVERALL|" v }
      exit
    }
    in_report && /^[[:space:]]*[0-9-]+[[:space:]]+[0-9-]+[[:space:]]+[0-9-]+[[:space:]]+[0-9]+%[[:space:]]+/ {
      print "DISK|" $NF "|" $(NF-1) "|" $1 "|" $3 "|" $4 "|" $(NF-2)
    }
  ' <<<"$block")

  local kind disk device temp errors fp serial fpnum warning
  local baseline delta key numeric_errors baseline_was_missing=0
  [[ -f "$SMART_ERROR_BASELINE_FILE" ]] || baseline_was_missing=1

  while IFS='|' read -r kind disk device temp errors fp serial; do
    case "$kind" in
      OVERALL)
        SMART_OVERALL_FP=${disk:--1}
        ;;
      DISK)
        SMART_PARSE_OK=1
        ((SMART_DISK_COUNT+=1))
        [[ "$disk" == parity || "$disk" == *-parity ]] && ((SMART_PARITY_COUNT+=1)) || ((SMART_DATA_COUNT+=1))
        if [[ "$temp" =~ ^[0-9]+$ ]] && (( temp > SMART_MAX_TEMP )); then
          SMART_MAX_TEMP=$temp
          SMART_MAX_TEMP_DISK=$disk
        fi

        numeric_errors=0
        [[ "$errors" =~ ^[0-9]+$ ]] && numeric_errors=$errors
        (( numeric_errors > 0 )) && ((SMART_ERROR_DISKS+=1))

        key=${serial:-$disk}
        [[ -z "$key" || "$key" == "-" ]] && key=$disk

        # A baseline must be tied to a stable disk identity. Version 2.1.5
        # accidentally parsed the size column instead of the serial column, so
        # multiple same-size disks could overwrite one another. Missing keys are
        # now initialized to the current value without producing a false alert.
        local baseline_exists=0
        if [[ ${SMART_ERROR_BASELINE[$key]+_} ]]; then
          baseline_exists=1
          baseline=${SMART_ERROR_BASELINE[$key]}
        else
          baseline=$numeric_errors
        fi
        delta=$(( numeric_errors - baseline ))
        SMART_BASELINE_ROWS+=("$key|$disk|$numeric_errors")

        warning=""
        case "$SMART_ERROR_HEALTH_MODE" in
          delta)
            if (( baseline_exists == 1 && delta >= SMART_ERROR_DELTA_WARN_COUNT )); then
              ((SMART_NEW_ERROR_DISKS+=1))
              warning="SMART error count increased ${baseline} to ${numeric_errors}"
              raise_health 2 "$disk SMART error count increased from ${baseline} to ${numeric_errors}"
            elif (( baseline_exists == 1 && delta < 0 )); then
              add_health_note "$disk SMART error counter reset from ${baseline} to ${numeric_errors}; baseline updated"
            elif (( numeric_errors > 0 && REPORT_HISTORICAL_SMART_ERRORS == 1 )); then
              SMART_INFO_ROWS+=("$disk|$device|$temp|$numeric_errors|$fp|$serial|historical SMART error count ${numeric_errors} (unchanged)")
            fi
            ;;
          threshold)
            if (( numeric_errors >= SMART_ERROR_WARN_COUNT )); then
              warning="${numeric_errors} SMART error(s)"
              raise_health 2 "$disk reports ${numeric_errors} SMART error(s)"
            fi
            ;;
          off)
            if (( numeric_errors > 0 && REPORT_HISTORICAL_SMART_ERRORS == 1 )); then
              SMART_INFO_ROWS+=("$disk|$device|$temp|$numeric_errors|$fp|$serial|historical SMART error count ${numeric_errors}")
            fi
            ;;
        esac

        fpnum=${fp%%%}
        if [[ "$fpnum" =~ ^[0-9]+$ ]]; then
          if (( fpnum >= SMART_FAILED_FP_PERCENT )); then
            warning="${warning:+$warning; }failure probability ${fp}"
            raise_health 3 "$disk is reporting an estimated ${fp} failure probability"
          elif [[ "$SMART_FP_HEALTH_MODE" == "warning" ]] && (( fpnum >= SMART_FP_WARN_PERCENT )); then
            warning="${warning:+$warning; }failure probability ${fp}"
            raise_health 2 "$disk has an estimated ${fp} failure probability"
          fi
        fi
        if [[ "$temp" =~ ^[0-9]+$ ]]; then
          if (( temp >= DISK_TEMP_CRITICAL_C )); then
            warning="${warning:+$warning; }temperature ${temp}C"
            raise_health 3 "$disk temperature is ${temp}C"
          elif (( temp >= DISK_TEMP_WARN_C )); then
            warning="${warning:+$warning; }temperature ${temp}C"
            raise_health 2 "$disk temperature is ${temp}C"
          fi
        fi
        [[ -n "$warning" ]] && SMART_WARNING_ROWS+=("$disk|$device|$temp|$numeric_errors|$fp|$serial|$warning")
        ;;
    esac
  done <<<"$parsed"

  if (( SMART_PARSE_OK == 0 )); then
    raise_health 1 "SMART output was collected but could not be summarized"
  else
    if ! write_smart_error_baseline; then
      raise_health 1 "Unable to update the SMART error baseline"
    elif (( baseline_was_missing == 1 )) && [[ "$SMART_ERROR_HEALTH_MODE" == "delta" ]]; then
      add_health_note "SMART error baseline initialized; only future increases will affect health"
    fi
  fi

  if (( SMART_OVERALL_FP >= 0 )); then
    if (( AGGREGATE_FP_IS_WARNING == 1 && SMART_OVERALL_FP >= SMART_FP_WARN_PERCENT )); then
      raise_health 2 "Estimated probability of at least one disk failure is ${SMART_OVERALL_FP}%"
    else
      add_health_note "Estimated probability of at least one disk failure within one year: ${SMART_OVERALL_FP}%"
    fi
  fi
}

evaluate_health() {
  HEALTH_LEVEL=0
  HEALTH_REASONS=()
  HEALTH_NOTES=()
  CAPACITY_WARNING_ROWS=()
  SMART_WARNING_ROWS=()
  SMART_INFO_ROWS=()

  if (( HAD_FAILURE == 1 )); then
    raise_health 3 "One or more maintenance commands failed"
  elif (( CHK_FAIL == 1 && DO_SYNC == 0 )); then
    raise_health 2 "Sync was blocked by safety thresholds"
  elif (( SYNC_FORCED == 1 )); then
    raise_health 1 "A threshold override forced synchronization"
  fi

  if (( ZERO_TIMESTAMP_FOUND > 0 )); then
    if (( ZERO_TIMESTAMP_CORRECTED == 1 )); then
      add_health_note "${ZERO_TIMESTAMP_FOUND} zero timestamp file(s) corrected"
    else
      raise_health 2 "${ZERO_TIMESTAMP_FOUND} zero timestamp file(s) were not corrected"
    fi
  fi

  if (( DIFF_RC == 0 )); then
    PARITY_STATE="CURRENT"
  elif (( DIFF_RC == 2 && DO_SYNC == 1 && SYNC_RC == 0 )); then
    PARITY_STATE="CURRENT"
  elif (( DIFF_RC == 2 && DO_SYNC == 0 )); then
    PARITY_STATE="OUT OF SYNC"
  else
    PARITY_STATE="UNKNOWN"
  fi

  parse_status_health
  parse_pool_capacity_health
  (( SMART_LOG == 1 )) && parse_smart_health
  HEALTH_LABEL=$(health_level_name "$HEALTH_LEVEL")

  if (( HAD_FAILURE == 1 )); then
    REPORT_DETAIL_EFFECTIVE=$EMAIL_DETAIL_ON_FAILURE
  elif (( HEALTH_LEVEL >= 2 || CHK_FAIL == 1 )); then
    REPORT_DETAIL_EFFECTIVE=$EMAIL_DETAIL_ON_WARNING
  else
    REPORT_DETAIL_EFFECTIVE=$EMAIL_DETAIL_LEVEL
  fi
  case "$REPORT_DETAIL_EFFECTIVE" in
    summary|changes|diagnostic|full) ;;
    *) REPORT_DETAIL_EFFECTIVE="summary" ;;
  esac
}

prepare_mail_subject() {
  local prefix detail=""
  if [[ -n "$EMAIL_SUBJECT_PREFIX" ]]; then
    prefix=$EMAIL_SUBJECT_PREFIX
  else
    prefix="SnapRAID $(hostname) [${SNAPRAID_TAG}]"
  fi

  if (( HAD_FAILURE == 1 )); then
    SUBJECT="🔴 [FAILED] ${prefix}"
  elif (( CHK_FAIL == 1 && DO_SYNC == 0 )); then
    SUBJECT="🟠 [SYNC BLOCKED] ${prefix} — ${DEL_COUNT} removed · ${UPDATE_COUNT} updated"
  elif (( HEALTH_LEVEL >= 3 )); then
    SUBJECT="🔴 [CRITICAL] ${prefix}"
  elif (( HEALTH_LEVEL >= 2 )); then
    if ((${#HEALTH_REASONS[@]} > 0)); then detail=${HEALTH_REASONS[0]}; fi
    SUBJECT="🟠 [ATTENTION] ${prefix}${detail:+ — $detail}"
  elif (( HEALTH_LEVEL == 1 )); then
    SUBJECT="🔵 [NOTICE] ${prefix} — synced · review notes"
  else
    SUBJECT="🟢 [HEALTHY] ${prefix} — parity current · scrub clean · ${SMART_DISK_COUNT} disks"
  fi
}

print_rule() { printf '%s\n' '────────────────────────────────────────────────────────────'; }
print_kv() { printf '%-24s %s\n' "$1" "$2"; }

append_change_details() {
  local block line count=0 max=$((DIFF_LIST_HEAD + DIFF_LIST_TAIL))
  block=$(extract_job_log DIFF)
  printf '\nCHANGE DETAILS\n'; print_rule
  while IFS= read -r line; do
    [[ "$line" =~ ^(add|remove|update|move|copy|restore)[[:space:]]+ ]] || continue
    printf '  %s\n' "$line"
    ((count+=1))
    (( count >= max )) && break
  done <<<"$block"
  local total=$((ADD_COUNT + DEL_COUNT + UPDATE_COUNT + MOVE_COUNT + COPY_COUNT + RESTORED_COUNT))
  (( total > count )) && printf '  ... %d additional change(s) are listed in the full log.\n' "$((total-count))"
}

append_diagnostic_excerpt() {
  printf '\nDIAGNOSTIC EXCERPT\n'; print_rule
  awk '
    /^__SNAPRAID_/ {next}
    /^###[A-Z0-9_]+ \[/ {next}
    /(^|[[:space:]])(ERROR|WARNING|failed|Failed|error detected|errors detected)/ {print; next}
    /^SnapRAID .* report:/ {print; next}
    /^The oldest block was scrubbed/ {print; next}
    /^[0-9]+% of the array is not scrubbed/ {print; next}
    /^Probability that at least one disk/ {print; next}
  ' "$TMP_OUTPUT" | tail -n 120
}

beautify_email_output_text() {
  local tmp duration execution="SUCCESS" health_symbol="✓"
  tmp=$(mktemp -t snapraid.pretty.XXXXXX)
  duration=$(format_duration "$SECONDS")
  (( HAD_FAILURE == 1 )) && execution="FAILED"
  (( CHK_FAIL == 1 && DO_SYNC == 0 )) && execution="SYNC BLOCKED"
  (( HEALTH_LEVEL >= 2 )) && health_symbol="⚠"
  (( HEALTH_LEVEL >= 3 )) && health_symbol="✗"

  {
    printf 'SNAPRAID HEALTH REPORT\n'
    printf '%s · %s\n\n' "$(hostname)" "$SNAPRAID_TAG"
    printf 'Overall health: %s %s\n' "$health_symbol" "$HEALTH_LABEL"
    printf 'Execution:      %s\n' "$execution"

    if ((${#HEALTH_REASONS[@]} > 0)); then
      printf '\nITEMS REQUIRING ATTENTION\n'; print_rule
      local reason
      for reason in "${HEALTH_REASONS[@]}"; do printf '  ⚠ %s\n' "$reason"; done
    fi
    if ((${#HEALTH_NOTES[@]} > 0)); then
      printf '\nINFORMATION\n'; print_rule
      local note
      for note in "${HEALTH_NOTES[@]}"; do printf '  ℹ %s\n' "$note"; done
    fi

    printf '\nPROTECTION STATUS\n'; print_rule
    printf 'Parity:          %s\n' "$PARITY_STATE"
    printf 'Sync:            %s\n' "$([[ $SYNC_RC -eq 0 && $JOBS_DONE == *SYNC* ]] && printf COMPLETED || ([[ $DO_SYNC -eq 0 ]] && printf 'NOT REQUIRED / BLOCKED' || printf 'NOT COMPLETED'))"
    printf 'Scrub:           %s\n' "$([[ $SCRUB_RC -eq 0 && $JOBS_DONE == *SCRUB* ]] && printf "COMPLETED — ${SCRUB_PERCENT}%% requested" || printf 'NOT COMPLETED')"
    printf 'Data errors:     %s\n' "$([[ $SCRUB_DATA_ERRORS -eq 0 ]] && printf 'NONE DETECTED' || printf '%d DETECTED' "$SCRUB_DATA_ERRORS")"
    if (( ZERO_TIMESTAMP_FOUND > 0 )); then
      printf 'Zero timestamps: %s\n' "${ZERO_TIMESTAMP_FOUND} found — $([[ $ZERO_TIMESTAMP_CORRECTED -eq 1 ]] && printf corrected || printf unresolved)"
    fi
    printf 'Duration:        %s\n' "$duration"
    printf 'Finished:        %s\n' "$(date)"

    printf '\nCHANGES PROTECTED\n'; print_rule
    printf 'Added:    %s\nRemoved:  %s\nUpdated:  %s\nMoved:    %s\nCopied:   %s\nRestored: %s\n' \
      "$ADD_COUNT" "$DEL_COUNT" "$UPDATE_COUNT" "$MOVE_COUNT" "$COPY_COUNT" "$RESTORED_COUNT"

    printf '\nSCRUB COVERAGE\n'; print_rule
    printf 'Checked this run: %s\n' "$([[ $JOBS_DONE == *SCRUB* ]] && printf '%s%% requested' "$SCRUB_PERCENT" || printf 'not run')"
    (( SCRUB_OLDEST_DAYS >= 0 )) && printf 'Oldest block:     %s days ago\n' "$SCRUB_OLDEST_DAYS"
    (( SCRUB_MEDIAN_DAYS >= 0 )) && printf 'Median block:     %s days ago\n' "$SCRUB_MEDIAN_DAYS"
    (( SCRUB_NEWEST_DAYS >= 0 )) && printf 'Newest block:     %s days ago\n' "$SCRUB_NEWEST_DAYS"
    (( UNSCRUBBED_PERCENT >= 0 )) && printf 'Not yet scrubbed: %s%%\n' "$UNSCRUBBED_PERCENT"
    printf 'Errors detected:  %s\n' "$SCRUB_DATA_ERRORS"

    printf '\nDRIVE HEALTH\n'; print_rule
    printf 'Drives monitored:    %s\n' "$SMART_DISK_COUNT"
    printf 'Data / parity:       %s / %s\n' "$SMART_DATA_COUNT" "$SMART_PARITY_COUNT"
    (( SMART_MAX_TEMP >= 0 )) && printf 'Highest temperature: %s°C on %s\n' "$SMART_MAX_TEMP" "$SMART_MAX_TEMP_DISK"
    (( MAX_DISK_USAGE >= 0 )) && printf 'Highest disk use:    %s%% on %s\n' "$MAX_DISK_USAGE" "$MAX_DISK_USAGE_DISK"
    (( SMART_OVERALL_FP >= 0 )) && printf 'Estimated array FP:  %s%% within one year\n' "$SMART_OVERALL_FP"


    printf '\nCAPACITY POLICY\n'; print_rule
    printf 'Health source:        %s\n' "$CAPACITY_HEALTH_SOURCE"
    if (( POOL_USAGE_PERCENT >= 0 )); then
      printf 'Pool path:            %s\n' "$MERGERFS_POOL_PATH"
      printf 'Pool utilization:     %s%%\n' "$POOL_USAGE_PERCENT"
      printf 'Pool free:            %s\n' "$(format_kib "$POOL_FREE_KB")"
      [[ -n "$POOL_FSTYPE" ]] && printf 'Pool filesystem:      %s\n' "$POOL_FSTYPE"
    fi

    if ((${#SMART_INFO_ROWS[@]} > 0)); then
      printf '\nSMART information:\n'
      local row disk dev temp err fp serial warning
      for row in "${SMART_INFO_ROWS[@]}"; do
        IFS='|' read -r disk dev temp err fp serial warning <<<"$row"
        printf '  %s — %s — %s°C — %s\n' "$disk" "$dev" "$temp" "$warning"
      done
    fi
    if ((${#SMART_WARNING_ROWS[@]} > 0)); then
      printf '\nDrives requiring attention:\n'
      local row disk dev temp err fp serial warning
      for row in "${SMART_WARNING_ROWS[@]}"; do
        IFS='|' read -r disk dev temp err fp serial warning <<<"$row"
        printf '  %s — %s — %s°C — FP %s — %s\n' "$disk" "$dev" "$temp" "$fp" "$warning"
      done
    fi
    if ((${#CAPACITY_WARNING_ROWS[@]} > 0)); then
      printf '\nCapacity warnings:\n'
      local row disk use free severity
      for row in "${CAPACITY_WARNING_ROWS[@]}"; do
        IFS='|' read -r disk use free severity <<<"$row"
        printf '  %s — %s%% used — %s GB free\n' "$disk" "$use" "$free"
      done
    fi

    printf '\nJOB RESULTS\n'; print_rule
    printf 'Jobs: %s\n' "${JOBS_DONE:-none}"
    printf 'Diff: %s\n' "$([[ $DIFF_RC -eq 0 ]] && printf 'PASS — no changes' || ([[ $DIFF_RC -eq 2 ]] && printf 'PASS — changes found' || printf 'FAILED rc=%d' "$DIFF_RC"))"
    [[ $JOBS_DONE == *SYNC* ]] && printf 'Sync: %s\n' "$([[ $SYNC_RC -eq 0 ]] && printf PASS || printf 'FAILED rc=%d' "$SYNC_RC")"
    [[ $JOBS_DONE == *SCRUB* ]] && printf 'Scrub: %s\n' "$([[ $SCRUB_RC -eq 0 ]] && printf PASS || printf 'FAILED rc=%d' "$SCRUB_RC")"
    (( SMART_LOG == 1 )) && printf 'SMART collection: %s\n' "$([[ $SMART_RC -eq 0 ]] && printf PASS || printf 'FAILED rc=%d' "$SMART_RC")"

    printf '\nREPORT DETAILS\n'; print_rule
    printf 'Config:              %s\n' "$SNAPRAID_CONF"
    printf 'Config ID:           %s\n' "$CONFIG_ID"
    printf 'Full diagnostic log: %s\n' "$FULL_LOG_FILE"

    case "$REPORT_DETAIL_EFFECTIVE" in
      changes) append_change_details ;;
      diagnostic) append_change_details; append_diagnostic_excerpt ;;
      full)
        printf '\nFULL COMMAND LOG\n'; print_rule
        sed -E '/^__SNAPRAID_[A-Z0-9_]+_(BEGIN|END)__/d; /^###[A-Z0-9_]+ \[/d' "$TMP_OUTPUT"
        ;;
    esac
  } >"$tmp"
  mv -f -- "$tmp" "$EMAIL_OUTPUT"
}

html_escape() {
  # Escape untrusted values before inserting them into the HTML report.
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

html_value() {
  printf '%s' "$1" | html_escape
}

html_row() {
  local label value
  label=$(html_value "$1")
  value=$(html_value "$2")
  printf '<tr><th>%s</th><td>%s</td></tr>\n' "$label" "$value"
}

html_section_start() {
  printf '<div class="section"><h2>%s</h2><table role="presentation">\n' "$(html_value "$1")"
}

html_section_end() {
  printf '</table></div>\n'
}

append_change_details_html() {
  local block line count=0 max=$((DIFF_LIST_HEAD + DIFF_LIST_TAIL))
  local total=$((ADD_COUNT + DEL_COUNT + UPDATE_COUNT + MOVE_COUNT + COPY_COUNT + RESTORED_COUNT))
  block=$(extract_job_log DIFF)
  printf '<div class="section"><h2>Change details</h2><pre>'
  while IFS= read -r line; do
    [[ "$line" =~ ^(add|remove|update|move|copy|restore)[[:space:]]+ ]] || continue
    printf '%s\n' "$line" | html_escape
    ((count+=1))
    (( count >= max )) && break
  done <<<"$block"
  (( total > count )) && printf '%s\n' "... $((total-count)) additional change(s) are listed in the full log." | html_escape
  printf '</pre></div>\n'
}

append_diagnostic_excerpt_html() {
  local excerpt
  excerpt=$(awk '
    /^__SNAPRAID_/ {next}
    /^###[A-Z0-9_]+ \[/ {next}
    /(^|[[:space:]])(ERROR|WARNING|failed|Failed|error detected|errors detected)/ {print; next}
    /^SnapRAID .* report:/ {print; next}
    /^The oldest block was scrubbed/ {print; next}
    /^[0-9]+% of the array is not scrubbed/ {print; next}
    /^Probability that at least one disk/ {print; next}
  ' "$TMP_OUTPUT" | tail -n 120)
  printf '<div class="section"><h2>Diagnostic excerpt</h2><pre>'
  printf '%s\n' "$excerpt" | html_escape
  printf '</pre></div>\n'
}

beautify_email_output_html() {
  local tmp duration execution="SUCCESS" status_class="healthy"
  local sync_state scrub_state data_error_state total_changes alert_count
  local sync_short scrub_short parity_short
  tmp=$(mktemp -t snapraid.pretty.XXXXXX)
  duration=$(format_duration "$SECONDS")

  (( HAD_FAILURE == 1 )) && execution="FAILED"
  (( CHK_FAIL == 1 && DO_SYNC == 0 )) && execution="SYNC BLOCKED"

  if (( HAD_FAILURE == 1 || HEALTH_LEVEL >= 3 )); then
    status_class="critical"
  elif (( CHK_FAIL == 1 || HEALTH_LEVEL >= 2 )); then
    status_class="warning"
  elif (( HEALTH_LEVEL == 1 )); then
    status_class="notice"
  fi

  sync_state=$([[ $SYNC_RC -eq 0 && $JOBS_DONE == *SYNC* ]] && printf COMPLETED || ([[ $DO_SYNC -eq 0 ]] && printf 'NOT REQUIRED / BLOCKED' || printf 'NOT COMPLETED'))
  scrub_state=$([[ $SCRUB_RC -eq 0 && $JOBS_DONE == *SCRUB* ]] && printf "COMPLETED — ${SCRUB_PERCENT}%% requested" || printf 'NOT COMPLETED')
  data_error_state=$([[ $SCRUB_DATA_ERRORS -eq 0 ]] && printf 'NONE DETECTED' || printf '%d DETECTED' "$SCRUB_DATA_ERRORS")
  total_changes=$((ADD_COUNT + DEL_COUNT + UPDATE_COUNT + MOVE_COUNT + COPY_COUNT + RESTORED_COUNT))
  alert_count=$((${#HEALTH_REASONS[@]}))

  parity_short="$PARITY_STATE"
  sync_short=$([[ $SYNC_RC -eq 0 && $JOBS_DONE == *SYNC* ]] && printf 'Complete' || ([[ $DO_SYNC -eq 0 ]] && printf 'Not needed' || printf 'Incomplete'))
  scrub_short=$([[ $SCRUB_RC -eq 0 && $JOBS_DONE == *SCRUB* ]] && printf 'Complete' || printf 'Not run')

  {
    cat <<'HTML'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<style>
  :root{color-scheme:light dark;supported-color-schemes:light dark}
  body{margin:0;padding:0;background:#f1f4f6;color:#1c2732;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;line-height:1.4}
  table{border-collapse:collapse;border-spacing:0}
  .outer{width:100%;background:#f1f4f6;padding:20px 12px}
  .shell{width:100%;max-width:1180px;margin:0 auto;background:#ffffff;border:1px solid #cfd7de}
  .header{background:#ffffff;color:#152536;padding:24px 28px;border-top:7px solid #20384d;border-bottom:1px solid #d8dfe5}
  .title{font-size:25px;line-height:1.2;font-weight:800;margin:0;color:#152536}
  .subtitle{font-size:14px;color:#5f6d79;padding-top:6px}
  .status-cell{padding:0 0 0 20px;text-align:right;vertical-align:middle}
  .status-badge{display:inline-block;padding:9px 13px;border:2px solid currentColor;border-radius:6px;font-size:13px;font-weight:800;letter-spacing:.02em;text-transform:uppercase;white-space:nowrap;background:#ffffff}
  .healthy .status-badge{color:#17613b}.warning .status-badge{color:#8a5900}.critical .status-badge{color:#a12620}.notice .status-badge{color:#1c5f94}
  .summary{padding:17px 28px;border-bottom:1px solid #d8dfe5;background:#ffffff}
  .summary-main{font-size:18px;font-weight:800;color:#1c2732}
  .summary-sub{font-size:13px;color:#65727e;padding-top:3px}
  .body{padding:22px 28px 28px;background:#ffffff}
  .kpis{width:100%;table-layout:fixed;margin-bottom:20px}
  .kpis td{width:16.666%;vertical-align:top;padding:0 5px}
  .kpis td:first-child{padding-left:0}.kpis td:last-child{padding-right:0}
  .kpi{border:1px solid #d5dce2;border-top:4px solid #7a8792;background:#ffffff;padding:12px 12px;min-height:76px}
  .kpi.good{border-top-color:#2c7a50}.kpi.warn{border-top-color:#d79000}.kpi.info{border-top-color:#3278aa}
  .kpi-label{font-size:10px;letter-spacing:.07em;text-transform:uppercase;color:#66737f;font-weight:800}
  .kpi-value{font-size:19px;line-height:1.15;font-weight:850;padding-top:7px;color:#1c2732}
  .kpi-sub{font-size:11px;color:#66737f;padding-top:4px}
  .section{padding-top:4px;margin-top:18px}
  .section-title{font-size:13px;text-transform:uppercase;letter-spacing:.06em;font-weight:800;color:#3d4c59;padding-bottom:8px;border-bottom:2px solid #dce3e8;margin-bottom:10px}
  .alert{width:100%;margin-bottom:8px;background:#ffffff;border:1px solid #e0e4e8;border-left:5px solid #d79000}
  .alert td{padding:11px 13px;font-size:14px;color:#1c2732}.alert-type{text-align:right;color:#815300;font-size:11px;font-weight:800;text-transform:uppercase;white-space:nowrap}
  .note{width:100%;margin-bottom:8px;background:#ffffff;border:1px solid #e0e4e8;border-left:5px solid #3278aa}
  .note td{padding:11px 13px;font-size:14px;color:#1c2732}
  .columns{width:100%;table-layout:fixed}.columns>tbody>tr>td{width:50%;vertical-align:top}.col-left{padding-right:9px}.col-right{padding-left:9px}
  .panel{width:100%;border:1px solid #d5dce2;background:#ffffff}
  .panel-head{background:#ffffff;padding:11px 13px;font-size:13px;font-weight:800;color:#293946;border-bottom:2px solid #dce3e8}
  .data{width:100%;background:#ffffff}.data th,.data td{padding:9px 12px;border-bottom:1px solid #e8edf1;font-size:13px;text-align:left;vertical-align:top}
  .data tr:last-child th,.data tr:last-child td{border-bottom:0}.data th{width:52%;color:#66737f;font-weight:600}.data td{font-weight:750;color:#1c2732}
  .good-text{color:#24764b!important}.warn-text{color:#8a5900!important}.critical-text{color:#a12620!important}
  .drive-table{width:100%;border:1px solid #d5dce2;background:#ffffff}.drive-table th,.drive-table td{padding:9px 10px;border-bottom:1px solid #e8edf1;font-size:12px;text-align:left;color:#1c2732}.drive-table th{background:#ffffff;color:#66737f;text-transform:uppercase;letter-spacing:.05em;font-size:10px;border-bottom:2px solid #dce3e8}.drive-table tr:last-child td{border-bottom:0}
  .detail-row{background:#ffffff}.detail-row td:last-child{font-weight:700;color:#815300}
  pre{white-space:pre-wrap;word-break:break-word;margin:0;background:#f4f6f8;color:#1e2933;border:1px solid #d5dce2;padding:14px;font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
  .footer{padding:15px 28px;background:#ffffff;color:#72808c;font-size:11px;border-top:1px solid #d8dfe5}
  .footer-table{width:100%}.footer-table td{vertical-align:top}.footer-right{text-align:right}

  /* Clients that support true dark-mode media queries get an intentional dark
     palette. Clients that force-invert instead see the neutral light palette,
     which avoids the large black/tinted blocks from the previous version. */
  @media (prefers-color-scheme:dark){
    body,.outer{background:#171b20!important;color:#e8edf1!important}
    .shell,.header,.summary,.body,.footer,.kpi,.panel,.panel-head,.data,.drive-table,.drive-table th,.alert,.note,.detail-row{background:#22272d!important}
    .shell{border-color:#414950!important}.header{border-top-color:#7290a8!important;border-bottom-color:#414950!important}
    .title,.summary-main,.kpi-value,.alert td,.note td,.data td,.drive-table td{color:#f2f5f7!important}
    .subtitle,.summary-sub,.kpi-label,.kpi-sub,.data th,.drive-table th,.footer{color:#aeb9c2!important}
    .summary,.footer,.panel,.kpi,.drive-table,.alert,.note,pre{border-color:#414950!important}
    .section-title,.panel-head,.drive-table th{color:#d7dfe5!important;border-color:#4b545c!important}
    .status-badge{background:#22272d!important}
    pre{background:#181c21!important;color:#e6ebef!important}
  }
  /* Outlook.com dark-mode hook. */
  [data-ogsc] body,[data-ogsc] .outer{background:#171b20!important;color:#e8edf1!important}
  [data-ogsc] .shell,[data-ogsc] .header,[data-ogsc] .summary,[data-ogsc] .body,[data-ogsc] .footer,[data-ogsc] .kpi,[data-ogsc] .panel,[data-ogsc] .panel-head,[data-ogsc] .data,[data-ogsc] .drive-table,[data-ogsc] .drive-table th,[data-ogsc] .alert,[data-ogsc] .note,[data-ogsc] .detail-row{background:#22272d!important}
  [data-ogsc] .title,[data-ogsc] .summary-main,[data-ogsc] .kpi-value,[data-ogsc] .alert td,[data-ogsc] .note td,[data-ogsc] .data td,[data-ogsc] .drive-table td{color:#f2f5f7!important}
  [data-ogsc] .subtitle,[data-ogsc] .summary-sub,[data-ogsc] .kpi-label,[data-ogsc] .kpi-sub,[data-ogsc] .data th,[data-ogsc] .drive-table th,[data-ogsc] .footer{color:#aeb9c2!important}

  @media only screen and (max-width:760px){
    .outer{padding:0}.shell{border-left:0;border-right:0}.header,.summary,.body,.footer{padding-left:16px!important;padding-right:16px!important}
    .header-table,.header-table tbody,.header-table tr,.header-table td{display:block!important;width:100%!important}.status-cell{padding:14px 0 0!important;text-align:left!important}
    .kpis,.kpis tbody,.kpis tr{display:block!important;width:100%!important}.kpis td{display:inline-block!important;width:50%!important;padding:5px!important;box-sizing:border-box}.kpis td:nth-child(odd){padding-left:0!important}.kpis td:nth-child(even){padding-right:0!important}
    .columns,.columns tbody,.columns tr,.columns>tbody>tr>td{display:block!important;width:100%!important}.col-left,.col-right{padding:0!important}.col-right{padding-top:16px!important}
    .footer-table,.footer-table tbody,.footer-table tr,.footer-table td{display:block!important;width:100%!important}.footer-right{text-align:left!important;padding-top:5px}
  }
  @media only screen and (max-width:440px){.kpis td{display:block!important;width:100%!important;padding:5px 0!important}.title{font-size:22px}}
</style>
</head>
<body style="margin:0;padding:0;background:#f1f4f6">
<table role="presentation" class="outer" width="100%" bgcolor="#f1f4f6"><tr><td>
<table role="presentation" class="shell" width="100%" bgcolor="#ffffff">
HTML
    printf '<tr><td class="header %s" bgcolor="#ffffff">\n' "$status_class"
    printf '<table role="presentation" class="header-table" width="100%%"><tr><td><div class="title">SnapRAID Health Report</div><div class="subtitle">%s &middot; %s &middot; %s</div></td><td class="status-cell"><span class="status-badge">%s</span></td></tr></table>\n' \
      "$(html_value "$(hostname)")" "$(html_value "$SNAPRAID_TAG")" "$(html_value "$(date '+%b %d, %Y · %l:%M %p')")" "$(html_value "$HEALTH_LABEL")"
    printf '</td></tr>\n'

    printf '<tr><td class="summary" bgcolor="#ffffff"><div class="summary-main">Execution: %s</div><div class="summary-sub">Parity %s &middot; %s active finding(s) &middot; completed in %s</div></td></tr>\n' \
      "$(html_value "$execution")" "$(html_value "${PARITY_STATE,,}")" "$alert_count" "$(html_value "$duration")"

    printf '<tr><td class="body" bgcolor="#ffffff">\n'

    # Compact KPI row. Tables are used rather than CSS grid so Outlook and
    # other conservative email clients preserve the intended alignment.
    printf '<table role="presentation" class="kpis" width="100%%"><tr>\n'
    printf '<td><div class="kpi good"><div class="kpi-label">Parity</div><div class="kpi-value">%s</div><div class="kpi-sub">Sync %s</div></div></td>\n' "$(html_value "$parity_short")" "$(html_value "$sync_short")"
    printf '<td><div class="kpi"><div class="kpi-label">Changes</div><div class="kpi-value">%s</div><div class="kpi-sub">%s added · %s removed</div></div></td>\n' "$total_changes" "$ADD_COUNT" "$DEL_COUNT"
    printf '<td><div class="kpi %s"><div class="kpi-label">Alerts</div><div class="kpi-value">%s</div><div class="kpi-sub">Health findings</div></div></td>\n' "$([[ $alert_count -gt 0 ]] && printf warn || printf good)" "$alert_count"
    printf '<td><div class="kpi info"><div class="kpi-label">Drives</div><div class="kpi-value">%s</div><div class="kpi-sub">%s data · %s parity</div></div></td>\n' "$SMART_DISK_COUNT" "$SMART_DATA_COUNT" "$SMART_PARITY_COUNT"
    printf '<td><div class="kpi"><div class="kpi-label">Max temp</div><div class="kpi-value">%s</div><div class="kpi-sub">%s</div></div></td>\n' "$([[ $SMART_MAX_TEMP -ge 0 ]] && printf '%s°C' "$SMART_MAX_TEMP" || printf '—')" "$(html_value "${SMART_MAX_TEMP_DISK:-No data}")"
    printf '<td><div class="kpi"><div class="kpi-label">Duration</div><div class="kpi-value">%s</div><div class="kpi-sub">Scrub %s</div></div></td>\n' "$(html_value "$duration")" "$(html_value "$scrub_short")"
    printf '</tr></table>\n'

    if ((${#HEALTH_REASONS[@]} > 0)); then
      printf '<div class="section"><div class="section-title">Items requiring attention</div>\n'
      local reason
      for reason in "${HEALTH_REASONS[@]}"; do
        printf '<table role="presentation" class="alert"><tr><td>%s</td></tr></table>\n' "$(html_value "$reason")"
      done
      printf '</div>\n'
    fi

    if ((${#HEALTH_NOTES[@]} > 0)); then
      printf '<div class="section"><div class="section-title">Information</div>\n'
      local note
      for note in "${HEALTH_NOTES[@]}"; do
        printf '<table role="presentation" class="note"><tr><td>%s</td></tr></table>\n' "$(html_value "$note")"
      done
      printf '</div>\n'
    fi

    # Two-column operational summary on wide screens; the media query stacks
    # these panels on phones without relying on flexbox or CSS grid.
    printf '<div class="section"><table role="presentation" class="columns" width="100%%"><tr><td class="col-left">\n'
    printf '<table role="presentation" class="panel"><tr><td class="panel-head">Protection status</td></tr><tr><td><table class="data">\n'
    html_row "Parity" "$PARITY_STATE"
    html_row "Sync" "$sync_state"
    html_row "Scrub" "$scrub_state"
    html_row "Data errors" "$data_error_state"
    if (( ZERO_TIMESTAMP_FOUND > 0 )); then
      html_row "Zero timestamps" "${ZERO_TIMESTAMP_FOUND} found — $([[ $ZERO_TIMESTAMP_CORRECTED -eq 1 ]] && printf corrected || printf unresolved)"
    fi
    printf '</table></td></tr></table>\n'
    printf '</td><td class="col-right">\n'
    printf '<table role="presentation" class="panel"><tr><td class="panel-head">Changes protected</td></tr><tr><td><table class="data">\n'
    html_row "Added" "$ADD_COUNT"; html_row "Removed" "$DEL_COUNT"; html_row "Updated" "$UPDATE_COUNT"; html_row "Moved" "$MOVE_COUNT"; html_row "Copied" "$COPY_COUNT"; html_row "Restored" "$RESTORED_COUNT"
    printf '</table></td></tr></table>\n'
    printf '</td></tr></table></div>\n'

    printf '<div class="section"><table role="presentation" class="columns" width="100%%"><tr><td class="col-left">\n'
    printf '<table role="presentation" class="panel"><tr><td class="panel-head">Drive health</td></tr><tr><td><table class="data">\n'
    html_row "Drives monitored" "$SMART_DISK_COUNT"
    html_row "Data / parity" "${SMART_DATA_COUNT} / ${SMART_PARITY_COUNT}"
    (( SMART_MAX_TEMP >= 0 )) && html_row "Highest temperature" "${SMART_MAX_TEMP}°C on ${SMART_MAX_TEMP_DISK}"
    (( MAX_DISK_USAGE >= 0 )) && html_row "Highest disk use" "${MAX_DISK_USAGE}% on ${MAX_DISK_USAGE_DISK}"
    (( POOL_USAGE_PERCENT >= 0 )) && html_row "Pool utilization" "${POOL_USAGE_PERCENT}% — $(format_kib "$POOL_FREE_KB") free"
    html_row "Capacity health source" "$CAPACITY_HEALTH_SOURCE"
    (( SMART_OVERALL_FP >= 0 )) && html_row "Estimated array FP" "${SMART_OVERALL_FP}% within one year"
    printf '</table></td></tr></table>\n'
    printf '</td><td class="col-right">\n'
    printf '<table role="presentation" class="panel"><tr><td class="panel-head">Scrub coverage</td></tr><tr><td><table class="data">\n'
    html_row "Checked this run" "$([[ $JOBS_DONE == *SCRUB* ]] && printf '%s%% requested' "$SCRUB_PERCENT" || printf 'not run')"
    (( SCRUB_OLDEST_DAYS >= 0 )) && html_row "Oldest block" "${SCRUB_OLDEST_DAYS} days ago"
    (( SCRUB_MEDIAN_DAYS >= 0 )) && html_row "Median block" "${SCRUB_MEDIAN_DAYS} days ago"
    (( SCRUB_NEWEST_DAYS >= 0 )) && html_row "Newest block" "${SCRUB_NEWEST_DAYS} days ago"
    (( UNSCRUBBED_PERCENT >= 0 )) && html_row "Not yet scrubbed" "${UNSCRUBBED_PERCENT}%"
    html_row "Errors detected" "$SCRUB_DATA_ERRORS"
    printf '</table></td></tr></table>\n'
    printf '</td></tr></table></div>\n'

    if ((${#SMART_WARNING_ROWS[@]} > 0 || ${#SMART_INFO_ROWS[@]} > 0 || ${#CAPACITY_WARNING_ROWS[@]} > 0)); then
      printf '<div class="section"><div class="section-title">Drive overview</div><table class="drive-table"><tr><th>Disk</th><th>Device / role</th><th>Temperature</th><th>Utilization</th><th>Finding</th></tr>\n'
      local row disk dev temp err fp serial warning use free severity
      for row in "${SMART_WARNING_ROWS[@]}"; do
        IFS='|' read -r disk dev temp err fp serial warning <<<"$row"
        printf '<tr class="detail-row"><td><strong>%s</strong></td><td>%s</td><td>%s&deg;C</td><td>&mdash;</td><td>%s</td></tr>\n' \
          "$(html_value "$disk")" "$(html_value "$dev")" "$(html_value "$temp")" "$(html_value "$warning")"
      done
      for row in "${SMART_INFO_ROWS[@]}"; do
        IFS='|' read -r disk dev temp err fp serial warning <<<"$row"
        printf '<tr class="detail-row"><td><strong>%s</strong></td><td>%s</td><td>%s&deg;C</td><td>&mdash;</td><td>%s</td></tr>\n' \
          "$(html_value "$disk")" "$(html_value "$dev")" "$(html_value "$temp")" "$(html_value "$warning")"
      done
      for row in "${CAPACITY_WARNING_ROWS[@]}"; do
        IFS='|' read -r disk use free severity <<<"$row"
        printf '<tr class="detail-row"><td><strong>%s</strong></td><td>Data disk</td><td>&mdash;</td><td>%s%%</td><td>%s GB free</td></tr>\n' \
          "$(html_value "$disk")" "$(html_value "$use")" "$(html_value "$free")"
      done
      printf '</table></div>\n'
    fi

    printf '<div class="section"><table role="presentation" class="columns" width="100%%"><tr><td class="col-left">\n'
    printf '<table role="presentation" class="panel"><tr><td class="panel-head">Job results</td></tr><tr><td><table class="data">\n'
    html_row "Jobs" "${JOBS_DONE:-none}"
    html_row "Diff" "$([[ $DIFF_RC -eq 0 ]] && printf 'PASS — no changes' || ([[ $DIFF_RC -eq 2 ]] && printf 'PASS — changes found' || printf 'FAILED rc=%d' "$DIFF_RC"))"
    [[ $JOBS_DONE == *SYNC* ]] && html_row "Sync" "$([[ $SYNC_RC -eq 0 ]] && printf PASS || printf 'FAILED rc=%d' "$SYNC_RC")"
    [[ $JOBS_DONE == *SCRUB* ]] && html_row "Scrub" "$([[ $SCRUB_RC -eq 0 ]] && printf PASS || printf 'FAILED rc=%d' "$SCRUB_RC")"
    (( SMART_LOG == 1 )) && html_row "SMART collection" "$([[ $SMART_RC -eq 0 ]] && printf PASS || printf 'FAILED rc=%d' "$SMART_RC")"
    printf '</table></td></tr></table>\n'
    printf '</td><td class="col-right">\n'
    printf '<table role="presentation" class="panel"><tr><td class="panel-head">Report details</td></tr><tr><td><table class="data">\n'
    html_row "Config" "$SNAPRAID_CONF"
    html_row "Config ID" "$CONFIG_ID"
    html_row "Finished" "$(date)"
    html_row "Full log" "$FULL_LOG_FILE"
    printf '</table></td></tr></table>\n'
    printf '</td></tr></table></div>\n'

    case "$REPORT_DETAIL_EFFECTIVE" in
      changes) append_change_details_html ;;
      diagnostic) append_change_details_html; append_diagnostic_excerpt_html ;;
      full)
        printf '<div class="section"><div class="section-title">Full command log</div><pre>'
        sed -E '/^__SNAPRAID_[A-Z0-9_]+_(BEGIN|END)__/d; /^###[A-Z0-9_]+ \[/d' "$TMP_OUTPUT" | html_escape
        printf '</pre></div>\n'
        ;;
    esac

    printf '</td></tr>\n'
    printf '<tr><td class="footer" bgcolor="#ffffff"><table role="presentation" class="footer-table"><tr><td>Generated by %s %s</td><td class="footer-right">Full diagnostic log retained on the server</td></tr></table></td></tr>\n' "$(html_value "$PROGRAM_NAME")" "$(html_value "$VERSION")"
    printf '</table></td></tr></table></body></html>\n'
  } >"$tmp"

  mv -f -- "$tmp" "$EMAIL_OUTPUT"
}

beautify_email_output() {
  case "${EMAIL_FORMAT,,}" in
    html) beautify_email_output_html ;;
    text) beautify_email_output_text ;;
    *)
      log "WARNING: Unknown EMAIL_FORMAT=${EMAIL_FORMAT}; falling back to text."
      beautify_email_output_text
      ;;
  esac
}

send_mail() {
  (( NO_EMAIL == 0 )) || return 0
  [[ -n "${EMAIL_ADDRESS:-}" ]] || return 0

  if [[ "${EMAIL_FORMAT,,}" == "html" ]]; then
    # Tell mutt to send the generated dashboard as HTML. Table layout is used
    # instead of spaces, so labels and values align in proportional-font clients.
    "$MAIL_BIN" -e 'set content_type=text/html' -s "$SUBJECT" -- "$EMAIL_ADDRESS" <"$EMAIL_OUTPUT"
  else
    "$MAIL_BIN" -s "$SUBJECT" -- "$EMAIL_ADDRESS" <"$EMAIL_OUTPUT"
  fi
}

###############################################################################
# WORKER EXECUTION FOR ONE CONFIG
###############################################################################

worker_run() {
  local final_rc=0

  if [[ -n "$PROFILE_FILE" ]]; then
    load_profile "$PROFILE_FILE"
  fi

  if [[ -n "$WORKER_CONFIG" ]]; then
    SNAPRAID_CONF=$WORKER_CONFIG
  fi

  [[ -n "${SNAPRAID_CONF:-}" ]] || die "Worker requires SNAPRAID_CONF"

  (( NO_SERVICES == 0 )) || MANAGE_SERVICES=0
  (( NO_EMAIL == 0 )) || EMAIL_ADDRESS=""

  require_common_bins
  require_worker_bins
  initialize_config_identity
  initialize_directories
  acquire_array_lock
  hc_init

  TMP_OUTPUT=$(mktemp -t snapraid.out.XXXXXX)
  EMAIL_OUTPUT=$(mktemp -t snapraid.email.XXXXXX)
  : >"$TMP_OUTPUT"
  : >"$EMAIL_OUTPUT"

  export PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:${PATH:-}"
  export LC_ALL="${LC_ALL:-C.UTF-8}"

  hc_start

  log "SnapRAID worker started: $(date)"
  log "Config: $SNAPRAID_CONF"
  log "Config ID: $CONFIG_ID"

  section "##Preprocessing"

  # Worker service management is used for a single-config direct worker run.
  # Multi-config orchestrator runs pass --no-services and manage them globally.
  if (( MANAGE_SERVICES == 1 )); then
    if ! service_pause; then
      die "One or more required services could not be paused"
    fi
  fi

  validate_capacity_configuration
  validate_required_mounts
  snapraid_preflight
  append_job STATUS

  if ! chk_zero_timestamps; then
    final_rc=1
    warn "Zero-timestamp remediation failed; risky downstream jobs will be skipped."
  fi

  section "##Processing"

  mark_begin DIFF
  {
    printf '###DIFF [%s]\n' "$(date)"
    snapraid_cmd diff
  } 2>&1 | tee -a "$TMP_OUTPUT"
  DIFF_RC=${PIPESTATUS[0]}
  mark_end DIFF "$DIFF_RC"
  append_job DIFF

  if ! is_snapraid_diff_ok "$DIFF_RC"; then
    HAD_FAILURE=1
    warn "DIFF failed with rc=${DIFF_RC}"
    final_rc=1
    (( FAIL_FAST == 1 )) && warn "FAIL_FAST=1: downstream sync/scrub work will be skipped."
  fi

  if ! get_counts; then
    HAD_FAILURE=1
    warn "Unable to parse required change counts from SnapRAID diff output"
    final_rc=1
  else
    log "Change summary: added=$ADD_COUNT removed=$DEL_COUNT updated=$UPDATE_COUNT moved=$MOVE_COUNT copied=$COPY_COUNT restored=$RESTORED_COUNT"
  fi

  if (( final_rc == 0 )); then
    if (( DEL_COUNT + ADD_COUNT + MOVE_COUNT + COPY_COUNT + UPDATE_COUNT > 0 )); then
      evaluate_thresholds
    else
      log "No changes detected; sync is not required."
      DO_SYNC=0
      CHK_FAIL=0
      # A clean no-change run resets consecutive warning state.
      clear_warning_count
    fi
  fi

  if (( final_rc == 0 && DO_SYNC == 1 )); then
    if run_cmd SYNC snapraid_cmd sync -q; then
      SYNC_RC=0
      append_job SYNC
      # Clear only after a genuinely successful sync.
      clear_warning_count
    else
      SYNC_RC=$?
      final_rc=1
      (( FAIL_FAST == 1 )) || true
    fi
  fi

  if (( SCRUB_PERCENT > 0 && final_rc == 0 )); then
    if (( CHK_FAIL == 1 && DO_SYNC == 0 )); then
      log "Scrub skipped because parity is intentionally left out of sync."
    elif (( DO_SYNC == 1 && SYNC_RC != 0 )); then
      warn "Scrub skipped because sync returned rc=${SYNC_RC}."
    elif (( DO_SYNC == 1 )) && ! marker_end_present SYNC; then
      warn "Scrub skipped because the sync completion marker is missing."
    else
      if run_cmd SCRUB snapraid_cmd scrub -p "$SCRUB_PERCENT" -o "$SCRUB_AGE" -q; then
        SCRUB_RC=0
        append_job SCRUB
      else
        SCRUB_RC=$?
        final_rc=1
      fi
    fi
  elif (( SCRUB_PERCENT == 0 )); then
    log "Scrub disabled (SCRUB_PERCENT=0)."
  fi

  # Capture a final status snapshot after any successful sync/scrub so the
  # health dashboard reflects the post-maintenance state rather than only the
  # initial preflight state. A failure here is reported, but does not erase the
  # results of jobs that already completed.
  if (( final_rc == 0 )); then
    if run_cmd FINAL_STATUS snapraid_cmd status; then
      :
    else
      warn "Final status snapshot failed; health summary may be incomplete."
      final_rc=1
    fi
  fi

  section "##Postprocessing"

  if (( SMART_LOG == 1 )); then
    if run_cmd SMART snapraid_cmd smart; then
      SMART_RC=0
      append_job SMART
    else
      SMART_RC=$?
      final_rc=1
    fi
  fi

  if (( SPINDOWN_DISKS == 1 )); then
    if run_cmd DOWN snapraid_cmd down; then
      DOWN_RC=0
      append_job DOWN
    else
      DOWN_RC=$?
      final_rc=1
    fi
  else
    log "Spindown disabled (SPINDOWN_DISKS=0)."
  fi

  if ! restore_services; then
    final_rc=1
  fi

  (( HAD_FAILURE == 0 )) || final_rc=1
  if (( final_rc == 0 && CHK_FAIL == 1 && DO_SYNC == 0 )); then
    final_rc=2
  fi

  persist_full_log
  prune_old_logs
  evaluate_health
  prepare_mail_subject
  beautify_email_output

  if ! send_mail; then
    warn "Failed to send email to $EMAIL_ADDRESS"
    HAD_FAILURE=1
    final_rc=1
    prepare_mail_subject
  fi

  if (( final_rc != 0 )); then
    hc_finish_fail "$final_rc"
  elif (( HEALTH_WARNINGS_FAIL_HEALTHCHECK == 1 && HEALTH_LEVEL >= 2 )); then
    # The automation succeeded, but the array needs attention. Keep the process
    # exit code at 0 while making the health condition visible in monitoring.
    hc_finish_fail 2
  else
    hc_finish_success
  fi

  log "SnapRAID worker finished with rc=${final_rc}: $(date)"
  return "$final_rc"
}

###############################################################################
# ORCHESTRATOR FOR MULTIPLE CONFIGS
###############################################################################

# Build a worker command while preserving invocation-level flags.
build_worker_command() {
  local config=$1 profile=${2:-}
  local -n _out=$3

  _out=("$0" --worker)
  [[ -n "$config" ]] && _out+=(--worker-config "$config")
  [[ -n "$profile" ]] && _out+=(--worker-profile "$profile")
  (( NO_EMAIL == 1 )) && _out+=(--no-email)
  # The orchestrator owns shared service management.
  _out+=(--no-services)
  (( VERBOSE == 1 )) && _out+=(--verbose)
}

# Source profiles temporarily to collect their service lists. This lets a
# multi-profile run pause the union of all configured services exactly once.
collect_orchestrator_services() {
  local original_services=("${SERVICES[@]}")
  local profile service
  local -A seen=()
  local combined=()

  for service in "${original_services[@]}"; do
    [[ -n "$service" && -z "${seen[$service]:-}" ]] || continue
    seen[$service]=1
    combined+=("$service")
  done

  for profile in "${PROFILES[@]}"; do
    # Run in a subshell so profile settings cannot alter orchestrator globals.
    while IFS= read -r service; do
      [[ -n "$service" && -z "${seen[$service]:-}" ]] || continue
      seen[$service]=1
      combined+=("$service")
    done < <(
      PROFILE_TO_READ=$profile bash -c '
        set -u
        SERVICES=()
        # shellcheck disable=SC1090
        source "$PROFILE_TO_READ"
        printf "%s\n" "${SERVICES[@]}"
      '
    )
  done

  SERVICES=("${combined[@]}")
}

orchestrator_run() {
  local rc=0 child_rc=0
  local -a cmd
  local config profile

  require_common_bins

  (( RUN_ALL == 0 )) || discover_all_configs

  if ((${#CONFIGS[@]} == 0 && ${#PROFILES[@]} == 0)); then
    CONFIGS=("/etc/snapraid.conf")
  fi

  if (( DRY_RUN == 1 )); then
    log "Selected SnapRAID configs:"
    printf '  %s\n' "${CONFIGS[@]}"
    if ((${#PROFILES[@]} > 0)); then
      log "Selected profiles:"
      printf '  %s\n' "${PROFILES[@]}"
    fi
    return 0
  fi

  # When profiles are used, adopt the first profile's host-level tool paths
  # (notably DOCKER_BIN and LOCK_DIR) for orchestration. Per-array workers still
  # load their own profiles in isolated processes.
  if ((${#PROFILES[@]} > 0)); then
    load_profile "${PROFILES[0]}"
  fi

  mkdir -p -- "$LOCK_DIR" || die "Unable to create lock directory"
  acquire_global_lock

  # Shared service management is meaningful only in the parent. Workers receive
  # --no-services, preventing one array from restoring services under another.
  if (( NO_SERVICES == 0 && MANAGE_SERVICES == 1 )); then
    [[ -x "$DOCKER_BIN" ]] || die "Docker binary not executable: $DOCKER_BIN"
    collect_orchestrator_services

    TMP_OUTPUT=$(mktemp -t snapraid.orchestrator.XXXXXX)
    : >"$TMP_OUTPUT"

    if ! service_pause; then
      die "One or more shared services could not be paused; no arrays were run"
    fi
  fi

  for config in "${CONFIGS[@]}"; do
    build_worker_command "$config" "" cmd
    log "Running config: $config"
    if "${cmd[@]}"; then
      child_rc=0
    else
      child_rc=$?
      warn "Worker failed or was blocked for $config (rc=$child_rc)"
      if (( rc == 0 || child_rc == 1 )); then
        rc=$child_rc
      fi
    fi
  done

  for profile in "${PROFILES[@]}"; do
    build_worker_command "" "$profile" cmd
    log "Running profile: $profile"
    if "${cmd[@]}"; then
      child_rc=0
    else
      child_rc=$?
      warn "Worker failed or was blocked for $profile (rc=$child_rc)"
      if (( rc == 0 || child_rc == 1 )); then
        rc=$child_rc
      fi
    fi
  done

  if ! restore_services; then
    rc=1
  fi

  return "$rc"
}

###############################################################################
# ENTRYPOINT
###############################################################################

main() {
  parse_args "$@"

  if [[ "$MODE" == "worker" ]]; then
    worker_run
  else
    orchestrator_run
  fi
}

main "$@"
exit $?
