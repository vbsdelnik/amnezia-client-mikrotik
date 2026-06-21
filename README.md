# AmneziaWG Docker Client for MikroTik RouterOS

Docker container with AmneziaWG client intended for deployment on MikroTik RouterOS Container subsystem.

The project builds a lightweight container image containing:

* amneziawg-go
* amneziawg-tools (`awg`, `awg-quick`)
* startup script (`start.sh`)
* support for external AWG configuration file
* automatic route handling
* tunnel validation
* routed LAN support behind MikroTik

---

## Docker Hub

Official image:

```bash
docker pull vbsdelnik/amneziawg-client-arm:latest
```

Docker Hub repository:

```text
https://hub.docker.com/r/vbsdelnik/amneziawg-client-arm
```

---

## Project Structure

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

## Supported Architectures

| Architecture | Status    |
| ------------ | --------- |
| ARMv7        | Supported |
| ARM64        | Planned   |
| AMD64        | Planned   |

---

## Configuration

The container expects an external configuration file:

```text
/config/awg.conf
```

The configuration file is mounted from RouterOS and is **not embedded into the image**.

---

### Example AWG Client Configuration

```ini
[Interface]
Address = 10.8.1.17/32
DNS = 1.1.1.1
PrivateKey = <client-private-key>

[Peer]
PublicKey = <server-public-key>
PresharedKey = <psk>
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

---

## Environment Variables

The container supports optional environment variables supplied through RouterOS `envlist`.

| Variable    | Required | Description                                                 |
| ----------- | -------- | ----------------------------------------------------------- |
| CONFIG_FILE | No       | Path to AWG configuration file. Default: `/config/awg.conf` |
| LOCAL_NET   | No       | LAN network located behind MikroTik                         |

Example:

```routeros
/container/envs
add list=amneziawg key=LOCAL_NET value=192.168.X.0/24
```

When specified, startup script automatically installs route:

```bash
ip route add ${LOCAL_NET} via 172.18.20.5
```

This allows return traffic from the VPN server to reach networks located behind MikroTik without NAT.

---

## RouterOS Network Topology

Typical deployment:

```text
                    Internet
                        |
                        |
               AWG VPS Server
                  10.8.1.0/24
                        |
                        |
                AWG Tunnel (awg)
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

## Creating veth Interface

Create veth interface on RouterOS:

```routeros
/interface/veth
add \
    name=veth-awg \
    address=172.18.20.5/30 \
    gateway=172.18.20.6
```

Container side:

```text
172.18.20.6/30
```

RouterOS side:

```text
172.18.20.5/30
```

---

## Mount Configuration

Create mount:

```routeros
/container/mounts
add \
    name=amnezia-config \
    src=disk1/config/amneziawg \
    dst=/config
```

Directory example:

```text
disk1/config/amneziawg/
└── awg.conf
```

---

## Environment List

Create envlist:

```routeros
/container/envs
add list=amneziawg key=LOCAL_NET value=192.168.X.0/24
```

---

## MikroTik RouterOS Deployment

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

## Routed Networks Behind MikroTik

The recommended deployment model uses routing instead of NAT.

Example:

```text
LAN behind MikroTik:

192.168.X.0/24

AWG client address:

10.8.1.17
```

Server peer configuration:

```ini
[Peer]
PublicKey = <client-public-key>
AllowedIPs = 10.8.1.17/32,192.168.X.0/24
```

After applying configuration, the server automatically installs route:

```text
192.168.X.0/24 dev awg0
```

allowing direct connectivity to the LAN behind MikroTik.

No NAT is required.

---

## Building

Change to the desired architecture directory:

```bash
cd arm
```

Build image:

```bash
./build.sh
```

---

## Verify Build

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

Expected output:

```text
armv7l
```

Verify binaries:

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

## Run Locally

```bash
docker run --rm -it \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -v $(pwd)/awg.conf:/config/awg.conf:ro \
  vbsdelnik/amneziawg-client-arm:latest
```

---

## Features

* AmneziaWG userspace implementation
* Automatic tunnel startup
* Automatic route management
* Tunnel validation
* Health monitoring
* External configuration via mounted file
* Routed LAN support behind MikroTik
* Optional LOCAL_NET route installation
* No NAT required
* Suitable for RouterOS container subsystem

---

## Notes

The image does **not** contain:

```text
/config/awg.conf
```

The configuration file must always be supplied externally.

Startup process is implemented in:

```text
start.sh
```

which is copied into the image and used as container entrypoint.

### RouterOS Container Limitations

RouterOS container subsystem may provide limited netfilter functionality.

The following may be unavailable:

* iptables
* iptables-restore
* nftables

Because of this, routed networking is recommended instead of NAT.

---

## Upgrading

Pull latest image:

```bash
docker pull vbsdelnik/amneziawg-client-arm:latest
```

Push locally built image:

```bash
docker push vbsdelnik/amneziawg-client-arm:latest
```

---

## License

This repository contains only Docker build and deployment files.

AmneziaWG components are distributed under their respective licenses:

* https://github.com/amnezia-vpn/amneziawg-go
* https://github.com/amnezia-vpn/amneziawg-tools

