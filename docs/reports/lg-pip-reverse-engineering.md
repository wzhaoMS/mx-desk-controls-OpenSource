# LG 45GX950A PIP Reverse-Engineering Report

Investigation started: 2026-09-09. Latest checkpoint: 2026-09-10, afternoon.
The dedicated PIP key now opens PIP through HID; a Mac inset was user-confirmed.
Healthy PC video and full visual acceptance remain open. Update the checklist as evidence
changes; do not restart from the early unsuccessful D7 experiments.

## Current Finding

The middle-left key is now PIP: short-on, 1.2-second long-off, with a native
icon and `PIP OFF` hold preview. [lg-input.lua](../../lg-input.lua) owns the full
transaction; [lg-pip.swift](../../scripts/lg-pip.swift) is the installed native
HID helper. Existing MAC/SWAP/PC, microphone, Dialpad and application keys
remain in place. The center PC POWER key is still unconfigured.

The production enable path temporarily establishes Mac main, waits for the LG
USB control identity as well as stable video, reads the current layout and only
closes it if it is not already single picture, validates
firmware 3.06 through the verified HID collection, and executes the calibrated
nine-frame reset/menu sequence once. It restores PC only after the helper and
connection checks pass. A MAC press can cancel this transaction; recovery waits
for the writer to exit. Unknown main intent uses an operation-specific chooser.

**The transport blocker is bypassed and PIP opening is demonstrated.** CDC
remained silent, including a reversible DTR/RTS comparison: modem bits were
already 6 and asserting them changed neither bits nor the empty brightness
response. The same monitor's HID collection continued returning brightness 75,
firmware 774 and layout 1 with valid checksums. The formal helper was moved to
that working interface, removing CDC and the extra DDC firmware subprocess.

The installed HID version passed Mac-main and PC-main `solo -> pipOn -> pipOff`
cycles with independent BetterDisplay D7 values `1 -> 0 -> 1`. After the final
readback-result cleanup, Mac again passed all three steps and PC passed off/on;
the final PC-on mode put Mac at 1920x1080, scale 1, 60 Hz. All recorded reads
succeeded on their first attempt. These are hardware control checks, not images.

The user then reported that the Mac small picture was visible and the PC main
area was black, perhaps still starting. This confirms an inset, not a healthy
PC source or the cause of black video. No PC power operation was performed.
MAC was selected afterward without disabling PIP; independent D7 remained 0,
Mac returned to 3360x1418@2x 100 Hz, and the controller was idle.

The controller reports a bounded `lastError` and does not silently continue to
PC after helper failure.
Failure after anchoring can leave the Mac main request in effect and clears
remembered SWAP intent. There is no automatic restoration to the original PC
target on error. Explicit MAC/PC selection remains the recovery path.

Final visual acceptance of both healthy sources, inset position and external
OSD-state idempotence remains open. D7=0 alone is still not a PIP identity.
The user-confirmed inset and calibrated sequence are additional evidence.
The HID path does not require serial reconnection or a firmware change.

### Earlier Physical Evidence

Native hardware PIP was successfully reopened through the monitor's ordinary
OSD key-event path over its USB CDC serial interface. An independent D7 read
changed from 1 to 0, and the user confirmed that PC remained the main picture
while Mac returned in the bottom-left inset.

Later static analysis shows D7=0 is a catch-all for several internal modes,
not a unique PIP identifier. The physical confirmation is essential to the
successful test above. Do not use a zero read alone as an automatic success gate.

The reverse-direction sequence passed a supervised Mac-main experiment, but
the subsequent PC-main experiment produced a black screen. The user had to
press MAC to recover. The bare navigation sequence is therefore NOT accepted
as a main-preserving general PIP control and must not be bound to the keypad.

**Earlier observed state: Mac picture recovered by the user; valid D7=0**, with
Mac mode 3360x1418@2x 100 Hz, keepalive connected, and the controller idle. The
last corrective MAC press was recorded as a 125 ms short press. D7=0 does not
independently establish the final input arrangement. Each experimental OSD key
had brightness baseline 75; Auto Input Switch was not changed. No further
hardware writes were sent in that earlier review. The afternoon experiments
and production activation above supersede its runtime status.

## User Requirements And Boundaries

- Middle-left Desktop key, row 2 / column 1, zero-based LCD index 3: short press
  enables the other connected computer as PIP while retaining the current main
  input; long press closes PIP only. This is NOT the bottom-left keypad key.
  Bottom-left describes the desired inset position, not the key's location.
- Preserve top-row MAC / SWAP / PC and the final 1.2-second same-target long
  presses. Keep PC POWER as an unconfigured placeholder until display work is
  complete. Keyboard-host switching is tracked separately as KB-01; no mouse
  or audio-routing changes are part of this PIP task.
- Auto Input Switch was intentionally disabled by the user. Never enable or
  alter it. Its row was gray and skipped in both tested layout states.
- The user authorized further independent investigation, Opus 5 assistance,
  a Markdown report with checkboxes, and committing/pushing the related work.
  Do not require repeated physical menu observations while the user is asleep.
- Firmware download and offline static analysis were explicitly approved.
  No flashing, firmware execution, arbitrary monitor-memory writes, service
  resets, calibration writes, or additional software installation is approved.
- Never weaken macOS password, sleep security, FileVault, or MDM policy.
- Do not replay non-idempotent key sequences after an unknown tool outcome.
  Read state first. Never infer physical success from CLI exit status alone.

## Brief Black Screen During Switching

The user subsequently asked whether the brief black interval on each switch is
a firmware design choice. The controlling paths distinguish three operations:

- MAC/PC short press submits one absolute alternate F4 source request. It does
  not write the PIP layout, simulate a blackout, sleep the Mac, or retry the
  setting. Repeating the current target still resubmits that absolute command.
- PIP-off writes D7=1 once without selecting a source. Changing picture layout
  can change the monitor's input processing and advertised video modes.
- PIP-on has several intentional transitions: Mac anchor, single picture,
  the fixed PIP menu sequence, and PC restoration when PC was requested.
  The latest optimization reads first and omits the single-picture write when
  that state is already confirmed; it does not remove the Mac anchor.
  Therefore some extra interruptions are introduced by our current sequence,
  not evidence of a mandatory single firmware delay. Removing the anchor is
  not yet validated, especially when the Mac USB-control collection disappears
  with PC-only output.

A passive controller/screen observer recorded one source-only MAC -> PC -> MAC
cycle without layout, refresh-rate, HDR or power writes. All three requests
completed. Command submission to the `settling` phase took approximately
264 ms, 305 ms and 602 ms; the additional settling period was about 1.56 s per
request and is our software stability gate, NOT measured black-screen duration.
The observed Mac mode stayed 3360x1418@2x100Hz, both physical and keepalive
displays stayed registered, and no screen-watcher event was received. The
watcher does not sample pixels or prove which computer appeared on the panel.

This trace does not support a Mac display disconnect or sleep as the cause of
that particular short interval. A monitor-internal input/scaler transition and
signal reacquisition is consistent with it, but the exact firmware mute timer,
link-training steps, HDCP/DSC/VRR participation, and panel blackout duration
were not measured. Do not call these proven faults or promise a firmware update
will remove the interval. Earlier source/layout changes DID change the Mac's
advertised mode, so the no-mode-change observation must not be generalized.

Separately, the most recent user PIP short press before this study left
`HID brightness baseline missing; OSD event not sent`. That is a real control
failure, not normal transient source blanking. The later source-only cycle
cleared the error and left MAC intent idle, but did not revalidate PIP-on or
prove this intermittent control failure fixed. Its frame position is unknown.

Further improvement requires trustworthy source state before suppressing source
requests, or validation of a PIP path with fewer source transitions. Reducing
the 1.5-second stability wait alone does not make the panel lock onto a video
signal faster.

## Multi-Agent Optimization Review

At the user's request, GPT-6 Astra reviewed state ownership, Claude Opus 5
reviewed HID failure handling, and Claude Opus 4.8 challenged the video-mechanism
explanation. Claude Opus 4.7 adjudicated the disputed claims. Code and live
evidence were then checked by the coordinating agent; model votes are not
hardware proof.

- No OS-visible reconfiguration does not rule out DP PHY retraining or an
  internal monitor mute that preserves the advertised display mode. A reviewer
  overstated that exclusion. The measured observation is only no watcher event
  or mode change in that sample.
- Several brightness reads occur while the OSD is open, but the claim that
  this caused the intermittent read failure was unproven: prior identical
  cycles succeeded and the failing frame position was not captured. The
  brightness guard was not deleted on that hypothesis.
- Main input could not be read reliably: an alternate F4 GET failed, as did
  one normal D7 attempt, while the later HID preflight succeeded. No cache-based
  removal of the Mac anchor or explicit source recovery was accepted.

The implemented change is narrower: after Mac/control settling, the existing
native helper runs `--probe-hid` under the controller's writer lock and a
five-second deadline. Validity requires `ok:true`, HID transport, zero navigation
frames, firmware 774, integer brightness 0..100 and integer layout 0..255.
Only layout 1 omits the preparatory off write. Other valid layouts retain it;
failed or malformed reads stop. The helper still independently validates
firmware and off layout before sending the nine navigation events. Existing
settling waits and PC restoration remain intact.

Regression tests cover both targets, layouts 1/0/3/5, setting-write counts,
invalid metadata and types, preflight timeout, cancellation during preflight,
late success callbacks, helper-result failures and unchanged explicit MAC
recovery. A failed extra read can reduce availability; it does not authorize
fallback writes or weaken the other gates.

Live Mac-side validation of the new controller passed `solo -> pipOn -> pipOff`
with independent D7 values `1 -> 0 -> 1`, first read attempt at each step.
The passive trace contained `checking-pip` but no `preparing-pip`, confirming
the skip branch used in this run. Final state was Mac intent, idle, single
picture, 3360x1418@2x100Hz and keepalive present. PC restoration is covered by
the updated isolated tests, not a new physical PC run in this optimization.
Panel blackout duration and before/after speed improvement were not measured;
the confirmed improvement is one fewer layout-setting command when already off.

## Open Desk Tasks
- [ ] **PIP-01: Middle-left PIP key.** Replace Desktop at row 2 / column 1,
  LCD index 3, with short-on / long-off PIP control that preserves the main
  computer. Implemented, bound and loaded; guarded enable temporarily changes
  main to Mac and restores the intended target on success. Resolve the current
  PC black-picture uncertainty and complete visual placement acceptance before
  closing. HID on/off control cycles passed and the Mac inset was user-confirmed.
- [ ] **KB-01: Keyboard follows MAC / PC.** Continue the separate
  keyboard host-switching investigation (not included in this release).
  A successful connection-type GET does not complete host switching or PIP-01.
- [ ] **PC POWER: Center key.** Still an unconfigured placeholder, deferred
  until a real power-on path is verified.
  Wi-Fi-only full-shutdown startup remains unverified and no power command is bound.

## Progress Checklist

- [x] Identify exact monitor, Mac/PC inputs, and the keepalive display.
- [x] Verify ordinary USB HID DDC GET framing and reply checksums.
- [x] Verify USB SetVCP with brightness 75 -> 74 -> 75 and independent reads.
- [x] Establish D7=1 as preserve-main single-picture/off.
- [x] Disprove D7=0 as an enable command on both tested transports.
- [x] Implement and test preserve-main `lg-input.pipOff()`; publish `288ccf8`.
- [x] Download the exact-model official firmware with explicit permission.
- [x] Reconstruct the compressed MT9810 program for static analysis.
- [x] Identify the LG CDC serial port by its IOKit USB parent chain.
- [x] Verify 19200-baud UART-wrapped DDC with brightness 75/100.
- [x] Read live firmware 3.06; distinguish it from offline firmware 3.07.
- [x] Verify single-frame Menu, Down, and OK against physical OSD observations.
- [x] Complete a physical PIP off -> on test while preserving PC as main.
- [x] Confirm disabled Auto Input Switch is skipped, not an extra Down step.
- [x] Reject repeated-Up homing because root-menu selection wraps.
- [x] Complete Opus 5 and independent follow-up analysis; recheck headline claims.
- [x] Locate the actual normal-source Set/Get VCP tables and F0 callback.
- [x] Correct missing halfword decoding and verify all F0 payload bytes initialize.
- [x] Establish D7's exact many-to-one read mapping in offline firmware 3.07.
- [x] Trace the real root, Input, and PIP-option widget registration chains.
- [x] Trace a navigation-memory reset that does not write layout/input settings.
- [x] Test reset receipt and unchanged layout on the live monitor.
- [x] Record the failed forward-count normalized sequence without replaying it.
- [x] Add six permanent hardware-free navigation-model regressions.
- [x] Physically verify reset plus reverse navigation reaches Input and the PIP option.
- [x] Record the PC-main black-screen failure and user MAC recovery separately from the Mac-main success.
- [ ] Verify the chosen entry from arbitrary root and submenu positions.
- [x] Implement a bounded, serialized, no-key-retry production PIP controller.
- [x] Test same-intent PIP-on idempotence and invalidate its cache on source changes.
- [ ] Verify already-enabled hardware PIP is an idempotent no-op, including external OSD changes.
- [ ] Verify both Mac-main and PC-main off/on round trips without changing inputs.
- [x] Verify HID-based production on/off control cycles for both intended main inputs.
- [x] Obtain user confirmation that the Mac inset appeared with PC selected as main.
- [ ] Confirm healthy PC video and the final inset position after the PC is ready.
- [x] Bind LCD index 3, the middle-left Desktop key, with short-on/long-off behavior and a PIP icon.
- [x] Test cancellation, disconnects, stale callbacks, unknown state, and busy keys.
- [x] Run the relevant existing regression suites and review the production diff.
- [ ] Publish the completed implementation and document remaining acceptance gaps.

## Afternoon Implementation And Experiments

### HID Follow-Up

- The HID preflight uses only GET 0x10, 0xc9 and 0xd7, requiring the exact LG
  VID/PID, usage page 0xff00, usage 1, report ID 0 and 64-byte report sizes.
  It returned brightness 75, firmware 774 and layout 1 with zero OSD writes.
- Each query uses the already validated submit/collect envelope with a 50 ms
  gap. Each allowed F0 navigation event uses exactly one submit report. There
  is no setting collect or setting retry, and a brightness GET precedes each
  event. This precise HID sequence was tested repeatedly through the controller.
- HID write success means host submission, not a device-side OSD receipt.
  Final layout is read back and returned, not hardcoded. `effectVerified:false`
  remains accurate because the helper cannot inspect the physical pictures.
  A silently ignored menu event cannot be detected individually; concurrent
  OSD/control activity must be avoided. Do not claim a per-key acknowledgement.
- Application deadlines and cancellation checks surround HID calls, but a
  stalled synchronous OS call can exceed them. The controller retains the
  writer lock until the child actually exits rather than overlapping recovery.
- Opus review verified callback cleanup and the fixed write allowlist. Its
  claim that prior serial navigation lacked brightness reads was incorrect:
  the saved serial probe also performed a brightness baseline before every key.
  Current HID timing is supported by the new live cycles, not merely that analogy.
- `hs` CLI's default receive timeout is four seconds. Diagnostics now use
  `hs -t 15` or an event-driven completion callback; an IPC receive timeout is
  not a monitor rejection. No active test is replayed after an ambiguous result.

### Earlier CDC Checkpoint

- Session-only staged executor: MAC anchor, off, confirmed off, reset/Menu/Up/
  Up/OK/Up/OK/Up/OK, layout read, PC restore, final layout read. Mocked tests
  covered cancellation, delayed process exit, stale callbacks and no write retries.
- The first run stopped at the off precondition. Its recovery command was
  accepted and a later independent read showed off. This does not establish
  whether the first off was delayed or only recovery took effect.
- The second staging run passed all protocol checks. The first final layout
  read timed out, the second returned 0. Mac subsequently reported 1920x1080
  at 60 Hz. No physical acceptance response was received for that run.
- Production validation initially used CDC after PC-only. The LG USB identity
  disappeared in that state and returned after MAC selection, while the
  keyboard stayed attached. This was a verifier transport error, not proof
  that off failed. Independent DDC readback subsequently confirmed off (1).
- Firmware C9 over CDC gave no reply; BetterDisplay DDC returned 774 (0x0306).
  The earlier helper therefore used a fixed, bounded DDC-read child for firmware
  and serial I/O for layout and OSD. Its read child is terminated/reaped on
  cancellation; it never sends settings. The helper has a 50-second total
  budget and its controlling task a 55-second budget. Frame exchanges remain
  bounded, only reads can repeat (at most three), and no OSD event is retried.
- The final CDC production run passed `solo("pc")` with independent DDC=1, then
  failed PIP-on with `layoutNotReady`. Separate CDC D7 and brightness reads
  both produced zero bytes. The helper's initial/final layout error was not
  stage-qualified, so do not infer its submitted-frame count from this error.
  The final code now includes expected layout and last observed value in this
  error: expected 1 is before navigation, expected 0 is final readback. Pure
  tests cover both. The silent CDC channel has not been retested with more writes.
- New tests cover exact helper output, firmware read arguments and parsing,
  incompatible/missing firmware, missing helper, USB readiness, interrupted
  writers, unknown main, chooser replacement, source-cache invalidation,
  PIP gestures, physical removal and unchanged ordinary key bindings.
- There was no keyboard transport SET, pairing, monitor firmware change,
  Auto Input Switch change, sleep-security change, or PC power operation.

## Verified Device And Transport Facts

| Item | Value or boundary |
| --- | --- |
| Physical model | LG UltraGear 45GX950A-B |
| USB control identity | VID 0x043e, PID 0x9a8a |
| Physical display UUID | Machine-specific; set `DISPLAY_UUID` |
| Keepalive UUID | Machine-specific; set `GUARD_UUID` |
| Mac source | USB-C; alternate-source F4 value 0xd1 |
| PC source | DisplayPort; alternate-source F4 value 0xd0 |
| HID interface with valid replies | Vendor usage page 0xff00 |
| Serial interface | Unique /dev/cu.usbmodem* with matching USB parent identity |
| Serial configuration | 19200 baud, 8N1, raw; exclusive open; restore termios |
| Live firmware | C9 read returned 0x0306 |
| Offline firmware | Official 3.07 package; no update performed |
| Last verified brightness | 75/100 |

The serial probe uses bounded I/O and a brightness read before a key event.
Each key is sent once; no automatic key retry. The reply `73 74 00 65 64`
means transport acceptance only, not that the menu moved as intended.

UART framing is ASCII `st`, then a complete DDC packet including destination
byte 0x6e, then ASCII `ed`. Ordinary OSD key events use standard source 0x51,
SetVCP 0xf0, high value byte 0x04, and the key in the low byte. This must not be
confused with the alternate-source factory/reset meanings of similar codes.

| Event | Key | Evidence |
| --- | --- | --- |
| Menu | 0x43 | Opened the monitor's ordinary settings menu |
| Down | 0x41 | Moved Sound to Input with a single serial frame |
| OK | 0x44 | Entered the Input middle column, confirmed by photo |
| Up | 0x40 | Navigation test exposed wraparound; not a homing operation |
| Right | 0x06 | Candidate allowed in session probe; not a verified entry replacement |

The old BetterDisplay key path gave inconsistent extra navigation. Repeated
writes are a hypothesis, not a proven root cause. The serial single-frame path
has the successful physical evidence; do not state that BetterDisplay retries
were conclusively diagnosed.

## Menu Evidence And Successful Test

The photographed root order is Game Adjust, Picture Adjust, Sound, Input,
General. Input is fourth, not fifth. After entering Input, the rows are:

1. Input List.
2. Aspect Ratio.
3. Auto Input Switch, gray/skipped in this user's configuration.
4. PBP / PIP.
5. PIP Size.
6. PIP Position.

Consequently, two Down events from Input List reach PBP/PIP. Three reach PIP
Size. The user corrected this navigation error. Do not change Auto Input
Switch to simplify automation.

The three PBP/PIP choices were observed in this order: single picture,
side-by-side PBP, bottom-left PIP. From the calibrated state where the root
remembers Input and PIP is off, this sequence succeeded:

`Menu, OK, Down, Down, OK, Down, Down, OK`

Precondition: independently read D7 result 0, current 1 after off.
Postcondition: independently read D7 result 0, current 0, plus physical user
confirmation of unchanged PC main and restored Mac inset. The interrupted tool
returned `outcome_unknown`; the sequence was not replayed blindly.

This is a successful calibrated experiment, not a general-purpose macro.
Menu wraparound, remembered location, disabled rows, open-menu state, focus,
and animations must be resolved before unattended integration.

## Static Analysis Artifacts

All raw images and one-off probes remain outside the repository under the
session files directory. Do not commit firmware, screenshots of personal
content, captured device identity, vendor passwords, or compiled probe binaries.

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| MODEL_45GX950A_US3.07_PV4.23.16_NV2.04_20251218.zip | 7794065 | b34b5ae39d3e6da864944ecbb26ee1f49991b07ac15ff109c9bd0e57d4480a87 |
| MT9810 raw image | 11698372 | 3738f23b4c3b820a061e69242c4d6a83a2d80b541879e78db5d3a23ea7713f62 |
| lg-45gx950a-main-reconstructed.bin | 3891216 | 6739c5f8335a56dd52396b3e8585c586ca3de0a68a30ec703ab9d71c2e4a2c83 |

These hashes identify the analyzed artifacts; they are not vendor-signed
authenticity attestations. The distribution came from the official LG index:
<https://lmu.lge.com/ExternalService/onscreencontrol/fw/45GX950A/FWLatestVersion.txt>.

Reconstruction facts: application base 0x41080; information header 0x42180;
LE magic 0x55aa5678; prefix size 1364040; raw DEFLATE starts at 0x18e0c8 and
consumes 1145323 bytes; output 2527176 bytes. The six-byte trailer starts with
the matching LE decoded length. Reconstructed image is prefix plus inflated
program. Nonzero main code begins at reconstructed offset 0x14e000.

Current session tools:

- `aeon-readonly-disasm.swift`: limited AEON/B2 instruction decoder, pure tests,
  disassembly, immediate candidates, and target candidates. Unknown instructions
  remain explicit. Candidate scans can hit the middle of other instructions;
  verify alignment and control flow before using a hit.
- `lg-firmware-table-probe.swift`: bounded segment-table parser with pure tests.
- `lg-serial-query-probe.swift`: brightness/firmware queries and fixed OSD keys.
  It is not read-only when an OSD flag is used.
- `lg-usb-read-probe.swift`: validated HID queries plus isolated experimental
  write flags. `--self-test` is pure; do not invoke old write experiments.

Useful reconstructed-file anchors, never monitor-memory write addresses:

- 0x2d3ead: D7 comparison in the traced layout event path.
- 0x2758d0: common internal layout setter.
- 0x2d120e / 0x2d138e: alternate internal layout-command path/call.
- 0x272768: event/state poster; do not assume it is a menu-opening API.
- 0x271314: key-history push, not the menu dispatcher.
- 0x257882: normal DDC opcode dispatcher.
- 0x2594a6 / 0x39c510: normal SetVCP handler / jump table.
- 0x259f3f / 0x39c9cc: normal GetVCP handler / jump table.
- 0x25962e: F0 value-to-event conversion.
- 0x2ac524: real root-menu list handler, identified through its registration veneer.
- 0x2abd17 / 0x2abb70: root creator / row-population function.
- 0x2a96ac / 0x2a9374 / 0x2aab89: Input creator / rows / event handler.
- 0x2aa8a1 / 0x2aa133: PBP/PIP options / apply callback.

The file-to-runtime delta 0x200000 is confirmed for these code/string tables by
matching explicit address construction and multiple jump tables. This does not
make every RAM address a file offset. Never write any of these addresses.

## Independent Analysis And Adjudication

The requested Opus 5 pass produced a generic-menu state-machine analysis. A
separate GPT-5.5 pass examined possible host-state routes, and Opus 4.8 examined
the newly identified multi-window function. Additional Opus 5 passes recovered
the actual normal DDC callback and GetVCP table. These are offline conclusions
from firmware 3.07, not new physical observations on live firmware 3.06.

### Normal F0 Contract, Independently Rechecked

Normal source 0x51, opcode 0x03 reaches 0x2594a6. The table at file 0x39c510 is
indexed by the raw VCP byte, has four-byte little-endian runtime-address entries,
and accepts indices through 0xfa. F0 points to 0x25962e. The handler constructs
internal message 0x80 with payload `[valueHigh, valueLow, 0, 0]`.

Two initially unknown instructions are important:

- 0x2594de, bytes `0c 01 0b`: halfword zero store at stack offset 10.
- 0x2594e1, bytes `0c 01 0d`: halfword zero store at stack offset 12.

Together they initialize all four payload bytes before the F0 handler fills the
first two. A reviewer initially called the fourth byte stale; this is false.
The decoder now has red/green regression fixtures for both stores, a negative
halfword offset, and the compact comparison branch used nearby.

The delivery shim is 0x2b9e7c. Its callback slot is populated by 0x2b9e60, called
at 0x24fcad with runtime address 0x47d261, confirming the indirect hop to the
already identified message sender 0x27d261. Scanning only direct queue calls
would miss this producer.

### GetVCP And D7

The real normal GetVCP table is at 0x39c9cc, indexed through 0xfe. F0 and D5 point
to the unsupported epilogue, while D7 reaches 0x25a81f and reads the raw layout
through 0x252094. Its current-value mapping is:

| Internal layout | D7 current value |
| --- | --- |
| 0 | 1 |
| 1 | 5 |
| 3 | 3 |
| Other values | 0 |

The high current byte is always zero. Therefore D7=1 uniquely reports the
single-picture branch in this implementation, but D7=0 alone cannot distinguish
PIP from all other non-enumerated modes. This is stronger evidence than the
early generic capability string and narrows how production verification may work.

The reviewed normal getter paths did not establish a page/selection oracle.
In particular F0 is write-only, 0x52 reads the low value written by its own
setter, and 0xca's complete semantics remain unresolved. Do not turn this
bounded negative evidence into a claim that no possible UI-state API exists.

### Rejected Or Still-Unverified Conclusions

- Relative selection and wraparound were rechecked at 0x2ac996 and 0x2aca14.
  Disabled item flag 2 is skipped. The later creator trace confirms this is the
  real root widget: 0x2abd62 constructs veneer 0x47ddf3, which jumps to 0x2ac524.
  These key-handler facts do not exclude other system-message entry paths.
- Candidate send sites 0x276af0 and 0x276b8f actually use message 0x10;
  0x26f218 uses 0x13; 0x271059 uses 0x31. Earlier short unaligned windows wrongly
  called them dynamic producers. The prefix bytes near 0x1429c0 are a numeric
  table, not the VCP record table.
- F0 subtype 13 reaches 0x2799e8, writing state offset 878. Two initial reviews
  mislabeled its ordinal as a window count. Deeper Opus 5 analysis and an
  independent read of 0x276120 show a scalar ladder 390/370/340/270/240, not a
  demonstrated multi-input PIP layout. Exact units remain unverified. The real
  PIP apply path uses 0x2758d0 and state offset 567. Subtype 13 was not tested.
- F0 subtype 12 reaches event/state poster 0x272768. Its state and power-related
  branches must be classified before use. It is not an approved menu shortcut.
- A normal E3 path is now a concrete next anchor: 0x2598bc -> 0x2bf229 posts
  message 0x3c with payload `[valueLow, valueHigh, ...]`; the system handler at
  0x2d43a2 branches to 0x2d4539 and calls 0x292ba7 / 0x292bb7 / 0x292bfe. Its
  creator draws a separate 676x125 popup through renderer 0x292c9a, not the
  established Input widget. Its visible purpose remains unclassified. No write.
- Extended DDC opcode 0xcc reaches a registered callback at 0x2c087f with
  EEPROM/update-related transfer branches. It was excluded from ordinary PIP
  control; no handshake or payload was sent on that path.

Agent working reports remain in the session directory as
`lg-opus5-menu-entry-report.md`, `lg-host-state-analysis-report.md`,
`lg-opus48-mode-semantics-report.md`, `lg-opus5-normal-ddc-callback-report.md`,
and `lg-opus5-getvcp-state-report.md`. Some contain superseded claims explicitly
corrected above. This adjudicated report, not an individual agent headline, is
the resume source of truth.

## Navigation Reset And Failed Live Test

### Reset Control Flow

Normal F0 value high=0, low=1 produces message 0x80 subtype 0. Table 0x3a523c
entry 0 stores runtime pointer 0x004d2a24. The handler's overlay branches all
converge at 0x2d2a2c; the unconditional branch at 0x2d2b0b returns there after
the optional OSD close. Parameter register r10 is preserved by the called
functions. The earlier claim that a missing overlay prevents reset was false.

For low=1, the loop visits indices 5 through 0 and calls leaf functions
0x2b699d and 0x2b69c4. It clears only the remembered root index and six
per-root submenu indices. It does not change Auto Input Switch, an input source,
PIP layout, brightness, calibration, firmware, or persistent security settings.

The close path is queued. Root teardown 0x2ac78f reads the live remembered index,
calls the navigation wipe 0x2b696e, then restores that same value in one handler.
It does not carry a pre-reset snapshot across the queue boundary. Pending key
events can still move the selection afterward, so serialization remains required.

Reset alone was tested once: valid D7=0 before and after, brightness 75, one
frame accepted. This proves receipt and unchanged reported layout, not visual
confirmation of the new root focus.

### Failed Forward-Count Test

After guarded D7=1 and an independent valid off read, the following was sent:

`reset, Menu, Down, Down, Down, OK, Down, Down, OK, Down, Down, OK`

Every serial frame was sent once after a validated brightness query, with a
successful transport receipt. Final D7 remained 1. Mac mode stayed wide at
100 Hz, and keepalive stayed connected. No automatic retry was attempted.
The device is left in that single-picture state, not silently marked restored.

Two source-backed failure mechanisms remain hypotheses, not diagnoses:

- Root creation sanitizes a disabled remembered index to the first enabled row.
  Three Down steps are not a stable count when leading rows are gray.
- In the Input submenu, Aspect Ratio can also be disabled. Two Down steps can
  then wrap back to Input List instead of PBP/PIP if Auto Input Switch is also
  disabled or absent. That can make later keys act on an unintended setting.
  No more unobserved navigation was attempted.

These are counterexamples, not evidence that either gray-row pattern occurred
during the failed test. The old forward sequence is arithmetically correct in
the previously photographed all-enabled root with Aspect Ratio enabled.

The root gray-state byte at state offset 558 is written by the normal 0xca
handler (0x2597ff / 0x259807 / 0x259936). Its proximity to the layout byte is
NOT proof that turning PIP off changed it. No 0xca write was sent to simplify
navigation. No readback or photo established which hypothesis occurred live.

An independent serial audit found no proven probe-layer cause. It raised a
conditional ACK-correlation risk: if a GET produces an extra transport ACK,
unconsumed bytes could satisfy a subsequent command's receipt parser. That
condition has not been observed, and a transport ACK still does not prove UI
completion. Do not paper over the failure with blind flushing, key retries,
or treating D7=0 as a unique PIP result.

## Reverse-Direction Sequence, Supervised Validation

The sequence validated with Mac as main is:

`reset, Menu, Up, Up, OK, Up, OK, Up, OK`

Required preconditions: fresh valid D7=1 (single picture), correct physical
monitor, keepalive present, exclusive serialized control, ordinary settings
menu, and a calibrated configuration exposing a PIP option. It must not be
run from unknown or already-active layouts. It has not been bound or hot-loaded.
One supervised success does not establish every possible starting menu state.

### Supervised Mac-Main Experiment

On 2026-09-10 at approximately 08:21 EDT, the user requested an experiment and
provided the physical observations that were unavailable overnight:

1. Pure serial-probe tests passed; LG and keepalive were present and the source
  controller idle. An independent serial D7 query returned valid current 1.
2. `reset, Menu, Up, Up`, with no OK, reached Input. The user confirmed the
  highlighted root item.
3. From a fresh valid off read, the full sequence except the final OK reached
  the bottom-left PIP icon. The user confirmed that exact option.
4. From another fresh valid off read, the full nine-frame sequence was sent
  once. Every frame received a transport receipt; no key was automatically
  retried and no input-selection command was included.
5. D7 changed from 1 to 0. The user explicitly confirmed Mac remained main and
  PC appeared in the bottom-left inset. Mac mode stayed 3360x1418@2x 100 Hz,
  keepalive stayed connected, and brightness baselines remained 75.

The readback supports the observed transition; the user's physical confirmation,
not D7=0 alone, establishes native PIP and preservation of the main input.

### Supervised PC-Main Follow-Up: Failed

Two follow-ups were performed with the user observing the monitor. Neither
qualifies as successful PC-main preservation:

- First, the existing serialized `solo("pc")` operation was accepted and the
  user confirmed PC full screen. The reverse PIP sequence returned successful
  transport receipts; the immediate D7 read was missing, then a later read was
  valid 0. The user reported a PC inset and missing Mac main until pressing MAC.
  Recent SWAP/MAC actions were also present, so this attempt was not used to
  attribute the source-selection failure to one operation.
- Next, the operations were separated. With PIP already on, the existing
  `select("pc")` operation produced PC main and Mac bottom-left, physically
  confirmed. A separate normal D7=1 command then removed the inset and the user
  confirmed that PC remained full screen. This establishes that source-only
  selection and PIP-off can each work in the tested PC-main path.
- From that reported PC-only baseline, a fresh valid D7=1 and idle/display guards
  were obtained. At 08:27:38 EDT the nine-frame reverse sequence was sent with
  no F4 source command and no automatic key retry. All transport receipts were
  successful; the first post-sequence read had zero response bytes.
- The user reported that applying the small-picture option made the whole
  screen black, and that pressing MAC restored the picture. The manual key log
  recorded that recovery at 08:28:11 EDT, after the sequence ended, as a 125 ms
  short MAC press. A later read returned valid D7=0. That post-recovery zero
  is not proof the sequence preserved PC main or displayed a usable PIP.

No repeated OSD sequence or unproven recovery was sent after this report. The
remaining local hypothesis is that entering PIP may reselect or reinitialize
inputs in a way that needs explicit source reconciliation; this is NOT yet a
diagnosis. A signal/timing or live-3.06 difference is also unresolved. Check the
actual layout-setter input handling before testing a repair. Do not blame the
user's recovery press for the black screen or mark the PC-main gate complete.

### Static Invariants

1. The root has five rows in both decoded configuration branches. Input and
  General are its final two enabled rows. Reset opens at the first enabled
  row, so two Up events reach Input regardless of disabled leading rows.
2. Reset also clears every per-root remembered submenu row. Input List, row 0,
  is always enabled, so the newly created Input page starts there.
3. With raw layout 0, every Input row after PBP/PIP is disabled. PBP/PIP itself
  has literal enabled flag 0 at 0x2a9426. One Up wraps to it, regardless of
  Aspect Ratio and Auto Input Switch availability.
4. The PBP/PIP option list starts at its off entry when D7=1. When capability
  bits equal 2, exactly one PIP value from 6/7/8/9 is appended last with an
  enabled flag, honoring the stored PIP position. One Up selects that entry.
5. The PIP option builder passes flag 0x40. Up/Down only change highlight;
  applying the setting requires OK. The candidate does not change sources or
  Auto Input Switch by design, but live focus still needs observation.

The capability getter 0x24ddea reads bits 1-2 at runtime 0x263ba0. The offline
image byte is 5, producing capability 2. That is not a fresh read of live 3.06
configuration. The earlier user observation of three mode choices is the live
evidence available; no broader mode compatibility is asserted. The model's
`pipCapability` is supplied by the test, not discovered from a device. The
latest supervised experiment confirmed the PIP option in its current live mode,
but other modes and future firmware still require their own validation.

### Repeatable Offline Checks

The permanent [navigation model tests](../../tests/lg-pip-navigation-model.test.mjs)
require only preinstalled Node.js and make no device, filesystem, or network
calls from the test body:

```sh
node --test tests/lg-pip-navigation-model.test.mjs
```

Six tests cover root flag regimes, the rejected forward-count counterexample,
Input disabled rows, variable PIP option counts/positions, strict preconditions,
and why the off-state condition is necessary. They validate navigation arithmetic
GIVEN assumed rows and flags; they do not derive those fixtures from firmware or
validate that the live monitor uses them. The session-only exploratory model
failed on the old three-Down rule before the two-Up correction passed. The
permanent suite preserves both its counterexamples and the nominal forward
success. These tests are not a firmware emulator or hardware acceptance.

### Next Acceptance Gates

- [x] Confirm the tested live mode exposes the calibrated native PIP option rather than substituting offline capability bits.
- [x] Observe reset-plus-two-Up reaching Input on live 3.06 before applying a setting.
- [ ] Verify reverse root navigation from all enabled/disabled leading-row regimes.
- [x] Verify one-Up Input navigation in the tested single-picture mode without changing Auto Input Switch.
- [x] Confirm the final option is native PIP and its position is the intended bottom-left inset.
- [x] Test the final OK with independent physical verification and layout readback, Mac as main.
- [ ] Repeat from another prior root/submenu location and with the other computer as main.
- [ ] Only then integrate, serialize, and bind the dedicated short-on/long-off key.

Do not request these observations while the user is asleep. They are blockers
for live acceptance, not reasons to claim the offline work failed or to replay
the previously failed sequence. No unattended background command loop was set up.

## PC-Main Source-Path Review

A further Opus 5 pass investigated the controlled PC-main black-screen result.
Its initial explanation treated state offset 568 as a remembered main source.
That interpretation was independently rejected before any new device test:

- The three-state getter 0x273615 and setter 0x275d16 belong to a distinct
  geometry-related option. Callback 0x2ab381 is registered through veneer
  0x2b4127 by builder 0x2aaa7b. It is separate from both the actual input-list
  builder 0x2a9c96 and PIP layout apply callback 0x2aa133.
- The parameter flows through 0x274bd7 to 0x2ba8e2, which interprets layout,
  size, and position parameters rather than an established physical source ID.
  The latch at runtime 0x5c3cce is used for equality checks in this function;
  it has not been shown to select a DisplayPort/USB-C input.
- The real alternate F4 route at 0x271bbc parses the input value through
  0x274284 and applies its 20-byte record with 0x276283(0, record, 1).
  It does not pass through 0x275d16. Therefore the claim that a MAC recovery
  press fixes state offset 568 is false.
- The pair 0x27873d / 0x278d0a reads and reapplies state offset 582 through
  0x2ba3eb. Calling this a link re-timing operation without tracing its actual
  driver effect was also premature.

The PC-main failure remains unattributed. The relevant record-adjustment path
is now localized: 0x27498f loads the resolved main record via 0x27495f, queries
its per-port configuration via 0x279686, then adjusts existing window records.
The source-apply function 0x276283 also loads both resolved records and branches
on active layout. Their complete live behavior on firmware 3.06 is not proven
by the offline 3.07 image. No screen/input command was sent in this review.

A possible future discriminating experiment is to establish PIP from the
already accepted Mac-main path, then use the already accepted source-only PC
request after settling. It combines two individually observed operations, but
the combined transaction is NOT verified and temporarily changes the main
picture. Do not silently use it as the default main-preserving PIP implementation.
No new recovery sequence or keypad binding was installed.

Session reports `lg-pc-main-pip-source-review.md` and
`lg-pip-size-source-adjudication.md` preserve the independent analysis. The
former contains the rejected source/size interpretation; this section is the
adjudicated status. PIP-01 remains open, including the PC-main acceptance gate.

## Failed Paths And Corrections

- D7 read 0 does not mean D7 write 0 enables PIP. It failed over both tested
  write transports; no reason to repeat it unchanged.
- D7=2 and normal ED=1 did not enable PIP. Unsupported ED GET result 1 is not
  a valid zero-valued setting. The later extended ED static path still requires
  explicit evidence; do not sweep ED values or payloads.
- D8 returned an empty supported-mode value even though PBP works. It is not
  authoritative absence proof.
- Old DualUp patch enums require firmware-specific modifications and are not
  portable to this monitor. No such patch was executed.
- `kn 00 ff` belongs to a different character-control UART path. The USB CDC
  connection needed UART-wrapped DDC at 19200 baud, not that raw text at 9600.
- Firmware-update UART state machines are outside the permitted write surface.
- Generic VESA color-window masks are not evidence of a second video input.
- LG software window tiling and high-refresh Dual Mode are not hardware PIP.
- Root menu wraparound invalidates fixed repeated-Up homing.

See [the historical investigation](../lg-pip-research.md) for the earlier
transport experiments and pinned public references.

## Resume Procedure

1. Read this report before older memory notes or plans. Preserve the latest user
   constraints, especially Auto Input Switch off and no overnight prompts.
2. Verify repository status and session artifact hashes. Production at the start
   of this checkpoint is `288ccf8`; the running keypad was not reloaded to add
   `pipOff()`. Desktop remains bound; do not claim it is a PIP button.
3. Run the applicable pure probe self-tests before trusting static output.
4. Run the permanent navigation-model tests. Continue from the reverse-direction
  candidate and the acceptance gates above. The actual Set/Get tables, root
  registration, reset control flow, and false multi-window lead are already
  resolved; do not ask another agent to rediscover them.
5. Keep unproven candidates off the hardware. If a proven ordinary command is
   tested, serialize it, do not retry keys, and require independent readback.
6. Update this report with exact evidence, eliminated hypotheses, next anchors,
   validation results, and checklist status before the next commit/push.

## Validation Log

- Historical: four isolated Lua suites passed for production checkpoint 288ccf8.
- Historical: serial probe packet/allowlist tests passed before physical OSD work.
- Current checkpoint: Markdown structure, checklist, local links, and whitespace
  checks passed; editor diagnostics found no errors in either edited document.
- Current checkpoint: serial framing, firmware table, and AEON decoder pure
  self-tests passed. Official ZIP and reconstructed-image hashes matched above.
- First report publication: commit `1eb002b`, pushed to `desk/main`, local and
  remote SHA equality verified. Production keypad unchanged.
- Second publication: `4da9edc`, local/remote equality verified; DDC tables and
  first adjudication preserved before the later normalized test.
- Follow-up: halfword and compact-branch decoder regression failed before the
  implementation and passed afterward; rebuilt local analysis binary decoded
  the F0 prologue consistently. No device opened during these analysis passes.
- Opus 5 and independent reports completed; selected claims were rechecked and
  rejected claims are retained above with their corrections. Further analysis
  is still in progress; no new unattended PIP control is claimed.
- Latest permanent model suite: 6 passed, 0 failed, 0 skipped. Editor diagnostics
  were clear for the new test and both modified session-only Swift probes.
- Historical overnight physical result: forward-count off/on failed, leaving
  D7=1. That failure remains unattributed and is not a production sequence.
- Latest supervised result: reverse sequence changed D7=1 to 0 and the user
  confirmed Mac main with PC bottom-left inset. No hot-loaded PIP key or PC
  power implementation is claimed; opposite-main/repetition gates remain open.
- Subsequent PC-main result: source-only selection and off separately passed
  physical checks, but reverse PIP enable caused a black screen and required
  user MAC recovery. The generic main-preservation gate is explicitly failed;
  do not infer success from the eventual D7=0 read after that recovery.
