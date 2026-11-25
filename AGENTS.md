# AGENTS.md — MX Desk Controls (`dell` branch)

Guide for AI coding agents (GitHub Copilot, Codex, Claude Code, and others) and
for the people who hand this repository to them. It describes what the code does,
how the pieces connect, and how to set it up on another Mac.

To use it, tell your agent: *"Read AGENTS.md and set up the parts that match my
hardware. Stop at every HUMAN step."*

```yaml
repo_root: ~/.hammerspoon
runtime: Hammerspoon (Lua); entry point init.lua; CLI hs
monitor: Alienware AW3926QW, KVM (USB-C upstream -> Mac, USB-B upstream -> PC), PC on DisplayPort
ddc: BetterDisplay CLI, VCP 0x60 (USB-C 0x1B, DisplayPort 0x0F, HDMI1 0x11, HDMI2 0x12)
control_surface: Logitech MX Creative Keypad + Dialpad via ~/.local/libexec/mxcc-helper (child process of Hammerspoon)
mouse: any mouse with standard back/forward/middle buttons
dictation: optional Handy, hold-to-talk chord control+option+command+d
tests: 4 mocked Lua suites run through hs -c
other_branches: lg (LG UltraGear 45GX950A-B PBP/PIP setup)
```

## How It Fits Together

| Physical control | Handled by | macOS receives | Result |
| --- | --- | --- | --- |
| Keypad MAC / PC | [keypad.lua](keypad.lua) → [dell-input.lua](dell-input.lua) | — | BetterDisplay sets VCP 0x60 to USB-C / DisplayPort |
| Keypad SWAP | keypad.lua → dell-input.lua | — | Reads VCP 0x60, selects the other input; unreadable → USB-C |
| Keypad Desktop | keypad.lua `showDesktop` | fn-F11 | Show Desktop |
| Keypad center, bottom row | keypad.lua `KEYS[4]`, `[6..8]` | — | Open or focus Chrome, Teams, VS Code, Terminal |
| Keypad MIC | keypad.lua `toggleMic` | — | Mute or unmute every physical input; the key turns red |
| Keypad page buttons | keypad.lua | ⌘[ and ⌘] | Back, forward |
| Dialpad keys 1, 2 | keypad.lua `DIAL_KEYS` | — | Open or focus VS Code, Terminal |
| Dialpad key 3 | keypad.lua `DIAL_KEYS[3]` | Return | Send |
| Dialpad key 4 (hold) | keypad.lua `DIAL_KEYS[4]` | ⌃⌥⌘D held | Push-to-talk, 120 s safety release |
| Dialpad dial, roller | keypad.lua `onDial` | Scroll events | Vertical, horizontal scroll |
| Mouse back (hold) | [mouse-buttons.lua](mouse-buttons.lua) | ⌃⌥⌘D held | Push-to-talk, 120 s safety release |
| Mouse forward | mouse-buttons.lua | Return | Send |
| Mouse middle | mouse-buttons.lua | ⌃⌘⇧4 | Region screenshot copied to the clipboard |
| Any display change or wake | [dell-refresh.lua](dell-refresh.lua) | — | After 1.5 s caps the AW3926QW at `MAX_HZ` (60), then selects the 8-bit RGB connection mode (no DSC) |

Every talk control holds one chord, ⌃⌥⌘D. A speech-to-text app such as Handy
must use exactly that chord in hold (push-to-talk) mode. Nothing is sent
automatically; Return is a separate button.

## Repository Map

| Path | Purpose | Loaded at startup |
| --- | --- | --- |
| [init.lua](init.lua) | Entry point; starts the modules, stops them in `hs.shutdownCallback` | — |
| [keypad.lua](keypad.lua) | Runs `mxcc-helper` over stdin/stdout, paints the 3×3 LCD keys, handles keypad and Dialpad events | Yes |
| [dell-input.lua](dell-input.lua) | Monitor input switching; finds the monitor by name on every press; one BetterDisplay process at a time with a 5 s timeout | Through keypad.lua |
| [dell-refresh.lua](dell-refresh.lua) | Refresh-rate cap and 8-bit connection mode after display changes and wakes; one BetterDisplay process at a time with a 10 s timeout | Yes |
| [mouse-buttons.lua](mouse-buttons.lua) | Mouse back, forward and middle button actions | Yes |
| [scripts/render-keypad-icons.swift](scripts/render-keypad-icons.swift) | Generates `keypad-icons/` locally (ignored by git) | Build step |
| [vendor/](vendor/) | Pinned MIT source of the Creative Console helper and its provenance | Build input |
| [tests/](tests/) | Mocked suites; each loads its module into a sandbox with a stub `hs` | Test |
| [docs/desk-controls.md](docs/desk-controls.md) | Behavior, connection findings, physical checks | Docs |

## Rules For Agents

- Do not download or install software, models or packages. Report what is
  missing and ask the user to install it from the official source.
- Never send an input write (`set ... -vcp=0x60`) to the monitor without the user
  present and agreeing: it changes what the monitor shows and can blank the
  screen the user is working on. Read-only `get` calls are fine.
- Keep `MAX_HZ` at 60 unless the user has switched the monitor to HIGH
  RESOLUTION and confirmed a picture at the higher rate.
- Keep the 8-bit connection mode on the 2-lane link: 10-bit at 5120x2160@60 Hz
  needs DSC there and shows a black picture.
- Keep the MX Creative Keypad plugged into the Mac, not into the monitor's hub.
- Run one `mxcc-helper` only, and no other app (such as Logi Options+) that
  claims the console.
- Every module exposes `start()`/`stop()`; stop any new module in
  `hs.shutdownCallback`. Keep references to `hs.timer` objects; an unreferenced
  timer can be garbage-collected and never fire.
- Do not steal focus or send real keystrokes while testing. Physical tests belong
  to the user.
- Never commit machine identifiers: display UUIDs, serial numbers, device names
  or account names.

## Setup Runbook

Steps marked **HUMAN** need a person: app installs, macOS permission prompts,
monitor menus and physical tests.

### Step 1 — HUMAN: Install The Apps

From official sources: Hammerspoon, BetterDisplay, Apple Command Line Tools
(`xcode-select --install`), `jq`, and optionally Handy. Quit Logi Options+.
In BetterDisplay, enable the CLI integration. On the monitor, enable DDC/CI.

### Step 2 — Place The Repository

Back up any existing configuration, then put this branch at `~/.hammerspoon`:

```zsh
{ [ ! -e ~/.hammerspoon ] || mv ~/.hammerspoon ~/.hammerspoon.backup-$(date +%Y%m%d-%H%M%S); } &&
git clone --branch dell <this repository's URL> ~/.hammerspoon
```

### Step 3 — Build The Keypad Helper

From the repository root, with the compiler preinstalled:

```zsh
cd ~/.hammerspoon &&
printf '%s\n' 'b66daef1334044c1663c5cea2658c221e364f5c00c00ab58ecfde94e79db21dd  vendor/mxcc-helper-source-2227b5b.tar.gz' | shasum -a 256 -c - &&
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/mxcc-build.XXXXXX") &&
tar -xzf vendor/mxcc-helper-source-2227b5b.tar.gz -C "$build_dir" --strip-components=1 &&
xcrun clang -Wall -O2 -framework IOKit -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework ImageIO -o "$build_dir/mxcc-helper" "$build_dir/src/helper.c" &&
mkdir -p "$HOME/.local/libexec" &&
install -m 755 "$build_dir/mxcc-helper" "$HOME/.local/libexec/mxcc-helper"
```

If linking fails with `unknown architecture` or `tapi error`, the default SDK is
newer than the linker: set `SDKROOT` to an older SDK from
`ls /Library/Developer/CommandLineTools/SDKs/` and run the block again.

### Step 4 — Generate The Icons

```zsh
xcrun swift "$HOME/.hammerspoon/scripts/render-keypad-icons.swift" "$HOME/.hammerspoon/keypad-icons"
```

### Step 5 — Configure For Your Hardware

| What | Where | Default |
| --- | --- | --- |
| Monitor name (as macOS reports it) | dell-input.lua `MONITOR_NAME`, dell-refresh.lua `MONITOR_NAME` | `AW3926QW` |
| Input values | dell-input.lua `INPUTS` | Mac `0x1B` (USB-C), PC `0x0F` (DisplayPort) |
| Refresh cap | dell-refresh.lua `MAX_HZ` | 60 |
| Keypad apps | keypad.lua `KEYS[4]`, `[6]`, `[7]`, `[8]` | Chrome, Teams, VS Code, Terminal |
| Dialpad apps | keypad.lua `DIAL_KEYS[1]`, `[2]` | VS Code, Terminal |
| Talk chord | keypad.lua and mouse-buttons.lua | ⌃⌥⌘D |

The monitor name is what Hammerspoon's console prints for:

```lua
local names = {}
for _, screen in ipairs(hs.screen.allScreens()) do names[#names + 1] = screen:name() end
return hs.json.encode(names)
```

Get an app's bundle ID with `osascript -e 'id of app "Microsoft Teams"'`. When
you change a value that a test checks, change the test in the same edit.

### Step 6 — HUMAN: Start Hammerspoon And Grant Permissions

Start Hammerspoon (or use Reload Config), install its `hs` CLI, and approve
Accessibility and Input Monitoring for Hammerspoon and `mxcc-helper` when macOS
asks. Permissions follow the code signature; approve again after a rebuild.

### Step 7 — Verify, Then HUMAN Physical Check

Run the suites below, then follow the physical check in
[docs/desk-controls.md](docs/desk-controls.md#verification).

## Verify

Mocked suites change no apps, focus or hardware. Check the JSON, because the
`hs` exit status does not reliably report a Lua assertion failure:

```zsh
out=$(hs -c 'local r={} for _,n in ipairs({"dell-input-test.lua","dell-refresh-test.lua","keypad-test.lua","mouse-buttons-test.lua"}) do local ok,m=pcall(dofile,os.getenv("HOME").."/.hammerspoon/tests/"..n) r[#r+1]={suite=n,ok=ok,message=tostring(m)} end return hs.json.encode({suites=r})')
printf '%s\n' "$out" | jq -Rse 'split("\n") | map(fromjson?) | any(has("suites") and (.suites | length == 4) and (.suites | all(.ok == true)))'
```

Expected: `true`. The suites resolve modules relative to their own location, so
they also run from a clone elsewhere (replace the path in `dofile`).

Read-only status:

```zsh
hs -c 'return hs.json.encode(require("dell-input").status())'
hs -c 'return hs.json.encode(dellRefresh.status())'
hs -c 'return hs.json.encode(mouseButtons.status())'
hs -c 'return hs.json.encode(keypad.recentActions())'
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Keypad keys blank or dead | `~/.local/libexec/mxcc-helper` exists and is executable; Logi Options+ is quit; the Hammerspoon console shows the helper's messages; reload Hammerspoon |
| MAC/PC/SWAP show `RETRY` or alert "not connected" | The Mac does not see the monitor, or BetterDisplay failed. Use the monitor's input button; check `require("dell-input").status()` and the Hammerspoon console |
| Monitor black or blinking on USB-C while the Mac lists it | Use the monitor's supplied 100 W USB-C cable (`pmset -g ac` should report 90 W). Keep `MAX_HZ` at 60 unless HIGH RESOLUTION gives a picture higher |
| Monitor black after closing the lid | The refresh guard corrects the saved lid-closed rate within about 1.5 s; check `dellRefresh.status()` |
| Monitor black at 60 Hz, then the Mac loses it (power, hub and video) about 3 minutes later | macOS 27.2.1 picked 10-bit, which needs DSC. The Hammerspoon console should show `[dell-refresh] AW3926QW … 10bit … -> … 8bit SDR RGB Full … ok=true` and the kernel log `DSC=NO`. Nothing runs before login; log in on the built-in display. If the monitor moved to the PC input meanwhile, press MAC |
| Cannot switch back from the PC with the keypad | The keypad is on the monitor's hub and followed the KVM to the PC; plug it into the Mac |
| Holding a talk button records nothing | The speech-to-text app uses exactly ⌃⌥⌘D in hold mode; Hammerspoon has Accessibility; MIC is not red |
| Middle click does not screenshot | macOS "Copy picture of selected area to the clipboard" (⌃⌘⇧4) is enabled in Keyboard Shortcuts |
