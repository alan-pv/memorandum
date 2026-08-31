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
Three ways to get one, in the order they are worth trying.

### Cloudflare Tunnel and a domain of your own

The recommended route. Nothing is opened on the router, the tunnel dials *out*
to Cloudflare, and Cloudflare terminates TLS for the domain — so it works behind
CGNAT and the home IP address never appears in a DNS record.

    sudo apt-get install cloudflared          # from pkg.cloudflare.com
    cloudflared tunnel login                  # one click in a browser
    cloudflared tunnel create memorandum-relay
    cloudflared tunnel route dns memorandum-relay play.example.com

Then `cloudflared.example.yml` becomes `/etc/cloudflared/config.yml`, and
`sudo cloudflared service install` turns it into a systemd service.

Two things it does not share with the Funnel below. Cloudflare **does not strip
the path prefix**, so Godot is handed `/ws` rather than `/` — it accepts either,
but a proxy that strips and one that does not are not interchangeable. And
Cloudflare closes a WebSocket it believes has been idle for around 100 seconds,
which is why the protocol carries its own keepalive.

The credentials JSON that `tunnel create` writes is a private key for the
tunnel. It stays in `/etc/cloudflared/` and never enters the repository.

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

**It cannot be tested from a machine on the tailnet.** MagicDNS resolves the
`ts.net` name to the tailnet address, so a device running Tailscale reaches the
relay over the tailnet and never touches the public ingress at all — the one
device that proves nothing is your own. Worse, a device whose Tailscale is
logged out or expired resolves the name to an address it cannot reach and fails
where a stranger with no Tailscale at all would have succeeded. Test it by
resolving the name against a public resolver and connecting to *that* address:

    dig +short @1.1.1.1 A <machine>.<tailnet>.ts.net

A domain of your own has none of this problem, which is the real argument for
moving off `ts.net` once something is published.

### A reverse proxy on the machine itself

Caddy or nginx terminating TLS on the Pi, with the router forwarding 80 and 443.
It works, and it is what the deploy files here used to cover, but it is strictly
worse than the tunnel above: it needs the router configured, it fails outright
behind CGNAT, it puts the home IP address in a public DNS record, and the
certificate becomes yours to keep renewing. Set `RELAY_BIND=127.0.0.1` and point
the proxy at it, exactly as the tunnel does.

## Watching it

    systemctl status memorandum-relay
    journalctl -u memorandum-relay -f

Every room created, joined, started and closed is logged, plus a heartbeat every
five minutes with the peer and room count.
