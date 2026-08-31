# Putting the relay on a machine

The relay is a standalone Godot project. It knows about peers, rooms and
passwords and forwards everything else without looking inside, so the same
binary serves any game whose clients agree on a `game_id`.

## Build

From the repository root, with the Godot editor binary on hand:

    godot --headless --path server/ --export-release "Linux ARM64" build/relay/memorandum-relay

The preset embeds the pack, so the result is one file and nothing beside it.
For a different machine, add a preset with the matching architecture.

## Install

Copy the binary and this folder to the target, then:

    ./install.sh memorandum-relay 127.0.0.1 8080

It creates a `memorandum` system user, installs the binary under
`/opt/memorandum-relay`, writes the systemd unit and starts it. Running it again
updates the binary in place.

Where it listens is one line in `/etc/default/memorandum-relay`:

| `RELAY_BIND` | Who can reach it |
|---|---|
| `127.0.0.1` | only this machine — correct once something else terminates TLS |
| a tailnet address | the tailnet and nowhere else, over plain `ws://` |
| `0.0.0.0` | everything the machine can be reached on |

## Facing the internet

A browser on an `https://` page refuses to open a `ws://` socket, so anything
published needs `wss://`, which needs a certificate, which needs a domain name.
Two ways to get one.

### Tailscale Funnel

No router to touch, no certificate to manage:

    sudo tailscale funnel --bg --set-path=/ws 8080

That publishes `https://<machine>.<tailnet>.ts.net/ws`, and the client connects
to the same URL with `wss://`. The Funnel config survives reboots; turn it off
with `tailscale funnel --https=443 off`.

**Use a path, not the root.** With the relay served at `/`, every crawler that
finds the host reaches the WebSocket server and Godot logs
*"Missing or invalid header 'upgrade'"* for each one — a couple a minute, all
day. Under `/ws`, Tailscale answers those with a 404 and they never arrive.

It needs two things enabled for the tailnet, both in the admin console: HTTPS
certificates (DNS page) and Funnel itself — running the command above prints the
exact link when it is missing.

### Caddy and a domain of your own

`Caddyfile.example` has the site block, for both the HTTP-01 challenge and the
DNS-01 one you need when the ISP blocks port 80. `duckdns.env.example` and
`duckdns-update.sh` cover a dynamic address. Set `RELAY_BIND=127.0.0.1` first:
from then on the thing facing the internet is Caddy, not the game server.

The real `Caddyfile` and `duckdns.env` are in `.gitignore`. The DNS token is a
password and does not belong in a repository.

## Watching it

    systemctl status memorandum-relay
    journalctl -u memorandum-relay -f

Every room created, joined, started and closed is logged, plus a heartbeat every
five minutes with the peer and room count.
