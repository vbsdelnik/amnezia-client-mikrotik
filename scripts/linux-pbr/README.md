# Linux client setup

Use this kit on a Debian 13 gateway to run the AWG client and send selected LAN traffic through it. Debian itself keeps its normal gateway.

All settings are in `/etc/amnezia-client/settings.conf`. `run.sh` starts the container, applies forwarding and enables host policy routing through `amnezia-pbr`. Neither script needs editing when you change settings.

## Before installing

* Install Docker Engine, Bash, curl, iproute2 and iptables.
* Docker must use its **iptables backend** with a `DOCKER-USER` chain. `iptables-nft` is supported; Docker's native nftables backend is not.
* Debian must have return routes to the LAN networks. The upstream router must send the selected traffic to Debian.
* Configure the AWG server peer AllowedIPs, LAN routes and Internet NAT as described in the main README.

All LAN networks in `LOCAL_NET` must arrive through `LOCAL_IF`.

## Install

Open a root Bash shell and run:

```bash
sudo -i
bash <(curl -fsSL https://raw.githubusercontent.com/vbsdelnik/amnezia-client-mikrotik/main/scripts/linux-pbr/install.sh)
```

The installer installs all files in one pass and creates `/etc/amnezia-client/settings.conf` if it does not exist. When launched through `bash <(curl ...)`, it also saves an executable `install.sh` in the current directory. Existing settings are kept. You do not need to rerun the installer after filling them in.

## Configure

After installation, edit settings:

```bash
vi /etc/amnezia-client/settings.conf
```

Fill in `LOCAL_IF` and `LOCAL_NET`. Review the defaults and change them if needed:

| Setting | Meaning / default |
| --- | --- |
| `CONTAINER_NAME` | Container name: `amneziawg-client` |
| `IMAGE` | AMD64 image: `vbsdelnik/amneziawg-client-amd64:latest` |
| `AWG_CONFIG` | Client profile: `/opt/amnezia-client/awg.conf` |
| `DOCKER_NETWORK` | Docker network name: `awg-client` |
| `AWG_BRIDGE` | Debian bridge name: `br-awg` |
| `AWG_NETWORK` | Docker transit subnet: `172.18.20.4/30` |
| `AWG_GATEWAY` | Debian address on that bridge: `172.18.20.5` |
| `AWG_IP` | Container address: `172.18.20.6` |
| `LOCAL_IF` | Interface receiving LAN traffic; replace `CHANGE_ME` |
| `LOCAL_NET` | Comma-separated LAN CIDRs; replace `CHANGE_ME` |
| `VPN_TABLE` | Dedicated routing table: `200` |
| `RULE_PRIORITY` | First policy-rule priority: `10000`; one per LAN entry |
| `WAIT_SECONDS` | PBR wait for interfaces and Docker firewall: `60` seconds |
| `HANDSHAKE_TIMEOUT` | Container startup handshake wait: `60` seconds |
| `PING_TARGET` | Container connectivity check: `1.1.1.1` |
| `DEBUG` | Extra container startup logs: `0` (off), `1` (on) |

For example, `LOCAL_NET="192.168.X.0/24,192.168.Y.0/24"` (replace `X` and `Y`). Spaces after commas are allowed. Use `/32` for a single host and do not repeat entries.

Table `200` and priorities starting at `10000` must be free. Check before choosing them:

```bash
ip -4 rule show
ip -4 route show table all
```

After completing settings and placing your client profile at `AWG_CONFIG`, run:

```bash
sudo /opt/amnezia-client/run.sh
```

`run.sh` checks settings and refuses to continue if required values are empty or contain `CHANGE_ME`.

**The installer does not run that command.** It does not start the container or PBR, enable services, or apply forwarding to the running system. Existing settings and sysctl files are kept. Temporary downloads are deleted automatically.

For a local checkout, run this from the repository root instead of the curl command:

```bash
cd scripts/linux-pbr && sudo ./install.sh
```

## Run the setup

Place your full client profile at `AWG_CONFIG` (the default path is shown below). Keep the existing `Table = off`, DNS and AWG parameters:

```bash
vi /opt/amnezia-client/awg.conf
chmod 0600 /opt/amnezia-client/awg.conf
sudo /opt/amnezia-client/run.sh
```

If you changed `AWG_CONFIG`, use that path for editing and permissions.

`run.sh` reads the current settings, checks that the profile and TUN device exist, creates the Docker network if needed, and starts the configured image. It passes `LOCAL_NET` to the container and enables forwarding inside the container. Docker automatically assigns `AWG_GATEWAY` to the host bridge. Then `run.sh` applies the host sysctl file, enables the PBR service and restarts it to apply the routing and firewall rules.

The image and its startup logic are unchanged. The network defaults to `awg-client`. If a matching Docker network already exists, it is reused. A network with different settings is not modified. If the bridge is already owned by a differently named Docker network, review that network or set `DOCKER_NETWORK` to its name before running.

An existing container is not replaced or restarted automatically. Use `docker start` for an existing stopped container. Recreate it separately if you need to apply changed container settings.

Check startup and the VPN connection (substitute your container name):

```bash
docker logs -f amneziawg-client
docker exec amneziawg-client awg show awg
```

The container has the `unless-stopped` restart policy. `run.sh` reports success only after the host forwarding and PBR commands also succeed. Check the VPN connection and real LAN traffic separately.

## Check host routing

Host forwarding and PBR are applied by `run.sh`; no separate activation command is needed. To inspect the result:

```bash
amnezia-pbr status
```

The sysctl file restores forwarding at boot. On Debian 13, use `/etc/sysctl.d/`, not `/etc/sysctl.conf`.

PBR matches both `LOCAL_NET` and incoming interface `LOCAL_IF`. It creates a separate table with a default through `AWG_IP`, and tagged forwarding rules in `DOCKER-USER`. The host's `main` table is unchanged; no host NAT is added.

After reboot, Docker restores the network/container and systemd restores PBR. If interfaces or the Docker firewall are not ready, PBR waits up to `WAIT_SECONDS` and systemd retries failed starts after 5 seconds. This wait does not check the VPN handshake.

```bash
systemctl status amnezia-pbr.service --no-pager
journalctl -u amnezia-pbr.service -n 30 --no-pager
```

Verify routing using a real LAN source address and interface:

```bash
ip -4 route get 1.1.1.1 from 192.168.X.10 iif enp1s0
ip -4 route get 1.1.1.1
```

The first query should use the container and VPN table; the second should use Debian's original gateway. Test traffic from an actual LAN host and repeat after a reboot. If routes are correct but packets are dropped, check forwarding and reverse-path filtering.

## Change settings, upgrade or disable

Stop PBR **before** editing settings so cleanup uses the old values:

```bash
systemctl stop amnezia-pbr.service
vi /etc/amnezia-client/settings.conf
```

For changes to container/network settings, recreate the container/network as needed, then run `run.sh`. It also starts PBR. For changes only to routing settings, start PBR after editing:

```bash
systemctl start amnezia-pbr.service
```

For an upgrade, stop PBR first, rerun `install.sh`, and start PBR when ready. The installer updates scripts and service files while preserving settings. An older `pbr.conf` is no longer used: copy its values into `settings.conf` before completing the upgrade.

If you recreate only the network or reload firewall rules, run `systemctl restart amnezia-pbr.service`. There is no periodic reconciliation timer. Repeating `amnezia-pbr apply` does not duplicate rules; conflicting priorities or routes are rejected.

To disable PBR:

```bash
systemctl disable --now amnezia-pbr.service
amnezia-pbr remove
```

This removes the configured PBR rules, tagged firewall rules and two reserved routes. Other tables/rules and `main` are kept. Forwarding, the Docker network and container are left in place. Run `remove` with the original settings if a start failed halfway.

This kit is not a VPN kill switch. If the VPN table has no usable route, traffic may fall back to `main`; blocking outside-VPN traffic needs separate rules.

## Uninstall

Open a root Bash shell and run:

```bash
sudo -i
bash <(curl -fsSL https://raw.githubusercontent.com/vbsdelnik/amnezia-client-mikrotik/main/scripts/linux-pbr/uninstall.sh)
```

Or use the installed copy:

```bash
sudo /opt/amnezia-client/uninstall.sh
```

The uninstaller lists the files it will delete and asks `Proceed? [Y/n]`. Enter `n` to cancel, or `Y`/Enter to continue. It requires a response; an unreadable/closed input cancels removal.

After confirmation, it stops and disables PBR, removes the configured PBR routes and tagged firewall rules, then deletes the installed scripts, service, settings and sysctl file. The legacy `pbr.conf` is removed if present. Empty project directories are removed; directories containing your profile or other files remain.

**Your `awg.conf` is preserved**, including a custom profile path from settings. Docker containers, networks and images are not removed. Forwarding is not switched off in the running system. Stopping PBR interrupts VPN routing for the selected LAN traffic.

The installer records the path and checksum of its saved local `install.sh`. The uninstaller deletes that copy only if it is unchanged. Repository source files and unrelated files are left alone. Older installations without this record may leave a saved installer to remove manually.

Uninstalling before filling in settings is supported. If PBR is still active but its settings are invalid, removal stops so the rules are not left behind without their helper files. Fix settings and rerun the uninstaller.

## Installed files

| File | Destination |
| --- | --- |
| `settings.conf.example` | `/etc/amnezia-client/settings.conf` |
| `run.sh` | `/opt/amnezia-client/run.sh` |
| `uninstall.sh` | `/opt/amnezia-client/uninstall.sh` |
| `common.sh` | `/usr/local/lib/amnezia-client/common.sh` |
| `amnezia-pbr` | `/usr/local/sbin/amnezia-pbr` |
| `amnezia-pbr.service` | `/etc/systemd/system/amnezia-pbr.service` |
| `90-awg-forwarding.conf.example` | `/etc/sysctl.d/90-awg-forwarding.conf` |

The installer also writes `/etc/amnezia-client/install-state.conf` to track its saved copy.

Keep settings root-owned and writable only by root; they are loaded as Bash code. No VPN keys belong in settings: they stay in `awg.conf`.

References: [ip rule](https://man7.org/linux/man-pages/man8/ip-rule.8.html), [Docker firewall](https://docs.docker.com/engine/network/firewall-iptables/), [Debian 13 sysctl changes](https://www.debian.org/releases/trixie/release-notes/issues.html#etc-sysctl-conf-is-no-longer-honored).
