#!/bin/sh

set -eu

INTERFACE="awg"
CONFIG_FILE="/config/awg.conf"

HANDSHAKE_TIMEOUT="${HANDSHAKE_TIMEOUT:-30}"
PING_TARGET="${PING_TARGET:-1.1.1.1}"
LOCAL_NET="${LOCAL_NET:-}"
DEBUG="${DEBUG:-0}"

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

VPN_ENDPOINT=$(awk -F' = ' \
    '/^Endpoint/ {print $2}' \
    "$CONFIG_FILE" | cut -d: -f1)

REAL_GW=$(ip route | awk '/default/ {print $3; exit}')
REAL_IF=$(ip route | awk '/default/ {print $5; exit}')

log "Replace ip route to Amnezia Endpoint: $VPN_ENDPOINT via $REAL_GW"

ip route replace \
    "$VPN_ENDPOINT" \
    via "$REAL_GW" \
    dev "$REAL_IF"


if [ -n "$LOCAL_NET" ]; then
    log "Adding local network route: $LOCAL_NET via $REAL_GW"
    ip route replace "$LOCAL_NET" via $REAL_GW
fi

log "Starting AmneziaWG..."

awg-quick up "$CONFIG_FILE"

sleep 2

log "Interface created successfully"

if [ "$DEBUG" = "1" ]; 
then
    log "[DEBUG] awg show $INTERFACE:"
    awg show "$INTERFACE" || true
fi


sleep 10

log "Replace default gateway: default via dev $INTERFACE"

ip route replace default dev $INTERFACE


log "Waiting for handshake..."

HANDSHAKE_OK=0

for i in $(seq 1 "$HANDSHAKE_TIMEOUT")
do
    if awg show "$INTERFACE" latest-handshakes \
        | awk '{ if ($2 > 0) found=1 } END { exit(found ? 0 : 1) }'
    then
        HANDSHAKE_OK=1
        break
    fi

    sleep 1
 done

if [ "$HANDSHAKE_OK" -eq 1 ] 
then
    log "Handshake established"
    awg show "$INTERFACE" | grep "latest handshake"
else
    log "WARNING: handshake was not detected during startup"
fi


log "Waiting interface initialization..."

sleep 5

if [ "$DEBUG" = "1" ] 
then
    log "[DEBUG] ip addr show $INTERFACE:"
    ip addr show $INTERFACE || true
    log "[DEBUG] ip route list:" 
    ip route list || true
    log "[DEBUG] cat /etc/resolv.conf:"
    cat /etc.resolv.conf
fi

log "Tunnel started"

log "Checking connectivity..."

if ping -c 3 -W 2 "$PING_TARGET" >/dev/null 2>&1
then
    log "Connectivity verified: $PING_TARGET is available"
else
    log "ERROR: connectivity check failed"
    exit 1
fi

log "AmneziaWG tunnel is operational"

tail -f /dev/null

