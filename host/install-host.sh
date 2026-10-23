#!/bin/bash
# Host setup for a termbox office box. Runs once inside the new install, from the
# autoinstall late-command (curtin in-target). Re-running it is safe.
set -euo pipefail
REF="${TERMBOX_REF:-main}"
RAW="https://raw.githubusercontent.com/AnEntrypoint/termbox/${REF}/host"
TZ_NAME="${TERMBOX_TZ:-Africa/Johannesburg}"

# Docker keeps images and layers on the large /srv partition, not the 80 GB root.
install -d -m 0755 /etc/docker /srv/docker
cat > /etc/docker/daemon.json <<JSON
{ "data-root": "/srv/docker", "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }
JSON
systemctl enable docker

# Shared Claude Code login. Mounted into every container, so it survives container restarts.
install -d -o 1000 -g 1000 -m 0700 /srv/termbox/claude

# Desktop password for this box, generated once. Read it with: sudo cat /srv/termbox/env
install -d -m 0755 /srv/termbox
if [ ! -f /srv/termbox/env ]; then
  printf 'PASSWORD=%s\nTZ=%s\n' "$(openssl rand -base64 18 | tr -d '/+=')" "$TZ_NAME" > /srv/termbox/env
  chmod 0600 /srv/termbox/env
fi

curl -fsSL "$RAW/termbox.service" -o /etc/systemd/system/termbox.service
curl -fsSL "$RAW/termbox-update.sh" -o /usr/local/sbin/termbox-update
chmod 0755 /usr/local/sbin/termbox-update
curl -fsSL "$RAW/termbox-update.service" -o /etc/systemd/system/termbox-update.service
curl -fsSL "$RAW/termbox-update.timer" -o /etc/systemd/system/termbox-update.timer
systemctl daemon-reload
systemctl enable termbox.service termbox-update.timer
echo "termbox host setup done (ref ${REF})"
