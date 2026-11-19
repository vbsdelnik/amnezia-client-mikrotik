#!/bin/bash
# Shared settings checks for the installer, container launcher and PBR helper.

SETTINGS_FILE="${AMNEZIA_SETTINGS:-/etc/amnezia-client/settings.conf}"

die() { echo "ERROR: $*" >&2; exit 1; }

load_settings() {
    [[ -f "$SETTINGS_FILE" ]] || die "Settings not found: $SETTINGS_FILE"
    # A trusted, root-owned shell file.
    source "$SETTINGS_FILE"

    local name missing=0
    for name in CONTAINER_NAME IMAGE AWG_CONFIG DOCKER_NETWORK AWG_BRIDGE AWG_NETWORK AWG_GATEWAY AWG_IP LOCAL_IF LOCAL_NET VPN_TABLE RULE_PRIORITY WAIT_SECONDS HANDSHAKE_TIMEOUT PING_TARGET DEBUG; do
        if [[ -z "${!name:-}" || "${!name}" == *CHANGE_ME* ]]; then
            echo "Fill in $name in $SETTINGS_FILE" >&2
            missing=1
        fi
    done
    [[ $missing -eq 0 ]] || die "Complete settings.conf before continuing."
    [[ "$AWG_CONFIG" == /* ]] || die "AWG_CONFIG must be an absolute path."
    [[ "$LOCAL_IF" != "$AWG_BRIDGE" && "$LOCAL_IF" != lo ]] || die "LOCAL_IF must be the incoming LAN interface."

    IFS=', ' read -r -a LOCAL_NETWORKS <<< "$LOCAL_NET"
    [[ ${#LOCAL_NETWORKS[@]} -gt 0 ]] || die "Set at least one LOCAL_NET entry."
    [[ "$VPN_TABLE" =~ ^[1-9][0-9]*$ && $VPN_TABLE -le 252 ]] || die "Use a dedicated VPN_TABLE numbered 1-252."
    [[ "$RULE_PRIORITY" =~ ^[1-9][0-9]*$ ]] || die "RULE_PRIORITY must be a positive integer."
    [[ $((RULE_PRIORITY + ${#LOCAL_NETWORKS[@]})) -le 32766 ]] || die "LAN rule priorities must precede main (32766)."
    [[ "$WAIT_SECONDS" =~ ^(0|[1-9][0-9]*)$ && $WAIT_SECONDS -le 60 ]] || die "WAIT_SECONDS must be 0-60."
    [[ "$HANDSHAKE_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "HANDSHAKE_TIMEOUT must be a positive integer."
    [[ "$DEBUG" == 0 || "$DEBUG" == 1 ]] || die "DEBUG must be 0 or 1."

    # Let iproute2 check CIDR syntax without changing routes.
    local network
    for network in "${LOCAL_NETWORKS[@]}"; do
        [[ "$network" == */* && "$network" != */0 ]] || die "Use explicit IPv4 LAN CIDRs, not /0: $network"
        ip -4 route show table main exact "$network" >/dev/null
    done
}
