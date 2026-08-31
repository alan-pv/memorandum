#!/usr/bin/env bash
# Tells DuckDNS the current public address. Run it from a systemd timer or cron
# every five minutes; a home connection changes address without warning.
#
#   sudo install -m 755 duckdns-update.sh /usr/local/bin/duckdns-update
#   */5 * * * * /usr/local/bin/duckdns-update >> /var/log/duckdns.log 2>&1
set -euo pipefail
# shellcheck source=/dev/null
source /etc/default/duckdns
curl -fsS "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip="
echo " $(date -Is)"
