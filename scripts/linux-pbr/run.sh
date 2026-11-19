#!/bin/bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }
source /usr/local/lib/amnezia-client/common.sh
load_settings

[[ -f "$AWG_CONFIG" ]] || die "Client configuration not found: $AWG_CONFIG"
[[ -c /dev/net/tun ]] || die "TUN device /dev/net/tun is not available."
docker info >/dev/null

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    die "Container $CONTAINER_NAME already exists. Inspect it with docker ps -a; start it with docker start, or recreate it separately to apply changed settings."
fi

if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
    driver=$(docker network inspect --format '{{.Driver}}' "$DOCKER_NETWORK")
    bridge=$(docker network inspect --format '{{index .Options "com.docker.network.bridge.name"}}' "$DOCKER_NETWORK")
    addressing=$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}} {{.Gateway}}{{end}}' "$DOCKER_NETWORK")
    [[ "$driver" == bridge && "$bridge" == "$AWG_BRIDGE" && "$addressing" == "$AWG_NETWORK $AWG_GATEWAY" ]] ||
        die "Docker network $DOCKER_NETWORK differs from settings.conf. Review the existing network before continuing."
else
    docker network create \
        --driver bridge \
        --subnet "$AWG_NETWORK" \
        --gateway "$AWG_GATEWAY" \
        --opt "com.docker.network.bridge.name=$AWG_BRIDGE" \
        "$DOCKER_NETWORK"
fi

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --network "$DOCKER_NETWORK" \
    --ip "$AWG_IP" \
    --cap-add NET_ADMIN \
    --device /dev/net/tun \
    --sysctl net.ipv4.ip_forward=1 \
    --mount "type=bind,src=$AWG_CONFIG,dst=/config/awg.conf,readonly" \
    --env "LOCAL_NET=$LOCAL_NET" \
    --env "HANDSHAKE_TIMEOUT=$HANDSHAKE_TIMEOUT" \
    --env "PING_TARGET=$PING_TARGET" \
    --env "DEBUG=$DEBUG" \
    "$IMAGE"

echo "Applying host forwarding and policy routing..."
sysctl -p /etc/sysctl.d/90-awg-forwarding.conf
systemctl enable amnezia-pbr.service
systemctl restart amnezia-pbr.service
amnezia-pbr status

printf '\nSetup completed: container started, host forwarding and PBR applied.\nCheck the VPN connection and LAN traffic:\n  docker logs -f %s\n' "$CONTAINER_NAME"
