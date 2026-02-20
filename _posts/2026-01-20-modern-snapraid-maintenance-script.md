---
layout: post
title: "A Modern, Updated SnapRAID Maintenance Script"
date: 2026-01-20
categories: [homelab, snapraid, storage, linux]
tags: [snapraid, split parity, docker, monitoring, bash]
image: /wp-content/uploads/images/snapraid_script_revised.webp
---

For the last few years, I’ve been running SnapRAID with an older version of my sync script. I've been slowly overhauling it to cover edge cases and to make it work better with modern BASH. That setup has worked extremely well, but the maintenance script I originally wrote grew organically over time. 

This post introduces a **fully modernized replacement** for that script.

The goal wasn’t to add features for the sake of it. The goal was to continue to make SnapRAID maintenance:
- Safer
- More observable
- Easier to debug
- Explicit about what happened during a run

If you’re already using my older Split Parity script, this is a **drop-in conceptual replacement** with much stronger guardrails for things like content/parity file naming.

---

## What This Script Handles

This script is designed for real-world SnapRAID use.

It supports:

- Split parity (multiple `.parity` files per parity level)
- Multiple `content` files
- Docker-based media services (sabnzbd, sonarr, radarr, lidarr, etc.)
- Email reporting with optional diff summarization
- Healthchecks.io-compatible monitoring
- Threshold-based sync authorization
- Automatic handling of zero sub-second timestamps (`snapraid touch`)
- Optional scrub, SMART reporting, and disk spindown

Every SnapRAID action is wrapped with **explicit BEGIN/END markers**, exit codes are captured correctly, and failures are handled intentionally instead of implicitly.

---

## What’s New Compared to the Old Script

If you’ve used my previous Split Parity script, the biggest improvements are:

### 1. Robust Job Markers
Each SnapRAID command is wrapped like this:

```bash
SNAPRAID_DIFF_BEGIN
...
SNAPRAID_DIFF_END rc=2
```

This makes parsing, alerting, and debugging dramatically easier.

---

### 2. Correct Handling of `snapraid diff`
SnapRAID returns `rc=2` when differences are found. That is **not an error**.

This script treats:
- `rc=0` → no differences
- `rc=2` → differences found (normal)
- anything else → failure

---

### 3. Docker-Aware Service Control
Docker services are only paused if:
- the container exists
- the container is actually running

Only containers that were successfully paused are later unpaused. No more false warnings.

---

### 4. Email Output That’s Actually Readable
The full log is always saved to disk into /var/log/snapraid/ 

The **email version** can optionally:
- Summarize massive diff lists
- Keep the first and last N file changes
- Include a breakdown of adds/removes/updates
- Point back to the full log file

---

### 5. Healthchecks Integration
If you use Healthchecks (or a compatible endpoint), the script can send:

- `/start` when the job begins
- success ping on clean completion
- failure ping (with exit code) on warning or error

## Required Packages

At minimum, you’ll need:

```bash
snapraid
docker
awk
sed
grep
mutt
```

## Email Sending
This script uses mutt for sending mail. You’ll also need a system mail transport.

Common options:
- ssmtp (deprecated but still widely used)
- msmtp (recommended replacement)

**If you already have working local mail, nothing else is required.**

## Healthchecks (Optional)
If you enable Healthchecks support, you’ll also need one of:
- curl (preferred)
- wget

## Configuration Philosophy
All user-tunable options live at the top of the script.

Things like:
- Thresholds
- Scrub percentage
- Docker services
- Email address
- Healthchecks endpoint
- Whether disks are spun down

Nothing under that section needs to be edited.

## The Script
Below is the complete, current version of the script as described in this post.

⚠️ This is long by design. The verbosity is intentional. Hopefully, with the comments, you'll be able to follow what it's doing.

{% raw %}
```bash
#!/usr/bin/env bash

#######################################################################
# SnapRAID helper script:
#   1) Optionally pauses configured Docker services
#   2) Runs snapraid diff
#   3) If del/updated thresholds exceeded -> warn + optionally force sync after N warnings
#   4) If authorized -> runs snapraid sync
#   5) If in-sync (or sync completed) -> runs snapraid scrub (partial, configurable)
#   6) Optionally runs snapraid smart + snapraid down
#   7) Restores services and emails output (if configured)
#
# Modernized with:
#   - Robust BEGIN/END markers for each SnapRAID job
#   - Exit-code capture + warning/failure reporting
#   - Optional DIFF list summarization for email (full untrimmed log still preserved)
#   - Optional Healthchecks ping integration (/start, success, /<exitcode>)
#######################################################################

#######################
# USER CONFIGURATION  #
#######################

EMAIL_ADDRESS="youruser@gmail.com"

# Set the threshold of deleted files to stop the sync job from running.
DEL_THRESHOLD=100
UP_THRESHOLD=500

#  0  -> always force a sync (ignore thresholds)
# -1  -> never force a sync (manual intervention required if thresholds exceeded)
#  N  -> force a sync after N warnings
SYNC_WARN_THRESHOLD=-1

# Set percentage of array to scrub if it is in sync.
# 0 disables scrub. 100 scrubs the full array in one run (can take a long time).
SCRUB_PERCENT=3
SCRUB_AGE=10

# Spindown disks after jobs complete.
# 1 = run `snapraid down` (spins down array disks)
# 0 = skip spindown (useful if you have other jobs running, or want disks warm)
SPINDOWN_DISKS=0

# Log SMART info.
SMART_LOG=1

SNAPRAID_BIN="/usr/local/bin/snapraid"
MAIL_BIN="/usr/bin/mutt"
DOCKER_BIN="/usr/bin/docker"

SNAPRAID_CONF="/etc/snapraid.conf"

# Docker services control (pause containers by name).
MANAGE_SERVICES=1
SERVICES=(sabnzbd sonarr radarr lidarr)
PAUSED_SERVICES=()

# Where to keep the warning counter (persistent across runs)
SYNC_WARN_FILE="/tmp/snapRAID.warnCount"

# Optional: prevent overlapping runs (recommended for cron)
LOCK_FILE="/tmp/snapraid-sync.lock"

# Exit-code policy:
# 0 = continue on failures (but warn and block downstream risky steps)
# 1 = fail fast (exit on first non-zero exit code from snapraid, except diff rc=2)
FAIL_FAST=1

# Summarize the verbose `snapraid diff` file list in the emailed report.
# Full untrimmed log is always saved to disk.
SUMMARIZE_DIFF_EMAIL=1  # This trims the huge per-file add/remove list in the EMAIL ONLY, while saving the full log to disk.

# When summarizing DIFF list: keep first N and last N file-change lines (add/remove/...)
DIFF_LIST_HEAD=20
DIFF_LIST_TAIL=20

# Where to store full logs persistently (email will include the path)
LOG_DIR="/var/log/snapraid"

# Healthchecks integration (optional)
HEALTHCHECKS_ALERTS=1
HEALTHCHECKS_ID="588220cd-28b1-40dc-6524-6e28a0g1d1a3"
HEALTHCHECKS_URL="https://healthchecks.yourdomain.com/ping/"

HC_TIMEOUT_SECS=10
HC_RETRIES=3

############################
# DO NOT EDIT BELOW THIS   #
############################

set -u
set -o pipefail
shopt -s lastpipe 2>/dev/null || true

SECONDS=0

TMP_OUTPUT=""
EMAIL_OUTPUT=""
FULL_LOG_FILE=""

EMAIL_SUBJECT_PREFIX=""
GRACEFUL=0

CHK_FAIL=0
DO_SYNC=0
JOBS_DONE=""

DEL_COUNT=""
ADD_COUNT=""
MOVE_COUNT=""
COPY_COUNT=""
UPDATE_COUNT=""
RESTORED_COUNT=""

SYNC_WARN_COUNT=""

DIFF_RC=0
SYNC_RC=0
SCRUB_RC=0
SMART_RC=0
DOWN_RC=0
TOUCH_RC=0
SERVICE_RC=0
HAD_FAILURE=0
SERVICES_PAUSED_COUNT=0
SERVICES_RESTORED_COUNT=0
SERVICES_FAILED_PAUSE=0
SERVICES_FAILED_RESTORE=0

# Healthchecks
HC_ENABLED=0
HC_TOOL=""   # curl|wget
HC_SENT_START=0

#######################################################################
# HELPER FUNCTIONS
#######################################################################

# Simple logging wrapper
log() { 
  printf '%s\n' "$*"
}

# Fatal error - exit immediately
die() {
  log "**ERROR** $*"
  exit 1
}

# Check if a command exists
have_cmd() { 
  command -v "$1" >/dev/null 2>&1
}

# Format duration in seconds to human-readable format
format_duration() {
  local total_seconds=$1
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

# Verify all required binaries are present and executable
require_bins() {
  [[ -x "$SNAPRAID_BIN" ]] || die "snapraid binary not found/executable at: $SNAPRAID_BIN"
  [[ -f "$SNAPRAID_CONF" ]] || die "snapraid config not found at: $SNAPRAID_CONF"

  if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
    [[ -x "$MAIL_BIN" ]] || die "mail binary not found/executable at: $MAIL_BIN"
  fi

  if (( MANAGE_SERVICES == 1 )); then
    [[ -x "$DOCKER_BIN" ]] || die "docker binary not found/executable at: $DOCKER_BIN"
  fi

  for b in awk sed grep hostname date tee mkdir mktemp; do
    have_cmd "$b" || die "$b not found"
  done
}

# Print a section header for better log readability
section() {
  log
  log "----------------------------------------"
  log "$1"
}

#######################################################################
# HEALTHCHECKS INTEGRATION
#######################################################################

# Initialize healthchecks - determine if enabled and which tool to use
hc_init() {
  if (( HEALTHCHECKS_ALERTS != 1 )); then
    HC_ENABLED=0
    return 0
  fi

  if [[ -z "${HEALTHCHECKS_ID:-}" || -z "${HEALTHCHECKS_URL:-}" ]]; then
    log "WARNING: HEALTHCHECKS_ALERTS=1 but HEALTHCHECKS_ID/HEALTHCHECKS_URL not set. Disabling."
    HC_ENABLED=0
    return 0
  fi

  if have_cmd curl; then
    HC_TOOL="curl"
    HC_ENABLED=1
  elif have_cmd wget; then
    HC_TOOL="wget"
    HC_ENABLED=1
  else
    log "WARNING: Healthchecks enabled but neither curl nor wget found. Disabling."
    HC_ENABLED=0
  fi
}

# Build the healthchecks ping URL with optional suffix
hc_ping_url() {
  local suffix="${1:-}"
  local base="${HEALTHCHECKS_URL%/}/"
  local url="${base}${HEALTHCHECKS_ID}"
  [[ -n "$suffix" ]] && url="${url}/${suffix}"
  printf '%s' "$url"
}

# Send a ping to healthchecks (monitoring must never block maintenance)
hc_send() {
  (( HC_ENABLED == 1 )) || return 0

  local suffix="${1:-}"
  local body="${2:-}"
  local url
  url="$(hc_ping_url "$suffix")"

  local result=0
  
  # Use curl if available, otherwise wget
  if [[ "$HC_TOOL" == "curl" ]]; then
    if [[ -n "$body" ]]; then
      curl -fsS --max-time "$HC_TIMEOUT_SECS" --retry "$HC_RETRIES" \
        --retry-delay 1 --retry-all-errors \
        -X POST --data-raw "$body" "$url" >/dev/null 2>&1 || result=$?
    else
      curl -fsS --max-time "$HC_TIMEOUT_SECS" --retry "$HC_RETRIES" \
        --retry-delay 1 --retry-all-errors \
        "$url" >/dev/null 2>&1 || result=$?
    fi
  else
    if [[ -n "$body" ]]; then
      printf '%s' "$body" | wget -qO- --timeout="$HC_TIMEOUT_SECS" --tries="$HC_RETRIES" \
        --method=POST --body-file=- "$url" >/dev/null 2>&1 || result=$?
    else
      wget -qO- --timeout="$HC_TIMEOUT_SECS" --tries="$HC_RETRIES" "$url" >/dev/null 2>&1 || result=$?
    fi
  fi
  
  # Log ping failures for debugging (non-fatal)
  if (( result != 0 )); then
    log "DEBUG: Healthcheck ping failed (non-fatal): $url" >&2
  fi
  
  return 0
}

# Signal job start to healthchecks
hc_start() {
  (( HC_ENABLED == 1 )) || return 0
  hc_send "start" "SnapRAID job started on $(hostname) at $(date)"
  HC_SENT_START=1
}

# Signal successful completion to healthchecks
hc_finish_success() {
  (( HC_ENABLED == 1 )) || return 0
  hc_send "" "SnapRAID job success on $(hostname) at $(date). Jobs: ${JOBS_DONE}"
}

# Signal failure to healthchecks with exit code
hc_finish_fail() {
  (( HC_ENABLED == 1 )) || return 0
  local code="${1:-1}"
  (( code >= 1 && code <= 255 )) || code=1
  hc_send "$code" "SnapRAID job WARNING/FAIL on $(hostname) at $(date). Subject: ${SUBJECT:-"(no subject)"}"
}

#######################################################################
# ROBUST JOB MARKERS AND COMMAND RUNNER
#######################################################################

# Mark the beginning of a SnapRAID job in the log
mark_begin() {
  local name="$1"
  echo "__SNAPRAID_${name}_BEGIN__ [$(date)]" | tee -a "$TMP_OUTPUT" >/dev/null
}

# Mark the end of a SnapRAID job with its exit code
mark_end() {
  local name="$1"
  local rc="$2"
  {
    echo "__SNAPRAID_${name}_END__ [$(date)] rc=${rc}"
    echo
  } | tee -a "$TMP_OUTPUT" >/dev/null
}

# Check if a job completed (has an END marker)
marker_end_present() {
  local name="$1"
  grep -q "__SNAPRAID_${name}_END__" "$TMP_OUTPUT"
}

# snapraid diff: rc=2 means "differences found" (normal, not an error)
is_snapraid_diff_ok() {
  local rc="$1"
  [[ "$rc" -eq 0 || "$rc" -eq 2 ]]
}

# Run a command with robust logging and error handling
run_cmd() {
  local name="$1"; shift

  mark_begin "$name"
  {
    echo "###${name} [$(date)]"
    "$@"
  } 2>&1 | tee -a "$TMP_OUTPUT"

  local rc=${PIPESTATUS[0]}
  mark_end "$name" "$rc"

  if (( rc != 0 )); then
    HAD_FAILURE=1
    log "**WARNING** ${name} returned non-zero exit code: ${rc}"
    if (( FAIL_FAST == 1 )); then
      die "${name} failed with rc=${rc} (FAIL_FAST=1)"
    fi
  fi

  return "$rc"
}

#######################################################################
# DOCKER SERVICE MANAGEMENT
#######################################################################

# Pause configured Docker services to prevent file changes during sync
service_pause() {
  local s running
  for s in "${SERVICES[@]}"; do
    running="$("$DOCKER_BIN" inspect -f '{{.State.Running}}' "$s" 2>/dev/null || true)"

    if [[ "$running" == "true" ]]; then
      echo "Pausing Service - ${s}" | tee -a "$TMP_OUTPUT"
      if "$DOCKER_BIN" pause "$s" >/dev/null 2>&1; then
        PAUSED_SERVICES+=("$s")
        ((SERVICES_PAUSED_COUNT++))
      else
        echo "WARNING: failed to pause $s" | tee -a "$TMP_OUTPUT"
        ((SERVICES_FAILED_PAUSE++))
        SERVICE_RC=1
        HAD_FAILURE=1
      fi
    elif [[ "$running" == "false" ]]; then
      echo "Service not running (skip pause) - ${s}" | tee -a "$TMP_OUTPUT"
    else
      echo "Service not found (skip pause) - ${s}" | tee -a "$TMP_OUTPUT"
    fi
  done
}

# Unpause previously paused Docker services
service_unpause() {
  local s st
  for s in "${PAUSED_SERVICES[@]}"; do
    st="$("$DOCKER_BIN" inspect -f '{{.State.Status}}' "$s" 2>/dev/null || true)"
    if [[ "$st" == "paused" ]]; then
      echo "Unpausing Service - ${s}" | tee -a "$TMP_OUTPUT"
      if "$DOCKER_BIN" unpause "$s" >/dev/null 2>&1; then
        ((SERVICES_RESTORED_COUNT++))
      else
        echo "WARNING: failed to unpause $s" | tee -a "$TMP_OUTPUT"
        ((SERVICES_FAILED_RESTORE++))
        SERVICE_RC=1
        HAD_FAILURE=1
      fi
    else
      echo "Service not paused (skip unpause) - ${s} (status: $st)" | tee -a "$TMP_OUTPUT"
    fi
  done
}

# Restore all paused services
restore_services() {
  (( MANAGE_SERVICES == 1 )) || return 0

  if [[ ${#PAUSED_SERVICES[@]} -eq 0 ]]; then
    log "No services to restore."
    return 0
  fi

  service_unpause
  return 0
}

# Cleanup function - runs on script exit (normal or interrupted)
cleanup() {
  local exit_code=$?
  
  # Always try to restore services
  restore_services || {
    log "WARNING: Failed to restore services during cleanup" >&2
    # Don't overwrite a non-zero exit code with service restoration failure
    (( exit_code == 0 )) && exit_code=1
  }
  
  # Clean up lock file on successful exit
  if (( exit_code == 0 )) && [[ -f "$LOCK_FILE" ]]; then
    rm -f "$LOCK_FILE" 2>/dev/null || true
  fi
  
  exit $exit_code
}

# Register cleanup to run on exit/interrupt
trap cleanup INT TERM EXIT

#######################################################################
# SNAPRAID CONFIG PARSING
#######################################################################

# Parse SnapRAID config to extract content and parity file paths
parse_snapraid_conf() {
  # Extract all content file paths
  mapfile -t CONTENT_FILES < <(
    awk '
      # Skip blank lines and comments
      /^[[:space:]]*($|#|;)/ { next }
      
      # Match "content" keyword (standard SnapRAID format)
      $1 == "content" && $2 != "" { 
        print $2 
      }
    ' "$SNAPRAID_CONF"
  )
  
  ((${#CONTENT_FILES[@]} > 0)) || die "Could not determine content files from $SNAPRAID_CONF"
  
  # Use the first content file as primary
  CONTENT_FILE="${CONTENT_FILES[0]}"

  # Extract all parity file paths (handles comma-separated values)
  mapfile -t PARITY_FILES < <(
    awk '
      function trim(s) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        return s
      }
      
      # Skip blank lines and comments
      /^[[:space:]]*($|#|;)/ { next }
      
      # Match parity keywords: parity, 2-parity, 3-parity, ..., z-parity
      $1 == "parity" || $1 ~ /^([2-6]|z)-parity$/ {
        if ($2 == "") next
        
        # Handle comma-separated paths in $2
        n = split($2, a, ",")
        for (i = 1; i <= n; i++) {
          path = trim(a[i])
          if (path != "") print path
        }
      }
    ' "$SNAPRAID_CONF"
  )
  
  ((${#PARITY_FILES[@]} > 0)) || die "Could not determine parity files from $SNAPRAID_CONF"
}

# Verify that all content and parity files exist
sanity_check() {
  local cf pf
  
  log "Verifying all content files are present."
  for cf in "${CONTENT_FILES[@]}"; do
    [[ -e "$cf" ]] || die "Content file not found: $cf"
  done

  log "Verifying all parity files are present."
  for pf in "${PARITY_FILES[@]}"; do
    [[ -e "$pf" ]] || die "Parity file not found: $pf"
  done
  
  log "All content and parity files found. Continuing..."
}

#######################################################################
# SNAPRAID DIFF ANALYSIS
#######################################################################

# Extract change counts from snapraid diff output
# Updated format (as of recent SnapRAID versions):
#   "      50 added"
#   "       9 removed"
#   "       0 updated"
get_counts() {
  # Extract only the DIFF section from the log
  # Note: Using "in_block" to avoid confusion with awk's `in` operator
  local diff_block
  diff_block="$(
    awk '
      /__SNAPRAID_DIFF_BEGIN__/ { in_block=1; next }
      /__SNAPRAID_DIFF_END__/   { in_block=0 }
      in_block { print }
    ' "$TMP_OUTPUT"
  )"

  # Fallback to full output if DIFF block not found
  [[ -n "$diff_block" ]] || diff_block="$(cat "$TMP_OUTPUT")"

  # Parse the summary lines from snapraid diff output
  ADD_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+added$/       {print $1; exit}' <<<"$diff_block" || true)"
  DEL_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+removed$/     {print $1; exit}' <<<"$diff_block" || true)"
  UPDATE_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+updated$/  {print $1; exit}' <<<"$diff_block" || true)"
  MOVE_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+moved$/      {print $1; exit}' <<<"$diff_block" || true)"
  COPY_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+copied$/     {print $1; exit}' <<<"$diff_block" || true)"
  RESTORED_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+restored$/ {print $1; exit}' <<<"$diff_block" || true)"
  
  # Ensure restored count defaults to 0 if not found
  RESTORED_COUNT="${RESTORED_COUNT:-0}"
}

# Check if deleted files are below threshold
chk_del() {
  if [[ -n "$DEL_COUNT" ]] && (( DEL_COUNT < DEL_THRESHOLD )); then
    log "Deleted files ($DEL_COUNT) below threshold ($DEL_THRESHOLD). SYNC authorized."
    DO_SYNC=1
  else
    log "**WARNING** Deleted files ($DEL_COUNT) exceeded threshold ($DEL_THRESHOLD)."
    CHK_FAIL=1
  fi
}

# Check if updated files are below threshold
chk_updated() {
  if (( UPDATE_COUNT < UP_THRESHOLD )); then
    log "Updated files ($UPDATE_COUNT) below threshold ($UP_THRESHOLD). SYNC authorized."
    DO_SYNC=1
  else
    log "**WARNING** Updated files ($UPDATE_COUNT) exceeded threshold ($UP_THRESHOLD)."
    CHK_FAIL=1
  fi
}

# Handle forced sync after N warnings
chk_sync_warn() {
  if (( SYNC_WARN_THRESHOLD > -1 )); then
    log "Forced sync is enabled. [$(date)]"

    # Load warning count from file
    if [[ -f "$SYNC_WARN_FILE" ]]; then
      SYNC_WARN_COUNT="$(awk 'NR==1 && $0 ~ /^[0-9]+$/ {print $0; exit}' "$SYNC_WARN_FILE" || true)"
    else
      SYNC_WARN_COUNT=""
    fi
    SYNC_WARN_COUNT="${SYNC_WARN_COUNT:-0}"

    # Check if we've hit the warning threshold
    if (( SYNC_WARN_COUNT >= SYNC_WARN_THRESHOLD )); then
      log "Warning count ($SYNC_WARN_COUNT) reached/exceeded threshold ($SYNC_WARN_THRESHOLD). Forcing SYNC. [$(date)]"
      DO_SYNC=1
    else
      # Increment warning count
      ((SYNC_WARN_COUNT += 1))
      printf '%s\n' "$SYNC_WARN_COUNT" > "$SYNC_WARN_FILE"
      log "$((SYNC_WARN_THRESHOLD - SYNC_WARN_COUNT)) warning(s) remaining until forced sync. NOT proceeding with SYNC. [$(date)]"
      DO_SYNC=0
    fi
  else
    log "Forced sync is not enabled. Check output for details. NOT proceeding with SYNC. [$(date)]"
    DO_SYNC=0
  fi
}

# Check for and fix files with zero sub-second timestamps
chk_zero() {
  run_cmd "TOUCH_CHECK" "$SNAPRAID_BIN" status
  
  local timelog
  timelog="$(grep -E 'You have [1-9][0-9]* files with zero sub-second timestamp\.' "$TMP_OUTPUT" | tail -n 1 || true)"

  if [[ -n "$timelog" ]]; then
    log "${timelog/You have/Found}"
    run_cmd "TOUCH" "$SNAPRAID_BIN" touch
    TOUCH_RC=$?
    JOBS_DONE="${JOBS_DONE:+$JOBS_DONE + }TOUCH"
  else
    log "No files with zero sub-second timestamps found."
  fi
}

#######################################################################
# EMAIL PREPARATION
#######################################################################

# Build the email subject line based on job results
prepare_mail_subject() {
  local msg=""
  local STATUS_ICON="🟢"
  local STATUS_WORD="COMPLETED"

  # Check for threshold violations (warnings)
  if (( CHK_FAIL == 1 )); then
    STATUS_ICON="🟠"
    STATUS_WORD="WARNING"

    if (( DEL_COUNT >= DEL_THRESHOLD && DO_SYNC == 0 )); then
      msg="Deleted ($DEL_COUNT>=$DEL_THRESHOLD)"
    fi
    if (( DEL_COUNT >= DEL_THRESHOLD && UPDATE_COUNT >= UP_THRESHOLD && DO_SYNC == 0 )); then
      msg="${msg} & "
    fi
    if (( UPDATE_COUNT >= UP_THRESHOLD && DO_SYNC == 0 )); then
      msg="${msg}Updated ($UPDATE_COUNT>=$UP_THRESHOLD)"
    fi

    SUBJECT="${STATUS_ICON} [${STATUS_WORD}] ${msg} ${EMAIL_SUBJECT_PREFIX}"
    return 0
  fi

  # Check for command failures
  if (( HAD_FAILURE == 1 )); then
    STATUS_ICON="🔴"
    STATUS_WORD="FAILED"
    SUBJECT="${STATUS_ICON} [${STATUS_WORD}] ${EMAIL_SUBJECT_PREFIX}"
    return 0
  fi

  # Success case
  SUBJECT="${STATUS_ICON} [${STATUS_WORD}] ${JOBS_DONE} ${EMAIL_SUBJECT_PREFIX}"
}

# Create a summarized email copy of the log (full log preserved separately)
# This intelligently trims the verbose file-change list while preserving context
summarize_diff_for_email() {
  # Start with a copy of the full log
  cp -f "$TMP_OUTPUT" "$EMAIL_OUTPUT"

  # Skip summarization if disabled
  (( SUMMARIZE_DIFF_EMAIL == 1 )) || return 0

  # Use awk to keep only head/tail of file-change lines and add summary
  awk -v head="$DIFF_LIST_HEAD" -v tail="$DIFF_LIST_TAIL" '
    # Helper function to identify file-change action lines
    function is_action(line) { 
      return (line ~ /^(add|remove|update|move|copy|restore)[[:space:]]+/) 
    }
    
    # Extract the action type from a line
    function action_type(line,   a) { 
      split(line, a, /[[:space:]]+/)
      return a[1] 
    }

    BEGIN { 
      in_block=0
      action_count=0
      tail_length=0
      tail_start=1
      
      # Counters for each action type
      add_count=0
      remove_count=0
      update_count=0
      move_count=0
      copy_count=0
      restore_count=0
    }

    # Detect start of DIFF block
    /__SNAPRAID_DIFF_BEGIN__/ { 
      in_block=1
      print
      next 
    }
    
    # Detect end of DIFF block - output tail buffer and summary
    /__SNAPRAID_DIFF_END__/ {
      if (in_block) {
        # If we omitted lines, show how many and breakdown by type
        if (action_count > head + tail) {
          omitted = action_count - (head + tail)
          print ""
          printf "... (%d file-change lines omitted from email; breakdown: add=%d remove=%d update=%d move=%d copy=%d restore=%d; see full log on disk) ...\n",
                 omitted, add_count, remove_count, update_count, move_count, copy_count, restore_count
          print ""
        }
        
        # Output the tail buffer
        for (i=1; i<=tail_length; i++) {
          idx = tail_start + i - 1
          if (idx > tail) idx -= tail
          print tail_buffer[idx]
        }
      }
      in_block=0
      print
      next
    }

    {
      # Pass through non-DIFF content unchanged
      if (!in_block) { 
        print
        next 
      }

      # Handle file-change action lines
      if (is_action($0)) {
        action_count++
        
        # Track action type
        t = action_type($0)
        if (t=="add") add_count++
        else if (t=="remove") remove_count++
        else if (t=="update") update_count++
        else if (t=="move") move_count++
        else if (t=="copy") copy_count++
        else if (t=="restore") restore_count++

        # Print first N lines directly
        if (action_count <= head) { 
          print
          next 
        }

        # Store last N lines in circular buffer
        if (tail > 0) {
          if (tail_length < tail) { 
            tail_length++
            pos=tail_length 
          } else { 
            pos=tail_start
            tail_start++
            if (tail_start > tail) tail_start=1 
          }
          tail_buffer[pos] = $0
        }
        next
      }

      # Pass through all other lines within DIFF block
      print
    }
  ' "$TMP_OUTPUT" > "$EMAIL_OUTPUT".tmp && mv -f "$EMAIL_OUTPUT".tmp "$EMAIL_OUTPUT"
}

# Format the email output for better readability (plain text optimized)
beautify_email_output() {
  local tmp duration_str
  tmp="$(mktemp -t snapraid.pretty.XXXXXX)"

  # Calculate human-readable duration
  local hours minutes seconds
  hours=$((SECONDS / 3600))
  minutes=$(((SECONDS % 3600) / 60))
  seconds=$((SECONDS % 60))

  if (( hours > 0 )); then
    duration_str="${hours}h ${minutes}m ${seconds}s"
  elif (( minutes > 0 )); then
    duration_str="${minutes}m ${seconds}s"
  else
    duration_str="${seconds}s"
  fi

  # Use awk to format the email with headers, sections, and simplified output
  awk -v subject="$SUBJECT" \
      -v host="$(hostname)" \
      -v logfile="$FULL_LOG_FILE" \
      -v duration="$duration_str" \
      -v del_count="${DEL_COUNT:-0}" \
      -v add_count="${ADD_COUNT:-0}" \
      -v update_count="${UPDATE_COUNT:-0}" \
      -v move_count="${MOVE_COUNT:-0}" \
      -v copy_count="${COPY_COUNT:-0}" \
      -v restored_count="${RESTORED_COUNT:-0}" \
      -v del_thresh="${DEL_THRESHOLD}" \
      -v up_thresh="${UP_THRESHOLD}" \
      -v warn_count="${SYNC_WARN_COUNT:-0}" \
      -v warn_thresh="${SYNC_WARN_THRESHOLD}" \
      -v chk_fail="${CHK_FAIL}" \
      -v do_sync="${DO_SYNC}" '
    
    # Helper functions for formatted output
    function hr() { 
      print "============================================================" 
    }
    
    function h1(t) { 
      print ""
      hr()
      print t
      hr()
      print ""
    }
    
    function h2(t) { 
      print ""
      print "=============="
      print t
      print "=============="
      print ""
    }
    
    # ASCII box drawing for critical warnings
    function box_start() { 
      print "╔════════════════════════════════════════════════════════════╗" 
    }
    
    function box_line(t) { 
      printf "║ %-58s ║\n", t 
    }
    
    function box_end() { 
      print "╚════════════════════════════════════════════════════════════╝" 
    }

    BEGIN {
      # Email header with key metadata
      h1(subject)
      print "Host:     " host
      print "Duration: " duration
      if (logfile != "") print "Full log: " logfile
      print "Finished: " strftime("%c")
      print ""

      # Change summary section (keep as-is - it is clean and useful)
      h2("Change Summary")
      printf "  Added:       %6d files\n", add_count
      printf "  Removed:     %6d files\n", del_count
      printf "  Updated:     %6d files\n", update_count
      printf "  Moved:       %6d files\n", move_count
      printf "  Copied:      %6d files\n", copy_count
      printf "  Restored:    %6d files\n", restored_count

      # Critical warning box if thresholds exceeded
      if (chk_fail == 1 && do_sync == 0) {
        print ""
        box_start()
        box_line("⚠  CRITICAL: Manual review needed")
        box_line("")
        if (del_count >= del_thresh) {
          box_line(sprintf("Deleted files: %d (threshold: %d)", del_count, del_thresh))
        }
        if (update_count >= up_thresh) {
          box_line(sprintf("Updated files: %d (threshold: %d)", update_count, up_thresh))
        }
        if (warn_thresh > -1) {
          box_line(sprintf("Warning count: %d/%d (will force sync at %d)", warn_count, warn_thresh, warn_thresh))
        }
        box_end()
      }

      # State tracking for content filtering
      in_status_report = 0
      skip_until_blank = 0
      in_scrub_section = 0
      in_smart_report = 0
      in_wait_chart = 0
      pause_header_shown = 0
      unpause_header_shown = 0
      pause_last_line = 0
      blank_count = 0
      just_had_verified = 0
      
      # Scrub stats tracking
      scrub_last = ""
      scrub_oldest = ""
      scrub_median = ""
      scrub_newest = ""
      scrub_errors = ""
      
      # SMART data tracking
      smart_disk_count = 0
      smart_data_count = 0
      smart_parity_count = 0
      smart_other_count = 0
      smart_high_temp_count = 0
      smart_high_fp_count = 0
      smart_error_count = 0
      smart_max_temp = 0
      smart_overall_fp = ""
      delete smart_warnings
      smart_warning_count = 0
    }

    # REMOVE ALL INTERNAL MARKERS - these should never appear in the email
    /^__SNAPRAID_[A-Z0-9_]+_(BEGIN|END)__/ { 
      next 
    }
    
    # Remove internal job timestamps
    /^###[A-Z0-9_]+ \[/ { 
      next 
    }

    # Group service pause messages into a dedicated section
    /^Pausing Service -/ || /^Service not running.*skip pause/ || /^Service not found.*skip pause/ {
      if (!pause_header_shown) {
        h2("Services Paused")
        pause_header_shown = 1
      }
      print "  " $0
      pause_last_line = NR
      next
    }

    # Group service unpause messages into a dedicated section
    /^Unpausing Service -/ || /^Service not paused.*skip unpause/ {
      if (!unpause_header_shown) {
        h2("Services Restored")
        unpause_header_shown = 1
      }
      print "  " $0
      next
    }
    
    # Add section header after service pause messages when we see "Self test..."
    /^Self test\.\.\./ {
      # If we just finished showing service pause messages, add a section header
      if (pause_header_shown && NR - pause_last_line < 5) {
        h2("DIFF Analysis")
      }
      print
      next
    }

    # FILTER OUT: Entire SnapRAID status report (verbose, not needed in email)
    /^SnapRAID status report:/ {
      in_status_report = 1
      next
    }
    
    # End status report when we hit "The oldest block was scrubbed" line
    in_status_report == 1 && /^The oldest block was scrubbed/ {
      # Extract scrub statistics for simplified summary
      if (match($0, /scrubbed ([0-9]+) days ago, the median ([0-9]+), the newest ([0-9]+)/, arr)) {
        scrub_oldest = arr[1]
        scrub_median = arr[2]
        scrub_newest = arr[3]
      }
      in_status_report = 0
      in_scrub_section = 1
      next
    }
    
    # Skip all lines within the status report
    in_status_report == 1 { 
      next 
    }
    
    # Capture scrub error info if present
    in_scrub_section == 1 && /^No error detected/ {
      scrub_errors = "✓ No errors detected"
      in_scrub_section = 0
      next
    }
    
    in_scrub_section == 1 && /error/ {
      scrub_errors = "⚠ Errors detected - check full log"
      in_scrub_section = 0
      next
    }
    
    # End scrub section after a few lines if no error line found
    in_scrub_section == 1 {
      scrub_line_count++
      if (scrub_line_count > 3) {
        in_scrub_section = 0
        if (scrub_errors == "") scrub_errors = "Status unknown"
      }
      next
    }

    # Detect SCRUB job completion and output simplified summary
    /^Self test completed OK/ || /^Scrubbing completed/ {
      # Only show scrub summary if we have data
      if (scrub_oldest != "" || scrub_errors != "") {
        h2("Scrub Summary")
        if (scrub_oldest != "") {
          print "  Last scrub:   " scrub_oldest " days ago"
          print "  Oldest block: " scrub_oldest " days (median: " scrub_median " days, newest: " scrub_newest " days)"
        }
        if (scrub_errors != "") {
          print "  Status:       " scrub_errors
        }
        print ""
      }
      # Reset for next potential scrub
      scrub_oldest = ""
      scrub_median = ""
      scrub_newest = ""
      scrub_errors = ""
      next
    }

    # FILTER OUT: Wait time charts (not readable in email, not actionable)
    /^[[:space:]]*(d[0-9]+|parity|2-parity|raid|hash|sched|misc)[[:space:]]+[0-9]+%[[:space:]]*\|/ {
      in_wait_chart = 1
      next
    }
    
    # End of wait time chart
    in_wait_chart == 1 && /wait time \(total, less is better\)/ {
      in_wait_chart = 0
      next
    }
    
    in_wait_chart == 1 {
      next
    }

    # Detect start of SMART report and begin parsing
    /^SnapRAID SMART report:/ {
      in_smart_report = 1
      smart_in_header = 1
      next
    }
    
    # Skip SMART header lines
    in_smart_report == 1 && smart_in_header == 1 && /^[[:space:]]*$/ {
      next
    }
    
    in_smart_report == 1 && smart_in_header == 1 && /Temp  Power   Error   FP Size/ {
      next
    }
    
    in_smart_report == 1 && smart_in_header == 1 && /C OnDays   Count        TB  Serial/ {
      next
    }
    
    in_smart_report == 1 && smart_in_header == 1 && /^[[:space:]]*-+[[:space:]]*$/ {
      smart_in_header = 0
      next
    }
    
    # Parse SMART data lines
    in_smart_report == 1 && !smart_in_header && /^[[:space:]]+[0-9-]+[[:space:]]+/ {
      # Extract fields: Temp, Power, Error, FP, Size, Serial, Device, Disk
      temp = $1
      power = $2
      error = $3
      fp = $4
      size = $5
      serial = $6
      device = $7
      disk = $8
      
      smart_disk_count++
      
      # Categorize disk
      if (disk ~ /^d[0-9]+$/) {
        smart_data_count++
      } else if (disk ~ /parity/) {
        smart_parity_count++
      } else {
        smart_other_count++
      }
      
      # Check for warnings
      has_warning = 0
      warning_msg = ""
      
      # High failure probability (>50%)
      if (fp ~ /^[0-9]+%$/) {
        fp_val = fp
        gsub(/%/, "", fp_val)
        if (fp_val + 0 > 50) {
          smart_high_fp_count++
          has_warning = 1
          if (warning_msg != "") warning_msg = warning_msg " | "
          warning_msg = warning_msg "High failure risk (" fp ")"
        }
      }
      
      # High temperature (>40°C)
      if (temp ~ /^[0-9]+$/ && temp + 0 > 40) {
        smart_high_temp_count++
        has_warning = 1
        if (warning_msg != "") warning_msg = warning_msg " | "
        warning_msg = warning_msg "High temp (" temp "°C)"
      }
      
      # Track max temp
      if (temp ~ /^[0-9]+$/ && temp + 0 > smart_max_temp) {
        smart_max_temp = temp
        smart_max_temp_disk = disk
      }
      
      # Errors present
      if (error ~ /^[0-9]+$/ && error + 0 > 0) {
        smart_error_count++
        has_warning = 1
        if (warning_msg != "") warning_msg = warning_msg " | "
        warning_msg = warning_msg error " errors"
      }
      
      # Store warning if present
      if (has_warning) {
        smart_warning_count++
        smart_warnings[smart_warning_count] = sprintf("    • %s (%s) - %s - %s - %s°C", \
          disk, fp, device, serial, temp)
        if (warning_msg != "") {
          smart_warnings[smart_warning_count] = smart_warnings[smart_warning_count] "\n      " warning_msg
        }
      }
      
      next
    }
    
    # Capture overall failure probability
    in_smart_report == 1 && /^Probability that at least one disk/ {
      if (match($0, /is ([0-9]+)%/, arr)) {
        smart_overall_fp = arr[1]
      }
      in_smart_report = 0
      
      # Output SMART summary
      h2("SMART Summary")
      
      printf "  Disks monitored: %d total", smart_disk_count
      if (smart_data_count > 0 || smart_parity_count > 0 || smart_other_count > 0) {
        printf " ("
        parts = 0
        if (smart_data_count > 0) {
          printf "%d data", smart_data_count
          parts++
        }
        if (smart_parity_count > 0) {
          if (parts > 0) printf " + "
          printf "%d parity", smart_parity_count
          parts++
        }
        if (smart_other_count > 0) {
          if (parts > 0) printf " + "
          printf "%d other", smart_other_count
        }
        printf ")"
      }
      print ""
      print ""
      
      # Show warnings or all-clear
      if (smart_warning_count > 0) {
        if (smart_high_fp_count > 0) {
          print "  ⚠ High failure probability:"
          for (i = 1; i <= smart_warning_count; i++) {
            if (smart_warnings[i] ~ /High failure risk/) {
              print smart_warnings[i]
            }
          }
          print ""
        }
        
        if (smart_high_temp_count > 0) {
          print "  ⚠ Temperature warnings (>40°C):"
          for (i = 1; i <= smart_warning_count; i++) {
            if (smart_warnings[i] ~ /High temp/) {
              print smart_warnings[i]
            }
          }
          print ""
        }
        
        if (smart_error_count > 0) {
          print "  ⚠ Disks with errors:"
          for (i = 1; i <= smart_warning_count; i++) {
            if (smart_warnings[i] ~ /errors/) {
              print smart_warnings[i]
            }
          }
          print ""
        }
      } else {
        print "  ✓ All disks healthy"
        print ""
      }
      
      # Always show max temp and overall failure probability
      if (smart_max_temp > 0) {
        printf "  Highest temp: %d°C", smart_max_temp
        if (smart_max_temp_disk != "") {
          printf " (%s)", smart_max_temp_disk
        }
        print ""
      }
      
      if (smart_overall_fp != "") {
        printf "  Overall failure probability: %s%%", smart_overall_fp
        print " (at least one disk in next year)"
      }
      
      print ""
      next
    }
    
    # Skip remaining SMART report lines
    in_smart_report == 1 {
      next
    }

    # Detect job section headers from the log structure
    /^##(Preprocessing|Processing|Postprocessing)/ {
      # Extract the section name
      section = $0
      gsub(/^##/, "", section)
      h2(section)
      next
    }

    # REMOVE: SnapRAID raw summary lines (duplicate of our formatted summary at top)
    /^[[:space:]]*[0-9]+[[:space:]]+equal/ { next }
    /^[[:space:]]*[0-9]+[[:space:]]+added/ { next }
    /^[[:space:]]*[0-9]+[[:space:]]+removed/ { next }
    /^[[:space:]]*[0-9]+[[:space:]]+updated/ { next }
    /^[[:space:]]*[0-9]+[[:space:]]+moved/ { next }
    /^[[:space:]]*[0-9]+[[:space:]]+copied/ { next }
    /^[[:space:]]*[0-9]+[[:space:]]+restored/ { next }
    /^There are differences!/ { next }
    /^No differences/ { next }
    /^\*\*SUMMARY of changes/ { next }

    # Remove the horizontal line separators from the log
    /^----------------------------------------$/ { next }
    
    # Remove standalone "Everything OK" lines (redundant with our summaries)
    /^Everything OK$/ { next }

    # Preserve the file-change omission message with better spacing
    /^\.\.\. \([0-9]+ file-change lines omitted/ { 
      # Ensure single blank line before
      if (blank_count == 0) print ""
      print $0
      print ""
      blank_count = 1
      next 
    }
    
    # Reduce excessive spacing around file operations (add/remove/update lines)
    /^(add|remove|update|move|copy|restore)[[:space:]]+/ {
      blank_count = 0
      print
      next
    }
    
    # Reduce spacing after "Verified" lines and similar status messages
    /^(Saving state to|Verified|Scanned|Using|Initializing|Resizing|Syncing|Scrubbing|Selecting|Comparing)/ {
      # Skip if we just had this type of message
      if ($0 !~ /^Verified/ || !just_had_verified) {
        print
      }
      if ($0 ~ /^Verified/) just_had_verified = 1
      else just_had_verified = 0
      blank_count = 0
      next
    }

    # Skip excessive blank lines (more than 1 in a row)
    /^[[:space:]]*$/ {
      if (blank_count >= 1) next
      blank_count++
      print
      next
    }

    # Reset blank line counter on non-blank lines
    {
      blank_count = 0
      print
    }
  ' "$EMAIL_OUTPUT" > "$tmp" && mv -f "$tmp" "$EMAIL_OUTPUT"
}

# Send the formatted email
send_mail() {
  if ! "$MAIL_BIN" -s "$SUBJECT" "$EMAIL_ADDRESS" < "$EMAIL_OUTPUT"; then
    log "ERROR: Failed to send email to $EMAIL_ADDRESS"
    return 1
  fi
}

# Save the full unformatted log to disk for reference
persist_full_log() {
  mkdir -p "$LOG_DIR" || die "Unable to create log dir: $LOG_DIR"
  
  local ts host
  ts="$(date +'%Y%m%d-%H%M%S')"
  host="$(hostname)"
  FULL_LOG_FILE="${LOG_DIR}/snapraid-${host}-${ts}.log"
  
  cp -f "$TMP_OUTPUT" "$FULL_LOG_FILE" || die "Unable to write full log to: $FULL_LOG_FILE"
}

#######################################################################
# MAIN EXECUTION
#######################################################################

main() {
  # Prevent overlapping runs using flock if available
  if have_cmd flock; then
    exec 200>"$LOCK_FILE"
    flock -n 200 || die "Another snapraid job appears to be running (lock: $LOCK_FILE)."
  fi

  # Initialize
  require_bins
  hc_init

  EMAIL_SUBJECT_PREFIX="(SnapRAID on $(hostname))"
  TMP_OUTPUT="$(mktemp -t snapraid.out.XXXXXX)"
  EMAIL_OUTPUT="$(mktemp -t snapraid.email.XXXXXX)"
  : > "$TMP_OUTPUT"
  : > "$EMAIL_OUTPUT"

  export PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:$PATH"

  parse_snapraid_conf
  hc_start

  log "SnapRAID Script Job started [$(date)]"
  
  #####################################################################
  # PREPROCESSING
  #####################################################################
  
  section "##Preprocessing"

  # Pause Docker services to prevent file changes during sync
  if (( MANAGE_SERVICES == 1 )); then
    log "###Stop Services [$(date)]"
    service_pause
  fi

  # Verify all content and parity files exist
  sanity_check

  #####################################################################
  # PROCESSING
  #####################################################################
  
  section "##Processing"

  # Check for and fix zero sub-second timestamp files
  chk_zero

  #
  # DIFF - Analyze what has changed since last sync
  # Note: snapraid diff returns rc=2 when differences are found (this is normal)
  #
  mark_begin "DIFF"
  {
    echo "###DIFF [$(date)]"
    "$SNAPRAID_BIN" diff
  } 2>&1 | tee -a "$TMP_OUTPUT"
  DIFF_RC=${PIPESTATUS[0]}
  mark_end "DIFF" "$DIFF_RC"
  JOBS_DONE="DIFF"

  # Handle DIFF exit code (0 or 2 are both acceptable)
  if ! is_snapraid_diff_ok "$DIFF_RC"; then
    HAD_FAILURE=1
    log "**WARNING** DIFF returned non-zero exit code: ${DIFF_RC}"
    if (( FAIL_FAST == 1 )); then
      die "DIFF failed with rc=${DIFF_RC} (FAIL_FAST=1)"
    fi
  fi

  # Extract change counts from DIFF output
  get_counts

  # Verify we got all required counts
  if [[ -z "${DEL_COUNT:-}" || -z "${ADD_COUNT:-}" || -z "${MOVE_COUNT:-}" || -z "${COPY_COUNT:-}" || -z "${UPDATE_COUNT:-}" ]]; then
    log "**ERROR** Failed to extract change counts from DIFF output. Unable to proceed safely."
    persist_full_log
    
    if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
      SUBJECT="${EMAIL_SUBJECT_PREFIX} WARNING - Unable to proceed with SYNC/SCRUB job(s). Check DIFF job output."
      summarize_diff_for_email
      beautify_email_output
      send_mail
    fi
    
    hc_finish_fail 2
    exit 1
  fi

  log
  log "**SUMMARY of changes - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Copied [$COPY_COUNT] - Updated [$UPDATE_COUNT]**"
  log

  #
  # SYNC Decision Logic
  #
  if (( DEL_COUNT > 0 || ADD_COUNT > 0 || MOVE_COUNT > 0 || COPY_COUNT > 0 || UPDATE_COUNT > 0 )); then
    # Changes detected - check thresholds
    if (( SYNC_WARN_THRESHOLD == 0 )); then
      # Always force sync when threshold is 0
      DO_SYNC=1
    else
      # Check deletion threshold
      chk_del
      
      # Only check update threshold if deletion check passed
      if (( CHK_FAIL == 0 )); then
        chk_updated
      fi
      
      # If either threshold was exceeded, check if we should force sync anyway
      if (( CHK_FAIL == 1 )); then
        chk_sync_warn
      fi
    fi
  else
    # No changes detected
    log "No changes detected. Not running SYNC job. [$(date)]"
    DO_SYNC=0
  fi

  #
  # SYNC - Update parity if authorized
  #
  if (( DO_SYNC == 1 )); then
    run_cmd "SYNC" "$SNAPRAID_BIN" sync -q
    SYNC_RC=$?
    JOBS_DONE="${JOBS_DONE} + SYNC"
    
    # Clear warning counter after successful sync authorization
    [[ -e "$SYNC_WARN_FILE" ]] && rm -f "$SYNC_WARN_FILE"
  fi

  #
  # SCRUB - Verify data integrity on a portion of the array
  #
  if (( SCRUB_PERCENT > 0 )); then
    # Don't scrub if thresholds were exceeded and sync was skipped
    if (( CHK_FAIL == 1 && DO_SYNC == 0 )); then
      log "Scrub job cancelled - parity info is out of sync (threshold breached). [$(date)]"
    else
      # If SYNC ran, verify it completed successfully before scrubbing
      if (( DO_SYNC == 1 )); then
        if ! marker_end_present "SYNC"; then
          log "**WARNING** SYNC end marker missing. Not proceeding with SCRUB. [$(date)]"
        elif (( SYNC_RC != 0 )); then
          log "**WARNING** SYNC failed with rc=${SYNC_RC}. Not proceeding with SCRUB. [$(date)]"
        else
          run_cmd "SCRUB" "$SNAPRAID_BIN" scrub -p "$SCRUB_PERCENT" -o "$SCRUB_AGE" -q
          SCRUB_RC=$?
          JOBS_DONE="${JOBS_DONE} + SCRUB"
        fi
      else
        # No SYNC needed, safe to scrub
        run_cmd "SCRUB" "$SNAPRAID_BIN" scrub -p "$SCRUB_PERCENT" -o "$SCRUB_AGE" -q
        SCRUB_RC=$?
        JOBS_DONE="${JOBS_DONE} + SCRUB"
      fi
    fi
  else
    log "Scrub job is not enabled (SCRUB_PERCENT=0). Skipping SCRUB. [$(date)]"
  fi

  #####################################################################
  # POSTPROCESSING
  #####################################################################
  
  section "##Postprocessing"

  #
  # SMART - Log disk SMART attributes
  #
  if (( SMART_LOG == 1 )); then
    run_cmd "SMART" "$SNAPRAID_BIN" smart
    SMART_RC=$?
    JOBS_DONE="${JOBS_DONE} + SMART"
  fi

  #
  # DOWN - Spindown array disks
  #
  if (( SPINDOWN_DISKS == 1 )); then
    run_cmd "DOWN" "$SNAPRAID_BIN" down
    DOWN_RC=$?
    JOBS_DONE="${JOBS_DONE} + DOWN"
  else
    log "Spindown disabled (SPINDOWN_DISKS=0). Skipping \`snapraid down\`."
    DOWN_RC=0
  fi

  # Restore paused services
  restore_services

  log "All jobs completed. [$(date)]"
  
  #####################################################################
  # REPORTING
  #####################################################################
  
  # Save full log to disk
  persist_full_log

  # Prepare and send email if configured
  if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
    prepare_mail_subject
    summarize_diff_for_email
    beautify_email_output
    send_mail
  fi

  # Send healthcheck ping
  if [[ "${SUBJECT:-}" == *"[WARNING]"* || $HAD_FAILURE -eq 1 || $CHK_FAIL -eq 1 ]]; then
    hc_finish_fail 1
  else
    hc_finish_success
  fi

  exit 0
}

# Execute main function
main "$@"
```
{% endraw %}

(**Editor note:** paste the full script here exactly as-is. Just modify the values at the top.)

## Final Thoughts
SnapRAID is incredibly powerful, but it assumes the operator knows what they’re doing. This script is my attempt to encode that operational knowledge directly into the automation.

If you adapt it, steal from it, or improve it, that’s a win. Just please let me know! 🤓

Happy scrubbing!