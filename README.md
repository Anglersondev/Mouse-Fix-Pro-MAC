<div align="center">

<img src="docs/icon.png" width="160" alt="Mouse Fix Pro icon, a mouse utility for Mac">

# Mouse Fix Pro for Mac

**The free, lightweight app that makes any mouse feel great on macOS.**
Remap your mouse side buttons, get smooth scrolling, turn off mouse acceleration and open Mission Control with a single click.

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple)](#install)
[![Apple Silicon and Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-5145E6)](#install)
[![Under 1 MB](https://img.shields.io/badge/size-%3C%201%20MB-3EE6C8)](#truly-lightweight)
[![Swift](https://img.shields.io/badge/Swift-100%25-F05138?logo=swift&logoColor=white)](#how-it-works)
[![Free](https://img.shields.io/badge/price-free-18A0FB)](#install)

[**⬇️ Download Mouse Fix Pro**](https://github.com/Anglersondev/Mouse-Fix-Pro-MAC/releases/latest) · [Features](#features) · [FAQ](#faq) · [Português](README.pt-BR.md)

</div>

---

## What is Mouse Fix Pro?

**Mouse Fix Pro** is a **macOS** utility that makes third-party mice (Logitech, UGREEN, Razer, Microsoft, HP, Dell, Redragon, vertical mice and generic USB or Bluetooth mice) work as well on a Mac as an Apple trackpad.

With it you can:

- **Remap mouse side buttons on Mac** to Mission Control, switch desktops (Spaces), go back and forward, control music, launch apps or trigger any keyboard shortcut.
- **Get smooth scrolling** on your mouse wheel, with the same feel as a trackpad.
- **Disable mouse acceleration on Mac** and pick a fixed pointer speed, ideal for gaming, design and video editing.
- **Keep your mouse speed** after locking the screen, waking from sleep or reconnecting Bluetooth. macOS tends to reset it on its own; Mouse Fix Pro re-applies your setting.
- **Use trackpad gestures with a mouse**: hold a button and drag to open Mission Control, show app windows or switch desktops.
- **Create per-app profiles**: the same button can do one thing in Safari and another in Photoshop, VS Code or Final Cut Pro.

It's free, open source and written from scratch in Swift.

## Works even with mice whose side buttons "can't be remapped"

Many affordable Bluetooth mice, such as the **UGREEN 5-button vertical mouse**, send their side buttons as a **media key or keyboard shortcut** instead of a real mouse button. That's why, in other apps, those buttons only go back and forward and can't be set to Mission Control.

Mouse Fix Pro reads the raw signal coming from the mouse (IOHID), recognizes that it came from the side button, blocks the original action and runs the one you picked. The **What the mouse sends** tab shows live how each button reaches your Mac.

## Features

| Area | What it does |
|---|---|
| 🖱️ **Buttons** | Click, double click, hold and hold + drag (↑ ↓ ← →) on any extra button, including the scroll wheel. Automatic detection: click *Detect button* and press it. |
| ⚡ **Actions** | Mission Control, App Exposé, Show Desktop, Launchpad/Apps, move one desktop left or right, back, forward, middle click, play/pause, next track, volume, mute, Look Up, screenshot, lock screen, new tab, close tab, reopen tab, zoom, custom keyboard shortcut and open any app. |
| 🎯 **Pointer** | Turn mouse acceleration off, set pointer speed from 0.25× to 4×, kept after lock, sleep and reconnect. |
| 📜 **Scrolling** | Smooth scrolling with natural acceleration, reverse scroll direction for the mouse only (the trackpad stays the same), scroll speed. |
| 🧩 **Per-app profiles** | Different button actions for each application. |
| 🔍 **Diagnostics** | Shows in real time what each mouse button sends. |
| ⚙️ **General** | Launch at login, optional menu bar and Dock icons, quick on/off switch. |
| 🌎 **Languages** | English and Portuguese, following your Mac's language. |

## Truly lightweight

| | Mouse Fix Pro | Mac Mouse Fix 3 |
|---|---|---|
| App size | **under 1 MB** | about 17 MB |
| Background process | UI-less helper (no SwiftUI) | Helper |
| Built-in update framework | none | Sparkle |
| Price | free | paid after the trial |

Like the original, it runs as two processes: the **settings window quits completely** when you close it, and only the **Mouse Fix Pro Helper** keeps running. The helper stays idle until you use your mouse:

- the keyboard listener only turns on if a mouse button arrives as a key;
- the motion listener only turns on while you hold a button that has a drag gesture;
- the smooth-scrolling animation only exists while a page is scrolling;
- speed and acceleration are written straight to the mouse driver, using no CPU.

## Install

1. Download **MouseFixPro.zip** from the [releases page](https://github.com/Anglersondev/Mouse-Fix-Pro-MAC/releases/latest).
2. Unzip it and drag **Mouse Fix Pro** into your **Applications** folder.
3. The first time, right-click the app and choose **Open**. If macOS still blocks it, run this in Terminal:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Mouse Fix Pro.app"
   ```
4. Grant the permissions the app asks for in **System Settings › Privacy & Security**. They go to **Mouse Fix Pro Helper**, which is what reads the mouse:
   - **Accessibility**: to intercept clicks and run actions.
   - **Input Monitoring**: to read mice that send side buttons as keys.

Requires **macOS 13 Ventura or later** (Ventura, Sonoma, Sequoia and newer) on a Mac with **Apple Silicon (M1, M2, M3, M4...) or Intel**.

### Build from source

You need the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/Anglersondev/Mouse-Fix-Pro-MAC.git
cd Mouse-Fix-Pro-MAC
./scripts/build-app.sh --install
```

Tip: ad-hoc signing changes with every build, so macOS forgets the permissions. Create a code signing certificate in Keychain Access and build with `SIGN_IDENTITY="Certificate name" ./scripts/build-app.sh --install`.

## FAQ

<details>
<summary><b>How do I remap mouse side buttons on a Mac?</b></summary>

Open Mouse Fix Pro, go to **Buttons**, click **Detect button** and press the side button. Then choose an action for *Click*, *Double click*, *Hold* or *Hold and drag*.
</details>

<details>
<summary><b>How do I open Mission Control with a mouse button?</b></summary>

In **Buttons**, pick **Mission Control** for the click of any button. To use it like a trackpad, open *Hold and drag* and click **Use Mission Control and desktop gestures**.
</details>

<details>
<summary><b>How do I turn off mouse acceleration on macOS?</b></summary>

In the **Pointer** tab, turn on *Adjust the pointer with Mouse Fix Pro* and turn off **Mouse acceleration**. The speed becomes linear and you set it with the *Speed* slider.
</details>

<details>
<summary><b>Why does my mouse speed change after I lock my Mac?</b></summary>

macOS re-applies default mouse values when the screen is unlocked, the Mac wakes up or a Bluetooth mouse reconnects. Mouse Fix Pro detects these moments and re-applies your setting automatically.
</details>

<details>
<summary><b>My mouse side buttons only go back and forward. Can I change that?</b></summary>

Yes. Those mice send the side buttons as a media key or keyboard shortcut. Mouse Fix Pro recognizes this and lets you remap them normally. Check the **What the mouse sends** tab to see how your mouse behaves.
</details>

<details>
<summary><b>How do I get smooth scrolling with a mouse on Mac?</b></summary>

In the **Scrolling** tab, turn on **Smooth scrolling**. You can also reverse the scroll direction for the mouse only, without changing the trackpad.
</details>

<details>
<summary><b>Does Mouse Fix Pro slow down my Mac?</b></summary>

No. The app is under 1 MB, the settings window leaves memory when you close it and the helper stays idle until you use your mouse. The **General** tab shows how much memory it uses.
</details>

<details>
<summary><b>Is it safe? Why does it need Accessibility access?</b></summary>

macOS requires that permission for any app that reads clicks and sends shortcuts. Mouse Fix Pro has no network access, collects no data, and its code is open in this repository.
</details>

<details>
<summary><b>How is it different from Mac Mouse Fix?</b></summary>

Mouse Fix Pro was inspired by [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) by Noah Nuebling, but it's an independent project written from scratch and not affiliated with it. It adds support for mice that send buttons as keys, per-app profiles, pointer acceleration and speed control, and it's free.
</details>

<details>
<summary><b>What languages does the app support?</b></summary>

English and Portuguese. The app follows your Mac's language automatically.
</details>

## How it works

```
Mouse Fix Pro.app                      settings window (SwiftUI), quits completely
└── Contents/Library/LoginItems/
    └── Mouse Fix Pro Helper.app       does the work, no UI, always running

Sources/
├── MouseFixShared/      settings (JSON) and communication between the two processes
├── MouseFixProHelper/
│   └── Core/
│       ├── MouseCore.swift      wires everything; three event taps, each active only when needed
│       ├── HIDMonitor.swift     reads raw HID reports from mice on its own thread
│       ├── ButtonEngine.swift   click / double / hold / drag, per-app profiles
│       ├── PointerManager.swift speed and acceleration straight to the driver
│       ├── ScrollEngine.swift   smooth scrolling
│       ├── ActionRunner.swift   runs actions (synthetic events, Dock)
│       └── EventTap.swift       CGEventTap wrapper
└── MouseFixPro/         user interface
```

The two processes talk through macOS distributed notifications and share `~/Library/Application Support/MouseFixPro/config.json`. When a side button arrives as a key, `HIDMonitor` sees the report coming from the mouse and opens a short window in which the keyboard, media or gesture event generated by macOS is blocked. Real keyboard shortcuts keep working normally.

To inspect a mouse from Terminal without the app: `swift Tools/hidprobe.swift`.

---

## Author

Built by **Anglerson** · [anglerson.com.br](https://anglerson.com.br/) · [github.com/Anglersondev](https://github.com/Anglersondev)

<sub>Keywords: Mac mouse app, remap mouse buttons Mac, mouse side buttons macOS, Mission Control mouse button, disable mouse acceleration Mac, mouse speed Mac, smooth scrolling mouse Mac, reverse scroll mouse only, Mac Mouse Fix alternative, Logitech Options alternative, SteerMouse alternative, vertical mouse Mac, Bluetooth mouse Mac, mouse fix pro.</sub>
