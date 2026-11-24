# MX Desk Controls — LG UltraGear 45GX950A-B

A Hammerspoon configuration that turns a Logitech MX Creative Console into desk
controls for a Mac and a Windows PC sharing an LG UltraGear 45GX950A-B: source
switching, a picture-in-picture (PIP) key backed by a reverse-engineered HID
control path, push-to-talk dictation and one-press app launch.

**Agents:** start with [AGENTS.md](AGENTS.md).

> The LG command values and the PIP helper are **model and firmware specific**
> (45GX950A-B, firmware 3.06). Do not use them on another monitor model or
> firmware. The newer setup for an Alienware AW3926QW lives on the `dell` branch.

## Key Layout

| | | |
| --- | --- | --- |
| MAC | SWAP | PC |
| PIP | PC POWER (unconfigured) | MIC |
| Teams | VS Code | Terminal |

- **MAC / PC**, short press: request that computer as the main picture.
  Hold at least 1.2 s, then release: turn PIP off and show only that computer
  (the preview reads `ONLY MAC` / `ONLY PC`).
- **SWAP**: request the opposite of the last accepted source request; if unknown,
  choose once. This is request intent, not hardware readback.
- **PIP**, short press: guarded PIP-on through the LG USB HID control interface;
  hold at least 1.2 s to turn PIP off (`PIP OFF`).
- **PC POWER** is a labeled placeholder and sends nothing.
- `WAIT` means a transaction is running and presses are ignored; `RETRY` means a
  command or check failed. There is no automatic recovery; use the explicit keys
  or the monitor joystick.

How it works, the safety limits and the research behind the PIP path:
[docs/lg-pbp.md](docs/lg-pbp.md),
[docs/reports/lg-pip-reverse-engineering.md](docs/reports/lg-pip-reverse-engineering.md),
[docs/lg-pip-research.md](docs/lg-pip-research.md).

## Hardware

| Part | Model | Notes |
| --- | --- | --- |
| Mac | Apple Silicon MacBook (lid closed) | USB-C to the monitor |
| Monitor | LG UltraGear 45GX950A-B, firmware 3.06 | PC on DisplayPort; LG USB control interface VID 0x043e, PID 0x9a8a |
| Control surface | Logitech MX Creative Keypad + Dialpad | |

## Requirements

- Hammerspoon with the `hs` CLI, BetterDisplay with CLI integration, Apple
  Command Line Tools, `jq`, and Node.js for the PIP navigation model test.
- A BetterDisplay virtual display named `MX PBP Keepalive`, connected as an
  extended, non-primary screen, so a closed-lid Mac survives the monitor's
  re-enumeration during source changes. `lg-window-rescue.lua` moves windows
  that macOS leaves on that invisible screen back to the LG.
- Your own display UUIDs in `lg-input.lua` and `lg-pbp.lua` (placeholders ship in
  this repository); see AGENTS.md, Step 5.

No script in this repository downloads or installs anything.

## License

[MIT](LICENSE). Third-party components and trademarks:
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
