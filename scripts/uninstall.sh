#!/usr/bin/env bash
#
# uninstall.sh — revert the fix installed by install.sh.
# Removes the udev rule and restores autosuspend (power/control=auto) on any
# connected dock hub. Requires sudo.

set -euo pipefail

VENDOR="045e"
PRODUCT="084a"
RULE_DST="/etc/udev/rules.d/50-msdock-nosuspend.rules"

echo ">>> Removing udev rule $RULE_DST"
sudo rm -f "$RULE_DST"
sudo udevadm control --reload-rules

echo ">>> Restoring power/control=auto on any connected dock hub..."
for dev in /sys/bus/usb/devices/*/; do
    [[ -f "${dev}idVendor" && -f "${dev}idProduct" ]] || continue
    if [[ "$(cat "${dev}idVendor")" == "$VENDOR" && "$(cat "${dev}idProduct")" == "$PRODUCT" ]]; then
        echo auto | sudo tee "${dev}power/control" >/dev/null
        echo "    restored ${dev}"
    fi
done

echo ">>> Done. Autosuspend behaviour reverted to kernel default."
