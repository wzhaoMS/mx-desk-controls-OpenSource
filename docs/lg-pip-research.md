# LG Hardware PIP Investigation

Historical checkpoint date: 2026-09-09. This document records the earlier
transport experiments, not a working unattended PIP-enable API.

**Latest status:** a native OSD PIP off/on round trip has since been physically
verified. Reliable menu anchoring is still unresolved. Read the
[reverse-engineering report and resume checklist](reports/lg-pip-reverse-engineering.md)
first; its newer findings supersede the early status statements below.

## Requested Behavior

Replace middle-left Desktop (LCD index 3) with a dedicated PIP key. A short
press should retain the current main computer and show the other input as an
inset. A long press should disable PIP without changing the main input.
The top-row MAC / SWAP / PC actions should remain separate from this layout
control. PC POWER is a later task, not part of this investigation.

No verified automatic PIP-enable operation is available yet. The Desktop key
has not been replaced with a misleading input-selection or PBP action.

## Verified USB Transport

The monitor is an LG 45GX950A-B with USB controls at VID `0x043e`, PID `0x9a8a`.
Its two HID interfaces use vendor usage pages `0xff00` and `0xff01` with 64-byte
reports. Only `0xff00` produced valid DDC replies in these experiments.

The [public LG USB bridge research](https://gist.github.com/shinyquagsire23/f6b2adef253c6c3ab557a4852bf3abad)
originally targeted a different product ID. Its packet format was independently
tested on this monitor using macOS IOKit and nonexclusive HID device handles:

- USB output envelope: `08 01 55 03 <DDC length> 00 03 37`, followed by the DDC
  message and zero padding to 64 bytes. A second report requests the reply.
- GetVCP uses DDC source `0x51`, opcode `0x01`, and an XOR checksum seeded with
  `0x6e`. Replies are accepted only with matching feature, packet length, and
  the reply checksum seeded with `0x50`.
- A 50 ms run-loop interval between query submission and reply collection fixed
  truncated reads in this setup. This is an observed working interval, not a
  universal timing guarantee.
- Brightness `0x10` returned a valid current value of 75 and maximum 100.
- Layout `0xd7` returned a valid current value of 1 while PIP was off.
- Standard capability queries `0xf3` / replies `0xe3` yielded 12 validated chunks
  with matching offsets. The embedded model name was `WK95U`, not the physical
  monitor model. Treat the capability string as a generic firmware template,
  not authoritative model identity or proof of supported layout writes.

USB request acceptance alone was never treated as monitor-setting success.
These results do not establish compatibility of the other USB interface.

## PIP Experiments

| Experiment | Observation | Conclusion |
| --- | --- | --- |
| Manual OSD PIP enable | D7 changed from 1 to 0 at 20:42:56 UTC; user confirmed Mac main with PC inset | Zero is an observed read value in this PIP state |
| Write D7=0 while PIP was already on | Readback stayed 0 | Does not prove this write enables PIP |
| Write D7=1 using BetterDisplay | Readback became 1; inset disappeared | Off command worked |
| Write D7=0 using BetterDisplay after off | CLI exit 0, empty stdout; USB readback remained 1 | Did not reopen PIP |
| Write D7=0 directly through validated USB bridge after off | Both output reports accepted; valid D7 readback remained 1 | Same failure without BetterDisplay in the write path |

The direct USB experiment sent the single DDC message
`51 84 03 d7 00 00 6f`, gated on a valid brightness read and a valid off-state
baseline. It did not select an input or sweep other values. The experiment is
not exposed by the production controller.

**A PIP read value of zero is not a verified PIP-enable command.** The evidence
rejects that specific operation on these paths; it does not prove the firmware
has no other PIP API. The final experiment left PIP off, with Mac and the
keepalive display connected. Manual OSD remains the known way to restore it.

## Independent Review Follow-Up

An Opus 5 review and follow-up primary-source inspection found two additional
leads. Neither establishes a native PIP-enable command for this monitor.

### Dedicated PIP Opcode

The original researcher's [pinned firmware notes](https://gist.github.com/shinyquagsire23/7ddd17d1569acb21920683866570cb35/4a529e248e934715b19458a488356f1ca3c37caa)
name normal-address feature `0xed` as `MANUFACTURER_PIPMODE_OPCODE`.
The USB probe was extended only to read that documented feature after a valid
brightness response. Its packet and allowlist tests passed.

On this 45GX950A-B, the checksum-validated reply was:

```text
6e 88 02 01 ed 01 ff ff 00 00 59
```

The result byte is `01` (unsupported feature), maximum `65535`, current `0`.
That zero is not a valid PIP state. No write was attempted for `0xed`; an
unsupported getter alone does not prove that every possible setter is absent.

The earlier valid PIP-state response for `0xd7` had result `0` and maximum `255`,
so it does not match the all-zero unsupported-code response reported on some
other LG monitors. It still does not identify a usable enable-write value.

### Firmware-Specific Open-Source Manager

[lg_display_manager at 84bc136](https://github.com/shinyquagsire23/lg_display_manager/tree/84bc13615780381681ff794619d2e86040afd1e8)
does define PIP layout enums, including bottom-left. However:

- Its README limits support to LG DualUp 28MQ780 and specific scaler firmware.
- `patch_d7_pbp_pip()` changes the firmware's D7 setter and getter to accept and
  expose raw layout values.
- `run_patches()` invokes those model-address-specific memory writes before the
  application uses the PIP layouts.
- The startup code explicitly checks the expected monitor model and firmware.

Those enums are not portable native DDC commands. The script was read only;
it was not executed, and no firmware or arbitrary memory writes were sent.
Its lack of a declared repository license also prevents treating the whole
source as a freely vendorable dependency without further permission.

The installed Dual Controller 2.76 is an Intel macOS executable linking
`/usr/local/dualcontrol/lib/libMonitorDDCCISDK.dylib`. Static inspection of its
`SetProperty` function showed optional capability checking and forwarding of
the opcode/value to its protocol engine, not a PIP-specific conversion there.
This limited inspection is not proof that no undocumented API exists elsewhere.

The new independent [diagnostic implementation](https://github.com/Jason7536/lg-input-switch/blob/main/tools/Diagnose.cs)
uses ordinary `0x82` GetVCP framing and expects possible NAKs on the LG `0x50`
side channel. It does not document a PIP setter. Do not use an invented `0x81`
GetVCP length or modify unrelated USB envelope fields based on an unverified
review suggestion.

## Additional Native And Positive-Control Checks

Further static inspection located the installed Dual Controller application
methods directly, rather than inferring behavior from library exports:

- `setPBPMode:` at `0x100014954` forwards its integer argument unchanged to
  `SetProperty(0xd7, value, false)`.
- `getSupportedPBPModeList` at `0x100014a44` reads feature `0xd8` and examines
  three bit positions. It does not derive PIP values from the five-entry enum
  found in older OSC notes.
- The exact monitor returned a valid D8 reply with result 0, maximum 255,
  current 0. Since a known PBP command works despite this empty result, it is
  not a complete or authoritative supported-layout list.

Two bounded setting hypotheses were tested with exact LG/keepalive guards and
a 25-second return-to-off timer. Both timers completed and were cleaned up.
No firmware or arbitrary memory was accessed:

| Candidate | Independent USB readback | Finding |
| --- | --- | --- |
| Normal D7=2, a reported LG layout value of uncertain meaning | Valid D7 result 0, current 1 | Did not activate PIP in this test |
| Normal ED=1, testing a PIP-named setter despite its unsupported getter | Valid D7 result 0, current 1; ED getter still unsupported | Did not establish a working PIP-enable operation |

The value 1 for ED was a hypothesis, not a documented enable enum. The negative
result does not justify sweeping other ED values or claiming all writes to that
feature are impossible.

### USB Write Positive Control

Successful GET queries alone do not prove a SetVCP implementation works. To test
the direct USB write path independently, a brightness-only positive control:

1. Required a valid brightness baseline of 75 with maximum 100.
2. Wrote 74 through USB and independently read 74.
3. Restored 75 through USB and independently read 75.

Both steps succeeded. The pure packet tests also cover rejecting values over
100 and attempting restoration even when the intermediate readback fails. No
input or layout was changed during this control. This validates this probe's
ordinary USB SetVCP framing, not PIP support in general.

### Other Open-Source Paths

- [ddccontrol's LG base profile](https://github.com/ddccontrol/ddccontrol-db/blob/master/db/monitor/GSMlcd.xml)
  adds a power LED setting to its VESA controls, not an LG PIP mapping. Its PIP
  option names do not themselves assign LG wire values.
- [deskmux's defaults](https://github.com/klaidliadon/deskmux/blob/main/config/config.go)
  and [template](https://github.com/klaidliadon/deskmux/blob/main/config/template.go)
  list D7 off=1, 50/50=5, and experimental 66/33=3. No inset enable mode is given.
  Its exact-model observations also warn that input feature 0x60 misreports.
- The [VESA window definitions](https://www.ddcutil.com/vcpinfo_output/) describe
  window-specific brightness/color operations and window masks. They are not
  evidence of selecting and compositing a second video input. No writes to that
  feature group were attempted.
- Other exact-model projects checked, including
  [controlLGMonitor](https://github.com/countermex/controlLGMonitor),
  [source-switcher](https://github.com/Swiftwork/source-switcher), and
  [LGInputSwitch](https://github.com/phillip9933/LGInputSwitch), document input
  switching or high-refresh Dual Mode, not the requested hardware PIP enable.

The production keypad is unchanged. A working native enable command or a
successful exact-model command capture remains the missing dependency; the
verified input-switch command is not an implementation of that dependency.

## Constraints And Next Check

- Keep the exact LG and keepalive guards. Do not change sleep, password, or MDM
  policy, or operate either computer's power while investigating PIP.
- Do not substitute D7=5 (50/50 PBP), a fullscreen input switch, or BetterDisplay's
  software window for hardware PIP.
- Do not infer main/sub or PIP state from resolution: Mac-main PIP and Mac
  fullscreen can report the same mode.
- Seek an independent PIP setter or documented OSD-control command in existing
  open-source implementations. Validate framing and matching readback before
  integrating anything into the keypad.
- LG Switch was not downloaded or installed. The user requested the open-source
  route. The existing Dual Controller app exposes PBP, not a verified PIP setter.
- Session-only diagnostic scripts, raw device identity reports, and experimental
  writes are not shipped as a runtime dependency.

## References

- [LG input side-channel notes](https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors)
- [Exact-model community profile](https://github.com/tyvsmith/streamcontroller-lg-monitor-control/blob/6d7b0aeda66bab15e158153c57b893d901a34744/monitors/lg_ultragear_45gx950a.toml)
- [Apple Silicon m1ddc](https://github.com/waydabber/m1ddc): its named PIP/PBP modes
  are for certain Dell displays, not this LG.
- [Current production setup](../README.md)
