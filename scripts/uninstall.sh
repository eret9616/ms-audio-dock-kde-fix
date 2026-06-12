#!/usr/bin/env bash
#
# uninstall.sh — revert the fixes installed by install.sh.
# Removes the udev rule, restores autosuspend (power/control=auto) on any
# connected dock hub, and removes the WirePlumber rule. Requires sudo.

set -euo pipefail

VENDOR="045e"
PRODUCTS=("084a" "0849")
RULE_DST="/etc/udev/rules.d/50-msdock-nosuspend.rules"
WP_DST="/etc/wireplumber/wireplumber.conf.d/50-msdock-no-suspend.conf"

echo ">>> Removing udev rule $RULE_DST"
sudo rm -f "$RULE_DST"
sudo udevadm control --reload-rules

echo ">>> Restoring power/control=auto on any connected dock hub..."
for dev in /sys/bus/usb/devices/*/; do
    [[ -f "${dev}idVendor" && -f "${dev}idProduct" ]] || continue
    [[ "$(cat "${dev}idVendor")" == "$VENDOR" ]] || continue
    pid="$(cat "${dev}idProduct")"
    for want in "${PRODUCTS[@]}"; do
        if [[ "$pid" == "$want" ]]; then
            echo auto | sudo tee "${dev}power/control" >/dev/null
            echo "    restored ${dev}"
        fi
    done
done

echo ">>> Removing WirePlumber rule $WP_DST"
sudo rm -f "$WP_DST"
real_user="${SUDO_USER:-$USER}"
if [[ "$real_user" != "root" ]] && id "$real_user" &>/dev/null; then
    uid="$(id -u "$real_user")"
    sudo -u "$real_user" XDG_RUNTIME_DIR="/run/user/$uid" \
        systemctl --user restart wireplumber 2>/dev/null \
        && echo "    wireplumber restarted for user $real_user." \
        || echo "    restart it yourself:  systemctl --user restart wireplumber"
fi

echo ">>> Done. Autosuspend and audio-suspend behaviour reverted to defaults."
