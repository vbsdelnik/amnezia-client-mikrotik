# AmneziaWG Docker Client

Docker container with an AmneziaWG client for Linux Docker environments and MikroTik RouterOS.

Originally developed for the MikroTik RouterOS Container subsystem, the project also supports deployment on AMD64 Linux hosts with Docker Engine.

The networking examples in this README use MikroTik RouterOS. For other environments, apply equivalent network settings appropriate to your setup.

## Features

* AmneziaWG userspace implementation
* Automatic tunnel startup
* Automatic route management
* Handshake verification
* Internet connectivity verification
* External configuration via mounted file
* Routed LAN support
* Optional automatic LAN route installation
* Configurable handshake timeout
* Configurable connectivity check target
* No NAT required inside the client container
* Suitable for RouterOS container subsystem and Linux Docker environments

## Choose Your Deployment

Use an existing image:

* [MikroTik Container Deployment](#mikrotik-container-deployment)
* [Linux Container Deployment](#linux-container-deployment)

Build your own image:

* [Building from Source](#building-from-source)

For routed LAN traffic, follow [LAN Networks Behind MikroTik](#lan-networks-behind-mikrotik--optional) for the configuration steps.

## Images and Supported Architectures

| Architecture | Status | Docker Hub image |
| --- | --- | --- |
| ARMv7 | Supported | [vbsdelnik/amneziawg-client-arm](https://hub.docker.com/r/vbsdelnik/amneziawg-client-arm) |
| AMD64 | Supported | [vbsdelnik/amneziawg-client-amd64](https://hub.docker.com/r/vbsdelnik/amneziawg-client-amd64) |
| ARM64 | Planned | — |

Both images use the same configuration path, environment variables and startup logic.

You do not need to build the image to use it. RouterOS downloads the selected image during container creation; Docker Engine downloads it when starting the container if it is not available locally.

---

# MikroTik Container Deployment

## RouterOS Network Topology

Example deployment:

```text
                    Internet
                        |
                        |
                 AWG VPS Server
                    10.8.1.0/24
                        |
                        |
                  AWG Tunnel
                        |
                        |
        +--------------------------------+
        |      AWG Container             |
        |      Tunnel: 10.8.1.17/32       |
        |      veth:   172.18.20.6/30     |
        +--------------------------------+
                        |
                        |
        +--------------------------------+
        |      MikroTik Router           |
        |      veth: 172.18.20.5/30       |
        |      LAN:  192.168.X.1/24       |
        +--------------------------------+
                        |
                        |
                 192.168.X.0/24
                    Local LAN
```

`172.18.20.5` is the MikroTik address used as the container's original gateway. It belongs to the same MikroTik router that serves the LAN.

Replace `X` with your LAN subnet value. The LAN address is an example; keep your existing LAN configuration.

## RouterOS Prerequisites and Limitations

Before deployment:

* Install the Container package for your RouterOS version and architecture.
* Enable container support in device mode, following the confirmation procedure for your device.
* Ensure the container can reach the VPN server through MikroTik and that the required TUN access is available on your RouterOS version.
* Ensure there is enough storage for the image and container files.

Configure Docker Hub as the image registry if it is not already configured:

```routeros
/container/config
set registry-url=https://registry-1.docker.io
```

RouterOS container subsystem may not provide full netfilter support.

The following may be unavailable:

* iptables
* iptables-restore
* nftables

Because of this, routed networking is preferred over NAT inside the client container.

See the [MikroTik Container documentation](https://help.mikrotik.com/docs/spaces/ROS/pages/84901929/Container) for the prerequisites and options supported by your RouterOS version.

## Deployment Steps

To deploy the container:

1. [Create the veth interface](#creating-veth-interface).
2. [Prepare the AWG client configuration](#example-awg-client-configuration).
3. [Configure the mount](#mount-configuration).
4. [Create the environment list](#environment-list).
5. [Create and start the container](#create-and-start-the-container).
6. [Verify the connection](#verify-the-connection).

For traffic from other devices, complete [LAN Networks Behind MikroTik](#lan-networks-behind-mikrotik--optional).

## Creating veth Interface

Create veth interface on RouterOS:

```routeros
/interface/veth
add \
    name=veth-awg \
    address=172.18.20.6/30 \
    gateway=172.18.20.5
```

The veth `address` is assigned to the container. The `gateway` must be an address configured on MikroTik on the connected container network; creating the veth alone does not assign that gateway address to RouterOS.

For this example, assign the gateway address directly to `veth-awg` if it is not already configured:

```routeros
/ip/address
add address=172.18.20.5/30 interface=veth-awg
```

This example uses a direct veth connection. If the veth is attached to a bridge, configure the gateway on the appropriate bridge instead. Do not add a duplicate address.

Addresses:

| Device    | Address        |
| --------- | -------------- |
| MikroTik  | 172.18.20.5/30 |
| Container | 172.18.20.6/30 |

## Example AWG Client Configuration

The container expects an external AWG configuration file:

```text
/config/awg.conf
```

The configuration is mounted from the host and is not embedded into the image. On RouterOS, the examples use `/awg.conf` as the source file.

Use the client profile exported for your server. The following example shows the configuration structure:

```ini
[Interface]
Address = 10.8.1.17/32
Table = off
DNS = 1.1.1.1, 1.0.0.1
MTU = 1376
PrivateKey = <client-private-key>

[Peer]
PublicKey = <server-public-key>
PresharedKey = <preshared-key>
Endpoint = 203.0.113.10:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

Replace the example endpoint with the server IPv4 address and UDP port. The current startup parser expects `Endpoint = IPv4:port` with the spacing shown above; hostname and IPv6 endpoints are not supported by this startup path.

Include the AmneziaWG parameters exported for the target server; the example alone is not a complete AmneziaWG 3.1 profile.

`Table = off` is intentional: `awg-quick` does not install routes. `start.sh` adds a host route to the endpoint through the original gateway, adds the optional LAN routes, then replaces the container IPv4 default route with `default dev awg`. This keeps encrypted endpoint traffic outside the tunnel while sending other container traffic through it. It does not change the RouterOS routing tables.

Before bringing up the tunnel, the script removes `/etc/resolv.conf` or clears its contents if the file cannot be removed, then runs `resolvconf -u`. `awg-quick` applies the configuration DNS using openresolv.

## Mount Configuration

Place `awg.conf` at `/awg.conf` on RouterOS and mount the file into the container:

```routeros
/container/mounts
add \
    comment=awgconf \
    src=/awg.conf \
    list=amnezia-config \
    dst=/config/awg.conf
```

## Environment List

The container supports optional environment variables supplied through RouterOS `envlist`.

| Variable          | Required | Default | Description                                   |
| ----------------- | -------- | ------- | --------------------------------------------- |
| LOCAL_NET         | No       | —       | LAN IPv4 addresses or CIDRs, separated by commas           |
| HANDSHAKE_TIMEOUT | No       | 30      | Time in seconds to wait for initial handshake |
| PING_TARGET       | No       | 1.1.1.1 | IP address used for connectivity verification |
| DEBUG             | No       | 0       | Set to 1 to print startup diagnostics         |

Example (create the envlist once and replace `X` with your LAN subnet value):

```routeros
/container/envs
add list=amneziawg key=LOCAL_NET value=192.168.X.0/24
add list=amneziawg key=HANDSHAKE_TIMEOUT value=60
add list=amneziawg key=PING_TARGET value=8.8.8.8
```

The container uses this list through `envlist=amneziawg`.

**Version compatibility:** Multiple addresses or subnets in `LOCAL_NET` are supported only in this project's 3.1 images. The 2.1 images support a single address or subnet only. This is a difference in the container startup script, not a limitation of the AmneziaWG protocol.

`LOCAL_NET` accepts one IPv4 address or subnet, or a comma-separated list. Existing single-subnet values continue to work. Spaces around entries are allowed; an address without a prefix is treated as `/32`. All entries use the same original container gateway.

For multiple entries, use this value instead of the single-subnet `LOCAL_NET` example above (replace `X` and `Y` with your values):

```routeros
/container/envs
add list=amneziawg key=LOCAL_NET value="192.168.X.0/24,192.168.Y.0/24,10.10.10.5"
```

Create only one `LOCAL_NET` entry in the envlist, or edit the existing entry. The script splits the list on commas, trims spaces and skips empty entries. `ip` checks each address or subnet when adding its route. If a route command fails, startup stops; previously added routes are not rolled back. An unset or blank `LOCAL_NET` adds no local routes.

For each address or subnet in `LOCAL_NET`, the container installs a return route through its original gateway (`172.18.20.5` in the RouterOS topology).

These routes direct return traffic toward the local addresses and networks rather than back into the tunnel. Existing routes to the same destinations are replaced; choose entries that do not conflict with the transit network or VPN server endpoint.

`LOCAL_NET` only controls client return routes; it does not configure the server or select MikroTik traffic.

## Create and Start the Container

Create container:

```routeros
/container/add \
    remote-image=vbsdelnik/amneziawg-client-arm:latest \
    interface=veth-awg \
    root-dir=amneziawg \
    mountlists=amnezia-config \
    envlist=amneziawg \
    logging=yes \
    start-on-boot=yes \
    restart-policy=on-failure \
    restart-interval=10s
```

`restart-policy=on-failure` restarts the container after a failure, with a 10-second delay between attempts. `start-on-boot=yes` starts it after the router boots. This does not detect a lost VPN connection while the container process is still running.

**RouterOS version compatibility:** The restart parameters above require RouterOS **7.23 or newer**. On RouterOS **7.20–7.22**, replace both `restart-policy=on-failure` and `restart-interval=10s` with:

```routeros
auto-restart-interval=10s
```

The older parameter is not available before RouterOS 7.20. See the [RouterOS 7.23 changelog](https://forum.mikrotik.com/t/v7-23-stable-is-released/270721/1) for the new restart parameters.

Wait for image download/extraction to finish, then check `/container/print` and start the correct container. The example uses index `0`; replace it with your container's index:

```routeros
/container/print
/container/start 0
```

## Verify the Connection

View container logs (`logging=yes` must be enabled). This shows messages for all containers:

```routeros
/log/print where topics~"container"
```

Open the client container shell:

```routeros
/container/shell 0
```

Run inside the container:

```bash
awg show
ip addr show awg
ip route
ping -c 3 1.1.1.1
```

Check that the interface exists, a successful handshake has been recorded and Internet connectivity works.

A successful ping from the container does not verify LAN forwarding. Test traffic from an actual LAN host after completing the routing and server configuration below.

## LAN Networks Behind MikroTik — Optional

The client container routes LAN traffic without NAT. NAT for Internet access is configured in the server container.

Example:

```text
LAN behind MikroTik: 192.168.X.0/24
AWG client address:  10.8.1.17/32
```

For this setup to work:

1. Set `LOCAL_NET` to the LAN addresses or subnets so the client container adds a return route for each through the MikroTik gateway. See [Environment List](#environment-list).
2. Configure the server peer's AllowedIPs, LAN routing and firewall/NAT rules. See [Server Side Configuration](#server-side-configuration).
3. Configure MikroTik to route the selected LAN traffic to the client container and allow return traffic. See [MikroTik Routing](#mikrotik-routing).
4. Test Internet access from an actual LAN host routed through the client.

IPv4 forwarding must be enabled in both the client and server containers, and firewall rules must allow the traffic. The client `start.sh` does not enable forwarding itself.

For multiple entries, include every local address or subnet in the server peer's `AllowedIPs` and configure the corresponding server routes and firewall/NAT rules. Use `/32` for individual addresses.

---

# Linux Container Deployment

For a Debian 13 gateway, [scripts/linux-pbr](scripts/linux-pbr/README.md) provides an installer/uninstaller, shared `settings.conf`, a setup script (`run.sh`) and persistent host policy routing.

The working files are kept together in `/opt/amnezia-client/`; only the systemd unit and sysctl file are installed under `/etc/`.

## Linux Network Topology

Example deployment with an upstream MikroTik router:

```text
                    Internet
                        |
                 AWG VPS Server
                    10.8.1.0/24
                        |
                  AWG Tunnel
                        |
        +--------------------------------+
        |      AWG Container             |
        |      Tunnel: 10.8.1.17/32       |
        |      Docker: 172.18.20.6/30     |
        +--------------------------------+
                        |
        +--------------------------------+
        |      Debian Gateway            |
        |      Docker: 172.18.20.5/30     |
        |      Uplink: 192.168.250.2/24   |
        +--------------------------------+
                        |
        +--------------------------------+
        |      MikroTik Router           |
        |      Transit: 192.168.250.1/24  |
        |      LAN:     192.168.X.1/24    |
        +--------------------------------+
                        |
                 192.168.X.0/24
                    Local LAN
```

MikroTik sends selected traffic to Debian. Debian sends selected transit traffic through the client container using a separate routing table; the host's main routing table is preserved.

The Docker transit subnet is separate from the network between Debian and MikroTik.

## Deploy Using the Linux Setup Kit

Install the files in one pass, fill in settings, then run the setup script separately to start the container and apply forwarding and PBR.

Run the installer as **root** in a Bash shell:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vbsdelnik/amnezia-client-mikrotik/main/scripts/linux-pbr/install.sh)
```

After installation:

1. Fill in `/opt/amnezia-client/settings.conf`.
2. Place the client profile at `AWG_CONFIG` from settings (default: `/opt/amnezia-client/awg.conf`).
3. Run `/opt/amnezia-client/run.sh`.
4. Verify the container connection and host policy routing.

The installer does not run `run.sh` automatically.

Follow the [Linux setup instructions](scripts/linux-pbr/README.md) for prerequisites, settings, verification, persistence after reboot and uninstallation. These files are installed on the Linux host, not inside the VPN image.

Configure the server as described in [Server Side Configuration](#server-side-configuration).

If MikroTik selects the traffic sent to Debian, follow [MikroTik Routing](#mikrotik-routing) using the Debian address as the next hop.

---

# Server Side Configuration

The following instructions apply to the server container `amnezia-awg2`, which loads `/opt/amnezia/awg/awg0.conf` with `awg-quick` and runs the iptables commands in `/opt/amnezia/start.sh` on every startup. Run the commands on the VPS host.

These steps apply to LAN traffic routed through either the RouterOS or Linux client deployment.

Replace `192.168.X.0/24` with your LAN subnet before applying the examples. Keep the actual client tunnel address (shown as `10.8.1.17/32` here) and all other existing AllowedIPs. The examples use `awg0` as the server VPN interface and `eth0` as the server container egress interface.

1. Edit the server configuration and find the client peer by its public key:

   ```bash
   docker exec -it amnezia-awg2 vi /opt/amnezia/awg/awg0.conf
   ```

   Add the LAN subnet to that peer's AllowedIPs:

   ```ini
   [Peer]
   PublicKey = <client-public-key>
   AllowedIPs = 10.8.1.17/32,192.168.X.0/24
   ```

   Keep the peer's keys, other settings and existing AllowedIPs. Add the LAN subnet to the existing AllowedIPs line.

2. Edit the server startup script:

   ```bash
   docker exec -it amnezia-awg2 vi /opt/amnezia/start.sh
   ```

   Add this beside the existing FORWARD rules, before `tail -f /dev/null`:

   ```bash
   iptables -A FORWARD -i awg0 -o eth0 -s 192.168.X.0/24 -j ACCEPT
   ```

   Add this beside the existing NAT rules, also before `tail -f /dev/null`:

   ```bash
   iptables -t nat -A POSTROUTING -s 192.168.X.0/24 -o eth0 -j MASQUERADE
   ```

   Keep the existing rules, including the ESTABLISHED,RELATED forwarding rule. Do not add duplicate LAN rules if they are already present. NAT is performed inside the server container; no NAT is needed inside the client container.

3. Restart the server container to apply both files. This interrupts connections for all clients served by this container:

   ```bash
   docker restart amnezia-awg2
   ```

4. Verify the peer, route and firewall rules:

   ```bash
   docker exec amnezia-awg2 awg show
   docker exec amnezia-awg2 ip route get 192.168.X.1
   docker exec amnezia-awg2 iptables -S FORWARD
   docker exec amnezia-awg2 iptables -t nat -S POSTROUTING
   ```

   The selected peer must include the LAN in AllowedIPs, and the route to a LAN host must use `awg0`. The server starts the interface with `awg-quick`, which can install the route from AllowedIPs depending on its routing settings; verify the result before adding a route manually. Test Internet access from an actual LAN host routed through the client.

For multiple LAN addresses or subnets, repeat the corresponding AllowedIPs and firewall/NAT configuration for every entry.

The shown server startup script recreates the firewall rules directly; it does not load an `iptables-save` file. A separate `iptables-save` is not required for this method. These changes remain after restarting the container. Persistence after container recreation depends on the deployment mounts; keep copies before recreating or upgrading the server container.

---

# MikroTik Routing

MikroTik selects which LAN traffic to send through the VPN.

The next hop depends on the deployment:

| Deployment | MikroTik next hop |
| --- | --- |
| Container on MikroTik | Container address: `172.18.20.6` |
| Container on Debian | Debian address: `192.168.250.2` |

The examples below use table `amnezia`. Replace example addresses and interface names with your values.

## Create the Routing Table

Create the RouterOS routing table if it does not already exist:

```routeros
/routing/table
add name=amnezia fib
```

This table belongs to MikroTik, outside the container. It is separate from the client's `Table = off` setting.

## Add Routes

Use **one** of the following route sets according to your deployment. Each set includes the transit network, the default route through the VPN next hop and the route back to the LAN.

For a container running on MikroTik:

```routeros
/ip/route
add dst-address=172.18.20.4/30 gateway=veth-awg routing-table=amnezia scope=10
add dst-address=0.0.0.0/0 gateway=172.18.20.6 routing-table=amnezia
add dst-address=192.168.X.0/24 gateway=bridge-lan routing-table=amnezia scope=10
```

For a container running on Debian:

```routeros
/ip/route
add dst-address=192.168.250.0/24 gateway=bridge-vpn routing-table=amnezia scope=10
add dst-address=0.0.0.0/0 gateway=192.168.250.2 routing-table=amnezia
add dst-address=192.168.X.0/24 gateway=bridge-lan routing-table=amnezia scope=10
```

Replace `bridge-vpn` with the MikroTik interface connected to Debian and `bridge-lan` with the interface serving the LAN. If `veth-awg` is attached to a bridge, use that bridge for the transit route instead.

The transit route covers the directly connected network containing the VPN next hop. The LAN route sends replies back to the clients instead of through the default route again. Add a route for every LAN network that must be reachable through this table, or omit the example LAN route if it is not needed.

These interface routes describe directly connected networks; they are added as static routes in table `amnezia`. For LAN networks behind another router, use the appropriate next-hop IP address instead of a directly connected interface.

## Select LAN Traffic

Create an address list containing the LAN networks and a list of clients whose traffic should use the VPN.

The example sends traffic from `192.168.X.10` through the VPN:

```routeros
/ip/firewall/address-list
add list=local-nets address=192.168.X.0/24
add list=to-amnezia address=192.168.X.10
```

Add the other local networks to `local-nets` as needed. To select an entire subnet, use its CIDR in `to-amnezia` instead of an individual client address.

Add the mangle rules in the order shown:

```routeros
/ip/firewall/mangle
add \
    action=accept \
    chain=prerouting \
    comment="Skip mangle processing for LAN-LAN traffic" \
    dst-address-list=local-nets \
    in-interface-list=!WAN \
    src-address-list=local-nets

add \
    action=mark-connection \
    chain=prerouting \
    comment="Mark connections from to-amnezia IPs" \
    connection-mark=no-mark \
    in-interface-list=!WAN \
    new-connection-mark=to-amnezia \
    passthrough=yes \
    src-address-list=to-amnezia

add \
    action=mark-routing \
    chain=prerouting \
    comment="Routing marked connections via amnezia routing table" \
    connection-mark=to-amnezia \
    new-routing-mark=amnezia \
    passthrough=no
```

These examples assume an existing interface list named `WAN` containing the Internet-facing interfaces. Place the rules before other mangle rules that would otherwise select a different routing table.

The connection mark applies to both directions. The final rule therefore sends both requests and replies through table `amnezia`. This is why the table must include routes to the LAN networks as well as the VPN default route.

The LAN–LAN rule skips further processing in the mangle chain; it does not bypass the firewall filter.

Adding the default route alone does not select any LAN traffic. Keep the VPN server endpoint reachable through the normal Internet path to avoid sending the tunnel's own traffic back into the tunnel.

Firewall rules must allow forwarding to the VPN next hop and back to the selected LAN clients. Exclude these connections from FastTrack if FastTrack is configured.

See [MikroTik Policy Routing](https://help.mikrotik.com/docs/spaces/ROS/pages/59965508/Policy+Routing) for routing table and traffic selection examples.

## Verify LAN Traffic

Test Internet access from an actual LAN host selected in `to-amnezia`.

Check the routing table and mangle counters:

```routeros
/ip/route/print detail where routing-table=amnezia
/ip/firewall/mangle/print stats
```

If requests leave but replies do not reach the LAN client, check:

* The LAN return routes in table `amnezia`.
* The interface or next hop selected for each LAN route.
* ARP resolution for the client on the correct LAN interface.
* Forwarding firewall rules.

For a directly connected LAN client, a failed ARP entry on the VPN transit interface usually indicates an incorrect LAN route.

---

# Troubleshooting and Runtime Checks

## Container Diagnostics

Run the following Linux commands inside the client container, not on the VPS or in the RouterOS terminal.

On RouterOS, identify the container and open its shell (replace index `0` as needed):

```routeros
/container/print
/container/shell 0
```

On Linux, open the container shell (replace the container name as needed):

```bash
docker exec -it amneziawg-client sh
```

Check handshake:

```bash
awg show
```

Check interface:

```bash
ip addr show awg
```

Check routing:

```bash
ip route
```

Check connectivity:

```bash
ping -c 3 1.1.1.1
```

For logs on RouterOS, return to the RouterOS terminal. Enable logging for the correct container if needed:

```routeros
/container/set 0 logging=yes
/log/print where topics~"container"
```

For logs on Linux:

```bash
docker logs -f amneziawg-client
```

For Linux host routing and systemd diagnostics, see the [Linux setup instructions](scripts/linux-pbr/README.md#check-host-routing).

## Runtime Checks

At startup, `start.sh` waits up to `HANDSHAKE_TIMEOUT` seconds for a nonzero `latest-handshakes` timestamp on `awg`. Zero means that no successful handshake has been recorded for that peer since its creation. A timeout produces a warning; the subsequent connectivity ping must succeed or the startup script exits.

The Docker HEALTHCHECK checks the same interface every 30 seconds. It succeeds when at least one peer has a nonzero handshake timestamp. This confirms a past handshake, not current connectivity: the timestamp remains nonzero after a connection is lost.

After startup, the script waits with `tail -f /dev/null`; it does not periodically ping or supervise the VPN process. Docker marks a failed HEALTHCHECK as unhealthy but does not restart the container solely for that status. Do not assume RouterOS executes Docker HEALTHCHECK metadata; verify monitoring and restart behavior on the deployed RouterOS version.

---

# Building from Source

Use this section if you want to build the image yourself. To deploy an existing image, follow [MikroTik Container Deployment](#mikrotik-container-deployment) or [Linux Container Deployment](#linux-container-deployment).

## Build Requirements

Docker with Buildx is required.

Docker Desktop supports building these platforms through emulation. On other Docker installations, building for a different CPU architecture requires a suitable builder or emulation.

Clone the repository and open its directory before running the commands below.

## Project Structure

```text
.
├── README.md
├── arm/
│   ├── Dockerfile
│   ├── build.sh
│   └── start.sh
├── amd64/
│   ├── Dockerfile
│   ├── build.sh
│   └── start.sh
└── scripts/
    └── linux-pbr/
```

ARMv7 and AMD64 have separate build directories. ARM64 is planned.

Each image contains:

* amneziawg-go
* amneziawg-tools (`awg`, `awg-quick`)
* startup script (`start.sh`)

## Build the Image

Choose the build directory from the repository root:

```bash
# ARMv7
cd arm
```

or:

```bash
# AMD64 (x86-64)
cd amd64
```

Build the image from the selected directory:

```bash
./build.sh
```

Each script loads the image into the local Docker image store. It does not publish it.

| Directory | Platform | Local image |
| --------- | -------- | ----------- |
| `arm/` | `linux/arm/v7` | `vbsdelnik/amneziawg-client-arm:latest` |
| `amd64/` | `linux/amd64` | `vbsdelnik/amneziawg-client-amd64:latest` |

## Verify the Build

List images:

```bash
docker image ls
```

Verify the image architecture without running the container.

ARMv7:

```bash
docker image inspect \
  --format '{{.Os}}/{{.Architecture}}{{if .Variant}}/{{.Variant}}{{end}}' \
  vbsdelnik/amneziawg-client-arm:latest
```

Expected: `linux/arm/v7`.

AMD64:

```bash
docker image inspect \
  --format '{{.Os}}/{{.Architecture}}{{if .Variant}}/{{.Variant}}{{end}}' \
  vbsdelnik/amneziawg-client-amd64:latest
```

Expected: `linux/amd64`. The same format includes the variant when present; ARMv7 uses `v7`, while AMD64 has no variant.

Verify installed binaries using a Docker environment that supports the selected architecture, either natively or through emulation.

ARMv7:

```bash
docker run --rm \
  --platform linux/arm/v7 \
  --entrypoint sh \
  vbsdelnik/amneziawg-client-arm:latest \
  -c '
    set -e
    command -v awg
    command -v awg-quick
    command -v amneziawg-go
    awg --version
    amneziawg-go --version
  '
```

AMD64:

```bash
docker run --rm \
  --platform linux/amd64 \
  --entrypoint sh \
  vbsdelnik/amneziawg-client-amd64:latest \
  -c '
    set -e
    command -v awg
    command -v awg-quick
    command -v amneziawg-go
    awg --version
    amneziawg-go --version
  '
```

`amneziawg-go --version` displays `0.0.20250522` because the version string in the upstream source code is outdated. This image is built from tag `v3.1.20260828`, as specified by `AWG_GO_REF` in the Dockerfile.

These checks verify the image architecture and binary startup. Test VPN connectivity and LAN forwarding with your actual configuration.

## Publish the Image — Optional

To publish a tested build to Docker Hub, choose its image:

```bash
# ARMv7
docker push vbsdelnik/amneziawg-client-arm:latest

# AMD64
docker push vbsdelnik/amneziawg-client-amd64:latest
```

These commands publish to the project repositories and require access to them. For your own Docker Hub repository, change the image tag before publishing.

---

# Updating

## RouterOS

Updating an image on a Docker workstation does not update the container installed on MikroTik. Restarting the RouterOS container alone also does not download a new image.

Keep a copy of `/awg.conf` and record the container's interface, mount list, envlist and root directory. The example uses index `0`; replace it with your container's index. VPN traffic through the container will be interrupted.

Identify the client container and note its index:

```routeros
/container/print detail
```

Stop that container. Replace `0` with the index you identified:

```routeros
/container/stop 0
```

Check its status and wait until it is stopped:

```routeros
/container/print
```

Remove the stopped client container. Use its index from the latest output:

```routeros
/container/remove 0
```

Repeat [Create and Start the Container](#create-and-start-the-container) to download the new image and create the container again. Reuse the existing veth interface, mount list and envlist; do not add them again. Keep the external configuration file. If the old root directory remains, choose a new, unused `root-dir` for the new container.

Check the new container's index before starting it, then [verify the connection](#verify-the-connection) and test traffic from a LAN host.

For version-specific update commands, see the [MikroTik Container documentation](https://help.mikrotik.com/docs/spaces/ROS/pages/84901929/Container).

## Linux Docker

For a deployment using the Linux setup kit, run these commands as **root**. The examples use the default container name and AMD64 image; replace them with `CONTAINER_NAME` and `IMAGE` from settings if changed.

Download the new image before stopping the existing container:

```bash
docker pull vbsdelnik/amneziawg-client-amd64:latest
```

This downloads the image only; an existing Docker container must be recreated to use it.

Stop host PBR, then stop and remove the client container. VPN traffic through it will be interrupted:

```bash
systemctl stop amnezia-pbr.service
docker stop amneziawg-client
docker rm amneziawg-client
```

Keep `/opt/amnezia-client/settings.conf`, the external client profile and the Docker network. Recreate the container using the existing settings:

```bash
/opt/amnezia-client/run.sh
```

The script also reapplies host forwarding and starts PBR. See [Run the setup](scripts/linux-pbr/README.md#run-the-setup) and [Check host routing](scripts/linux-pbr/README.md#check-host-routing) to verify the connection and LAN forwarding.

Updating the Linux setup scripts is separate from updating the image. See the [Linux setup instructions](scripts/linux-pbr/README.md#change-settings-upgrade-or-disable).

---

# License

This repository contains Docker build and deployment files only.

AmneziaWG components are distributed under their respective licenses:

* [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go)
* [amneziawg-tools](https://github.com/amnezia-vpn/amneziawg-tools)
