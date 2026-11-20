#!/bin/bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ $# -eq 0 ]] || die "Usage: sudo $0"
[[ $EUID -eq 0 ]] || die "Run as root."
command -v systemctl >/dev/null || die "A systemd host is required."

APP_DIR=/opt/amnezia-client
SETTINGS_FILE="$APP_DIR/settings.conf"
PBR_HELPER="$APP_DIR/amnezia-pbr"
COMMON_FILE="$APP_DIR/common.sh"
PROFILE_FILE="$APP_DIR/awg.conf"
if [[ -f "$SETTINGS_FILE" ]]; then
    PROFILE_FILE=$(bash -c 'source "$1" || exit 1; printf "%s" "${AWG_CONFIG:-/opt/amnezia-client/awg.conf}"' _ "$SETTINGS_FILE") ||
        die "Cannot read settings. Fix their syntax before uninstalling."
fi

FILES=(
    "$APP_DIR/install.sh"
    "$APP_DIR/run.sh"
    "$APP_DIR/uninstall.sh"
    "$APP_DIR/amnezia-pbr"
    "$APP_DIR/common.sh"
    "$SETTINGS_FILE"
    /etc/systemd/system/amnezia-pbr.service
    /etc/sysctl.d/90-awg-forwarding.conf
)

# No recursive directory deletion; the AWG profile and unrelated files stay in place.
DELETE_FILES=()
for file in "${FILES[@]}"; do
    [[ "$file" == "$PROFILE_FILE" ]] && continue
    if [[ -e "$file" || -L "$file" ]]; then DELETE_FILES+=("$file"); fi
done

printf 'This will stop/disable Amnezia PBR and remove its routing/firewall rules.\nVPN routing for the selected LAN traffic will be interrupted.\n\nFiles to delete:\n'
if [[ ${#DELETE_FILES[@]} -gt 0 ]]; then
    printf '  %s\n' "${DELETE_FILES[@]}"
else
    echo '  (none)'
fi
printf '\nEmpty project directories will also be removed.\nKeeping your AWG profile: %s\nDocker containers, networks and images will not be removed.\nIPv4 forwarding will not be switched off in the running system.\n\nProceed? [Y/n] ' "$PROFILE_FILE"
IFS= read -r answer || die "No confirmation received; nothing removed."
case "$answer" in
    ''|y|Y|yes|YES|Yes) ;;
    *) echo 'Cancelled; nothing removed.'; exit 0 ;;
esac

can_cleanup=0
if [[ -x "$PBR_HELPER" && -f "$COMMON_FILE" && -f "$SETTINGS_FILE" ]]; then
    if AMNEZIA_SETTINGS="$SETTINGS_FILE" bash -e -c 'source "$1"; load_settings' _ "$COMMON_FILE" >/dev/null 2>&1; then
        can_cleanup=1
    fi
fi
if [[ $can_cleanup -eq 0 ]]; then
    if systemctl is-active --quiet amnezia-pbr.service ||
       { iptables -w 5 -S DOCKER-USER 2>/dev/null | grep -F -- '--comment amnezia-pbr ' >/dev/null; }; then
        die "PBR is still configured but settings cannot be read. Fix settings before removing the files."
    fi
fi

if [[ -e /etc/systemd/system/amnezia-pbr.service ]] || systemctl is-active --quiet amnezia-pbr.service; then
    systemctl disable --now amnezia-pbr.service || die "Could not stop/disable PBR; files kept."
fi
if [[ $can_cleanup -eq 1 ]]; then
    AMNEZIA_SETTINGS="$SETTINGS_FILE" "$PBR_HELPER" remove || die "PBR cleanup failed; files kept."
fi

if [[ ${#DELETE_FILES[@]} -gt 0 ]]; then rm -f -- "${DELETE_FILES[@]}"; fi
systemctl daemon-reload
systemctl reset-failed amnezia-pbr.service 2>/dev/null || true
rmdir "$APP_DIR" 2>/dev/null || true
printf '\nUninstallation completed. AWG configuration, Docker resources and unrelated files were preserved.\n'
