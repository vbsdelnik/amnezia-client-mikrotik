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
├── arm/
│   ├── Dockerfile
│   ├── build.sh
│   └── start.sh
├── arm64/
│   ├── Dockerfile
│   ├── build.sh
│   └── start.sh
└── ...
```

Each architecture has its own build directory.

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
DNS = 1.1.1.1
PrivateKey = <client-private-key>

[Peer]
PublicKey = <server-public-key>
PresharedKey = <preshared-key>
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

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
ip route add ${LOCAL_NET} via 172.18.20.5
```

This allows traffic returning from the VPN server to reach networks located behind MikroTik without using NAT.

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
                   veth-awg
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
    address=172.18.20.5/30 \
    gateway=172.18.20.6
```

Addresses:

| Device    | Address        |
| --------- | -------------- |
| MikroTik  | 172.18.20.5/30 |
| Container | 172.18.20.6/30 |

---

# Mount Configuration

Create mount:

```routeros
/container/mounts
add \
    name=amnezia-config \
    src=disk1/config/amneziawg \
    dst=/config
```

Directory structure:

```text
disk1/config/amneziawg/
└── awg.conf
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
    root-dir=disk1/amneziawg \
    mounts=amnezia-config \
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

After applying configuration, the server automatically installs route:

```text
192.168.X.0/24 dev awg0
```

This allows direct communication with hosts located behind MikroTik.

No NAT is required.

---

# Server Side Configuration

Verify peer configuration:

```bash
docker exec amnezia-awg2 awg show
```

Expected:

```text
peer: <client-public-key>
allowed ips: 10.8.1.17/32, 192.168.X.0/24
```

Verify route:

```bash
docker exec amnezia-awg2 ip route
```

Expected:

```text
192.168.X.0/24 dev awg0
```

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

