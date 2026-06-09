#!/usr/bin/env bash
#
# install.sh — fix repeated "USB device detected" notifications caused by the
# Microsoft Audio Dock's internal USB hubs flapping on Linux (tested on
# Kubuntu / KDE Plasma 6).
#
# What it does:
#   1. Installs a udev rule that stops the dock's two internal hubs (045e:084a
#      USB 3.0 + 045e:0849 USB 2.0) from autosuspending — the persistent,
#      reboot-safe fix.
#   2. Applies the same setting live to any currently-connected dock hub, so
#      you don't need to replug or reboot.
#
# Safe to re-run. Requires sudo.

set -euo pipefail

VENDOR="045e"
PRODUCTS=("084a" "0849")     # 084a = USB 3.0 hub, 0849 = USB 2.0 hub (both inside the dock)
RULE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/udev/50-msdock-nosuspend.rules"
RULE_DST="/etc/udev/rules.d/50-msdock-nosuspend.rules"

echo ">>> Microsoft Audio Dock USB3 hub fix"

if [[ ! -f "$RULE_SRC" ]]; then
    echo "!! Cannot find udev rule at $RULE_SRC" >&2
    exit 1
fi

# 1. Install persistent udev rule
echo ">>> Installing udev rule -> $RULE_DST"
sudo install -m 0644 "$RULE_SRC" "$RULE_DST"
sudo udevadm control --reload-rules
echo "    done."

# 2. Apply live to any connected dock hub (find it by VID:PID, don't hardcode path)
echo ">>> Looking for connected dock hubs ($VENDOR:${PRODUCTS[*]})..."
found=0
for dev in /sys/bus/usb/devices/*/; do
    [[ -f "${dev}idVendor" && -f "${dev}idProduct" ]] || continue
    [[ "$(cat "${dev}idVendor")" == "$VENDOR" ]] || continue
    pid="$(cat "${dev}idProduct")"
    for want in "${PRODUCTS[@]}"; do
        [[ "$pid" == "$want" ]] || continue
        if [[ -w "${dev}power/control" ]] || sudo test -w "${dev}power/control"; then
            echo on | sudo tee "${dev}power/control" >/dev/null
            echo "    set power/control=on for ${dev} ($(cat "${dev}product" 2>/dev/null || echo hub))"
            found=1
        fi
    done
done

if [[ "$found" -eq 0 ]]; then
    echo "    no dock connected right now — that's fine, the rule applies on next plug-in."
fi

echo ">>> Done. The dock's internal hubs will no longer autosuspend."
echo "    Verify with:  journalctl -k -f | grep -i 'usb .*disconnect'"
echo "    (you should see no more periodic disconnect/reconnect of the hub)"
