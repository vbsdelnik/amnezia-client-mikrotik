# AmneziaWG Docker Client for MikroTik RouterOS

Docker container with AmneziaWG client intended for deployment on MikroTik RouterOS Container subsystem.

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

Official image:

```bash
docker pull vbsdelnik/amneziawg-client-arm:latest
```

Repository:

```text
https://hub.docker.com/r/vbsdelnik/amneziawg-client-arm
```

---

# Project Structure

```text
.
├── README.md
└── arm/
    ├── Dockerfile
    ├── build.sh
    └── start.sh
```

Only the ARMv7 build directory currently exists. ARM64 and AMD64 builds are planned.

---

# Supported Architectures

| Architecture | Status    |
| ------------ | --------- |
| ARMv7        | Supported |
| ARM64        | Planned   |
| AMD64        | Planned   |

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
| LOCAL_NET         | No       | —       | LAN network located behind MikroTik           |
| HANDSHAKE_TIMEOUT | No       | 30      | Time in seconds to wait for initial handshake |
| PING_TARGET       | No       | 1.1.1.1 | IP address used for connectivity verification |

Example:

```routeros
/container/envs
add list=amneziawg key=LOCAL_NET value=192.168.X.0/24
add list=amneziawg key=HANDSHAKE_TIMEOUT value=60
add list=amneziawg key=PING_TARGET value=8.8.8.8
```

Environment variables are used by `start.sh`:

```bash
HANDSHAKE_TIMEOUT="${HANDSHAKE_TIMEOUT:-30}"
PING_TARGET="${PING_TARGET:-1.1.1.1}"
```

If `LOCAL_NET` is specified, the container automatically installs route:

```bash
ip route replace "${LOCAL_NET}" via "${REAL_GW}"
```

`REAL_GW` is the container default gateway captured before the VPN starts (172.18.20.5 in the topology below). This route directs return traffic toward the LAN through MikroTik rather than back into the tunnel. Server routing and forwarding must also be configured as described below.

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

Create envlist:

```routeros
/container/envs
add list=amneziawg key=LOCAL_NET value=192.168.X.0/24
add list=amneziawg key=HANDSHAKE_TIMEOUT value=60
add list=amneziawg key=PING_TARGET value=8.8.8.8
```

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
    start-on-boot=yes
```

Start container:

```routeros
/container/start 0
```

View logs:

```routeros
/log/print where message~"amneziawg"
```

---

# MikroTik Routing

Route LAN traffic through the container:

```routeros
/ip/route
add dst-address=0.0.0.0/0 gateway=172.18.20.6 routing-table=amnezia
```

Create routing rules according to your deployment requirements.

---

# Routed Networks Behind MikroTik

The recommended deployment model uses routing instead of NAT.

Example:

```text
LAN behind MikroTik:

192.168.X.0/24

AWG client:

10.8.1.17
```

On the VPS server, update client peer configuration:

```ini
[Peer]
PublicKey = <client-public-key>
AllowedIPs = 10.8.1.17/32,192.168.X.0/24
```

The server must also have a route to the LAN through its AWG interface (named `awg0` in this example):

```text
192.168.X.0/24 dev awg0
```

Updating peer `AllowedIPs` alone does not install a Linux route when using `awg set` or `awg setconf`. A configuration manager such as `awg-quick` may install the route depending on its routing settings; verify the actual server routing table.

For routed LAN traffic, verify all of the following:

* The server peer `AllowedIPs` includes both the client tunnel address and LAN subnet.
* The server route points the LAN subnet into the AWG interface.
* `LOCAL_NET` is set so the client container installs the LAN return route through MikroTik.
* IPv4 forwarding is enabled in the container and on the server, and forwarding rules allow the required traffic. `start.sh` does not enable IP forwarding itself.
* MikroTik routes the selected LAN traffic to the container and permits the return path.

No NAT is required inside the client container for this routed topology. Server-side NAT may still be needed for LAN access to the public Internet, depending on upstream routing.

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

Go to architecture directory:

```bash
cd arm
```

Build image:

```bash
./build.sh
```

---

# Verify Build

List images:

```bash
docker image ls
```

Verify architecture:

```bash
docker run --rm \
  --entrypoint sh \
  vbsdelnik/amneziawg-client-arm:latest \
  -c 'uname -m'
```

Expected:

```text
armv7l
```

Verify installed binaries:

```bash
docker run --rm \
  --entrypoint sh \
  vbsdelnik/amneziawg-client-arm:latest \
  -c '
    which awg
    which awg-quick
    which amneziawg-go
  '
```

---

# Run Locally

```bash
docker run --rm -it \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -v $(pwd)/awg.conf:/config/awg.conf:ro \
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

Container logs:

```routeros
/log/print where message~"amneziawg"
```

---

# Runtime Checks

At startup, `start.sh` waits up to `HANDSHAKE_TIMEOUT` seconds for a nonzero `latest-handshakes` timestamp on `awg`. Zero means that no successful handshake has been recorded for that peer since its creation. A timeout produces a warning; the subsequent connectivity ping must succeed or the startup script exits.

The Docker HEALTHCHECK checks the same interface every 30 seconds. It succeeds when at least one peer has a nonzero handshake timestamp. This confirms a past handshake, not current connectivity: the timestamp remains nonzero after a connection is lost.

After startup, the script waits with `tail -f /dev/null`; it does not periodically ping or supervise the VPN process. Docker marks a failed HEALTHCHECK as unhealthy but does not restart the container solely for that status. Do not assume RouterOS executes Docker HEALTHCHECK metadata; verify monitoring and restart behavior on the deployed RouterOS version.

---

# Upgrading

Pull latest image:

```bash
docker pull vbsdelnik/amneziawg-client-arm:latest
```

Push newly built image:

```bash
docker push vbsdelnik/amneziawg-client-arm:latest
```

---

# License

This repository contains Docker build and deployment files only.

AmneziaWG components are distributed under their respective licenses:

* https://github.com/amnezia-vpn/amneziawg-go
* https://github.com/amnezia-vpn/amneziawg-tools

