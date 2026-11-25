# MX Desk Controls

A Hammerspoon configuration that turns a Logitech MX Creative Console into desk
controls for a Mac and a Windows PC sharing one KVM monitor.

- **Keypad (3×3 LCD keys):** switch the monitor between the Mac and the PC,
  show the desktop, open apps, mute the microphone.
- **Dialpad:** push-to-talk dictation, Return, app launch, scrolling.
- **Mouse:** hold back = push-to-talk, forward = Return, middle = region
  screenshot copied to the clipboard.
- **Refresh guard:** keeps the monitor at a refresh rate its USB-C link can carry,
  including after macOS restores a saved rate when the lid closes.

**Agents:** start with [AGENTS.md](AGENTS.md). It has the repository map, rules,
a setup runbook with the human steps marked, and the verification commands.

## Branches

| Branch | Setup |
| --- | --- |
| `dell` (this one) | Alienware AW3926QW KVM monitor: DDC input switching, mouse buttons, refresh guard |
| `lg` | Earlier LG UltraGear 45GX950A-B setup: alternate-address DDC source switching, a reverse-engineered HID PIP helper, and a keepalive virtual display |

## Hardware This Was Built On

| Part | Model | Notes |
| --- | --- | --- |
| Mac | Apple Silicon MacBook Pro (Thunderbolt 5) | One USB-C cable to the monitor: video, USB hub and power |
| Monitor | Alienware AW3926QW (5120×2160) | KVM: USB-C upstream to the Mac, USB-B upstream to the PC; PC on DisplayPort |
| Control surface | Logitech MX Creative Keypad + Dialpad | Keypad plugged into the Mac directly |
| Mouse | ROG HARPE II | Any mouse with standard back, forward and middle buttons works |

## Key Layout

| | | |
| --- | --- | --- |
| MAC | SWAP | PC |
| Desktop | Chrome | MIC |
| Teams | VS Code | Terminal |

- **MAC / PC** select the monitor's USB-C / DisplayPort input over DDC/CI
  (VCP `0x60` = `0x1B` / `0x0F`) through the BetterDisplay CLI.
- **SWAP** reads the current input and selects the other computer; if the input
  cannot be read, it selects the Mac.
- Keys act on key-down. `WAIT` means a command is running and presses are
  ignored; `RETRY` means the last command failed. Nothing retries automatically.
- **MIC** mutes or unmutes every physical input and turns red while muted.
- **Dialpad:** key 1 VS Code, key 2 Terminal, key 3 Return, key 4 held =
  push-to-talk; the dial and roller scroll; the page buttons send ⌘[ and ⌘].

Details: [docs/desk-controls.md](docs/desk-controls.md).

## Requirements

- macOS on Apple Silicon.
- [Hammerspoon](https://www.hammerspoon.org) with its `hs` command-line tool.
- [BetterDisplay](https://github.com/waydabber/BetterDisplay) with CLI integration
  enabled; the DDC features used here do not need a Pro license.
- Apple Command Line Tools (`clang`, `swift`), and `jq` for the test check.
- Optional: [Handy](https://github.com/cjpais/Handy) for local speech-to-text,
  set to hold-to-talk on ⌃⌥⌘D.
- Quit Logi Options+; only one program may claim the MX Creative Console.

No script in this repository downloads or installs anything.

## Quick Start

1. Back up `~/.hammerspoon`, then clone this branch there.
2. Build and install the keypad helper from [vendor/](vendor/) (see AGENTS.md,
   Step 3), and grant the permissions macOS asks for.
3. Generate the keypad icons with `scripts/render-keypad-icons.swift`.
4. Check `MONITOR_NAME` and `INPUTS` in `dell-input.lua`, `MAX_HZ` in
   `dell-refresh.lua`, and the app bundle IDs in `keypad.lua`.
5. Reload Hammerspoon and run the tests in AGENTS.md before pressing keys.

## Lessons From This Desk

- A black or blinking USB-C picture was a 3 A cable. The monitor's supplied
  100 W cable fixed it; `pmset -g ac` should report 90 W.
- In HIGH DATA SPEED mode the USB-C link has 2 DisplayPort lanes. Above 60 Hz the
  picture went black, so the refresh guard caps the monitor at 60 Hz.
- Since macOS 27.2.1 the Mac also picks 10-bit colour at 60 Hz, which needs DSC on
  that link and stays black; the monitor then powers off after about 3 minutes.
  The guard selects the 8-bit RGB connection mode after every display change or wake.
- macOS stores a separate display configuration for the lid-closed layout; the
  guard corrects the rate it restores.
- A BetterDisplay "keepalive" virtual display strands windows on an invisible
  screen whenever this monitor drops. Don't use one with this setup.
- DDC reads can fail while the other computer is shown; writes from the Mac
  still switch the input.

## License

[MIT](LICENSE). Third-party components and trademarks:
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
