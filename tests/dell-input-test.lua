local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/[^/]+$") or (os.getenv("HOME") .. "/.hammerspoon")
local modulePath = ROOT .. "/dell-input.lua"
local executable = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
local usbcUUID = "00000000-0000-4000-8000-00000000DE11"

local function fixture(options)
  options = options or {}
  local calls, timers, alerts = {}, {}, {}
  local state = { screens = { { name = "AW3926QW", uuid = usbcUUID } } }
  local stub = {
    screen = { allScreens = function()
      local screens = {}
      for _, item in ipairs(state.screens) do
        screens[#screens + 1] = { name = function() return item.name end, getUUID = function() return item.uuid end }
      end
      return screens
    end },
    task = { new = function(path, callback, arguments)
      if options.creationFails then return nil end
      local process = { path = path, callback = callback, arguments = arguments }
      function process:start()
        if options.startFails then return false end
        self.running = true
        return self
      end
      function process:isRunning() return self.running end
      function process:setCallback(replacement) self.callback = replacement end
      function process:terminate() self.terminated = true end
      function process:finish(code, stdout, stderr)
        self.running = false
        self.callback(code, stdout or "", stderr or "")
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
  local changes = 0
  controller.onChange = function() changes = changes + 1 end
  assert(#calls == 0, "loading must not send monitor commands")
  controller.start()
  assert(#calls == 0, "starting must not send monitor commands")
  return {
    controller = controller, calls = calls, timers = timers, alerts = alerts,
    state = state, changes = function() return changes end,
  }
end

local function assertArguments(process, expected, message)
  local actual = table.concat(process.arguments, " ")
  assert(process.path == executable, message .. ": wrong executable " .. tostring(process.path))
  assert(actual == table.concat(expected, " "), message .. ": got " .. actual)
end
local function writeArguments(uuid, value) return { "set", "-UUID=" .. uuid, "-ddc", "-vcp=0x60", "-value=" .. value } end
local function readArguments(uuid) return { "get", "-UUID=" .. uuid, "-ddc", "-vcp=0x60" } end

local f = fixture()
assert(f.controller.INPUTS.mac == 0x1B and f.controller.INPUTS.pc == 0x0F and f.controller.MONITOR_NAME == "AW3926QW")
assert(f.controller.select("mac") == true)
assertArguments(f.calls[1], writeArguments(usbcUUID, "0x1B"), "MAC selects USB-C")
assert(f.controller.subtitle() == "WAIT" and f.controller.status().busy)
assert(f.controller.select("pc") == false and f.controller.swap() == false and #f.calls == 1,
  "requests while a command runs are ignored, not queued")
f.calls[1]:finish(0, "")
local status = f.controller.status()
assert(not status.busy and status.phase == "idle" and status.lastTarget == "mac" and status.connected)
assert(f.controller.subtitle() == "" and f.timers[1].stopped, "a finished command clears WAIT and its deadline")
assert(f.controller.select("pc") == true)
assertArguments(f.calls[2], writeArguments(usbcUUID, "0x0F"), "PC selects DisplayPort")
f.calls[2]:finish(0, "true\n")
assert(f.controller.status().lastTarget == "pc")
assert(f.controller.select("hdmi") == false and #f.calls == 2, "unknown targets are rejected")
assert(f.changes() >= 5, "start, busy and idle transitions repaint the keys")

-- macOS assigns the monitor a new UUID per cable or port; never send to another screen.
f.state.screens = { { name = "Built-in Retina Display", uuid = "BUILTIN" }, { name = "AW3926QW", uuid = "OTHER-PORT" } }
assert(f.controller.select("mac") == true)
assertArguments(f.calls[3], writeArguments("OTHER-PORT", "0x1B"), "follow the monitor to its current UUID")
f.calls[3]:finish(0, "")

-- SWAP reads the live input and selects the other computer.
assert(f.controller.swap() == true)
assertArguments(f.calls[4], readArguments("OTHER-PORT"), "SWAP reads VCP 0x60 first")
f.calls[4]:finish(0, "6939\n")
assertArguments(f.calls[5], writeArguments("OTHER-PORT", "0x0F"), "SWAP from USB-C (0x1B1B) goes to the PC")
assert(f.controller.status().busy, "the follow-up write keeps the lock")
f.calls[5]:finish(0, "")
assert(f.controller.swap() == true)
f.calls[6]:finish(0, "3855")
assertArguments(f.calls[7], writeArguments("OTHER-PORT", "0x1B"), "SWAP from DisplayPort (0x0F0F) returns to the Mac")
f.calls[7]:finish(0, "")
assert(f.controller.swap() == true)
f.calls[8]:finish(0, "17")
assertArguments(f.calls[9], writeArguments("OTHER-PORT", "0x1B"), "any input other than USB-C swaps to the Mac")
f.calls[9]:finish(0, "")

-- An unreadable input selects the Mac, which is harmless when the Mac is already showing.
assert(f.controller.swap() == true)
f.calls[10]:finish(1, "", "Failed.")
assertArguments(f.calls[11], writeArguments("OTHER-PORT", "0x1B"), "an unreadable input selects the Mac")
f.calls[11]:finish(0, "")
assert(f.controller.status().lastTarget == "mac" and f.controller.subtitle() == "")
assert(f.controller.swap() == true)
f.calls[12]:finish(0, "Failed.")
assertArguments(f.calls[13], writeArguments("OTHER-PORT", "0x1B"), "a non-numeric read also selects the Mac")
f.calls[13]:finish(0, "")
assert(#f.calls == 13)
assert(f.controller.select("pc") == true)
f.calls[14]:finish(0, "")

-- Failures are visible, never retried, and the next press clears them.
assert(f.controller.select("mac") == true)
f.calls[15]:finish(1, "", "DDC write failed")
assert(f.controller.subtitle() == "RETRY" and f.alerts[#f.alerts]:find("failed", 1, true))
assert(#f.calls == 15, "no automatic retry")
assert(f.controller.select("mac") == true)
f.calls[16]:finish(0, "false")
assert(f.controller.status().phase == "error", "an unexpected reply is a failure")
assert(f.controller.select("mac") == true)
f.calls[17]:finish(0, "")
assert(f.controller.subtitle() == "" and f.controller.status().lastError == nil)

-- A missing monitor fails visibly and never falls back to another screen.
f.state.screens = { { name = "Built-in Retina Display", uuid = "BUILTIN" } }
assert(f.controller.select("pc") == false and f.controller.swap() == false and #f.calls == 17)
assert(f.alerts[#f.alerts]:find("input button", 1, true), "point the user at the monitor's input button")
assert(f.controller.subtitle() == "RETRY" and f.controller.status().connected == false)

-- A hung BetterDisplay call times out and keeps the lock until it exits.
local t = fixture()
assert(t.controller.select("mac"))
local hung = t.calls[1]
assert(t.timers[1].seconds == 5)
t.timers[1].callback()
assert(hung.terminated and t.controller.subtitle() == "WAIT", "the lock is held until the process exits")
assert(t.controller.select("pc") == false and #t.calls == 1)
assert(t.alerts[#t.alerts]:find("timed out", 1, true))
hung:finish(143, "", "")
assert(not t.controller.status().busy and t.controller.subtitle() == "RETRY")
assert(t.controller.select("pc") == true and #t.calls == 2, "a later press works after the hung process exits")

-- Stop terminates the running command and ignores its late callback.
local s = fixture()
assert(s.controller.select("mac"))
s.controller.stop()
assert(s.calls[1].terminated)
s.calls[1]:finish(0, "")
assert(s.controller.status().lastTarget == nil, "callbacks after stop are ignored")
assert(s.controller.select("mac") == false and s.controller.swap() == false and #s.calls == 1)
s.controller.start()
assert(s.controller.select("mac") == true and #s.calls == 2)

-- BetterDisplay missing or failing to launch is reported without leaving a lock.
local missing = fixture({ creationFails = true })
assert(missing.controller.select("mac") == false and missing.controller.subtitle() == "RETRY")
local noStart = fixture({ startFails = true })
assert(noStart.controller.select("mac") == false and not noStart.controller.status().busy)
assert(noStart.timers[1].stopped, "a failed launch stops its deadline")

return "PASS: Dell input values, per-press monitor lookup, SWAP readback, hidden-Mac fallback, failures, timeout, missing monitor, and lifecycle"
