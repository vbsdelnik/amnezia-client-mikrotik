#!/bin/bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -eq 0 ]] || die "Usage: sudo $0"
[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"
command -v install >/dev/null || die "The install command is required."
command -v systemctl >/dev/null || die "A systemd host is required."

if systemctl is-active --quiet amnezia-pbr.service; then
    die "Stop amnezia-pbr.service with its current settings before upgrading."
fi

FILES=(install.sh settings.conf.example common.sh run.sh amnezia-pbr amnezia-pbr.service 90-awg-forwarding.conf.example)
SCRIPT_DIR=""
SOURCE_FILE="${BASH_SOURCE[0]:-}"
DOWNLOAD_DIR=""
SAVE_INSTALLER=0
RERUN_COMMAND="./install.sh"
SETTINGS_PENDING=0

cleanup() {
    local status=$?
    if [[ -n "$DOWNLOAD_DIR" ]]; then
        rm -rf -- "$DOWNLOAD_DIR"
    fi
    if [[ $status -ne 0 && $SETTINGS_PENDING -eq 1 ]]; then
        printf '\nAfter completing %s, run:\n  %s\n' "$SETTINGS_FILE" "$RERUN_COMMAND" >&2
    fi
}
trap cleanup EXIT

if [[ -n "$SOURCE_FILE" && -f "$SOURCE_FILE" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "$SOURCE_FILE")" && pwd)"
    if [[ "$SCRIPT_DIR" != "$(pwd -P)" ]]; then
        RERUN_COMMAND="$SCRIPT_DIR/$(basename -- "$SOURCE_FILE")"
    fi
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
        cmp -s "$SCRIPT_DIR/install.sh" ./install.sh || die "A different ./install.sh already exists. Rename it or run this command in an empty directory."
    fi
    install -o 0 -g 0 -m 0755 "$SCRIPT_DIR/install.sh" ./install.sh
    printf 'Saved installer: %s/install.sh\n' "$(pwd -P)"
fi

source "$SCRIPT_DIR/common.sh"
if [[ ! -e "$SETTINGS_FILE" && ! -L "$SETTINGS_FILE" ]]; then
    install -d -m 0700 "$(dirname -- "$SETTINGS_FILE")"
    install -o 0 -g 0 -m 0600 "$SCRIPT_DIR/settings.conf.example" "$SETTINGS_FILE"
    printf 'Created %s.\nReplace CHANGE_ME values and review the defaults:\n  vi %s\n\nThen run:\n  %s\n' "$SETTINGS_FILE" "$SETTINGS_FILE" "$RERUN_COMMAND"
    exit 1
fi
SETTINGS_PENDING=1
load_settings
SETTINGS_PENDING=0

# Installation only: do not start containers/services or apply sysctl settings.
install -d -m 0755 /usr/local/sbin /usr/local/lib/amnezia-client /etc/systemd/system /etc/sysctl.d
install -d -m 0700 /opt/amnezia-client
if [[ ! -e /etc/sysctl.d/90-awg-forwarding.conf && ! -L /etc/sysctl.d/90-awg-forwarding.conf ]]; then
    install -o 0 -g 0 -m 0644 "$SCRIPT_DIR/90-awg-forwarding.conf.example" /etc/sysctl.d/90-awg-forwarding.conf
fi
install -o 0 -g 0 -m 0644 "$SCRIPT_DIR/common.sh" /usr/local/lib/amnezia-client/common.sh
install -o 0 -g 0 -m 0755 "$SCRIPT_DIR/run.sh" /opt/amnezia-client/run.sh
install -o 0 -g 0 -m 0755 "$SCRIPT_DIR/amnezia-pbr" /usr/local/sbin/amnezia-pbr
install -o 0 -g 0 -m 0644 "$SCRIPT_DIR/amnezia-pbr.service" /etc/systemd/system/amnezia-pbr.service
systemctl daemon-reload

printf '\nInstallation completed successfully.\nSettings: %s\n\nPlace your client profile at:\n  %s\n\nWhen ready, run the setup:\n  sudo /opt/amnezia-client/run.sh\n' "$SETTINGS_FILE" "$AWG_CONFIG"
echo 'The installer has not started the container or PBR, or applied forwarding.'
