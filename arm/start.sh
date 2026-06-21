#!/bin/sh

set -eu

INTERFACE="awg"
CONFIG_FILE="/config/awg.conf"

HANDSHAKE_TIMEOUT="${HANDSHAKE_TIMEOUT:-30}"
PING_TARGET="${PING_TARGET:-1.1.1.1}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

cleanup() {
    log "Stopping tunnel..."

    awg-quick down "$CONFIG_FILE" 2>/dev/null || true

    pkill amneziawg-go 2>/dev/null || true
}

trap cleanup EXIT INT TERM 

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config file not found: $CONFIG_FILE"
    exit 1
fi

rm -f /etc/resolv.conf

log "Replace ip route to Amnezia Endpoint..."

VPN_ENDPOINT=$(awk -F' = ' \
    '/^Endpoint/ {print $2}' \
    "$CONFIG_FILE" | cut -d: -f1)

REAL_GW=$(ip route | awk '/default/ {print $3; exit}')
REAL_IF=$(ip route | awk '/default/ {print $5; exit}')

ip route replace \
    "$VPN_ENDPOINT" \
    via "$REAL_GW" \
    dev "$REAL_IF"

log "Replace default gateway..."

ip route del default
ip route add default dev awg

log "Starting AmneziaWG..."

awg-quick up "$CONFIG_FILE"

sleep 2

log "Interface created successfully"
awg show awg || true

sleep 10


# log "Waiting for handshake..."

HANDSHAKE_OK=0

# for i in $(seq 1 "$HANDSHAKE_TIMEOUT")
# do
#    if awg show "$INTERFACE" latest-handshakes \
#        | awk '{ if ($2 > 0) found=1 } END { exit(found ? 0 : 1) }'
#    then
#        HANDSHAKE_OK=1
#        break
#    fi
#
#    sleep 1
# done

# if [ "$HANDSHAKE_OK" -ne 1 ]; then
#    log "ERROR: handshake timeout"
#
#    awg show "$INTERFACE" || true
#
#    exit 1
# fi

# log "Handshake established"

log "Waiting interface initialization..."

sleep 5

ip addr show awg || true
ip route || true

log "Tunnel started"

log "Checking connectivity..."

if ping -c 3 -W 2 "$PING_TARGET" >/dev/null 2>&1
then
    log "Connectivity verified"
else
    log "ERROR: connectivity check failed"
    exit 1
fi

log "AmneziaWG tunnel is operational"

tail -f /dev/null

