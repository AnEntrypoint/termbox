#!/bin/bash
# Pull the latest termbox image. Restart the desktop only when the image changed,
# then prune images unused for a week.
set -euo pipefail
IMG=ghcr.io/anentrypoint/termbox:latest
before=$(docker image inspect -f '{{.Id}}' "$IMG" 2>/dev/null || echo none)
docker pull -q "$IMG" >/dev/null
after=$(docker image inspect -f '{{.Id}}' "$IMG")
if [ "$before" != "$after" ]; then
  echo "termbox image updated: restarting desktop"
  systemctl restart termbox.service
fi
docker image prune -af --filter "until=168h" >/dev/null
