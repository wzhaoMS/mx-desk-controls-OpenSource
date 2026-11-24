local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/[^/]+$") or (os.getenv("HOME") .. "/.hammerspoon")
local modulePath = ROOT .. "/lg-pbp.lua"
local displayUUID = "00000000-0000-4000-8000-0000000000A1"
local guardUUID = "00000000-0000-4000-8000-0000000000B2"
local full = { w = 3360, h = 1418, scale = 2, freq = 100 }
local split = { w = 2560, h = 2160, scale = 1, freq = 75 }
local reconnecting = { w = 1920, h = 1080, scale = 1, freq = 60 }

local function fixture(options)
  options = options or {}
  local calls, timers, alerts = {}, {}, {}
  local state = { mode = options.mode or full, present = not options.noScreen, guard = not options.noGuard }
  local screen = {
    getUUID = function() return options.otherUUID or displayUUID end,
    currentMode = function() return state.mode end,
  }
  local stub = {
    screen = { allScreens = function()
      local displays = state.present and { screen } or {}
      if state.guard then
        displays[#displays + 1] = { getUUID = function() return guardUUID end }
      end
      return displays
    end },
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
  }
  local environment = setmetatable({ hs = stub }, { __index = _G })
  local controller = assert(loadfile(modulePath, "t", environment))()
  local function complete(index, exitCode, stdout, stderr)
    local process = assert(calls[index], "expected DDC process " .. index)
    process.running = false
    process.callback(exitCode or 0, stdout or "", stderr or "")
  end
  return controller, calls, timers, alerts, complete, state
end

local function assertWrite(process, value)
  assert(process.path == "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay")
  local expected = { "set", "-UUID=" .. displayUUID, "-ddc", "-vcp=0xD7", "-value=" .. value }
  assert(table.concat(process.arguments, " ") == table.concat(expected, " "),
    "use the exact LG target and known write value without unreliable DDC reads")
end

local function fireRetry(timers)
  local timer = timers[#timers]
  assert(timer.seconds == 0.5 and not timer.stopped, "wait for native display mode to settle")
  timer.stopped = true
  timer.callback()
end

local controller, calls, timers, alerts, complete, state = fixture()
assert(#calls == 0 and controller.label() == "PBP", "loading must not change the monitor")
assert(controller.toggle())
assertWrite(calls[1], "5")
assert(not controller.toggle() and #calls == 1, "rapid presses must not overlap")
state.mode = split
complete(1)
assert(controller.label() == "PBP ON" and #alerts == 0)
controller.toggle()
assertWrite(calls[2], "1")
state.mode = full
complete(2)
assert(controller.label() == "FULL")
state.mode = split
controller.toggle()
assertWrite(calls[3], "1")
state.mode = full
complete(3)
assert(controller.label() == "FULL", "manual monitor changes must not desynchronize the next toggle")

controller, calls, timers, alerts, complete, state = fixture()
controller.toggle()
state.mode = reconnecting
complete(1)
assert(controller.label() ~= "PBP ON" and #calls == 1, "a write is not proof of a settled layout")
fireRetry(timers)
state.present = false
fireRetry(timers)
state.present = true
state.mode = split
fireRetry(timers)
assert(controller.label() == "PBP ON" and #alerts == 0)

controller.toggle()
state.mode = reconnecting
complete(2)
for attempt = 1, 12 do
  fireRetry(timers)
  assert(controller.label() == "PBP ...", "allow a measured slow full-screen reconnection")
end
state.mode = full
fireRetry(timers)
assert(controller.label() == "FULL" and #alerts == 0)

for _, options in ipairs({ { noScreen = true }, { mode = reconnecting }, { otherUUID = "other-display" } }) do
  controller, calls, timers, alerts, complete, state = fixture(options)
  controller.toggle()
  assert(#calls == 0, "unknown or unrelated display state must never enable PBP")
  for attempt = 1, 23 do fireRetry(timers) end
  assertWrite(calls[1], "1")
  controller.stop()
end

controller, calls, timers, alerts, complete, state = fixture()
controller.toggle()
complete(1)
for attempt = 1, 23 do fireRetry(timers) end
assertWrite(calls[2], "1")
complete(2)
assert(controller.label() == "FULL" and #alerts == 1, "failed convergence must recover and report it")

for _, failure in ipairs({ { 1, "", "Failed." }, { 0, "false", "" } }) do
  controller, calls, timers, alerts, complete, state = fixture()
  controller.toggle()
  complete(1, table.unpack(failure))
  assertWrite(calls[2], "1")
  complete(2)
  assert(controller.label() == "FULL" and #alerts == 1)
end

controller, calls, timers, alerts, complete, state = fixture()
controller.toggle()
timers[1].callback()
assert(calls[1].terminated)
assertWrite(calls[2], "1")
calls[1].originalCallback(0, "", "")
assert(#calls == 2, "timed-out writes must not restart old work")
complete(2)
assert(controller.label() == "FULL")

controller, calls, timers, alerts, complete, state = fixture()
controller.toggle()
complete(1)
local staleRetry = timers[#timers]
controller.off()
assert(staleRetry.stopped)
staleRetry.callback()
assert(#calls == 2)
complete(2)
assert(controller.label() == "FULL")

controller, calls, timers, alerts, complete, state = fixture({ asyncTermination = true })
controller.toggle()
controller.off()
assert(calls[1].terminated and calls[1].running and #calls == 1, "off must wait for a cancelled writer")
calls[1].originalCallback(0, "", "")
assert(#calls == 1 and not controller.toggle())
complete(1, 143)
assertWrite(calls[2], "1")
complete(2)
assert(controller.label() == "FULL")

controller, calls, timers, alerts, complete, state = fixture({ asyncTermination = true })
controller.toggle()
controller.off()
assert(timers[#timers].seconds <= 2)
timers[#timers].callback()
assert(controller.label() == "PBP ERR" and #calls == 1 and not controller.toggle())
complete(1, 143)
assert(#calls == 1, "expired recovery must not execute a late continuation")
controller.off()
complete(2)
assert(controller.label() == "FULL")

controller, calls, timers, alerts, complete, state = fixture()
controller.toggle()
controller.stop()
calls[1].originalCallback(0, "", "")
assert(#calls == 1 and controller.label() == "PBP", "reload must cancel work without new writes")

controller, calls, timers, alerts, complete, state = fixture()
controller.off()
complete(1, 0, "false")
assert(controller.label() == "PBP ERR" and #calls == 1)
assert(alerts[1]:find("joystick", 1, true))

for _, options in ipairs({ { creationFails = true }, { startFails = true } }) do
  controller, calls, timers, alerts = fixture(options)
  controller.toggle()
  assert(controller.label() == "PBP ERR" and #alerts == 1)
  for _, timer in ipairs(timers) do assert(timer.stopped) end
end

controller, calls, timers, alerts, complete, state = fixture({ noGuard = true })
assert(controller.toggle() == false, "do not switch without the verified keepalive display")
assert(#calls == 0 and #alerts == 1 and controller.label() == "PBP ERR")
assert(alerts[1]:find("Keepalive", 1, true), "explain how to restore the required guard")
state.guard = true
assert(controller.toggle(), "restore normal operation after the guard reconnects")
assertWrite(calls[1], "5")
state.mode = split
complete(1)
assert(controller.label() == "PBP ON")

return "PASS: native-mode toggles, reconnects, external changes, failures, timeouts, cancellation, and recovery"