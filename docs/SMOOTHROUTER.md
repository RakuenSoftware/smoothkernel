# SmoothRouter

Router flavor — headless, CLI-administrable, primary management via web UI. Greenfield: the product repo does not exist yet.

## What it is

A Debian-based router that replaces the typical "consumer router firmware + FreeBSD-based pfSense/OPNsense" choice for people who want:

- The full Linux networking stack (nftables, unbound, Kea, wireguard, strongSwan, FRR) under a browser-driven admin UI
- Packages from real Debian, not a frozen BSD port tree
- The same kernel as SmoothNAS (so the same RMA tooling, driver coverage, and firmware baseline works for both)

Not trying to match consumer routers on hardware cost; target audience is homelab / small office / prosumer.

## Stack

**Networking:**
- `nftables` — packet filter + NAT (not iptables)
- `unbound` — recursive DNS resolver (primary); optionally `dnsmasq` for the forwarder + DHCP combo case
- `kea-dhcp-server` — DHCPv4 + DHCPv6 (ISC's successor to isc-dhcp-server; modern, JSON-configurable)
- `wireguard` — primary VPN
- `strongswan` (optional) — IPsec for interop
- `frr` (optional) — BGP/OSPF for users who want dynamic routing
- `conntrack-tools`, `iproute2`, `ethtool`, `tcpdump` — diagnostics

**Management:**
- `smoothrouterd` — Go + CGO backend, matches `tierd` pattern (single daemon, REST API, SQLite state, background jobs for applying config changes)
- `smoothrouter-ui` — React + `@rakuensoftware/smoothgui` frontend
- `nginx` — reverse proxy with TLS (generated on first boot, same pattern as SmoothNAS)
- `smoothrouter-setup` — first-boot CLI wizard

## Suite composition (`smoothrouter` suite)

| Package | Purpose |
|---|---|
| `smoothrouter` | Meta — pulls kernel + tuning + daemon + UI + networking stack |
| `smoothrouter-tuning` | sysctl + udev + tuned profile |
| `smoothrouterd` | Go backend daemon |
| `smoothrouter-ui` | React frontend static assets |
| `smoothrouter-setup` | First-boot CLI wizard |

From `common`: `linux-smoothkernel`, `linux-firmware-smooth`, `smooth-base`.

## Meta-package dependencies

```
Depends:
 linux-image-smoothkernel,
 linux-firmware-smooth,
 smooth-base,
 smoothrouter-tuning,
 smoothrouterd,
 smoothrouter-ui,
 smoothrouter-setup,
 nftables,
 unbound,
 kea-dhcp-server,
 kea-admin,
 wireguard,
 conntrack,
 iproute2,
 ethtool,
 tcpdump,
 vnstat,
 nginx,
 openssh-server
Recommends:
 strongswan,
 frr,
 bird2,
 iperf3
```

No graphical deps.

## The first-boot wizard problem

A router's web UI binds to the LAN interface. On first boot, the router doesn't know which interface *is* the LAN yet. Binding to a WAN interface by default would expose the admin panel to the internet — unacceptable.

Default state at first boot:

- All interfaces DOWN except loopback
- `smoothrouterd` not running
- `nginx` not running
- Admin login on the serial/HDMI console runs `smoothrouter-setup` automatically (bashrc hook on first login)

`smoothrouter-setup` walks through:

1. Identify interfaces (`ip link show`), prompt which is WAN and which is LAN (or select "single-interface router-on-a-stick").
2. Configure LAN: IP address, netmask, DHCP range for Kea.
3. Configure WAN: DHCP (default), static, or PPPoE.
4. Set admin password for the web UI.
5. Generate TLS cert for `nginx`.
6. Enable and start `smoothrouterd` and `nginx`.
7. Print the LAN URL for follow-up admin.

After that, web UI is the primary interface. The wizard script runs only on first login; subsequent logins drop to a normal shell.

## smoothrouterd responsibilities

Same architectural shape as `tierd`:

- REST API at `127.0.0.1:<port>` (nginx proxies `/api` to it)
- SQLite state under `/var/lib/smoothrouter/`
- Background job queue for slow/destructive ops (wireguard peer add, Kea restart, nftables ruleset reload)
- Monitor/alert surface (interface up/down, DHCP lease exhaustion, wireguard handshake timeouts)
- Version/update flow reading from the `smoothrouter` apt suite

What it orchestrates:

- `nftables` ruleset generation (writes `/etc/nftables.conf`, reloads)
- `kea-dhcp-server` config generation (writes Kea's JSON config, restarts service)
- `unbound` config (writes `/etc/unbound/unbound.conf.d/smoothrouter.conf`)
- `wireguard` interface lifecycle (`wg-quick up/down`, config file management)
- Interface configuration (via `systemd-networkd` or `NetworkManager` — pick one; leaning systemd-networkd for less moving parts on a router)

What it does not do:

- Re-implement packet filtering. nftables does the packet path; smoothrouterd writes the rules and never touches packets.
- Re-implement DHCP / DNS. Kea and unbound do the work.
- Talk to shell scripts from the UI. UI talks to smoothrouterd; smoothrouterd owns the subprocess interface.

## Security posture

- Web UI binds to LAN interfaces only. Never WAN. Enforced at nginx config level and cross-checked by `smoothrouterd` on interface events.
- SSH on the WAN disabled by default; user can enable explicitly from the UI.
- TLS self-signed by default; ACME (Let's Encrypt) integration via DNS-01 for users with a routable domain — deferred to v2.
- No default admin password. Set via wizard.
- Session tokens in HTTP-only secure cookies; CSRF tokens on mutating requests.
- Audit log of config changes persisted to SQLite.

## Router-specific tuning (`smoothrouter-tuning`)

**Sysctl:**

```
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.netfilter.nf_conntrack_max = 262144
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
```

**tuned profile:** CPU governor `performance` (a router's latency matters more than power).

**udev:** typically no rules needed — routers rarely have block devices that matter.

## Hardware baseline

- 2+ NICs (any speed; modern boxes with 2.5GbE/10GbE well-supported)
- 2GB+ RAM (1GB technically works; 2GB is comfortable with conntrack + wireguard + UI)
- 8GB+ storage for OS + logs
- amd64 only at v1 (arm64 is a strong future target for low-power routers — see [`ARCHITECTURE.md`](ARCHITECTURE.md))

No GPU requirements. No audio requirements.

## Non-goals

- **Replacing enterprise-grade routers.** No carrier-grade NAT, MPLS, session border control, etc.
- **GUI wizardry for BGP/OSPF.** Advanced routing (`frr`) is installable but we don't try to build a GUI for it. Power users use `vtysh`.
- **VoIP / SIP ALG.** Not our business.

## Open questions

- **systemd-networkd vs NetworkManager** for interface management. Leaning systemd-networkd for declarative config and fewer moving parts. NM's only appeal is parity with HTPC/desktop, which doesn't matter on a router.
- **VRF for tenant isolation.** Worth designing if we expect multi-tenant homelab use cases; overkill for single-site. Defer.
- **Mesh / multi-WAN failover.** Common enough to want, complex enough to not want in v1. Plan for v2.
