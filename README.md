# deploy-watchdog

VPS automation for personal projects: catches missed Coolify deployments and runs weekly server cleanup.

## Problem

When you push multiple commits in quick succession, Coolify's webhook listener drops events while a build is already running. The result: your latest code never gets deployed until you manually trigger a rebuild.

## How it works

Two-part system:

```
git push (rapid, 3 times)
  │
  ├─ GitHub webhook → Coolify (might miss it if busy)
  │
  └─ pre-push hook → SSH → writes expected commit to VPS
                              │
                    ┌─────────┘
                    ▼
          deploy-watchdog.sh (runs every 2 min via systemd)
                    │
                    ├─ expected ≠ deployed?
                    │     └─ wait 90s settle (no more pushes?)
                    │           └─ trigger Coolify API → deploy ✓
                    │
                    └─ expected = deployed? → skip (all good)
```

**Settle logic**: after detecting a new commit, the watchdog waits 90 seconds before triggering a deploy. If another push arrives during that window, the timer resets. This prevents deploying mid-burst.

## Setup

### 1. Create env file

```bash
cp .env.example .env
# Edit .env with your Coolify API token and server details
```

### 2. Install on VPS

```bash
./install.sh root@your-server.com
```

This copies the script, systemd units, and env file to the server.

### 3. Set up local git hook

```bash
# Option A: use this directory as your global hooks path
git config --global core.hooksPath /path/to/deploy-watchdog

# Option B: symlink just the pre-push hook
ln -sf /path/to/deploy-watchdog/pre-push ~/.config/git/hooks/pre-push
```

## Adding a new project

1. In `deploy-watchdog.sh`, add an entry to the `PROJECTS` associative array:
   ```bash
   [my-new-project]="coolify-app-uuid"
   ```

2. In `pre-push`, add an entry to the `PROJECTS` array:
   ```bash
   "my-new-project|my-new-project|main"
   ```

3. Re-run `./install.sh` to update the VPS.

## Server Cleanup

A daily cleanup timer (`23:00 UTC`) that frees disk space:

- **Docker**: dangling images, stopped containers, unused networks, old images (>48h, not running), build cache, unused volumes
- **System**: apt package cache, journal logs (>7d, cap 100M), stale `/tmp` files (>7d)
- **App-specific**: old Prisma migration temp dirs

Logs to `/var/log/server-cleanup.log`. Last run freed ~1.6 GB.

## Files

| File | Where it lives | Purpose |
|---|---|---|
| `deploy-watchdog.sh` | VPS: `/usr/local/bin/` | Checks for missed deploys, triggers Coolify |
| `server-cleanup.sh` | VPS: `/usr/local/bin/` | Weekly Docker/system cleanup |
| `pre-push` | Local: `~/.config/git/hooks/` | Notifies VPS of each push |
| `systemd/deploy-watchdog.timer` | VPS: `/etc/systemd/system/` | Runs watchdog every 2 min |
| `systemd/deploy-watchdog.service` | VPS: `/etc/systemd/system/` | Watchdog service wrapper |
| `systemd/server-cleanup.timer` | VPS: `/etc/systemd/system/` | Runs cleanup daily at 23:00 UTC |
| `systemd/server-cleanup.service` | VPS: `/etc/systemd/system/` | Cleanup service wrapper |
| `install.sh` | Local | Deploys everything to VPS |
| `.env` | VPS: `/etc/deploy-watchdog.env` | Coolify token and config |

## Other cron jobs on the VPS

Not managed by this project, but documented here for reference:

| Schedule | Command | Purpose |
|---|---|---|
| `* * * * *` | `curl .../api/cron/notifications` | Workhub push notification check (every minute) |

## Logs

```bash
# Watchdog (auto-trimmed to 500 lines)
ssh your-server 'cat /root/.deploy-watchdog/watchdog.log'

# Server cleanup
ssh your-server 'cat /var/log/server-cleanup.log'
```
