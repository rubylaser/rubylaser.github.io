---
layout: post
title: "A Modern SnapRAID Maintenance Script (Split Parity, Docker-Aware, and Monitored)"
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

EMAIL_ADDRESS="email.address@gmail.com"

# Set the threshold of deleted files to stop the sync job from running.
DEL_THRESHOLD=50
UP_THRESHOLD=500

#  0  -> always force a sync (ignore thresholds)
# -1  -> never force a sync (manual intervention required if thresholds exceeded)
#  N  -> force a sync after N warnings
SYNC_WARN_THRESHOLD=-1

# Set percentage of array to scrub if it is in sync.
# 0 disables scrub. 100 scrubs the full array in one run (can take a long time).
SCRUB_PERCENT=0
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
DIFF_LIST_HEAD=40
DIFF_LIST_TAIL=40

# Where to store full logs persistently (email will include the path)
LOG_DIR="/var/log/snapraid"

# Healthchecks integration (optional)
HEALTHCHECKS_ALERTS=1
HEALTHCHECKS_ID="5fd000cd-58IS-40dc-5678-6e28a091d1a8"
HEALTHCHECKS_URL="https://healthchecks.hostname.com/ping/"

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

# Healthchecks
HC_ENABLED=0
HC_TOOL=""   # curl|wget
HC_SENT_START=0

log() { printf '%s\n' "$*"; }

die() {
  log "**ERROR** $*"
  exit 1
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

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

section() {
  log
  log "----------------------------------------"
  log "$1"
}

# -------------------------
# Healthchecks integration
# -------------------------

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

hc_ping_url() {
  local suffix="${1:-}"
  local base="${HEALTHCHECKS_URL%/}/"
  local url="${base}${HEALTHCHECKS_ID}"
  [[ -n "$suffix" ]] && url="${url}/${suffix}"
  printf '%s' "$url"
}

hc_send() {
  (( HC_ENABLED == 1 )) || return 0

  local suffix="${1:-}"
  local body="${2:-}"
  local url
  url="$(hc_ping_url "$suffix")"

  # Monitoring must never block maintenance.
  if [[ "$HC_TOOL" == "curl" ]]; then
    if [[ -n "$body" ]]; then
      curl -fsS --max-time "$HC_TIMEOUT_SECS" --retry "$HC_RETRIES" \
        --retry-delay 1 --retry-all-errors \
        -X POST --data-raw "$body" "$url" >/dev/null 2>&1 || true
    else
      curl -fsS --max-time "$HC_TIMEOUT_SECS" --retry "$HC_RETRIES" \
        --retry-delay 1 --retry-all-errors \
        "$url" >/dev/null 2>&1 || true
    fi
  else
    if [[ -n "$body" ]]; then
      printf '%s' "$body" | wget -qO- --timeout="$HC_TIMEOUT_SECS" --tries="$HC_RETRIES" \
        --method=POST --body-file=- "$url" >/dev/null 2>&1 || true
    else
      wget -qO- --timeout="$HC_TIMEOUT_SECS" --tries="$HC_RETRIES" "$url" >/dev/null 2>&1 || true
    fi
  fi
}

hc_start() {
  (( HC_ENABLED == 1 )) || return 0
  hc_send "start" "SnapRAID job started on $(hostname) at $(date)"
  HC_SENT_START=1
}

hc_finish_success() {
  (( HC_ENABLED == 1 )) || return 0
  hc_send "" "SnapRAID job success on $(hostname) at $(date). Jobs: ${JOBS_DONE}"
}

hc_finish_fail() {
  (( HC_ENABLED == 1 )) || return 0
  local code="${1:-1}"
  (( code >= 1 && code <= 255 )) || code=1
  hc_send "$code" "SnapRAID job WARNING/FAIL on $(hostname) at $(date). Subject: ${SUBJECT:-"(no subject)"}"
}

# -------------------------
# Robust markers + runner
# -------------------------

mark_begin() {
  local name="$1"
  echo "__SNAPRAID_${name}_BEGIN__ [$(date)]" | tee -a "$TMP_OUTPUT" >/dev/null
}

mark_end() {
  local name="$1"
  local rc="$2"
  {
    echo "__SNAPRAID_${name}_END__ [$(date)] rc=${rc}"
    echo
  } | tee -a "$TMP_OUTPUT" >/dev/null
}

marker_end_present() {
  local name="$1"
  grep -q "__SNAPRAID_${name}_END__" "$TMP_OUTPUT"
}

# snapraid diff: rc=2 means "differences found" (normal)
is_snapraid_diff_ok() {
  local rc="$1"
  [[ "$rc" -eq 0 || "$rc" -eq 2 ]]
}

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

# -------------------------
# Docker service management
# -------------------------

service_pause() {
  local s running
  for s in "${SERVICES[@]}"; do
    # Read the value, don't just test whether `docker inspect` succeeded.
    running="$("$DOCKER_BIN" inspect -f '{{.State.Running}}' "$s" 2>/dev/null || true)"

    if [[ "$running" == "true" ]]; then
      log "Pausing Service - ${s}"
      if "$DOCKER_BIN" pause "$s" >/dev/null 2>&1; then
        PAUSED_SERVICES+=("$s")
      else
        log "WARNING: failed to pause $s"
        SERVICE_RC=1
        HAD_FAILURE=1
      fi
    elif [[ -n "$running" ]]; then
      # Container exists, but isn't running
      log "Service not running (skip pause) - ${s}"
    else
      # Container doesn't exist / inspect failed
      log "Service not found (skip pause) - ${s}"
    fi
  done
}

service_unpause() {
  local s st
  for s in "${PAUSED_SERVICES[@]}"; do
    st="$("$DOCKER_BIN" inspect -f '{{.State.Status}}' "$s" 2>/dev/null || true)"
    if [[ "$st" == "paused" ]]; then
      log "Unpausing Service - ${s}"
      "$DOCKER_BIN" unpause "$s" >/dev/null 2>&1 || {
        log "WARNING: failed to unpause $s"
        SERVICE_RC=1
        HAD_FAILURE=1
      }
    else
      log "Service not paused (skip unpause) - ${s} (status: $st)"
    fi
  done
}

restore_services() {
  (( MANAGE_SERVICES == 1 )) || return 0
  service_unpause
  return 0
}

cleanup() {
  # Avoid noisy unpause attempts if the script is already in "graceful" end.
  restore_services || true
}

trap cleanup INT TERM EXIT

# -------------------------
# SnapRAID config parsing
# -------------------------

parse_snapraid_conf() {
  mapfile -t CONTENT_FILES < <(
    awk '
      $0 !~ /^[[:space:]]*($|#|;)/ && ($1=="content" || $1=="snapraid.content") { print $2 }
    ' "$SNAPRAID_CONF"
  )
  ((${#CONTENT_FILES[@]} > 0)) || die "Could not determine content files from $SNAPRAID_CONF"
  CONTENT_FILE="${CONTENT_FILES[0]}"

  mapfile -t PARITY_FILES < <(
    awk '
      function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
      $0 !~ /^[[:space:]]*($|#|;)/ && ($1=="parity" || $1 ~ /^([2-6]|z)-parity$/) {
        n=split($2,a,",");
        for (i=1;i<=n;i++) print trim(a[i]);
      }
    ' "$SNAPRAID_CONF"
  )
  ((${#PARITY_FILES[@]} > 0)) || die "Could not determine parity files from $SNAPRAID_CONF"
}

sanity_check() {
  local cf pf
  for cf in "${CONTENT_FILES[@]}"; do
    [[ -e "$cf" ]] || die "Content file not found: $cf"
  done

  log "Testing that all parity files are present."
  for pf in "${PARITY_FILES[@]}"; do
    [[ -e "$pf" ]] || die "Parity file not found: $pf"
  done
  log "All parity files found. Continuing..."
}

# UPDATED SnapRAID summary footer format:
#   "      50 added"
#   "       9 removed"
#   "       0 updated"
get_counts() {
  # IMPORTANT: awk has an `in` operator; don't use "in" as a variable name.
  local diff_block
  diff_block="$(
    awk '
      /__SNAPRAID_DIFF_BEGIN__/ {inblk=1; next}
      /__SNAPRAID_DIFF_END__/   {inblk=0}
      inblk {print}
    ' "$TMP_OUTPUT"
  )"

  [[ -n "$diff_block" ]] || diff_block="$(cat "$TMP_OUTPUT")"

  ADD_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+added$/       {print $1; exit}' <<<"$diff_block" || true)"
  DEL_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+removed$/     {print $1; exit}' <<<"$diff_block" || true)"
  UPDATE_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+updated$/  {print $1; exit}' <<<"$diff_block" || true)"
  MOVE_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+moved$/      {print $1; exit}' <<<"$diff_block" || true)"
  COPY_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+copied$/     {print $1; exit}' <<<"$diff_block" || true)"
  RESTORED_COUNT="$(awk '/^[[:space:]]*[0-9]+[[:space:]]+restored$/ {print $1; exit}' <<<"$diff_block" || true)"
  RESTORED_COUNT="${RESTORED_COUNT:-0}"
}

chk_del() {
  if (( DEL_COUNT < DEL_THRESHOLD )); then
    log "There are deleted files. Deleted ($DEL_COUNT) is below threshold ($DEL_THRESHOLD). SYNC Authorized."
    DO_SYNC=1
  else
    log "**WARNING** Deleted files ($DEL_COUNT) exceeded threshold ($DEL_THRESHOLD)."
    CHK_FAIL=1
  fi
}

chk_updated() {
  if (( UPDATE_COUNT < UP_THRESHOLD )); then
    log "There are updated files. Updated ($UPDATE_COUNT) is below threshold ($UP_THRESHOLD). SYNC Authorized."
    DO_SYNC=1
  else
    log "**WARNING** Updated files ($UPDATE_COUNT) exceeded threshold ($UP_THRESHOLD)."
    CHK_FAIL=1
  fi
}

chk_sync_warn() {
  if (( SYNC_WARN_THRESHOLD > -1 )); then
    log "Forced sync is enabled. [$(date)]"

    if [[ -f "$SYNC_WARN_FILE" ]]; then
      SYNC_WARN_COUNT="$(awk 'NR==1 && $0 ~ /^[0-9]+$/ {print $0; exit}' "$SYNC_WARN_FILE" || true)"
    else
      SYNC_WARN_COUNT=""
    fi
    SYNC_WARN_COUNT="${SYNC_WARN_COUNT:-0}"

    if (( SYNC_WARN_COUNT >= SYNC_WARN_THRESHOLD )); then
      log "Number of warning(s) ($SYNC_WARN_COUNT) reached/exceeded threshold ($SYNC_WARN_THRESHOLD). Forcing SYNC. [$(date)]"
      DO_SYNC=1
    else
      ((SYNC_WARN_COUNT += 1))
      printf '%s\n' "$SYNC_WARN_COUNT" > "$SYNC_WARN_FILE"
      log "$((SYNC_WARN_THRESHOLD - SYNC_WARN_COUNT)) warning(s) till forced sync. NOT proceeding with SYNC. [$(date)]"
      DO_SYNC=0
    fi
  else
    log "Forced sync is not enabled. Check output for details. NOT proceeding with SYNC. [$(date)]"
    DO_SYNC=0
  fi
}

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
    log "No zero sub-second timestamp files found."
  fi
}

prepare_mail_subject() {
  local msg=""
  local STATUS_ICON="🟢"
  local STATUS_WORD="COMPLETED"

  # Threshold violations
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

  # Command failures
  if (( HAD_FAILURE == 1 )); then
    STATUS_ICON="🔴"
    STATUS_WORD="FAILED"
    SUBJECT="${STATUS_ICON} [${STATUS_WORD}] ${EMAIL_SUBJECT_PREFIX}"
    return 0
  fi

  SUBJECT="${STATUS_ICON} [${STATUS_WORD}] ${JOBS_DONE} ${EMAIL_SUBJECT_PREFIX}"
}

# Create a summarized email copy of the log (full log is preserved separately).
# This counts line types (add/remove/update/move/copy/restore) and includes them in the omission message.
summarize_diff_for_email() {
  cp -f "$TMP_OUTPUT" "$EMAIL_OUTPUT"

  (( SUMMARIZE_DIFF_EMAIL == 1 )) || return 0

  awk -v head="$DIFF_LIST_HEAD" -v tail="$DIFF_LIST_TAIL" '
    function is_action(line) { return (line ~ /^(add|remove|update|move|copy|restore)[[:space:]]+/) }
    function action_type(line,   a) { split(line, a, /[[:space:]]+/); return a[1] }

    BEGIN { inblk=0; a_count=0; tlen=0; tstart=1; addc=remc=updc=movc=copyc=restc=0 }

    /__SNAPRAID_DIFF_BEGIN__/ { inblk=1; print; next }
    /__SNAPRAID_DIFF_END__/ {
      if (inblk) {
        if (a_count > head + tail) {
          omitted = a_count - (head + tail)
          print ""
          printf "... (%d file-change lines omitted from email; breakdown: add=%d remove=%d update=%d move=%d copy=%d restore=%d; see full log on disk) ...\n",
                 omitted, addc, remc, updc, movc, copyc, restc
          print ""
        }
        for (i=1; i<=tlen; i++) {
          idx = tstart + i - 1
          if (idx > tail) idx -= tail
          print tbuf[idx]
        }
      }
      inblk=0
      print
      next
    }

    {
      if (!inblk) { print; next }

      if (is_action($0)) {
        a_count++
        t = action_type($0)
        if (t=="add") addc++
        else if (t=="remove") remc++
        else if (t=="update") updc++
        else if (t=="move") movc++
        else if (t=="copy") copyc++
        else if (t=="restore") restc++

        if (a_count <= head) { print; next }

        if (tail > 0) {
          if (tlen < tail) { tlen++; pos=tlen }
          else { pos=tstart; tstart++; if (tstart > tail) tstart=1 }
          tbuf[pos] = $0
        }
        next
      }

      print
    }
  ' "$TMP_OUTPUT" > "$EMAIL_OUTPUT".tmp && mv -f "$EMAIL_OUTPUT".tmp "$EMAIL_OUTPUT"
}

# Email formatting that reads well as plain text AND in Markdown-aware clients.
beautify_email_output() {
  local tmp
  tmp="$(mktemp -t snapraid.pretty.XXXXXX)"

  awk -v subject="${SUBJECT}" -v host="$(hostname)" -v logfile="${FULL_LOG_FILE}" '
    function hr() { print "------------------------------------------------------------" }
    function h1(t) { hr(); print t; hr() }
    function h2(t) { print ""; print "### " t; print "" }

    BEGIN {
      h1(subject)
      print "Host: " host
      if (logfile != "") print "Full log: " logfile
      print "Run finished: " strftime("%c")
      hr()
      print ""
    }

    /^__SNAPRAID_[A-Z0-9_]+_BEGIN__/ {
      block=$0
      gsub(/^__SNAPRAID_/, "", block)
      gsub(/_BEGIN__.*$/, "", block)
      gsub(/_/, " ", block)
      h2(block)
      next
    }

    /^__SNAPRAID_[A-Z0-9_]+_END__/ { print ""; next }

    /^###[A-Z0-9_]+ \[/ { next }

    /^Pausing Service -/   { if (!svc) { h2("Services"); svc=1 } print "- " $0; next }
    /^Unpausing Service -/ { if (!svc) { h2("Services"); svc=1 } print "- " $0; next }

    /^\*\*SUMMARY of changes/ { h2("Diff Summary"); print $0; next }

    { print }
  ' "$EMAIL_OUTPUT" > "$tmp" && mv -f "$tmp" "$EMAIL_OUTPUT"
}

send_mail() {
  "$MAIL_BIN" -s "$SUBJECT" "$EMAIL_ADDRESS" < "$EMAIL_OUTPUT"
}

persist_full_log() {
  mkdir -p "$LOG_DIR" || die "Unable to create log dir: $LOG_DIR"
  local ts host
  ts="$(date +'%Y%m%d-%H%M%S')"
  host="$(hostname)"
  FULL_LOG_FILE="${LOG_DIR}/snapraid-${host}-${ts}.log"
  cp -f "$TMP_OUTPUT" "$FULL_LOG_FILE" || die "Unable to write full log to: $FULL_LOG_FILE"
}

main() {
  # Optional lock
  if have_cmd flock; then
    exec 200>"$LOCK_FILE"
    flock -n 200 || die "Another snapraid job appears to be running (lock: $LOCK_FILE)."
  fi

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
  section "##Preprocessing"

  if (( MANAGE_SERVICES == 1 )); then
    log "###Stop Services [$(date)]"
    service_pause | tee -a "$TMP_OUTPUT"
  fi

  sanity_check

  section "##Processing"

  chk_zero

  # DIFF (special handling: rc=2 means "differences found" and is normal)
  mark_begin "DIFF"
  {
    echo "###DIFF [$(date)]"
    "$SNAPRAID_BIN" diff
  } 2>&1 | tee -a "$TMP_OUTPUT"
  DIFF_RC=${PIPESTATUS[0]}
  mark_end "DIFF" "$DIFF_RC"
  JOBS_DONE="DIFF"

  if ! is_snapraid_diff_ok "$DIFF_RC"; then
    HAD_FAILURE=1
    log "**WARNING** DIFF returned non-zero exit code: ${DIFF_RC}"
    if (( FAIL_FAST == 1 )); then
      die "DIFF failed with rc=${DIFF_RC} (FAIL_FAST=1)"
    fi
  fi

  get_counts

  if [[ -z "${DEL_COUNT:-}" || -z "${ADD_COUNT:-}" || -z "${MOVE_COUNT:-}" || -z "${COPY_COUNT:-}" || -z "${UPDATE_COUNT:-}" ]]; then
    log "**ERROR** failed to get one or more count values. Unable to proceed."
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

  # Decide on SYNC
  if (( DEL_COUNT > 0 || ADD_COUNT > 0 || MOVE_COUNT > 0 || COPY_COUNT > 0 || UPDATE_COUNT > 0 )); then
    if (( SYNC_WARN_THRESHOLD == 0 )); then
      DO_SYNC=1
    else
      chk_del
      if (( CHK_FAIL == 0 )); then
        chk_updated
      fi
      if (( CHK_FAIL == 1 )); then
        chk_sync_warn
      fi
    fi
  else
    log "No change detected. Not running SYNC job. [$(date)]"
    DO_SYNC=0
  fi

  if (( DO_SYNC == 1 )); then
    run_cmd "SYNC" "$SNAPRAID_BIN" sync -q
    SYNC_RC=$?
    JOBS_DONE="${JOBS_DONE} + SYNC"
    [[ -e "$SYNC_WARN_FILE" ]] && rm -f "$SYNC_WARN_FILE"
  fi

  # SCRUB
  if (( SCRUB_PERCENT > 0 )); then
    if (( CHK_FAIL == 1 && DO_SYNC == 0 )); then
      log "Scrub job cancelled as parity info is out of sync (threshold breached). [$(date)]"
    else
      if (( DO_SYNC == 1 )); then
        if ! marker_end_present "SYNC"; then
          log "**WARNING** - SYNC end marker missing. Not proceeding with SCRUB. [$(date)]"
        elif (( SYNC_RC != 0 )); then
          log "**WARNING** - SYNC rc=${SYNC_RC}. Not proceeding with SCRUB. [$(date)]"
        else
          run_cmd "SCRUB" "$SNAPRAID_BIN" scrub -p "$SCRUB_PERCENT" -o "$SCRUB_AGE" -q
          SCRUB_RC=$?
          JOBS_DONE="${JOBS_DONE} + SCRUB"
        fi
      else
        run_cmd "SCRUB" "$SNAPRAID_BIN" scrub -p "$SCRUB_PERCENT" -o "$SCRUB_AGE" -q
        SCRUB_RC=$?
        JOBS_DONE="${JOBS_DONE} + SCRUB"
      fi
    fi
  else
    log "Scrub job is not enabled. Not running SCRUB job. [$(date)]"
  fi

  section "##Postprocessing"

  if (( SMART_LOG == 1 )); then
    run_cmd "SMART" "$SNAPRAID_BIN" smart
    SMART_RC=$?
    JOBS_DONE="${JOBS_DONE} + SMART"
  fi

  if (( SPINDOWN_DISKS == 1 )); then
    # NOTE: This runs `snapraid down` which spins down the array disks after maintenance.
    run_cmd "DOWN" "$SNAPRAID_BIN" down
    DOWN_RC=$?
    JOBS_DONE="${JOBS_DONE} + DOWN"
  else
    log "Spindown disabled (SPINDOWN_DISKS=0). Skipping \`snapraid down\`."
    DOWN_RC=0
  fi

  restore_services

  log "All jobs ended. [$(date)]"
  persist_full_log

  if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
    prepare_mail_subject
    summarize_diff_for_email
    beautify_email_output
    send_mail
  fi

  if [[ "${SUBJECT:-}" == *"[WARNING]"* || $HAD_FAILURE -eq 1 || $CHK_FAIL -eq 1 ]]; then
    hc_finish_fail 1
  else
    hc_finish_success
  fi

  exit 0
}

main "$@"
```
(**Editor note:** paste the full script here exactly as-is. Just modify the values at the top.)

## Final Thoughts
SnapRAID is incredibly powerful, but it assumes the operator knows what they’re doing. This script is my attempt to encode that operational knowledge directly into the automation.

If you adapt it, steal from it, or improve it, that’s a win. Just please let me know! 🤓

Happy scrubbing!