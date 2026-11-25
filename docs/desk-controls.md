# Desk Controls (Alienware AW3926QW)

The MX Creative Keypad's top row switches an Alienware AW3926QW between a Mac and
a Windows PC. The monitor is a KVM: the Mac uses its USB-C input and USB-C
upstream port, the PC uses DisplayPort and the USB-B upstream port, and the
monitor's USB hub follows the selected input.

## Behavior

| LCD position | Label | Press |
| --- | --- | --- |
| Top left | MAC | Select the monitor's USB-C input (VCP `0x60` = `0x1B`) |
| Top middle | SWAP | Read the current input; USB-C goes to the PC, anything else to USB-C |
| Top right | PC | Select the monitor's DisplayPort input (`0x0F`) |
| Middle left | Desktop | Show Desktop (fn-F11) |
| Center | Chrome | Open or focus Chrome |

- Keys act once, on key-down. There are no hold actions and no PIP or PBP keys.
- `WAIT` shows while a BetterDisplay command runs; presses are ignored, not
  queued. `RETRY` means the last command failed or the monitor was not found.
  Nothing is retried automatically.
- If SWAP cannot read the current input, it selects USB-C (the Mac). That is a
  no-op when the Mac is already showing.
- The monitor is found by its macOS name, `AW3926QW`, on every press, because
  macOS gives it a different display UUID per cable and port. If the Mac does not
  currently see the monitor, the key shows an alert and sends nothing: use the
  monitor's own input button.
- The PC is assumed to be on DisplayPort. If it uses HDMI, set `INPUTS.pc` in
  [dell-input.lua](../dell-input.lua) to `0x11` (HDMI 1) or `0x12` (HDMI 2), and
  change the matching value in [the test](../tests/dell-input-test.lua).

The implementation is [dell-input.lua](../dell-input.lua), called by
[keypad.lua](../keypad.lua). Commands use standard DDC/CI through the BetterDisplay
CLI, for example `set -UUID=<uuid> -ddc -vcp=0x60 -value=0x1B`. An accepted reply
means the monitor received the request, not that a picture is visible.

## Connection Notes

Observed with an Apple Silicon MacBook Pro (Thunderbolt 5) on the monitor's USB-C
upstream port:

- **A black or blinking USB-C picture was the cable.** With a 3 A USB-C cable
  (`pmset -g ac` reported 60 W) the panel stayed black or blinked at 165 and
  60 Hz, while DDC and the USB hub kept working. With the monitor's supplied
  100 W cable (`pmset -g ac` reports 90 W) the picture works.
- The link is DisplayPort 2.1 Alt Mode on 2 lanes of UHBR10 (about 19 Gbps)
  because the monitor's **USB-C Prioritization** is HIGH DATA SPEED, which Dell
  recommends for DP 2.1 hosts. At 5120x2160, 120 and 165 Hz need DSC compression
  on that link, and 165 Hz still showed a black picture with the good cable.
  [dell-refresh.lua](../dell-refresh.lua) therefore caps the monitor at
  `MAX_HZ` = 60. HIGH RESOLUTION (4 lanes; the hub drops to USB 2.0) is the path
  to test higher rates; raise `MAX_HZ` only after a picture is confirmed.
- macOS remembers display settings per set of connected displays. The lid-closed
  set restored 165 Hz and went black; the refresh guard corrects it about 1.5 s
  after any display change.
- **After the macOS 27.2.1 update the picture was black at 60 Hz too.** About 3
  minutes after a connect without a picture the monitor powered down and dropped
  USB-C entirely (power, hub and video; `pmset -g log` alternated `Using AC` and
  `Using Batt`). The kernel log
  (`log show --predicate 'eventMessage CONTAINS "mode_set_gated"'`) showed every
  connect as `5120x2160@59 Hz DSC=YES`: macOS now drives the monitor at 10 bits
  per colour, about 21.7 Gbps at 60 Hz against the link's 19.2 Gbps, so it needs
  DSC, which this link shows black. 8-bit RGB needs about 16.9 Gbps and runs
  without DSC (`DSC=NO`); the monitor showed it as soon as it was on USB-C. After
  every display change or wake [dell-refresh.lua](../dell-refresh.lua) therefore
  selects the `8bit SDR RGB Full` connection mode with
  `BetterDisplay get|set -name=AW3926QW -connectionMode`, because BetterDisplay
  does not keep it across reconnects. HDR is left alone. Before login Hammerspoon
  is not running and the monitor stays black: log in on the built-in display.
  While the USB-C picture is black the monitor may move to DisplayPort on its own
  (VCP `0x60` reads `0x1B0F`); press MAC once the Mac sends 8-bit.
- Input switching from the Mac works in both directions, including while the PC
  is on screen. The Mac keeps the monitor connected throughout.
- Reads of VCP `0x60` return USB-C as `0x1B1B` and DisplayPort as `0x1B0F`; the
  low byte is the input. Reads sometimes fail while another input is shown.
- Plug the MX Creative Keypad into the Mac directly. On the monitor's hub it
  follows the KVM to the PC, and MAC can no longer be pressed from the Mac.
- With the lid closed, any monitor dropout leaves macOS without a display and the
  Mac sleeps (`Clamshell Sleep` in `pmset -g log`), so the monitor stays black
  until the Mac wakes.

## Mouse Buttons

[mouse-buttons.lua](../mouse-buttons.lua) maps standard mouse buttons on the Mac
(built with a ROG HARPE II on the monitor's KVM hub):

| Button | Action |
| --- | --- |
| Back, held | Push-to-talk: holds ⌃⌥⌘D for [Handy](https://github.com/cjpais/Handy), released with the button; 120 s safety release |
| Forward | Return (send) |
| Middle | Region screenshot copied to the clipboard (⌃⌘⇧4) |

The buttons keep their normal behavior on the PC. While Hammerspoon runs, every
mouse that sends these standard buttons gets the same mapping.

## No Keepalive Display

An earlier LG setup (branch `lg`) kept a BetterDisplay virtual screen connected so
a closed-lid Mac survived monitor re-enumeration. With this monitor it did harm:
each time the monitor dropped, macOS made the invisible virtual screen the main
display and moved windows onto it, so the monitor showed an empty desktop. It
also did not prevent sleep, because the same USB-C cable powers the Mac and that
dropped too. Do not add a keepalive virtual display for this setup.

## Dependencies

- Hammerspoon, the `mxcc-helper` built from [vendor/](../vendor/), and
  BetterDisplay with its CLI integration enabled. DDC/CI must be on in the
  monitor's menu.
- The runtime does not download or install software.

The LCD icons are generated locally with preinstalled Swift/AppKit:

```zsh
xcrun swift "$HOME/.hammerspoon/scripts/render-keypad-icons.swift" "$HOME/.hammerspoon/keypad-icons"
```

If the compiler rejects the default SDK, prefix the command with
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/<an SDK that matches the compiler>`.
Missing icons degrade to readable labels.

## Verification

The mocked suites are listed in [AGENTS.md](../AGENTS.md#verify). They switch no
real monitor. Read-only state:

```zsh
hs -c 'return hs.json.encode(require("dell-input").status())'
hs -c 'return hs.json.encode(dellRefresh.status())'
hs -c 'return hs.json.encode(keypad.recentActions())'
```

Physical check, with the user present (an input switch changes what the monitor
shows):

1. Switch the monitor to USB-C. The Mac's desktop should appear; if it is black,
   see [Connection Notes](#connection-notes).
2. With the PC running, press PC: the monitor shows the PC. Press MAC: the Mac
   returns. If a key alerts that the monitor is not connected, use the monitor's
   input button.
3. Press SWAP twice: PC, then Mac.
