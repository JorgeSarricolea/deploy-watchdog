#!/usr/bin/env bash
set -euo pipefail

# deploy-watchdog — ensures every push gets deployed
#
# Two-part system:
#   LOCAL:  Git pre-push hook writes commit hash to $STATE_DIR/<project>.expected
#   SERVER: This script (runs every 2min via systemd) detects the mismatch and triggers Coolify
#
# Settle logic: waits SETTLE_SECONDS after the last new commit before deploying,
# so rapid pushes don't trigger multiple builds.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${DEPLOY_WATCHDOG_ENV:-/etc/deploy-watchdog.env}"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${COOLIFY_API:?COOLIFY_API not set — create $ENV_FILE from .env.example}"
: "${COOLIFY_TOKEN:?COOLIFY_TOKEN not set — create $ENV_FILE from .env.example}"
: "${SETTLE_SECONDS:=90}"

STATE_DIR="/root/.deploy-watchdog"

# ── Project registry ──────────────────────────────────────────────
# Format: [project_name]="coolify_app_uuid"
# Add new projects here when onboarding them to auto-deploy.
declare -A PROJECTS=(
  [workhub]="aq24a7bq5pgq224y3ck3d7p0"
  [mikascoffee]="o64g4hmceugv2dsju990mw2x"
  [portfolio]="pf44pziysccg7avkm9sy3lvk"
)

mkdir -p "$STATE_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$STATE_DIR/watchdog.log"; }

for name in "${!PROJECTS[@]}"; do
  uuid="${PROJECTS[$name]}"
  expected_file="$STATE_DIR/$name.expected"
  deployed_file="$STATE_DIR/$name.deployed"

  [ -f "$expected_file" ] || continue

  expected=$(cat "$expected_file")
  deployed=$(cat "$deployed_file" 2>/dev/null || echo "")

  if [ "$expected" = "$deployed" ]; then
    rm -f "$expected_file"
    continue
  fi

  pending_file="$STATE_DIR/$name.pending"
  pending_ts_file="$STATE_DIR/$name.pending_ts"
  stored_pending=$(cat "$pending_file" 2>/dev/null || echo "")

  if [ "$stored_pending" != "$expected" ]; then
    echo "$expected" > "$pending_file"
    date +%s > "$pending_ts_file"
    log "PENDING $name: expecting ${expected:0:8}, waiting ${SETTLE_SECONDS}s settle..."
    continue
  fi

  pending_ts=$(cat "$pending_ts_file" 2>/dev/null || echo "0")
  now_ts=$(date +%s)
  elapsed=$(( now_ts - pending_ts ))

  if [ "$elapsed" -lt "$SETTLE_SECONDS" ]; then
    continue
  fi

  log "DEPLOY $name: commit ${expected:0:8} settled for ${elapsed}s, triggering Coolify..."

  response=$(curl -s -w '\n%{http_code}' -X GET \
    "${COOLIFY_API}/deploy?uuid=${uuid}&force=false" \
    -H "Authorization: Bearer $COOLIFY_TOKEN" 2>/dev/null || echo -e "\n000")

  http_code=$(echo "$response" | tail -1)

  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
    echo "$expected" > "$deployed_file"
    rm -f "$expected_file" "$pending_file" "$pending_ts_file"
    log "OK $name: deploy queued for ${expected:0:8}"
  else
    body=$(echo "$response" | head -n -1)
    log "FAIL $name: HTTP $http_code — $body"
  fi
done

# Trim log to last 500 lines
if [ -f "$STATE_DIR/watchdog.log" ]; then
  tail -500 "$STATE_DIR/watchdog.log" > "$STATE_DIR/watchdog.log.tmp" 2>/dev/null
  mv "$STATE_DIR/watchdog.log.tmp" "$STATE_DIR/watchdog.log" 2>/dev/null
fi
