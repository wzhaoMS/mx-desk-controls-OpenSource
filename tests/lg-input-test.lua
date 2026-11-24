local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/[^/]+$") or (os.getenv("HOME") .. "/.hammerspoon")
local modulePath = ROOT .. "/lg-input.lua"
local displayUUID = "00000000-0000-4000-8000-0000000000A1"
local guardUUID = "00000000-0000-4000-8000-0000000000B2"

local function fixture(options)
  options = options or {}
  local calls, timers, alerts, choosers = {}, {}, {}, {}
  local state = {
    present = not options.noScreen, guard = not options.noGuard,
    control = true,
    mode = { w = 3360, h = 1418, scale = 2, freq = 100, depth = 8 },
  }
  local watcher
  local stub = {
    json = hs.json,
    fs = { attributes = function() return not options.noPipHelper and "file" or nil end },
    usb = { attachedDevices = function()
      return state.control and { { vendorID = 0x043e, productID = 0x9a8a } } or {}
    end },
    screen = {
      allScreens = function()
        local screens = {}
        if state.present then
          screens[#screens + 1] = {
            getUUID = function() return options.otherUUID or displayUUID end,
            currentMode = function() return state.mode end,
          }
        end
        if state.guard then screens[#screens + 1] = { getUUID = function() return guardUUID end } end
        return screens
      end,
      watcher = { new = function(callback)
        watcher = { callback = callback }
        function watcher:start() self.running = true; return self end
        function watcher:stop() self.running = false end
        return watcher
      end },
    },
    task = { new = function(path, callback, arguments)
      if options.creationFails then return nil end
      local process = { path = path, callback = callback, originalCallback = callback, arguments = arguments }
      function process:start()
        if options.startFails then return false end
        self.running = true
        return self
      end
      function process:isRunning() return self.running end
      function process:setCallback(replacement) self.callback = replacement end
      function process:terminate()
        self.terminated = true
        if not options.asyncTermination then
          self.running = false
          self.callback(143, "", "")
        end
      end
      calls[#calls + 1] = process
      return process
    end },
    timer = { doAfter = function(seconds, callback)
      local timer = { seconds = seconds, callback = callback }
      function timer:stop() self.stopped = true end
      timers[#timers + 1] = timer
      return timer
    end },
    alert = { show = function(message) alerts[#alerts + 1] = message end },
    chooser = { new = function(callback)
      local choice = { callback = callback }
      function choice:choices(items) self.items = items; return self end
      function choice:placeholderText(text) self.placeholder = text; return self end
      function choice:rows(count) self.rowCount = count; return self end
      function choice:show() self.visible = true; return self end
      function choice:hide() self.visible = false; return self end
      choosers[#choosers + 1] = choice
      return choice
    end },
  }
  local environment = setmetatable({ hs = stub }, { __index = _G })
  local controller = assert(loadfile(modulePath, "t", environment))()
  assert(#calls == 0, "loading must not send display commands")
  controller.start()
  assert(#calls == 0, "starting must not send display commands")
  local function complete(index, exitCode, stdout, stderr)
    local process = assert(calls[index], "missing process " .. index)
    process.running = false
    process.callback(exitCode or 0, stdout or "", stderr or "")
  end
  local function tick()
    for index = #timers, 1, -1 do
      local timer = timers[index]
      if not timer.stopped and timer.seconds == 0.5 then
        timer.stopped = true
        timer.callback()
        return true
      end
    end
    return false
  end
  local function settle()
    for attempt = 1, 3 do assert(tick(), "expected bounded settling timer") end
  end
  return controller, calls, alerts, complete, settle, timers, state, choosers, tick, watcher
end

local function assertCommand(process, feature, code, value)
  assert(process.path == "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay")
  local expected = { "set", "-UUID=" .. displayUUID, feature, "-vcp=" .. code, "-value=" .. value }
  assert(table.concat(process.arguments, " ") == table.concat(expected, " "), "exact allowlisted command only")
end

local function assertPipHelper(process, operation)
  assert(process.path == os.getenv("HOME") .. "/.local/libexec/lg-pip-helper", "use the native PIP helper")
  assert(table.concat(process.arguments, " ") == operation, "exact fixed helper operation")
end

local function pipProbeReply(layout)
  return hs.json.encode({ ok = true, transport = "hid", submittedFrames = 0,
    firmwareValue = 774, brightness = 75, layoutValue = layout })
end

local controller, calls, alerts, complete, settle, timers, state, choosers, tick, watcher = fixture()
assert(controller.select("mac"))
assertCommand(calls[1], "-ddcAlt", "0xF4", "0xD1")
assert(not controller.select("pc") and not controller.swap(), "reject overlapping presses")
complete(1)
assert(not controller.select("pc"), "lock must cover settling, not just task execution")
settle()
assert(#calls == 1 and #alerts == 0, "short press must not write PIP/PBP layout")
assert(controller.select("mac"), "repeating an absolute target must stay idempotent")
complete(2, 0, "true\n")
settle()
assertCommand(calls[2], "-ddcAlt", "0xF4", "0xD1")
assert(controller.swap())
assertCommand(calls[3], "-ddcAlt", "0xF4", "0xD0")
complete(3)
settle()
assert(controller.swap())
assertCommand(calls[4], "-ddcAlt", "0xF4", "0xD1")
complete(4)
settle()

controller, calls, alerts, complete, settle, timers, state, choosers = fixture()
assert(controller.swap() and #calls == 0 and #choosers == 1, "unknown SWAP must ask, never guess from geometry")
assert(#choosers[1].items == 2)
choosers[1].callback(choosers[1].items[2])
assertCommand(calls[1], "-ddcAlt", "0xF4", "0xD0")
complete(1)
settle()

for _, target in ipairs({ "mac", "pc" }) do
  controller, calls, alerts, complete, settle = fixture()
  assert(controller.solo(target))
  assertCommand(calls[1], "-ddcAlt", "0xF4", target == "mac" and "0xD1" or "0xD0")
  complete(1)
  assert(#calls == 1, "do not disable PIP before source settling")
  settle()
  assertCommand(calls[2], "-ddc", "0xD7", "1")
  assert(not controller.select("mac"), "solo transaction must keep its lock across both writes")
  complete(2)
  settle()
  assert(#calls == 2 and #alerts == 0)
end

controller, calls, alerts, complete, settle, timers, state, choosers = fixture()
assert(type(controller.pipOff) == "function", "dedicated PIP-off must not require an input target")
assert(controller.pipOff())
assertCommand(calls[1], "-ddc", "0xD7", "1")
assert(not controller.pipOff() and not controller.select("pc"), "PIP-off must share the writer lock")
complete(1)
assert(not controller.pipOff(), "PIP-off must stay locked during settling")
settle()
assert(#calls == 1 and #alerts == 0, "PIP-off must never send an input-selection command")
assert(controller.swap() and #choosers == 1 and #calls == 1, "PIP-off must not invent a main-input intent")

controller, calls, alerts, complete, settle, timers, state, choosers = fixture()
assert(type(controller.pipOn) == "function", "middle-left PIP enable API is required")
assert(controller.pipOn() and #calls == 0 and #choosers == 1, "unknown PIP main input must ask rather than infer from geometry")
choosers[1].callback(choosers[1].items[1])
assertCommand(calls[1], "-ddcAlt", "0xF4", "0xD1")
controller.stop()

controller, calls, alerts, complete, settle, timers, state, choosers = fixture()
assert(controller.swap())
local oldSourceChooser = choosers[1]
assert(controller.pipOn() and #choosers == 2, "PIP must not reuse an open source-only chooser")
oldSourceChooser.callback(oldSourceChooser.items[2])
assert(#calls == 0, "replaced chooser cannot submit its old operation")
choosers[2].callback(choosers[2].items[2])
assertCommand(calls[1], "-ddcAlt", "0xF4", "0xD1")
controller.stop()

for _, target in ipairs({ "mac", "pc" }) do
  for _, layout in ipairs({ 1, 0, 3, 5 }) do
    controller, calls, alerts, complete, settle, timers, state, choosers = fixture()
    assert(controller.select(target))
    complete(1)
    settle()
    assert(controller.pipOn())
    assertCommand(calls[2], "-ddcAlt", "0xF4", "0xD1")
    assert(not controller.pipOn() and not controller.select("pc") and not controller.pipOff(), "PIP staging owns the display writer")
    complete(2)
    settle()
    assertPipHelper(calls[3], "--probe-hid")
    assert(not controller.pipOff() and not controller.swap(), "preflight shares the writer lock")
    complete(3, 0, pipProbeReply(layout))
    local enableIndex = 4
    if layout ~= 1 then
      assertCommand(calls[4], "-ddc", "0xD7", "1")
      complete(4)
      enableIndex = 5
    end
    settle()
    assertPipHelper(calls[enableIndex], "--enable")
    complete(enableIndex, 0, '{"ok":true,"submittedFrames":9,"layoutValue":0,"effectVerified":false}')
    assert(not controller.pipOn(), "retain writer during post-helper settling")
    settle()
    local expectedCount = enableIndex
    if target == "pc" then
      expectedCount = expectedCount + 1
      assertCommand(calls[expectedCount], "-ddcAlt", "0xF4", "0xD0")
      complete(expectedCount)
      settle()
    end
    local layoutWrites = 0
    for _, process in ipairs(calls) do
      if process.arguments[4] == "-vcp=0xD7" then layoutWrites = layoutWrites + 1 end
    end
    assert(layoutWrites == (layout == 1 and 0 or 1), "only fresh single-picture readback skips the off write")
    assert(#calls == expectedCount and #alerts == 0)
    assert(controller.status().lastTarget == target and controller.status().pipEstablished)
    assert(controller.pipOn() and #calls == expectedCount, "repeated PIP-on is a no-op while this controller owns the established layout")
    assert(controller.swap() and #choosers == 0)
    assertCommand(calls[expectedCount + 1], "-ddcAlt", "0xF4", target == "mac" and "0xD0" or "0xD1")
    complete(expectedCount + 1)
    settle()
    assert(not controller.status().pipEstablished, "a new source request invalidates the remembered PIP result")
    controller.stop()
  end
end

for _, reply in ipairs({ "", "true", '{"ok":false}', '{"ok":true,"layoutValue":1}' }) do
  controller, calls, alerts, complete, settle = fixture()
  controller.select("pc"); complete(1); settle()
  controller.pipOn(); complete(2); settle()
  assertPipHelper(calls[3], "--probe-hid")
  complete(3, 0, reply)
  assert(#calls == 3 and #alerts == 1 and controller.subtitle("pip") == "RETRY", "invalid preflight cannot write layout or restore PC")
end

for _, override in ipairs({ { transport = "serial" }, { submittedFrames = 1 }, { firmwareValue = 775 },
    { firmwareValue = "774" }, { layoutValue = "1" }, { layoutValue = -1 }, { layoutValue = 256 },
    { layoutValue = 1.5 }, { brightness = 101 }, { brightness = "75" } }) do
  local reply = hs.json.decode(pipProbeReply(1))
  for field, value in pairs(override) do reply[field] = value end
  controller, calls, alerts, complete, settle = fixture()
  controller.select("mac"); complete(1); settle()
  controller.pipOn(); complete(2); settle()
  complete(3, 0, hs.json.encode(reply))
  assert(#calls == 3 and #alerts == 1, "wrong preflight metadata cannot skip or send a layout write")
end

for _, reply in ipairs({ "", "true", '{"ok":false}', '{"ok":true,"submittedFrames":8,"layoutValue":0}', '{"ok":true,"submittedFrames":9,"layoutValue":1}' }) do
  controller, calls, alerts, complete, settle = fixture()
  controller.select("pc"); complete(1); settle()
  controller.pipOn(); complete(2); settle(); complete(3, 0, pipProbeReply(0)); complete(4); settle()
  complete(5, 0, reply)
  assert(#calls == 5 and #alerts == 1 and controller.subtitle("pip") == "RETRY", "bad helper result must not select PC or claim PIP")
  assert(not controller.status().pipEstablished)
end

controller, calls, alerts, complete, settle, timers = fixture({ asyncTermination = true })
controller.select("pc"); complete(1); settle()
controller.pipOn(); complete(2); settle(); complete(3, 0, pipProbeReply(1)); settle()
assert(controller.select("mac"), "explicit MAC press cancels a PIP transaction")
assert(calls[4].terminated and #calls == 4, "wait for the helper to exit before MAC recovery")
calls[4].originalCallback(0, '{"ok":true,"submittedFrames":9,"layoutValue":0}', "")
assert(#calls == 4 and not controller.select("pc"), "stale helper success cannot restore PC")
complete(4, 143)
assertCommand(calls[5], "-ddcAlt", "0xF4", "0xD1")
complete(5)
settle()
assert(controller.status().lastTarget == "mac" and not controller.status().busy)

controller, calls, alerts, complete, settle, timers = fixture({ asyncTermination = true })
controller.select("pc"); complete(1); settle()
controller.pipOn(); complete(2); settle()
assertPipHelper(calls[3], "--probe-hid")
assert(controller.select("mac") and calls[3].terminated and #calls == 3, "MAC cancellation waits for the read-only child too")
calls[3].originalCallback(0, pipProbeReply(1), "")
assert(#calls == 3 and not controller.select("pc"), "stale preflight cannot start navigation")
complete(3, 143)
assertCommand(calls[4], "-ddcAlt", "0xF4", "0xD1")
complete(4); settle()

controller, calls, alerts, complete, settle, timers = fixture({ asyncTermination = true })
controller.select("mac"); complete(1); settle()
controller.pipOn(); complete(2); settle()
local probeDeadline = timers[#timers]
assert(probeDeadline.seconds == 5, "preflight has a five-second task deadline")
probeDeadline.callback()
assert(calls[3].terminated and #calls == 3 and not controller.pipOff(), "preflight timeout retains the writer lock")
calls[3].originalCallback(0, pipProbeReply(1), "")
complete(3, 143)
assert(#calls == 3 and controller.subtitle("pip") == "RETRY", "timed-out preflight sends no fallback")

controller, calls, alerts, complete, settle = fixture({ noPipHelper = true })
controller.select("pc"); complete(1); settle()
assert(not controller.pipOn() and #calls == 1 and #alerts == 1, "missing helper fails before staging any input")
assert(controller.status().lastError:find("lg%-pip%-helper"), "retain a bounded actionable failure reason")

controller, calls, alerts, complete, settle, timers, state, choosers, tick = fixture()
controller.select("pc"); complete(1); settle()
controller.pipOn(); complete(2)
state.control = false
for attempt = 1, 4 do assert(tick()) end
assert(#calls == 2, "Mac anchoring must wait for the LG USB control interface, not only video geometry")
state.control = true
settle()
assertPipHelper(calls[3], "--probe-hid")
controller.stop()

for _, target in ipairs({ "mac", "pc" }) do
  controller, calls, alerts, complete, settle, timers, state, choosers = fixture()
  assert(controller.select(target))
  complete(1)
  settle()
  assert(controller.pipOff())
  assertCommand(calls[2], "-ddc", "0xD7", "1")
  assert(not controller.solo(target) and not controller.swap(), "PIP-off blocks every competing source action")
  complete(2)
  settle()
  assert(controller.pipOff(), "repeated PIP-off must remain target-free")
  assertCommand(calls[3], "-ddc", "0xD7", "1")
  complete(3, 0, "true\n")
  settle()
  assert(controller.swap() and #choosers == 0, "successful PIP-off must preserve the existing SWAP intent")
  assertCommand(calls[4], "-ddcAlt", "0xF4", target == "mac" and "0xD0" or "0xD1")
end

for _, failure in ipairs({ { 1, "", "Failed." }, { 0, "false", "" }, { 0, "unexpected", "" } }) do
  controller, calls, alerts, complete, settle, timers, state, choosers = fixture()
  controller.solo("pc")
  complete(1, table.unpack(failure))
  assert(#calls == 1 and #alerts == 1, "failure must not send layout or fallback commands")
  controller.swap()
  assert(#calls == 1 and #choosers == 1, "failed request must invalidate SWAP intent")

  controller, calls, alerts, complete, settle, timers, state, choosers = fixture()
  assert(controller.pipOff())
  complete(1, table.unpack(failure))
  assert(#calls == 1 and #alerts == 1 and controller.subtitle("swap") == "RETRY", "failed PIP-off must not send a fallback")
  assert(controller.swap() and #choosers == 1 and #calls == 1, "failed PIP-off must not guess a main input")
end

controller, calls, alerts, complete, settle, timers, state, choosers = fixture()
controller.solo("pc")
complete(1)
settle()
complete(2, 1, "", "off failed")
assert(#calls == 2 and #alerts == 1, "failed PIP-off must not retry or change input automatically")
controller.swap()
assert(#choosers == 1)

for _, options in ipairs({ { noGuard = true }, { noScreen = true }, { otherUUID = "unrelated" } }) do
  controller, calls, alerts = fixture(options)
  assert(not controller.select("pc") and #calls == 0 and #alerts == 1, "require both exact displays")
  assert(not controller.pipOff() and #calls == 0 and #alerts == 2, "PIP-off requires the same exact displays")
end
controller, calls, alerts = fixture()
assert(not controller.select("hdmi") and not controller.solo("invalid") and #calls == 0)
assert(not controller.select(nil) and not controller.solo(nil) and #calls == 0, "missing source targets must not become PIP-off")

controller, calls, alerts, complete, settle, timers, state, choosers, tick = fixture()
controller.select("pc")
complete(1)
state.present = false
for attempt = 1, 8 do assert(tick()) end
state.present = true
state.mode = { w = 1920, h = 1080, scale = 1, freq = 60 }
assert(tick())
state.mode = { w = 3360, h = 1418, scale = 2, freq = 100 }
settle()
assert(#alerts == 0 and controller.swap(), "settling compares samples, never a per-source expected resolution")
assertCommand(calls[2], "-ddcAlt", "0xF4", "0xD1")

controller, calls, alerts, complete, settle, timers, state, choosers, tick = fixture()
controller.solo("pc")
complete(1)
state.present = false
for attempt = 1, 24 do assert(tick()) end
assert(not tick() and #calls == 1 and #alerts == 1, "bounded settling failure must not disable PIP")

controller, calls, alerts, complete, settle, timers = fixture({ asyncTermination = true })
controller.solo("pc")
timers[1].callback()
assert(calls[1].terminated and calls[1].running)
assert(not controller.select("mac") and #calls == 1, "timed-out process retains the writer lock until exit")
calls[1].originalCallback(0, "", "")
assert(#calls == 1, "late accepted response must not resume cancelled solo")
complete(1, 143)
assert(controller.select("mac"))
assertCommand(calls[2], "-ddcAlt", "0xF4", "0xD1")

controller, calls, alerts, complete, settle, timers = fixture({ asyncTermination = true })
assert(controller.pipOff())
timers[1].callback()
assert(calls[1].terminated and calls[1].running)
assert(not controller.pipOff() and not controller.select("mac"), "timed-out PIP-off retains the writer lock until exit")
calls[1].originalCallback(0, "", "")
assert(#calls == 1 and controller.subtitle("swap") == "RETRY", "stale PIP-off success must not resume the transaction")
complete(1, 143)
assert(controller.pipOff())
assertCommand(calls[2], "-ddc", "0xD7", "1")
controller.stop()
assert(not controller.pipOff(), "stopped controller rejects PIP-off")

controller, calls, alerts, complete, settle, timers = fixture({ asyncTermination = true })
controller.select("pc")
controller.stop()
controller.start()
assert(not controller.select("mac"), "restart must not overlap a cancelled writer")
calls[1].originalCallback(0, "", "")
complete(1, 143)
assert(controller.select("mac"))

controller, calls, alerts, complete, settle, timers, state, choosers, tick, watcher = fixture()
controller.select("mac")
complete(1)
settle()
state.present = false
watcher.callback()
assert(#choosers == 0, "screen loss never opens a chooser by itself")
state.present = true
controller.swap()
assert(#choosers == 1, "idle disconnect clears remembered intent")
local staleChoice = choosers[1]
controller.stop()
staleChoice.callback(staleChoice.items[2])
assert(#calls == 1 and not watcher.running, "stopped chooser and watcher cannot send commands")

controller, calls, alerts, complete, settle, timers = fixture()
controller.solo("mac")
complete(1)
local staleTimer = timers[#timers]
controller.stop()
staleTimer.callback()
assert(#calls == 1 and not controller.select("pc"), "stop cancels queued PIP-off and rejects later presses")

for _, options in ipairs({ { creationFails = true }, { startFails = true } }) do
  controller, calls, alerts, complete, settle, timers = fixture(options)
  controller.solo("pc")
  assert(#alerts == 1, "task startup failure must be reported")
  for _, timer in ipairs(timers) do assert(timer.stopped) end
end

controller = fixture()
assert(controller.DISPLAY_UUID == displayUUID and controller.GUARD_UUID == guardUUID,
  "lg-window-rescue reads the exact display UUIDs from lg-input")

return "PASS: exact source requests, solo sequencing, preserve-main PIP-off, unknown swap, settling, failures, cancellation, and lifecycle"