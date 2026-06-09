# ms-audio-dock-kde-fix

**Fix the endless "USB device detected" notifications from the Microsoft Audio Dock (a.k.a. Surface Audio Dock) on Linux / KDE Plasma.**

修复 **Microsoft Audio Dock(Surface Audio Dock)** 在 Linux / KDE Plasma 下**反复弹出「检测到 USB 设备」通知**的问题。

---

## English

### Symptom

You plug in a Microsoft Audio Dock. Audio and the microphone work fine, but
every minute or two KDE pops up a notification like:

> **USB device detected**
> 4-Port USB 3.0 Hub connected.

It never stops. It is not a real disconnect of your audio/mic — those keep working.

### Root cause

The dock contains an internal **4-Port USB 3.0 hub** (`045e:084a`). USB 3.0 has a
link power-management feature (LPM U1/U2) plus runtime autosuspend: when a device
sits idle, the kernel suspends it to save power.

This hub's firmware **mishandles the suspend→resume handshake on Linux**. When the
kernel suspends the idle hub, it fails to resume cleanly, so the kernel decides the
device vanished (`usb 2-2: USB disconnect`) and immediately re-enumerates it
(`New USB device found … 4-Port USB 3.0 Hub`). Every cycle makes KDE's device-
notifier (KDED) fire another "USB device detected" popup.

Because the dock's USB-A ports usually have **nothing plugged into them**, that
USB 3.0 hub is permanently idle, so the kernel suspends it constantly and the bug
fires on a steady ~1–2 minute cadence.

> **The dock actually has two internal hubs, and either one can be the culprit.**
> Besides the USB 3.0 hub (`045e:084a`), there's a USB 2.0 hub (`045e:0849`) that
> the audio interface and HID hang off of. Depending on cabling — notably when the
> dock is connected **through a USB extension cable**, where the SuperSpeed link
> can degrade — it's the **USB 2.0 hub** that autosuspends and fails to resume,
> taking the whole dock tree down (`usb 3-2: USB disconnect` for `0849`, then the
> audio/HID children re-enumerate). The fix below pins **both** hubs so it doesn't
> matter which one your setup trips.

Kernel log fingerprint:

```
usb 2-2: USB disconnect, device number 3
usb 2-2: new SuperSpeed Plus Gen 2x1 USB device number 4 using xhci_hcd
usb 2-2: New USB device found, idVendor=045e, idProduct=084a
usb 2-2: Product: 4-Port USB 3.0 Hub
...repeats every 1–2 minutes...
```

> **It is not a microphone incompatibility.** The audio interface (`045e:084d`)
> lives on a separate USB 2.0 bus and stays connected the whole time. Only the
> empty SuperSpeed hub flaps.

### The fix

Stop those hubs from autosuspending (`power/control = on`). If they never
suspend, the broken resume handshake never happens.

**One-liner (quick install):**

```bash
git clone https://github.com/eret9616/ms-audio-dock-kde-fix.git
cd ms-audio-dock-kde-fix
sudo bash scripts/install.sh
```

**Or do it by hand:**

```bash
# persistent udev rule (survives reboots & replugs)
sudo cp udev/50-msdock-nosuspend.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules

# apply immediately to the already-connected hubs (no replug needed):
for d in /sys/bus/usb/devices/*/; do
  v=$(cat "$d/idVendor" 2>/dev/null); p=$(cat "$d/idProduct" 2>/dev/null)
  [ "$v" = "045e" ] && { [ "$p" = "084a" ] || [ "$p" = "0849" ]; } &&
  echo on | sudo tee "$d/power/control"
done
```

### Verify

```bash
journalctl -k -f | grep -i 'usb .*disconnect'
```

Before the fix you'd see the hub disconnect every 1–2 minutes. After the fix:
silence. The KDE popups stop too.

### Revert

```bash
sudo bash scripts/uninstall.sh
```

### Alternatives (and why this is better)

| Approach | Verdict |
|---|---|
| Disable the KDE notification (System Settings → Notifications → KDED) | Hides the symptom, hub still flaps in the kernel. |
| `usbcore.autosuspend=-1` kernel param | Works but global — kills laptop power savings everywhere. Overkill. |
| **Targeted udev rule (this repo)** | Fixes only the broken hub, keeps autosuspend for everything else. |
| Plug any always-active device (USB stick, mouse) into the dock | Accidentally "fixes" it by keeping the hub busy. Not reliable. |

### Tested on

- Kubuntu / KDE Plasma 6, kernel 6.x
- Microsoft Audio Dock (`045e:084d`), internal hubs `045e:084a` + `045e:0849`

USB IDs in this dock for reference:

| VID:PID | Device | Bus | Notes |
|---|---|---|---|
| `045e:084a` | 4-Port USB 3.0 Hub | USB 3.0 | **can flap** — pinned by the rule |
| `045e:0849` | 4-Port USB 2.0 Hub | USB 2.0 | **can also flap** (esp. via extension cable) — pinned by the rule |
| `045e:084d` | Microsoft Audio Dock (audio + HID) | USB 2.0 | your speaker/mic, hangs off `0849` |
| `045e:084c` | Realtek USB2.0 HID | USB 2.0 | hangs off `0849` |

---

## 简体中文

### 现象

插上 Microsoft Audio Dock 后,音频和麦克风都能正常用,但每隔一两分钟 KDE 就弹一次:

> **检测到 USB 设备**
> 4-Port USB 3.0 Hub 已连接。

弹个不停。这**不是**你的音频/麦克风真的掉线了——它们一直在正常工作。

### 根本原因

Dock 内部有一颗 **4 口 USB 3.0 集线器**(`045e:084a`)。USB 3.0 有链路电源管理
(LPM U1/U2)和运行时自动挂起(autosuspend):设备闲置时,内核会让它进入低功耗
休眠以省电。

这颗 hub 的**固件在 Linux 下处理「休眠→唤醒」握手有 bug**。内核让闲置的它休眠后,
它无法正常唤醒,于是内核判定设备消失了(`usb 2-2: USB disconnect`),紧接着又重新
枚举它(`New USB device found … 4-Port USB 3.0 Hub`)。每循环一次,KDE 的设备通知
服务(KDED)就弹一次「检测到 USB 设备」。

由于 Dock 上的 USB-A 口通常**什么都没插**,这颗 3.0 hub 永远处于闲置,内核就不停地
让它休眠,于是 bug 以稳定的 ~1–2 分钟节奏反复触发。

> **Dock 内部其实有两颗 hub,哪一颗都可能是元凶。** 除了 USB 3.0 hub(`045e:084a`),
> 还有一颗 USB 2.0 hub(`045e:0849`),音频接口和 HID 都挂在它下面。视连线情况而定
> ——尤其是**经过 USB 延长线**连接、SuperSpeed 链路质量下降时——抖动的会变成那颗
> **USB 2.0 hub**:它休眠后唤醒失败,把整棵 dock 树拽下来(日志里是 `usb 3-2:
> USB disconnect` 对应 `0849`,随后音频/HID 子设备一起重新枚举)。下面的修复会把
> **两颗 hub 都摁住**,这样无论你的环境触发的是哪一颗都不受影响。

内核日志特征:

```
usb 2-2: USB disconnect, device number 3
usb 2-2: new SuperSpeed Plus Gen 2x1 USB device number 4 using xhci_hcd
usb 2-2: New USB device found, idVendor=045e, idProduct=084a
usb 2-2: Product: 4-Port USB 3.0 Hub
...每 1–2 分钟重复一次...
```

> **不是麦克风不兼容。** 音频接口(`045e:084d`)挂在另一条 USB 2.0 总线上,全程
> 保持连接。抖动的只是那颗空着的 SuperSpeed hub。

### 解决方案

让这两颗 hub 不要自动休眠(`power/control = on`)。它们永不休眠,那个有问题的唤醒
握手就永远不会发生。

**一键安装:**

```bash
git clone https://github.com/eret9616/ms-audio-dock-kde-fix.git
cd ms-audio-dock-kde-fix
sudo bash scripts/install.sh
```

**或者手动操作:**

```bash
# 永久 udev 规则(重启、重插都生效)
sudo cp udev/50-msdock-nosuspend.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules

# 立即对已连接的 hub 生效(不用重插):
for d in /sys/bus/usb/devices/*/; do
  v=$(cat "$d/idVendor" 2>/dev/null); p=$(cat "$d/idProduct" 2>/dev/null)
  [ "$v" = "045e" ] && { [ "$p" = "084a" ] || [ "$p" = "0849" ]; } &&
  echo on | sudo tee "$d/power/control"
done
```

### 验证

```bash
journalctl -k -f | grep -i 'usb .*disconnect'
```

修复前每 1–2 分钟会看到 hub 掉线一次;修复后:一片安静,KDE 弹窗也停了。

### 撤销

```bash
sudo bash scripts/uninstall.sh
```

### 其它做法对比

| 做法 | 评价 |
|---|---|
| 关掉 KDE 通知(系统设置 → 通知 → KDED) | 只是把症状藏起来,内核里 hub 照样抖。 |
| `usbcore.autosuspend=-1` 内核参数 | 有效但全局生效,牺牲整机待机续航,杀鸡用牛刀。 |
| **针对性 udev 规则(本仓库)** | 只修这颗有问题的 hub,其它设备照常省电。 |
| 往 Dock 上插个一直活动的设备(U 盘/鼠标) | 靠让 hub 一直忙来「歪打正着」,不可靠。 |

### 测试环境

- Kubuntu / KDE Plasma 6,内核 6.x
- Microsoft Audio Dock(`045e:084d`),内部 hub `045e:084a` + `045e:0849`

本 Dock 的 USB ID 一览:

| VID:PID | 设备 | 总线 | 说明 |
|---|---|---|---|
| `045e:084a` | 4-Port USB 3.0 Hub | USB 3.0 | **可能抖** —— 规则已摁住 |
| `045e:0849` | 4-Port USB 2.0 Hub | USB 2.0 | **也可能抖**(尤其过延长线时)—— 规则已摁住 |
| `045e:084d` | Microsoft Audio Dock(音频 + HID) | USB 2.0 | 你的音箱/麦克风,挂在 `0849` 下面 |
| `045e:084c` | Realtek USB2.0 HID | USB 2.0 | 挂在 `0849` 下面 |

---

## License

MIT — see [LICENSE](LICENSE).

Contributions / reports welcome. 欢迎贡献与反馈。
