# AmneziaWG Docker Client

Docker container with an AmneziaWG client for Linux Docker environments and MikroTik RouterOS.

The networking examples in this README use MikroTik RouterOS. For other environments, apply equivalent network settings appropriate to your setup.

The project provides a lightweight container image containing:

* amneziawg-go
* amneziawg-tools (`awg`, `awg-quick`)
* startup script (`start.sh`)
* automatic tunnel initialization
* connectivity validation
* routed LAN support behind MikroTik
* RouterOS Container compatibility

---

# Features

* AmneziaWG userspace implementation
* Automatic tunnel startup
* Automatic route management
* Handshake verification
* Internet connectivity verification
* External configuration via mounted file
* Routed LAN support behind MikroTik
* Optional automatic LAN route installation
* Configurable handshake timeout
* Configurable connectivity check target
* No NAT required inside container
* Suitable for RouterOS container subsystem

---

# Docker Hub

Project image:

```bash
docker pull vbsdelnik/amneziawg-client-arm:latest
```

Repository: [Docker Hub](https://hub.docker.com/r/vbsdelnik/amneziawg-client-arm).

---

# Project Structure

```text
.
├── README.md
├── arm/
│   ├── Dockerfile
│   ├── build.sh
│   └── start.sh
└── amd64/
    ├── Dockerfile
    ├── build.sh
    └── start.sh
```

ARMv7 and AMD64 have separate build directories. ARM64 is planned.

---

# Supported Architectures

| Architecture | Status    |
| ------------ | --------- |
| ARMv7        | Supported |
| ARM64        | Planned   |
| AMD64        | Build verified |

---

# Configuration

The container expects an external AWG configuration file:

```text
/config/awg.conf
```

The configuration is mounted from RouterOS and is not embedded into the image.

---

# Example AWG Client Configuration

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

This example shows the configuration structure only. Include the AmneziaWG parameters exported for the target server; the example alone is not a complete AmneziaWG 3.1 profile.

`Table = off` is intentional: `awg-quick` does not install routes. `start.sh` adds a host route to the endpoint through the original gateway, adds the optional LAN route, then replaces the container IPv4 default route with `default dev awg`. This keeps encrypted endpoint traffic outside the tunnel while sending other container traffic through it. It does not change the RouterOS routing tables.

Before bringing up the tunnel, the script removes `/etc/resolv.conf` and runs `resolvconf -u`; `awg-quick` then applies the configuration DNS using openresolv.

---

# Environment Variables

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

**Version compatibility:** Multiple addresses or subnets in `LOCAL_NET` are supported only in this project's 3.1 images. The 2.1 images support a single address or subnet only. This is a difference in the container startup script, not a limitation of the AmneziaWG protocol.

`LOCAL_NET` accepts one IPv4 address or subnet, or a comma-separated list. Existing single-subnet values continue to work. Spaces around entries are allowed; an address without a prefix is treated as `/32`. All entries use the same original MikroTik gateway.

For multiple entries, use this value instead of the single-subnet `LOCAL_NET` example above (replace `X` and `Y` with your values):

```routeros
/container/envs
add list=amneziawg key=LOCAL_NET value="192.168.X.0/24,192.168.Y.0/24,10.10.10.5"
```

Create only one `LOCAL_NET` entry in the envlist, or edit the existing entry. The script splits the list on commas, trims spaces and skips empty entries. `ip` checks each address or subnet when adding its route. If a route command fails, startup stops; previously added routes are not rolled back. An unset or blank `LOCAL_NET` adds no local routes.

Environment variables are used by `start.sh`:

```bash
HANDSHAKE_TIMEOUT="${HANDSHAKE_TIMEOUT:-30}"
PING_TARGET="${PING_TARGET:-1.1.1.1}"
```

For each address or subnet in `LOCAL_NET`, the container installs a return route:

```bash
ip -4 route replace "$local_route" via "$REAL_GW" dev "$REAL_IF"
```

`REAL_GW` is the container default gateway captured before the VPN starts (172.18.20.5 in the topology below). These routes direct return traffic toward the local addresses and networks through MikroTik rather than back into the tunnel. Existing routes to the same destinations are replaced; choose entries that do not conflict with the transit network or VPN server endpoint. Server routing and forwarding must also be configured as described below.

---

# RouterOS Network Topology

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
        |      10.8.1.17/32              |
        |      172.18.20.6/30            |
        +--------------------------------+
                        |
                        |
              MikroTik gateway
                 172.18.20.5/30
                        |
                        |
                 MikroTik Router
                        |
                        |
                 192.168.X.0/24
                    Local LAN
```

---

# RouterOS Prerequisites

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

See the [MikroTik Container documentation](https://help.mikrotik.com/docs/spaces/ROS/pages/84901929/Container) for the prerequisites and options supported by your RouterOS version.

---

# Creating veth Interface

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

---

# Mount Configuration

Place `awg.conf` at `/awg.conf` on RouterOS and mount the file into the container:

```routeros
/container/mounts
add \
    comment=awgconf \
    src=/awg.conf \
    list=amnezia-config \
    dst=/config/awg.conf
```

---

# Environment List

Create the `amneziawg` envlist using the example in [Environment Variables](#environment-variables) if you have not already done so. The container uses this list through `envlist=amneziawg`.

---

# Container Deployment

Create container:

```routeros
/container/add \
    remote-image=vbsdelnik/amneziawg-client-arm:latest \
    interface=veth-awg \
    root-dir=amneziawg \
    mountlists=amnezia-config \
    envlist=amneziawg \
    logging=yes \
    start-on-boot=yes
```

Wait for image download/extraction to finish, then check `/container/print` and start the correct container. The example uses index `0`; replace it with your container's index:

```routeros
/container/print
/container/start 0
```

View container logs (`logging=yes` must be enabled). This shows messages for all containers:

```routeros
/log/print where topics~"container"
```

---

# MikroTik Routing

Create the RouterOS routing table if it does not already exist:

```routeros
/routing/table
add name=amnezia fib
```

This table belongs to MikroTik, outside the container. It is separate from the client's `Table = off` setting.

Add the route through the container to this table:

```routeros
/ip/route
add dst-address=0.0.0.0/0 gateway=172.18.20.6 routing-table=amnezia
```

Select the traffic that should use this table with routing rules or mangle marks according to your deployment requirements. Adding the route alone does not select any LAN traffic. Keep the VPN server endpoint reachable through the normal Internet path to avoid sending the tunnel's own traffic back into the tunnel.

See [MikroTik Policy Routing](https://help.mikrotik.com/docs/spaces/ROS/pages/59965508/Policy+Routing) for routing table and traffic selection examples.

---

# Routed Networks Behind MikroTik

The client container routes LAN traffic without NAT. NAT for Internet access is configured in the server container.

Example:

```text
LAN behind MikroTik: 192.168.X.0/24
AWG client address:  10.8.1.17/32
```

Set `LOCAL_NET` to the LAN addresses or subnets so the client container adds a return route for each through the MikroTik gateway. MikroTik selects which LAN traffic to send through the VPN.

For this setup to work:

* The server peer's `AllowedIPs` must include the client tunnel address and LAN subnet.
* The server must have a route to the LAN through its AWG interface.
* IPv4 forwarding must be enabled in both the client and server containers, and firewall rules must allow the traffic. The client `start.sh` does not enable forwarding itself.
* MikroTik must route the selected LAN traffic to the client container and allow return traffic.
* The server container must have a MASQUERADE rule for the LAN subnet to provide Internet access.

For multiple entries, include every local address or subnet in the server peer's `AllowedIPs` and configure the corresponding server routes and firewall/NAT rules. Use `/32` for individual addresses. `LOCAL_NET` only controls client return routes; it does not configure the server or select MikroTik traffic.

See [Server Side Configuration](#server-side-configuration) for server configuration and verification steps.

---

# Server Side Configuration

The following instructions apply to the server container `amnezia-awg2`, which loads `/opt/amnezia/awg/awg0.conf` with `awg-quick` and runs the iptables commands in `/opt/amnezia/start.sh` on every startup. Run the commands on the VPS host.

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

The shown server startup script recreates the firewall rules directly; it does not load an `iptables-save` file. A separate `iptables-save` is not required for this method. These changes remain after restarting the container. Persistence after container recreation depends on the deployment mounts; keep copies before recreating or upgrading the server container.

---

# Building

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

Docker Desktop supports building these platforms through emulation. On other Docker installations, building for a different CPU architecture requires a suitable builder or emulation.

To publish a tested build to Docker Hub, choose its image:

```bash
# ARMv7
docker push vbsdelnik/amneziawg-client-arm:latest

# AMD64
docker push vbsdelnik/amneziawg-client-amd64:latest
```

---

# Verify Build

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

For AMD64, the image build and binary startup have been verified. VPN connectivity and LAN forwarding still require testing with your actual configuration.

---

# Run Locally

The examples below use the ARMv7 image. For AMD64, replace the image name with `vbsdelnik/amneziawg-client-amd64:latest`. Both images use the same configuration path, environment variables and startup logic.

Local startup requires Linux Docker with `/dev/net/tun` and support for the selected image architecture, either native or through emulation. Run it from the directory containing your actual `awg.conf`; this file is not included in the repository.

The local startup example has not been independently verified. The current `start.sh` deletes `/etc/resolv.conf`, which can fail when Docker mounts that file. The RouterOS startup behavior should not be assumed to work unchanged in standard Docker.

```bash
docker run --rm -it \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -v "$(pwd)/awg.conf:/config/awg.conf:ro" \
  vbsdelnik/amneziawg-client-arm:latest
```

---

# RouterOS Container Limitations

RouterOS container subsystem may not provide full netfilter support.

The following may be unavailable:

* iptables
* iptables-restore
* nftables

Because of this, routed networking is preferred over NAT.

---

# Troubleshooting

Run the following Linux commands inside the client container, not on the VPS or in the RouterOS terminal. On RouterOS, identify the container and open its shell (replace index `0` as needed):

```routeros
/container/print
/container/shell 0
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
ping 1.1.1.1
```

For logs, return to the RouterOS terminal. Enable logging for the correct container if needed (replace index `0`):

```routeros
/container/set 0 logging=yes
/log/print where topics~"container"
```

---

# Runtime Checks

At startup, `start.sh` waits up to `HANDSHAKE_TIMEOUT` seconds for a nonzero `latest-handshakes` timestamp on `awg`. Zero means that no successful handshake has been recorded for that peer since its creation. A timeout produces a warning; the subsequent connectivity ping must succeed or the startup script exits.

The Docker HEALTHCHECK checks the same interface every 30 seconds. It succeeds when at least one peer has a nonzero handshake timestamp. This confirms a past handshake, not current connectivity: the timestamp remains nonzero after a connection is lost.

After startup, the script waits with `tail -f /dev/null`; it does not periodically ping or supervise the VPN process. Docker marks a failed HEALTHCHECK as unhealthy but does not restart the container solely for that status. Do not assume RouterOS executes Docker HEALTHCHECK metadata; verify monitoring and restart behavior on the deployed RouterOS version.

---

# Upgrading

Updating an image on a Docker workstation does not update the container installed on MikroTik. Restarting the RouterOS container alone also does not download a new image.

To upgrade on RouterOS:

1. Keep a copy of `/awg.conf` and record the container's interface, mount list, envlist and root directory.
2. Stop the client container. VPN traffic through it will be interrupted.
3. Download and apply the new image using the container update or reimport procedure supported by your RouterOS version. If recreating the container, preserve the external configuration file and reuse the required mount list, envlist and interface settings.
4. Start the container and verify its logs, handshake and connectivity from a LAN host.

For version-specific update commands, see the [MikroTik Container documentation](https://help.mikrotik.com/docs/spaces/ROS/pages/84901929/Container).

To download the latest image on a Docker workstation:

```bash
docker pull --platform linux/arm/v7 vbsdelnik/amneziawg-client-arm:latest
```

This downloads the image only; an existing Docker container must be recreated to use it. Image publication is described in [Building](#building).

---

# License

This repository contains Docker build and deployment files only.

AmneziaWG components are distributed under their respective licenses:

* https://github.com/amnezia-vpn/amneziawg-go
* https://github.com/amnezia-vpn/amneziawg-tools

