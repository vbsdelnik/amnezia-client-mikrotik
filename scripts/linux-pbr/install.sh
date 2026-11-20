#!/bin/bash
set -euo pipefail
umask 077

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -eq 0 ]] || die "Usage: sudo $0"
[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"
command -v install >/dev/null || die "The install command is required."
command -v systemctl >/dev/null || die "A systemd host is required."

if systemctl is-active --quiet amnezia-pbr.service; then
    die "Stop amnezia-pbr.service with its current settings before upgrading."
fi

FILES=(install.sh uninstall.sh settings.conf.example common.sh run.sh amnezia-pbr amnezia-pbr.service 90-awg-forwarding.conf.example)
SCRIPT_DIR=""
SOURCE_FILE="${BASH_SOURCE[0]:-}"
DOWNLOAD_DIR=""
SAVE_INSTALLER=0

cleanup() {
    if [[ -n "$DOWNLOAD_DIR" ]]; then
        rm -rf -- "$DOWNLOAD_DIR"
    fi
}
trap cleanup EXIT

if [[ -n "$SOURCE_FILE" && -f "$SOURCE_FILE" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "$SOURCE_FILE")" && pwd)"
else
    SAVE_INSTALLER=1
fi
need_download=0
for file in "${FILES[@]}"; do
    if [[ -z "$SCRIPT_DIR" || ! -f "$SCRIPT_DIR/$file" ]]; then need_download=1; fi
done
if [[ $need_download -eq 1 ]]; then
    command -v curl >/dev/null || die "Install curl before running this installer."
    BASE_URL="https://raw.githubusercontent.com/vbsdelnik/amnezia-client-mikrotik/main/scripts/linux-pbr"
    DOWNLOAD_DIR=$(mktemp -d)
    SCRIPT_DIR="$DOWNLOAD_DIR"
    echo "Downloading Linux client setup files..."
    for file in "${FILES[@]}"; do
        curl -fsSL "$BASE_URL/$file" -o "$SCRIPT_DIR/$file"
    done
fi

if [[ $SAVE_INSTALLER -eq 1 ]]; then
    if [[ -e ./install.sh || -L ./install.sh ]]; then
        [[ -f ./install.sh && ! -L ./install.sh ]] || die "Cannot save ./install.sh: the path is not a regular file."
        cmp -s "$SCRIPT_DIR/install.sh" ./install.sh ||
            grep -Fq 'https://raw.githubusercontent.com/vbsdelnik/amnezia-client-mikrotik/main/scripts/linux-pbr' ./install.sh ||
            die "A different ./install.sh already exists. Rename it or run this command in an empty directory."
    fi
    install -o 0 -g 0 -m 0755 "$SCRIPT_DIR/install.sh" ./install.sh
    printf 'Saved installer: %s/install.sh\n' "$(pwd -P)"
fi

SETTINGS_FILE="${AMNEZIA_SETTINGS:-/etc/amnezia-client/settings.conf}"
STATE_FILE=/etc/amnezia-client/install-state.conf
INSTALLER_COPY=""
INSTALLER_SHA256=""
if [[ -f "$STATE_FILE" ]]; then
    source "$STATE_FILE"
fi
if [[ $SAVE_INSTALLER -eq 1 ]]; then
    INSTALLER_COPY="$(pwd -P)/install.sh"
    read -r INSTALLER_SHA256 _ < <(sha256sum -- "$INSTALLER_COPY")
fi

install -d -m 0700 /etc/amnezia-client "$(dirname -- "$SETTINGS_FILE")"
if [[ ! -e "$SETTINGS_FILE" && ! -L "$SETTINGS_FILE" ]]; then
    install -o 0 -g 0 -m 0600 "$SCRIPT_DIR/settings.conf.example" "$SETTINGS_FILE"
fi

# Installation only: do not start containers/services or apply sysctl settings.
install -d -m 0755 /usr/local/sbin /usr/local/lib/amnezia-client /etc/systemd/system /etc/sysctl.d
install -d -m 0700 /opt/amnezia-client
if [[ ! -e /etc/sysctl.d/90-awg-forwarding.conf && ! -L /etc/sysctl.d/90-awg-forwarding.conf ]]; then
    install -o 0 -g 0 -m 0644 "$SCRIPT_DIR/90-awg-forwarding.conf.example" /etc/sysctl.d/90-awg-forwarding.conf
fi
install -o 0 -g 0 -m 0644 "$SCRIPT_DIR/common.sh" /usr/local/lib/amnezia-client/common.sh
install -o 0 -g 0 -m 0755 "$SCRIPT_DIR/run.sh" /opt/amnezia-client/run.sh
install -o 0 -g 0 -m 0755 "$SCRIPT_DIR/uninstall.sh" /opt/amnezia-client/uninstall.sh
install -o 0 -g 0 -m 0755 "$SCRIPT_DIR/amnezia-pbr" /usr/local/sbin/amnezia-pbr
install -o 0 -g 0 -m 0644 "$SCRIPT_DIR/amnezia-pbr.service" /etc/systemd/system/amnezia-pbr.service
printf 'INSTALLER_COPY=%q\nINSTALLER_SHA256=%q\nSETTINGS_PATH=%q\n' "$INSTALLER_COPY" "$INSTALLER_SHA256" "$SETTINGS_FILE" > "$STATE_FILE"
chmod 0600 "$STATE_FILE"
systemctl daemon-reload

printf '\nInstallation completed successfully.\n\nFill in settings (replace CHANGE_ME and review the defaults):\n  vi %s\n\nPlace your client profile at AWG_CONFIG from settings\n(default: /opt/amnezia-client/awg.conf), then run:\n  sudo /opt/amnezia-client/run.sh\n' "$SETTINGS_FILE"
echo 'No second installer run is needed. The installer has not started the container or PBR, or applied forwarding.'
