#!/bin/bash
# Office layer startup. Runs on every container start, as root, before the desktop services.
# The box starts this image with --rm, so the desktop is always rebuilt clean. Only the
# shared Claude Code login survives, because the host mounts it at /config/.claude-shared.
set -e

LOG=/config/logs/office-setup.log
SHARED=/config/.claude-shared
mkdir -p /config/logs
log() { echo "[office] $(date '+%F %T') $*" | tee -a "$LOG"; }

# Claude Code reads ~/.claude and ~/.claude.json. Point both at the shared copy on the host.
if [ -d "$SHARED" ]; then
  mkdir -p "$SHARED/dot-claude"
  [ -f "$SHARED/claude.json" ] || echo '{}' > "$SHARED/claude.json"
  ln -sfn "$SHARED/dot-claude" /config/.claude
  ln -sfn "$SHARED/claude.json" /config/.claude.json
  chown -R 1000:1000 "$SHARED"
  log "shared Claude login linked from $SHARED"
else
  log "no shared login mount; Claude login will not persist after this session"
fi

# Start freddie with the desktop session. It listens on 127.0.0.1:3080 inside the container.
install -d -o 1000 -g 1000 /config/.config/autostart
cat > /config/.config/autostart/freddie.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Freddie
Exec=bash -lc 'cd /opt/office/freddie && exec pnpm freddie web --no-open >> /config/logs/freddie.log 2>&1'
X-GNOME-Autostart-enabled=true
DESK
chown 1000:1000 /config/.config/autostart/freddie.desktop
log "freddie autostart written"
