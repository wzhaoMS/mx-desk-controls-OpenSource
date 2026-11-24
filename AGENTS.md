# AGENTS.md — MX Desk Controls (`lg` branch)

Guide for AI coding agents and the people who hand this repository to them. This
branch controls an LG UltraGear 45GX950A-B (firmware 3.06) from a Logitech MX
Creative Keypad. The newer Alienware AW3926QW setup is on the `dell` branch.

To use it, tell your agent: *"Read AGENTS.md and set up the parts that match my
hardware. Stop at every HUMAN step."*

```yaml
repo_root: ~/.hammerspoon
runtime: Hammerspoon (Lua); entry point init.lua; CLI hs
monitor: LG UltraGear 45GX950A-B, firmware 3.06 (model and firmware specific)
sources: alternate-address DDC VCP 0xF4 through BetterDisplay (USB-C 0xD1, DisplayPort 0xD0); 0xD7=1 turns PIP off
pip_on: ~/.local/libexec/lg-pip-helper, built from scripts/lg-pip.swift; LG HID vendor page 0xff00, VID 0x043e PID 0x9a8a
keepalive: BetterDisplay virtual display "MX PBP Keepalive" (required before any source request)
control_surface: Logitech MX Creative Keypad + Dialpad via ~/.local/libexec/mxcc-helper
tests: 4 mocked Lua suites through hs -c, plus 1 Node test for the PIP navigation model
```

## How It Fits Together

| Physical control | Handled by | Result |
| --- | --- | --- |
| Keypad MAC / PC (short) | [keypad.lua](keypad.lua) → [lg-input.lua](lg-input.lua) | Request USB-C / DisplayPort as the main picture (VCP 0xF4) |
| Keypad MAC / PC (hold ≥ 1.2 s) | keypad.lua → lg-input.lua `solo` | Request that source, wait for the connection to settle, then turn PIP off (0xD7=1) |
| Keypad SWAP | keypad.lua → lg-input.lua `swap` | Opposite of the last accepted request; a chooser when unknown |
| Keypad PIP (short / hold) | keypad.lua → lg-input.lua → `lg-pip-helper` | Guarded PIP-on through HID / PIP off |
| Keypad PC POWER | keypad.lua | Placeholder alert only |
| Keypad MIC, app keys, Dialpad | keypad.lua | Mute toggle; Teams, VS Code, Terminal; push-to-talk ⌃⌥⌘D, Return, scrolling |
| Display changes | [lg-window-rescue.lua](lg-window-rescue.lua) | Moves windows stranded on the keepalive screen back to the LG after 3 s of quiet |

## Repository Map

| Path | Purpose | Loaded at startup |
| --- | --- | --- |
| [init.lua](init.lua) | Entry point | — |
| [keypad.lua](keypad.lua) | Keypad and Dialpad through `mxcc-helper`; short/long gestures; LCD painting | Yes |
| [lg-input.lua](lg-input.lua) | Source, solo and PIP transactions with settling checks and a single-writer lock | Through keypad.lua |
| [lg-window-rescue.lua](lg-window-rescue.lua) | Keepalive window rescue | Yes |
| [lg-pbp.lua](lg-pbp.lua) | Legacy 50/50 PBP controller, kept for reference | No |
| [scripts/lg-pip.swift](scripts/lg-pip.swift) | Source of `lg-pip-helper` (HID PIP enable, read-only probe, self-test) | Build step |
| [scripts/render-keypad-icons.swift](scripts/render-keypad-icons.swift) | Generates `keypad-icons/` locally | Build step |
| [vendor/](vendor/) | Pinned MIT source of the Creative Console helper | Build input |
| [tests/](tests/) | Mocked suites and the PIP navigation model test | Test |
| [docs/](docs/) | Setup notes, safety limits and the reverse-engineering report | Docs |

## Rules For Agents

- Do not download or install software. Report what is missing.
- Monitor writes (source, PIP, `lg-pip-helper` without `--probe-hid` or
  `--self-test`) need the user present: they change the picture. Never run the LG
  modules or helper against another monitor model or firmware.
- Do not remove the keepalive or exact-UUID guards to work around a missing
  display. Do not use the physical OSD or another monitor-control app during a
  transaction.
- Run one `mxcc-helper` only; quit Logi Options+.
- Keep references to `hs.timer` objects; stop new modules in
  `hs.shutdownCallback`.
- Never commit machine identifiers (display UUIDs, serial numbers).

## Setup Runbook

### Step 1 — HUMAN: Install The Apps

Hammerspoon, BetterDisplay (CLI integration on), Apple Command Line Tools, `jq`,
Node.js, and optionally Handy (hold-to-talk on ⌃⌥⌘D). Quit Logi Options+.

### Step 2 — Place The Repository

```zsh
{ [ ! -e ~/.hammerspoon ] || mv ~/.hammerspoon ~/.hammerspoon.backup-$(date +%Y%m%d-%H%M%S); } &&
git clone --branch lg <this repository's URL> ~/.hammerspoon
```

### Step 3 — Build The Keypad Helper

```zsh
cd ~/.hammerspoon &&
printf '%s\n' 'b66daef1334044c1663c5cea2658c221e364f5c00c00ab58ecfde94e79db21dd  vendor/mxcc-helper-source-2227b5b.tar.gz' | shasum -a 256 -c - &&
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/mxcc-build.XXXXXX") &&
tar -xzf vendor/mxcc-helper-source-2227b5b.tar.gz -C "$build_dir" --strip-components=1 &&
xcrun clang -Wall -O2 -framework IOKit -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework ImageIO -o "$build_dir/mxcc-helper" "$build_dir/src/helper.c" &&
mkdir -p "$HOME/.local/libexec" &&
install -m 755 "$build_dir/mxcc-helper" "$HOME/.local/libexec/mxcc-helper"
```

### Step 4 — Build The PIP Helper And Icons

```zsh
xcrun swift "$HOME/.hammerspoon/scripts/lg-pip.swift" --self-test &&
pip_build=$(mktemp -d "${TMPDIR:-/tmp}/lg-pip-build.XXXXXX") &&
xcrun swiftc "$HOME/.hammerspoon/scripts/lg-pip.swift" -o "$pip_build/lg-pip-helper" &&
install -d "$HOME/.local/libexec" &&
install -m 755 "$pip_build/lg-pip-helper" "$HOME/.local/libexec/lg-pip-helper" &&
xcrun swift "$HOME/.hammerspoon/scripts/render-keypad-icons.swift" "$HOME/.hammerspoon/keypad-icons"
```

`lg-pip-helper --probe-hid` performs reads only. A firmware other than 3.06 is
rejected before any OSD event. If the compiler rejects the default SDK, set
`SDKROOT` to an SDK that matches it.

### Step 5 — HUMAN + Agent: Keepalive Display And UUIDs

1. HUMAN: in BetterDisplay, create a virtual screen named `MX PBP Keepalive`
   (1280×720 at 60 Hz worked), connect it as an extended, non-primary screen, and
   keep the LG primary.
2. Find your display UUIDs in the Hammerspoon console:

   ```lua
   local displays = {}
   for _, screen in ipairs(hs.screen.allScreens()) do
     displays[#displays + 1] = { name = screen:name(), uuid = screen:getUUID() }
   end
   return hs.json.encode(displays)
   ```

3. Put the LG's UUID in `DISPLAY_UUID` and the keepalive's in `GUARD_UUID`, in
   both `lg-input.lua` and `lg-pbp.lua`. The shipped values are placeholders. The
   tests use the placeholders as fixtures; if you change the module constants,
   change `displayUUID` / `guardUUID` at the top of `tests/lg-input-test.lua` and
   `tests/lg-pbp-native-test.lua` to match.

### Step 6 — HUMAN: Monitor Menu And Permissions

In the LG menu, configure PBP / PIP with USB-C and DisplayPort and the inset size
and position once. Start Hammerspoon, install the `hs` CLI, and approve
Accessibility and Input Monitoring when macOS asks.

### Step 7 — Verify

```zsh
out=$(hs -c 'local r={} for _,n in ipairs({"keypad-pbp-test.lua","lg-input-test.lua","lg-pbp-native-test.lua","lg-window-rescue-test.lua"}) do local ok,m=pcall(dofile,os.getenv("HOME").."/.hammerspoon/tests/"..n) r[#r+1]={suite=n,ok=ok,message=tostring(m)} end return hs.json.encode({suites=r})')
printf '%s\n' "$out" | jq -Rse 'split("\n") | map(fromjson?) | any(has("suites") and (.suites | length == 4) and (.suites | all(.ok == true)))'
node --test ~/.hammerspoon/tests/lg-pip-navigation-model.test.mjs
```

Expected: `true`, and all Node tests passing. Then the HUMAN physical check: MAC,
PC, SWAP, PIP on/off, with the joystick (Input → USB-C) as the recovery path.

Read-only status: `hs -c 'return hs.json.encode(require("lg-input").status())'`
and `hs -c 'return hs.json.encode(lgWindowRescue.status())'`.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Alert "connect MX PBP Keepalive before switching" | The keepalive virtual display is disconnected or its UUID changed; reconnect it in BetterDisplay and update `GUARD_UUID` |
| Alert "LG is disconnected" | The LG UUID differs from `DISPLAY_UUID`, or the LG shows another input; select USB-C with the joystick |
| A window vanished after a source or PIP switch | It is on the keepalive screen; `hs -c 'return lgWindowRescue.rescue()'` moves it back |
| Mac slept during a PBP or source change with the lid closed | Keep the keepalive display connected; macOS sleeps when no display remains |
| PIP-on shows `RETRY` | Firmware, HID interface or layout preflight failed; nothing further was sent. Use the joystick: PBP / PIP → PIP |
