#!/usr/bin/env bash
# Installs (or updates) the relay on a Debian machine. Run it there, as a user
# with sudo, from the directory holding the exported binary.
#
#   ./install.sh memorandum-relay [bind-address] [port]
set -euo pipefail

BINARY="${1:-memorandum-relay}"
BIND="${2:-127.0.0.1}"
PORT="${3:-8080}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo useradd --system --no-create-home --shell /usr/sbin/nologin memorandum 2>/dev/null || true
sudo install -d -o root -g root -m 755 /opt/memorandum-relay
sudo install -o root -g root -m 755 "$BINARY" /opt/memorandum-relay/memorandum-relay

sudo install -o root -g root -m 644 "$HERE/memorandum-relay.service" /etc/systemd/system/memorandum-relay.service
printf 'RELAY_PORT=%s\nRELAY_BIND=%s\n' "$PORT" "$BIND" | sudo tee /etc/default/memorandum-relay > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable --now memorandum-relay
sudo systemctl restart memorandum-relay
sleep 1
systemctl --no-pager --lines=10 status memorandum-relay
