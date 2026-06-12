#!/usr/bin/env bash
#
# install.sh — fix repeated "USB device detected" notifications caused by the
# Microsoft Audio Dock's internal USB hubs flapping on Linux (tested on
# Kubuntu / KDE Plasma 6).
#
# What it does:
#   1. Installs a udev rule that stops the dock's two internal hubs (045e:084a
#      USB 3.0 + 045e:0849 USB 2.0) from autosuspending — fixes failure mode 1
#      (kernel-initiated hub suspend, ~1-2 min flapping).
#   2. Applies the same setting live to any currently-connected dock hub, so
#      you don't need to replug or reboot.
#   3. Installs a WirePlumber rule that keeps the dock's audio output node
#      open — fixes failure mode 2 (the dock firmware resets itself every
#      ~5 min when its audio interface is suspended; see README).
#
# Safe to re-run. Requires sudo.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="045e"
PRODUCTS=("084a" "0849")     # 084a = USB 3.0 hub, 0849 = USB 2.0 hub (both inside the dock)
RULE_SRC="$REPO_ROOT/udev/50-msdock-nosuspend.rules"
RULE_DST="/etc/udev/rules.d/50-msdock-nosuspend.rules"
WP_SRC="$REPO_ROOT/wireplumber/50-msdock-no-suspend.conf"
WP_DST="/etc/wireplumber/wireplumber.conf.d/50-msdock-no-suspend.conf"

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

# 3. Install WirePlumber rule (failure mode 2: dock firmware idle reset)
if [[ -f "$WP_SRC" ]]; then
    echo ">>> Installing WirePlumber rule -> $WP_DST"
    sudo install -D -m 0644 "$WP_SRC" "$WP_DST"
    # Restart wireplumber in the *real* user's session so it takes effect now.
    real_user="${SUDO_USER:-$USER}"
    if [[ "$real_user" != "root" ]] && id "$real_user" &>/dev/null; then
        uid="$(id -u "$real_user")"
        if sudo -u "$real_user" XDG_RUNTIME_DIR="/run/user/$uid" \
             systemctl --user restart wireplumber 2>/dev/null; then
            echo "    wireplumber restarted for user $real_user."
        else
            echo "    !! could not restart wireplumber automatically — run this yourself:"
            echo "       systemctl --user restart wireplumber"
        fi
    else
        echo "    restart it from your desktop session:  systemctl --user restart wireplumber"
    fi
else
    echo "!! Cannot find WirePlumber rule at $WP_SRC — skipped (failure mode 2 not fixed)" >&2
fi

echo ">>> Done. Hubs no longer autosuspend, and the dock's audio node stays open."
echo "    Verify with:  journalctl -k -f | grep -i 'usb .*disconnect'"
echo "    (you should see no more periodic disconnect/reconnect of the dock)"
