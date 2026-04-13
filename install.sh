#!/usr/bin/env bash
set -euo pipefail

# install.sh — deploy the watchdog to a VPS
#
# Run locally: ./install.sh [ssh-host]
# Default host: root@jorgesarricolea.com

SSH_HOST="${1:-root@jorgesarricolea.com}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Deploying to $SSH_HOST..."

# Copy script
scp "$SCRIPT_DIR/deploy-watchdog.sh" "$SSH_HOST:/usr/local/bin/deploy-watchdog.sh"
ssh "$SSH_HOST" "chmod +x /usr/local/bin/deploy-watchdog.sh"

# Copy systemd units
scp "$SCRIPT_DIR/systemd/deploy-watchdog.service" "$SSH_HOST:/etc/systemd/system/"
scp "$SCRIPT_DIR/systemd/deploy-watchdog.timer" "$SSH_HOST:/etc/systemd/system/"

# Copy env file if it doesn't already exist on server
if ! ssh "$SSH_HOST" "test -f /etc/deploy-watchdog.env"; then
  if [ -f "$SCRIPT_DIR/.env" ]; then
    scp "$SCRIPT_DIR/.env" "$SSH_HOST:/etc/deploy-watchdog.env"
    ssh "$SSH_HOST" "chmod 600 /etc/deploy-watchdog.env"
    echo "==> Copied .env to /etc/deploy-watchdog.env"
  else
    echo "==> WARNING: No .env file found. Create /etc/deploy-watchdog.env on the server."
  fi
fi

# Enable and start
ssh "$SSH_HOST" "
  mkdir -p /root/.deploy-watchdog
  systemctl daemon-reload
  systemctl enable deploy-watchdog.timer
  systemctl restart deploy-watchdog.timer
  echo '==> Timer status:'
  systemctl status deploy-watchdog.timer --no-pager
"

echo ""
echo "==> Done. Watchdog runs every 2 minutes."
echo ""
echo "To set up the local git hook:"
echo "  git config --global core.hooksPath $SCRIPT_DIR"
echo "  (or symlink $SCRIPT_DIR/pre-push to ~/.config/git/hooks/pre-push)"
