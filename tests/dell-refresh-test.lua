local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/[^/]+$") or (os.getenv("HOME") .. "/.hammerspoon")
local modulePath = ROOT .. "/dell-refresh.lua"
local timers, setModes, watchers, tasks, wakeWatchers = {}, {}, {}, {}, {}
local screens = {}
local clock = 1000
local holdTasks, stubborn = false, false

local EIGHT_BIT = "1621304110078497792 - 5120x2160 59.98Hz Fixed 8bit SDR RGB Full SRGB (6720x4608)"
local TEN_BIT = "1657332907097461760 - 5120x2160 59.98Hz Fixed 10bit SDR RGB Full SRGB (6720x4608)"
local MODE_LIST = table.concat({
  TEN_BIT,
  EIGHT_BIT,
  "2774225614685344768 - 5120x2160 59.98Hz Fixed 8bit SDR RGB Limited SRGB (6720x4608)",
  "2594081629590524928 - 5120x2160 59.98Hz Fixed 10bit SDR YCbCr 4:2:2 Limited SRGB (6720x4608)",
}, "\n") .. "\n"
local connectionMode, modeList = TEN_BIT, MODE_LIST

-- Stands in for the BetterDisplay CLI and answers like BetterDisplay 4 does.
local function betterDisplay(arguments)
  local joined = table.concat(arguments, " ")
  if joined:find("-connectionModeList", 1, true) then return 0, modeList, "" end
  local id = joined:match("%-connectionMode=(%d+)")
  if arguments[1] == "set" and id then
    if stubborn then return 0, "", "" end
    for line in modeList:gmatch("[^\n]+") do
      if line:find(id .. " - ", 1, true) == 1 then connectionMode = line; return 0, "", "" end
    end
    return 1, "Failed.\n", ""
  end
  if joined:find("-connectionMode", 1, true) then return 0, connectionMode .. "\n", "" end
  return 1, "Failed.\n", ""
end

local function screen(name, mode)
  local item = { mode = mode }
  function item:name() return name end
  function item:currentMode() return self.mode end
  function item:setMode(w, h, scale, freq, depth)
    setModes[#setModes + 1] = { name = name, w = w, h = h, scale = scale, freq = freq, depth = depth }
    self.mode = { w = w, h = h, scale = scale, freq = freq, depth = depth }
    return true
  end
  return item
end
local stub = {
  screen = {
    allScreens = function() return screens end,
    watcher = { new = function(callback)
      local watcher = { callback = callback }
      function watcher:start() self.running = true; return self end
      function watcher:stop() self.running = false end
      watchers[#watchers + 1] = watcher
      return watcher
    end },
  },
  timer = {
    doAfter = function(seconds, callback)
      local timer = { seconds = seconds, callback = callback }
      function timer:stop() self.stopped = true end
      timers[#timers + 1] = timer
      return timer
    end,
    secondsSinceEpoch = function() return clock end,
  },
  caffeinate = { watcher = {
    systemDidWake = 0, screensDidWake = 4, screensDidUnlock = 11, screensaverDidStart = 7,
    new = function(callback)
      local watcher = { callback = callback }
      function watcher:start() self.running = true; return self end
      function watcher:stop() self.running = false end
      wakeWatchers[#wakeWatchers + 1] = watcher
      return watcher
    end,
  } },
  task = { new = function(path, callback, arguments)
    local process = { path = path, callback = callback, arguments = arguments }
    function process:start()
      tasks[#tasks + 1] = self
      if not holdTasks then self:exit(betterDisplay(self.arguments)) end
      return self
    end
    function process:exit(code, stdout, stderr) self.callback(code, stdout, stderr) end
    function process:terminate() self.terminated = true end
    return process
  end },
}

local function pendingSettle()
  for i = #timers, 1, -1 do
    local timer = timers[i]
    if timer.seconds == 1.5 and not timer.stopped and not timer.fired then return timer end
  end
end
local function settle()
  local timer = assert(pendingSettle(), "a screen check is pending")
  timer.fired = true
  timer.callback()
end
local function calls(from)
  local made = {}
  for i = from + 1, #tasks do made[#made + 1] = table.concat(tasks[i].arguments, " ") end
  return made
end
local function screenChange()
  watchers[1].callback()
  settle()
end

local environment = setmetatable({ hs = stub, print = function() end }, { __index = _G })
local guard = assert(loadfile(modulePath, "t", environment))()
assert(guard.MAX_HZ == 60)
assert(#watchers == 0 and #wakeWatchers == 0 and #timers == 0 and #tasks == 0,
  "loading must not watch or change displays")

-- The lid-closed restore of native 5K2K at 165 Hz is capped to 60 Hz, keeping resolution and scale.
local dell = screen("AW3926QW", { w = 5120, h = 2160, scale = 1, freq = 165, depth = 8 })
local builtin = screen("Built-in Retina Display", { w = 1728, h = 1117, scale = 2, freq = 120, depth = 8 })
screens = { builtin, dell }
guard.start()
assert(#watchers == 1 and watchers[1].running and #setModes == 0, "start checks only after the settle delay")
assert(timers[1].seconds == 1.5)
settle()
assert(#setModes == 1, "only the Dell is changed; the built-in display keeps 120 Hz")
local change = setModes[1]
assert(change.name == "AW3926QW" and change.w == 5120 and change.h == 2160 and change.scale == 1
  and change.freq == 60 and change.depth == 8)
assert(#tasks == 0, "the connection mode waits until the new refresh rate has settled")
local status = guard.status()
assert(status.running and status.lastFix.from == 165 and status.lastFix.ok)

-- macOS does not always report a refresh change, so the guard looks once more on its own and
-- replaces 10-bit (which needs DSC on two lanes) with 8-bit RGB.
settle()
local made = calls(0)
assert(#made == 3, table.concat(made, " | "))
assert(made[1] == "get -name=AW3926QW -connectionMode")
assert(made[2] == "get -name=AW3926QW -connectionModeList")
assert(made[3] == "set -name=AW3926QW -connectionMode=1621304110078497792", made[3])
assert(connectionMode == EIGHT_BIT and not pendingSettle(), "one follow-up look, then 8-bit")
status = guard.status()
assert(status.lastDepthFix.ok and status.lastDepthFix.from:find(" 10bit SDR ", 1, true)
  and status.lastDepthFix.to:find(" 8bit SDR RGB Full ", 1, true))

-- A burst of screen changes is checked once, and 60 Hz 8-bit is only read.
local before = #tasks
watchers[1].callback()
local first = pendingSettle()
watchers[1].callback()
assert(first.stopped and pendingSettle() ~= first, "a newer screen change replaces the pending check")
settle()
made = calls(before)
assert(#setModes == 1 and #made == 1 and made[1] == "get -name=AW3926QW -connectionMode")

-- Waking repeats macOS's mode choice without always raising a screen event, so wakes are checked too.
assert(#wakeWatchers == 1 and wakeWatchers[1].running)
local power = stub.caffeinate.watcher
wakeWatchers[1].callback(power.screensaverDidStart)
assert(not pendingSettle(), "other power events are ignored")
for _, event in ipairs({ power.systemDidWake, power.screensDidWake, power.screensDidUnlock }) do
  before = #tasks
  wakeWatchers[1].callback(event)
  settle()
  assert(#calls(before) == 1, "a wake reads the connection mode")
end

-- The user's scaled mode keeps its scaling.
dell.mode = { w = 2560, h = 1080, scale = 2, freq = 120, depth = 8 }
screenChange()
assert(#setModes == 2 and setModes[2].w == 2560 and setModes[2].scale == 2 and setModes[2].freq == 60)
settle()

-- A mode that will not change is retried after 30 seconds, not on every screen change.
stubborn, connectionMode = true, TEN_BIT
clock = clock + 100
before = #tasks
screenChange()
assert(#calls(before) == 3, "a reconnect at 10-bit is fixed")
before = #tasks
screenChange()
assert(#calls(before) == 1, "no second attempt within 30 seconds")
clock = clock + 31
before = #tasks
screenChange()
assert(#calls(before) == 3, "retried after 30 seconds")
stubborn = false

-- HDR is the user's choice and is left alone; without an 8-bit RGB mode nothing is guessed.
connectionMode = "1700000000000000000 - 5120x2160 59.98Hz Fixed 10bit HDR RGB Full PQ (6720x4608)"
clock = clock + 100
before = #tasks
screenChange()
assert(#calls(before) == 1, "HDR is not replaced")
connectionMode, modeList = TEN_BIT, TEN_BIT .. "\n"
clock = clock + 100
before = #tasks
screenChange()
assert(#calls(before) == 2 and connectionMode == TEN_BIT, "nothing is set without an 8-bit RGB mode")
status = guard.status()
assert(status.lastDepthFix.ok == false and status.lastDepthFix.error)
modeList = MODE_LIST

-- Without the monitor nothing happens.
screens = { builtin }
before = #tasks
assert(guard.check() == false and #setModes == 2 and #calls(before) == 0)
screens = { builtin, dell }

-- One BetterDisplay process at a time; a hung one is killed after 10 seconds.
holdTasks = true
clock = clock + 100
before = #tasks
screenChange()
local hung = tasks[#tasks]
screenChange()
assert(#calls(before) == 1, "no second process while one is running")
local deadline
for i = #timers, 1, -1 do
  if timers[i].seconds == 10 and not timers[i].stopped then deadline = timers[i]; break end
end
assert(deadline, "each process has a deadline")
deadline.callback()
assert(hung.terminated, "the hung process is killed")
hung:exit(0, TEN_BIT .. "\n", "")
assert(#calls(before) == 1, "a reply after the deadline starts nothing")

-- Stop removes the watcher, any pending check, and a running process.
screenChange()
local running = tasks[#tasks]
assert(running ~= hung, "the lock is free again after the deadline")
dell.mode.freq = 165
watchers[1].callback()
local pending = pendingSettle()
guard.stop()
assert(not watchers[1].running and not wakeWatchers[1].running and pending.stopped and running.terminated
  and guard.status().running == false)
assert(#setModes == 2, "a stopped guard changes nothing")
holdTasks = false

return "PASS: caps the AW3926QW at 60 Hz and 8-bit RGB (no DSC) after settling, keeps resolution, scale and HDR, rate-limits retries, runs one bounded BetterDisplay process, and stops cleanly"
