#!/usr/bin/env bash
set -euo pipefail

# server-cleanup.sh — weekly VPS maintenance
#
# Runs via systemd timer (Sundays 04:00 UTC). Cleans:
#   - Dangling Docker images, stopped containers, unused networks
#   - Old unused images (not running, >48h old)
#   - Docker build cache (>48h)
#   - Unused Docker volumes
#   - Apt package cache
#   - Journal logs (>7 days, capped at 100M)
#   - Old Prisma migration temp dirs
#   - Stale /tmp files (>7 days)

LOG="/var/log/server-cleanup.log"
exec >> "$LOG" 2>&1

echo "============================================"
echo "Server cleanup — $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "============================================"

BEFORE=$(df / --output=used -B1 | tail -1 | tr -d " ")

echo ""
echo "── Docker: prune dangling images, stopped containers, unused networks ──"
docker image prune -f
docker container prune -f
docker network prune -f

echo ""
echo "── Docker: remove images older than 48h not used by running containers ──"
RUNNING_IMAGES=$(docker ps --format "{{.Image}}" | sort -u)
docker images --format "{{.ID}} {{.Repository}}:{{.Tag}} {{.CreatedSince}}" | while read -r id repo age; do
  if echo "$RUNNING_IMAGES" | grep -qF "$repo"; then
    continue
  fi
  if echo "$age" | grep -qE "(weeks?|months?|years?) ago"; then
    echo "  Removing unused image: $repo ($id, $age)"
    docker rmi "$id" 2>/dev/null || true
  fi
done

echo ""
echo "── Docker: prune unused build cache ──"
docker builder prune -f --filter "until=48h" 2>/dev/null || true

echo ""
echo "── Docker: remove unused volumes (not attached to any container) ──"
docker volume prune -f

echo ""
echo "── Apt: clean package cache ──"
apt-get clean -y 2>/dev/null || true

echo ""
echo "── Journal: vacuum logs older than 7 days, cap at 100M ──"
journalctl --vacuum-time=7d --vacuum-size=100M 2>/dev/null || true

echo ""
echo "── Temp: clean old Prisma migration dirs ──"
find /root -maxdepth 1 -name "workhub-prisma-migrate-*" -mtime +3 -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "── Temp: clean /tmp files older than 7 days ──"
find /tmp -type f -mtime +7 -delete 2>/dev/null || true

AFTER=$(df / --output=used -B1 | tail -1 | tr -d " ")
FREED=$(( (BEFORE - AFTER) / 1048576 ))
echo ""
echo "── Summary ──"
echo "Freed: ${FREED} MB"
df -h / | tail -1 | awk "{print \"Disk: \" \$3 \" used / \" \$2 \" total (\" \$5 \")\"}"
echo "Done."
echo ""
