#!/usr/bin/env bash
set -euo pipefail

# install.sh — deploy watchdog + server cleanup to a VPS
#
# Run locally: ./install.sh [ssh-host]
# Default host: root@jorgesarricolea.com

SSH_HOST="${1:-root@jorgesarricolea.com}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Deploying to $SSH_HOST..."

# ── Deploy Watchdog ────────────────────────────────────────────────
echo ""
echo "── Deploy Watchdog ──"

scp "$SCRIPT_DIR/deploy-watchdog.sh" "$SSH_HOST:/usr/local/bin/deploy-watchdog.sh"
ssh "$SSH_HOST" "chmod +x /usr/local/bin/deploy-watchdog.sh"

scp "$SCRIPT_DIR/systemd/deploy-watchdog.service" "$SSH_HOST:/etc/systemd/system/"
scp "$SCRIPT_DIR/systemd/deploy-watchdog.timer" "$SSH_HOST:/etc/systemd/system/"

if ! ssh "$SSH_HOST" "test -f /etc/deploy-watchdog.env"; then
  if [ -f "$SCRIPT_DIR/.env" ]; then
    scp "$SCRIPT_DIR/.env" "$SSH_HOST:/etc/deploy-watchdog.env"
    ssh "$SSH_HOST" "chmod 600 /etc/deploy-watchdog.env"
    echo "  Copied .env to /etc/deploy-watchdog.env"
  else
    echo "  WARNING: No .env file found. Create /etc/deploy-watchdog.env on the server."
  fi
fi

# ── Server Cleanup ─────────────────────────────────────────────────
echo ""
echo "── Server Cleanup ──"

scp "$SCRIPT_DIR/server-cleanup.sh" "$SSH_HOST:/usr/local/bin/server-cleanup.sh"
ssh "$SSH_HOST" "chmod +x /usr/local/bin/server-cleanup.sh"

scp "$SCRIPT_DIR/systemd/server-cleanup.service" "$SSH_HOST:/etc/systemd/system/"
scp "$SCRIPT_DIR/systemd/server-cleanup.timer" "$SSH_HOST:/etc/systemd/system/"

# Remove legacy script if it exists at old location
ssh "$SSH_HOST" "rm -f /root/cleanup-server.sh" 2>/dev/null || true

# ── Enable & start ─────────────────────────────────────────────────
echo ""
echo "── Enabling timers ──"

ssh "$SSH_HOST" "
  mkdir -p /root/.deploy-watchdog
  systemctl daemon-reload
  systemctl enable deploy-watchdog.timer server-cleanup.timer
  systemctl restart deploy-watchdog.timer server-cleanup.timer
  echo ''
  echo 'Deploy watchdog (every 2 min):'
  systemctl status deploy-watchdog.timer --no-pager -n0
  echo ''
  echo 'Server cleanup (weekly Sun 04:00 UTC):'
  systemctl status server-cleanup.timer --no-pager -n0
"

echo ""
echo "==> Done."
echo ""
echo "To set up the local git hook:"
echo "  ln -sf $SCRIPT_DIR/pre-push ~/.config/git/hooks/pre-push"
