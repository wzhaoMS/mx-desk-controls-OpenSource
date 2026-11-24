# LG Desk Controls

The legacy 50/50 PBP controller is kept as `lg-pbp.lua`. The active keypad
uses dedicated input commands instead of the old PBP toggle.

## Behavior

| LCD position | Icon / label | Short press | Hold at least 1.2 seconds, then release |
| --- | --- | --- | --- |
| Top left | Apple / MAC | Request USB-C as main | Request USB-C, then turn PIP off; Mac only |
| Top middle | Opposing arrows / SWAP | Request the opposite of the last accepted source request | No separate hold action |
| Top right | Four panes / PC | Request DisplayPort as main | Request DisplayPort, then turn PIP off; PC only |
| Middle left | Inset / PIP | Enable PIP through the calibrated HID sequence | Turn PIP off without selecting a source |
| Center | Power / PC POWER | Explain that cold power-on is not configured | No power action |

The top row replaces PBP, TIDAL, and GLKVM. The center replaces Chrome and
middle-left PIP replaces Desktop. MIC, the app keys, and every
Dialpad action remain unchanged.

Initially configure PIP with the LG joystick: Settings > Input > PBP / PIP. Select
USB-C and DisplayPort, then use PIP Size and PIP Position for the bottom-left
inset. Source requests preserve an existing layout; the separate PIP key requests
on. The installed helper now uses HID, bypassing the silent CDC interface.
Both main-input on/off cycles passed independent layout checks, and the user
confirmed a visible Mac inset. The PC main area was black, possibly starting;
its healthy picture remains unverified. See the [current report](reports/lg-pip-reverse-engineering.md).
PIP-on temporarily selects Mac and restores the intended main only on success.
After Mac/control settling, a strict read-only HID preflight checks firmware
3.06 and the current layout. If the layout is already 1, PIP-on skips only the
redundant off write, keeping the settling and helper admission checks. Other
valid layouts retain the off step. No main source is inferred from this read.
Failure can leave Mac selected and clear SWAP intent; use MAC/PC explicitly.
No remote size or position control is implemented.

Brief black intervals can occur during a source or layout transition. The
source-only study observed no Mac display removal or mode change, but did not
measure panel pixels or prove a fixed firmware timer. PIP-on deliberately adds
more transitions than a source-only key. The 1.5-second software settling gate
is not a measured black-screen duration. See the
[switching investigation](reports/lg-pip-reverse-engineering.md#brief-black-screen-during-switching).

Corner actions execute on release, never both a short action and a hold action.
While held, `ONLY MAC` or `ONLY PC` previews keeping the labeled computer as
the only picture. Both short and long presses select that same computer, not
opposite targets. This is the same action whether the labeled
computer is currently main or inset. Mixed-key holds, holds longer than
10 seconds, and release events after keypad removal are discarded. During a
display transaction, source actions are locked and display `WAIT`, except that
an explicit MAC press during PIP-on cancels it and requests Mac after the writer
exits. The PIP hold preview is `PIP OFF`, and its long press is target-free.

SWAP remembers request intent, not proven hardware state. After startup, failure,
or idle display disconnection, it shows `CHOOSE` and opens a Mac/PC chooser when
pressed. After changing inputs manually, press MAC or PC once to resynchronize
intent. `RETRY` means a command or local connection check failed; there is no
automatic source or layout recovery. Icon accents are static, not active-source
indicators.

The implementation is [lg-input.lua](../lg-input.lua), called by
[keypad.lua](../keypad.lua). The legacy [lg-pbp.lua](../lg-pbp.lua) is retained for
the historical checkpoint but is not loaded by the active keypad.

## PC Power

The center key is a labeled placeholder. It sends no wake, shutdown, or power
command, and it does not switch the picture. Waking a PC from full shutdown
over Wi-Fi was not verified on this desk.

## Keepalive Display

Changing PBP briefly disconnects the physical display. On this closed-lid MacBook, that triggered `Clamshell Sleep` and then the normal password prompt. Temporary caffeinate assertions did not prevent it.

BetterDisplay's connected `MX PBP Keepalive` virtual display preserves a display connection across the transition. The user confirmed the small-screen key switched successfully without another password prompt after this display was added.

While the LG is away, macOS moves its windows onto the keepalive screen, which nothing displays, and many stay there after the LG returns. [lg-window-rescue.lua](../lg-window-rescue.lua) moves standard, visible windows that sit mostly on the keepalive back to the LG once the screens have been quiet for 3 s, and once when Hammerspoon loads. It waits while the input controller is busy, reads both UUIDs from `lg-input.lua`, never focuses or activates an app, and shows `LG: moved N window(s) back` when it moves something.

The input controller requires both the exact LG and keepalive display UUIDs
before any source or solo request. Do not remove this guard to work around a
missing virtual display. No password, automatic-login, FileVault, or MDM policy
settings were changed. No persistent caffeinate assertions are required.

## Dependencies And Restoration

- Hammerspoon, the existing `mxcc-helper`, and BetterDisplay must be available.
- PIP-on additionally requires the locally compiled `lg-pip-helper`, the LG HID
	control collection and firmware 3.06. Its guarded build is in the setup guide below.
- BetterDisplay 4.3.6 was installed from its official release after SHA-256, Developer ID signature, notarization, and Gatekeeper verification.
- Approved installer SHA-256: `04e212bb1dfa5622e1a0bba078f5aa454e82e73ae3209faf00be413b5dbc854f`.
- Developer ID: Istvan Toth, team `299YSU96J7`.
- The runtime does not download or install software. No Pro license was purchased.

The native LCD icons are generated locally with preinstalled Swift/AppKit:

```zsh
xcrun swift "$HOME/.hammerspoon/scripts/render-keypad-icons.swift" "$HOME/.hammerspoon/keypad-icons"
```

Generated PNGs stay in the ignored icon directory. No external assets are
downloaded, and the keypad does not run the generator automatically. Missing
icons degrade to readable labels. The five control PNGs are 128x128; the keypad
renders fixed 118x118 frames.

The [repository setup guide](../README.md) includes the pinned helper source
archive, local build instructions, required permissions, and machine-specific
UUID setup. Local diagnostics are available with
`hs.json.encode(keypad.recentActions())`: the latest 32 display-key actions in
memory, including held duration and request submission, not typed text.

To restore this setup, create a BetterDisplay virtual screen named `MX PBP Keepalive`, connect it as an extended non-primary screen, and keep LG as primary. The accepted layout is a 1280x720 at 60 Hz virtual screen at logical position (3360, 1418), with the LG at 3360x1418 HiDPI, 100 Hz. Recreating the virtual screen or moving to another Mac may change its OS UUID; verify the actual UUID before updating `GUARD_UUID` and the matching test fixture. Do the same for `DISPLAY_UUID` if the LG identity changes.

BetterDisplay stores the live virtual-display configuration outside this repository and must keep it connected. Restart/login restoration and operation after the Pro trial expires have not been validated in this checkpoint.

## Safety And Limits

- Source commands use alternate-address VCP `0xF4`: `0xD1` for USB-C and `0xD0`
	for DisplayPort. Solo, PIP-off and PIP-on staging use normal-address `0xD7=1`.
	The active controller never sends `0xD7=5` or a computer power command.
- DDC reads are unreliable. Fullscreen and Mac-main PIP can report the same
	`3360x1418@2x 100Hz` mode. No aspect ratio or resolution is used to infer which
	computer is main, or whether PIP is on.
- Empty or `true` stdout with exit 0 means BetterDisplay accepted a request, not
	proof that the monitor applied it. Three consecutive matching connection
	samples establish only local stability, never physical source verification.
- A transaction allows a five-second task timeout and up to 24 half-second
	connection samples per stage. The HID helper has a 50-second application
	budget, with a 55-second controlling task deadline. These do not guarantee
	an OS-level HID call cannot stall; the writer lock remains held until exit.
	Rapid overlapping presses are ignored.
- The read-only PIP preflight has its own five-second task deadline and the
	same writer ownership. A failed preflight does not fall back to extra writes.
	Its observation is used only inside that transaction, not as a source cache.
- HID submission is not per-key OSD acknowledgement. The calibrated sequence
	is sent once, with brightness liveness checks and final layout readback.
	Do not use another monitor-control writer or the physical OSD during it.
- A long press makes a solo request for the labeled computer. That request
	selects its source and waits for local settling before turning PIP off.
	Failed source requests never send the PIP-off step. Failures do not
	trigger retries, fallback inputs, PBP, or fullscreen recovery automatically.
- Cancellation retains the writer lock until the previous task actually exits.
	Stale callbacks cannot resume a cancelled transaction or a stopped chooser.
- Physical recovery: joystick Settings > Input > Input List > USB-C. To restore
	the inset, use PBP / PIP > PIP, then size/position. The legacy PBP recovery
	function is not part of this input-control workflow.
- Restart/login restoration and the keepalive's post-trial behavior remain
	unverified. Do not treat this as a permanent never-sleep configuration.

## Verification

The following tests use mocked display/process APIs and do not switch the real monitor.

```zsh
validation=$(/opt/homebrew/bin/hs -c 'local results={}; for _,name in ipairs({"lg-input-test.lua","lg-pbp-native-test.lua","lg-window-rescue-test.lua","keypad-pbp-test.lua"}) do local ok,message=pcall(dofile,os.getenv("HOME").."/.hammerspoon/tests/"..name); results[#results+1]={suite=name,ok=ok,message=tostring(message)} end; return hs.json.encode({suites=results})') &&
printf '%s\n' "$validation" &&
printf '%s\n' "$validation" | jq -Rse 'split("\n") | map(fromjson?) | any(has("suites") and (.suites | length == 4) and (.suites | all(.ok == true)))'
```

The JSON result is checked because the `hs` process exit status alone does not reliably indicate a Lua assertion failure.

## References

- [Exact-model profile: PIP enable remains unsupported via DDC/CI](https://github.com/tyvsmith/streamcontroller-lg-monitor-control/blob/6d7b0aeda66bab15e158153c57b893d901a34744/monitors/lg_ultragear_45gx950a.toml)
- [Exact-model DDC/PBP notes](https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors)
- [Community PBP hardware test](https://github.com/meer-cha/lg-input-switch/pull/6)
- [BetterDisplay CLI documentation](https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI)
- [Verified BetterDisplay release](https://github.com/waydabber/BetterDisplay/releases/tag/v4.3.6)