# Keep a Mac Awake Behind an External Monitor (No Black Screen)

A standalone guide for AI agents. Use it when a Mac goes to sleep, or its external
monitor stays black, while the Mac drives a monitor or shares a KVM monitor with
another computer. Diagnose read-only first, apply the smallest fix that matches,
then verify with the user looking at the monitor.

Tested on 2026-11-25: Apple Silicon MacBook Pro (M4 Max, Thunderbolt 5) on
macOS 27.2.1, lid closed, on the USB-C input of an Alienware AW3926QW (5120×2160
KVM monitor, with a PC on its DisplayPort input). Numbers that belong to that
monitor are marked as such; measure them on yours.

## The Short Version

1. **Cable and power.** Use the monitor's supplied USB-C cable. `pmset -g ac` should
   report the monitor's full power (90W here). A 3 A cable reported 60W and gave a
   black or blinking picture at every refresh rate.
2. **A signal the monitor can show.** If the kernel log shows `DSC=YES` for the
   monitor and the picture is black, ask less of the link: 60 Hz and 8-bit color,
   which runs with `DSC=NO`. [dell-refresh.lua](../dell-refresh.lua) applies both
   after every display change and wake.
3. **No idle sleep.** A per-user LaunchAgent that runs `/usr/bin/caffeinate -di`.
4. **Lid closed.** Keep the external display connected and powered. Nothing else
   prevents `Clamshell Sleep`: not `caffeinate`, and not a virtual "keepalive"
   display.

With all four in place the Mac stayed awake for more than 8 hours with its lid
closed while the monitor switched between the Mac and the PC six times. No switch
caused a sleep, a power change or a new mode set, so the Mac's desktop was there as
soon as the monitor showed the Mac again.

## Rules For Agents

- Every command under Diagnose only reads. Run them before changing anything.
- Never switch the monitor's input (DDC/CI VCP `0x60` writes) or change its
  on-screen menu unless the user is present and agrees. It changes what the user
  sees and can blank the computer they are working on.
- `sudo pmset` needs the user's password and changes the whole system. Ask first,
  save the output of `pmset -g custom` beforehand, and restore it to undo.
- Do not download or install anything. If a fix needs a missing tool (BetterDisplay,
  for example), say so; the user installs it from the official source.
- Do not stop an existing keep-awake process (`caffeinate`, a LaunchAgent, an app)
  without asking. `pmset -g assertions` shows what holds the Mac awake.
- Do not add or turn on a virtual display as a keepalive (see [Lid Closed](#lid-closed)).
- Cables, the monitor's buttons and menu, the lid and the login password belong to
  the user. Ask them to act, and to tell you what the monitor shows.

## Diagnose

1. Why and when did the Mac sleep?

   ```sh
   pmset -g log | grep -E "Entering Sleep|Wake from|DarkWake to FullWake|Display is turned" | tail -30
   pmset -g log | grep -E "Summary.*Using Batt" | tail -5
   ```

   | Log text | Meaning | Go to |
   | --- | --- | --- |
   | `Entering Sleep state due to 'Idle Sleep'` | The idle timer won; nothing held the Mac awake | [Keep Awake](#keep-awake) |
   | `Entering Sleep state due to 'Clamshell Sleep'` | The lid was closed and the external display went away | [Lid Closed](#lid-closed) |
   | `Using Batt` on a Mac that normally runs on the monitor's power | The monitor cut its USB-C power too | [Black Picture](#black-picture), item 3 |
   | `'Maintenance Sleep'`, `'Notification Wake Back to Sleep'` | Ordinary sleep after a background wake | — |

2. What holds the Mac awake now, and what are the sleep timers?

   ```sh
   pmset -g assertions
   pmset -g custom
   ```

   `PreventUserIdleSystemSleep 1` means idle sleep is blocked; the processes that
   hold it are listed further down. In `pmset -g custom`, `sleep` is the system
   sleep timer in minutes (0 = never) for battery and for AC power.

3. Power, lid and displays:

   ```sh
   pmset -g ac
   ioreg -r -k AppleClamshellState -d 4 | grep -E "AppleClamshell(State|CausesSleep)"
   system_profiler SPDisplaysDataType
   ```

   `pmset -g ac` prints `Wattage = 90W` or similar, or `No adapter attached`. A
   closed lid that is holding shows `AppleClamshellState = Yes` together with
   `AppleClamshellCausesSleep = No`. `system_profiler` lists the monitor, its
   resolution and refresh rate, and whether it is mirrored.

4. The video link, and what macOS sends over it (`log show` can take a minute):

   ```sh
   ioreg -l -w0 | grep -v EventLog | grep -E '"(LinkRateDescription|LaneCount)"'
   log show --last 2h --style compact --predicate 'process == "kernel" AND eventMessage CONTAINS "mode_set_gated"' | tail -5
   ```

   On the tested monitor: `"LaneCount" = 2` and
   `"LinkRateDescription" = "10 Gbps (UHBR10)"` (ports without a monitor show
   `No Link`), and mode sets such as `5120x2160@59 Hz DSC=YES VRR=NO`.

5. For a KVM monitor on a USB-C cable: which computer has it?

   ```sh
   ioreg -r -k TransportsActive -w0 | grep TransportsActive
   ```

   One line per USB-C port. `DisplayPort` together with `USB2`/`USB3` means the
   monitor's input and USB hub are on this Mac. `DisplayPort` without them means the
   monitor shows the other computer but kept this Mac's video link. No
   `DisplayPort` on any port means the monitor dropped the Mac.

## Keep Awake

Tested: a per-user LaunchAgent that runs `caffeinate -di`. `-i` blocks idle system
sleep and `-d` blocks idle display sleep (`man caffeinate`), so the Mac keeps sending
a picture while a KVM monitor shows the other computer. It also works on battery,
and it runs only while the user is logged in.

Save as `~/Library/LaunchAgents/com.example.keep-awake.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.keep-awake</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/caffeinate</string>
    <string>-di</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>30</integer>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
</dict>
</plist>
```

Load it and check:

```sh
plutil -lint ~/Library/LaunchAgents/com.example.keep-awake.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.keep-awake.plist
launchctl print gui/$(id -u)/com.example.keep-awake | grep -E "^\s*state ="
pmset -g assertions | grep caffeinate
```

Expect `state = running`, and `caffeinate` holding `PreventUserIdleSystemSleep` and
`PreventUserIdleDisplaySleep`. macOS may announce a new background item; it has to
stay allowed in the Login Items list under System Settings > General.

Alternatives, not tested on this desk:

- Let the displays sleep: use `-i` alone. After a KVM switch back, the monitor then
  stays black until a key or mouse press wakes the Mac's display.
- No LaunchAgent: `sudo pmset -c sleep 0` turns off idle system sleep on AC power
  (`-c` is the charger setting). Restore the saved `sleep` value to undo.
- Hammerspoon: `hs.caffeinate.set("displayIdle", true)` holds while Hammerspoon runs.

## Lid Closed

A closed MacBook keeps running only while an external display stays connected. When
that display goes away the Mac sleeps at once (`Clamshell Sleep`), whatever else
holds it awake.

- Keep-awake assertions do not cover the lid. Apple's `IOPMLib.h`, on
  `kIOPMAssertPreventUserIdleSystemSleep` (the assertion `caffeinate -i` takes): "The
  system may still sleep for lid close, Apple menu, low battery, or other sleep
  reasons." Observed: two `Clamshell Sleep` entries on 2026-11-25 while
  `caffeinate -di` was running, each when the monitor dropped the link and its USB-C
  power (`Using Batt`).
- A virtual display used as a keepalive (a BetterDisplay virtual screen here) made
  things worse. Each time the real monitor dropped, macOS made the invisible virtual
  display the main display and moved windows onto it, so the monitor came back to an
  empty desktop. It did not prevent the sleep either, because the same USB-C cable
  powered the Mac and that power dropped too. Keep virtual displays disconnected.
- `sudo pmset -a disablesleep 1` is undocumented (the option exists in macOS 27's
  `pmset`) and stops all sleep, including with the lid closed and no display, in a
  bag too. Not tested here. Use it only if the user asks for it; undo with
  `sudo pmset -a disablesleep 0`.

So: remove the cause of the dropouts ([Black Picture](#black-picture)) and keep the
Mac powered. With a KVM monitor, check once (the user switches the input) that
showing the other computer keeps the Mac's link: Diagnose step 5 still lists
`DisplayPort`, and `pmset -g log` shows no new `Clamshell Sleep`. The tested monitor
keeps it: on a switch only `USB2`/`USB3` leave the Mac's port, because the monitor's
USB hub follows the input. If yours drops the Mac, keep the lid open while the other
computer is shown.

## Black Picture

The Mac is awake, or wakes, but the monitor stays black. Work down the list.

1. **Cable or power.** `pmset -g ac` should show the monitor's full power. Here a
   3 A cable (60W) gave a black or blinking picture at every refresh rate while DDC
   and the monitor's USB hub still worked; the supplied 5 A / 100 W cable (90W)
   fixed it.
2. **A signal the link cannot carry (DSC).** `DSC=YES` in the latest mode set
   (Diagnose step 4) means macOS compresses the picture because it does not fit the
   link, and some monitor and link combinations show compressed video as black. On
   the tested monitor's USB-C input in its default mode (2 DisplayPort lanes of
   UHBR10, about 19.2 Gbps) every DSC signal was black:
   - every refresh rate above 60 Hz;
   - since macOS 27.2.1 also 60 Hz, because macOS now sends 10 bits per color:
     5120×2160 at 60 Hz then needs about 21.7 Gbps. 8-bit RGB needs about 16.9 Gbps,
     runs with `DSC=NO`, and showed a picture.

   Fixes, in order:

   - **Refresh rate:** 60 Hz in System Settings > Displays. macOS saves display
     settings per set of connected displays, so set it with the lid open and again
     with it closed, or let a guard enforce it.
   - **Color depth:** macOS has no setting for it. BetterDisplay's command line (the
     free version worked) switches the connection mode:

     ```sh
     BD=/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay
     "$BD" get -name="MONITOR NAME" -connectionMode
     "$BD" get -name="MONITOR NAME" -connectionModeList
     "$BD" set -name="MONITOR NAME" -connectionMode=ID
     ```

     `MONITOR NAME` is the name `system_profiler SPDisplaysDataType` shows. The list
     prints one `ID - mode` per line, for example
     `1621304110078497792 - 5120x2160 59.98Hz Fixed 8bit SDR RGB Full SRGB (6720x4608)`;
     pick the `8bit SDR RGB Full` line with the current timing. macOS returns to its
     own choice when the monitor reconnects, and a wake repeats the mode set, so
     re-apply it after every display change and wake.
     [dell-refresh.lua](../dell-refresh.lua) does both fixes that way.
   - **More lanes (not tested):** a monitor menu option that gives the USB-C input 4
     lanes (on this Dell: USB-C Prioritization = HIGH RESOLUTION; its USB hub then
     drops to USB 2.0) carries 10-bit at 60 Hz without DSC, and would also cover the
     login window.
3. **The monitor gave up.** About 3 minutes after a connect without a picture, the
   tested monitor powered down and dropped USB-C entirely: power, hub and video. With
   the lid closed the Mac then slept (`Clamshell Sleep` with `Using Batt`). Once,
   while the picture was black, the monitor's input also moved to its other source.
   Fix the signal first, then ask the user to select the Mac's input again.
4. **Login window.** LaunchAgents, Hammerspoon and other per-user tools start only
   after login, so neither a guard nor `caffeinate` runs at the login window. If the
   monitor is black there, the user opens the lid and logs in on the built-in
   display.
5. **Mirroring.** If the user mirrored the displays while looking for a lost picture,
   turn mirroring off in System Settings > Displays (in Hammerspoon:
   `hs.screen.primaryScreen():mirrorStop(true)`).
6. **Wrong input.** A KVM monitor may simply show the other computer (Diagnose step
   5). DDC can read the input: `"$BD" get -name="MONITOR NAME" -ddc -vcp=0x60` (on
   this Dell the low byte is `0x1B` for USB-C and `0x0F` for DisplayPort). Reads
   often fail while the other input is shown. Switching back is the user's decision.

## Verify

Done means all of these, checked after the change while the user watches the
monitor:

- `pmset -g assertions` lists the keep-awake assertion, for example `caffeinate`
  holding `PreventUserIdleSystemSleep`.
- The latest `mode_set_gated` line for the monitor shows `DSC=NO`, unless the user
  confirms a picture with `DSC=YES`.
- The picture stays for more than 5 minutes (past the give-up time above), the
  wattage in `pmset -g ac` does not change, and `pmset -g log` shows no new
  `Clamshell Sleep` or `Using Batt`.
- With a KVM monitor, after the user switches to the other computer and back: no
  new sleep, power change or `mode_set_gated` line, and the desktop appears at once.

## Undo

- LaunchAgent: `launchctl bootout gui/$(id -u)/com.example.keep-awake`, then delete
  the plist.
- `pmset`: restore the values saved from `pmset -g custom` (with `sudo`).
- Connection mode: set the previous ID again with `"$BD" set ... -connectionMode=ID`,
  or reconnect the monitor; remove any guard that re-applies it.
