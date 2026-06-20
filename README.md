# AmneziaWG Docker Client for MikroTik RouterOS

Docker container with AmneziaWG client intended for deployment on MikroTik RouterOS Container subsystem.

The project builds a lightweight container image containing:

- amneziawg-go
- amneziawg-tools (`awg`, `awg-quick`)
- startup script (`start.sh`)
- support for external AWG configuration file
- automatic route handling and tunnel validation

## Docker Hub

Official image:

```bash
docker pull vbsdelnik/amneziawg-client-arm:latest
```

Docker Hub repository:

:contentReference[oaicite:0]{index=0}

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

## Supported Architectures

| Architecture | Status |
|-------------|---------|
| ARMv7 | Supported |
| ARM64 | Planned |
| AMD64 | Planned |

## Configuration

The container expects an external configuration file:

```text
/config/awg.conf
```

The configuration file is mounted from RouterOS and is **not embedded into the image**.

Example:

```routeros
/container/mounts/add \
    list=awg \
    src=awg.conf \
    dst=/config/awg.conf \
    comment=awgconf
```

Attach the mount list to the container:

```routeros
/container/add \
    remote-image=vbsdelnik/amneziawg-client-arm:latest \
    mounts=awg
```

## Building

Change to the desired architecture directory:

```bash
cd arm
```

Build the image:

```bash
./build.sh
```

The script builds and loads the image into the local Docker engine.

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

## Run Locally

Example:

```bash
docker run --rm -it \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -v $(pwd)/awg.conf:/config/awg.conf:ro \
  vbsdelnik/amneziawg-client-arm:latest
```

## MikroTik RouterOS Deployment

Create mount:

```routeros
/container/mounts/add \
    list=awg \
    src=awg.conf \
    dst=/config/awg.conf
```

Create container:

```routeros
/container/add \
    remote-image=vbsdelnik/amneziawg-client-arm:latest \
    interface=veth1 \
    root-dir=disk1/amneziawg \
    mounts=awg \
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

## Features

- AmneziaWG userspace implementation
- Automatic tunnel startup
- Automatic route management
- Tunnel validation checks
- Health monitoring
- External configuration via mounted file
- Suitable for RouterOS container subsystem

## Notes

The image does **not** contain:

```text
/config/awg.conf
```

The configuration file must always be supplied externally through RouterOS mounts.

The startup process is implemented in:

```text
start.sh
```

which is copied into the image and used as the container entrypoint.

## Upgrading

Pull latest image:

```bash
docker pull vbsdelnik/amneziawg-client-arm:latest
```

Push locally built image:

```bash
docker push vbsdelnik/amneziawg-client-arm:latest
```

## License

This repository contains only Docker build and deployment files.

AmneziaWG components are distributed under their respective licenses:

- :contentReference[oaicite:1]{index=1}
- :contentReference[oaicite:2]{index=2}
