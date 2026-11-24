local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/[^/]+$") or (os.getenv("HOME") .. "/.hammerspoon")
local modulePath = ROOT .. "/dell-refresh.lua"
local timers, setModes, watchers = {}, {}, {}
local screens = {}
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
    secondsSinceEpoch = function() return 1000 end,
  },
}
local environment = setmetatable({ hs = stub, print = function() end }, { __index = _G })
local guard = assert(loadfile(modulePath, "t", environment))()
assert(guard.MAX_HZ == 60)
assert(#watchers == 0 and #timers == 0, "loading must not watch or change displays")

-- The lid-closed restore of native 5K2K at 165 Hz is capped to 60 Hz, keeping resolution and scale.
local dell = screen("AW3926QW", { w = 5120, h = 2160, scale = 1, freq = 165, depth = 8 })
local builtin = screen("Built-in Retina Display", { w = 1728, h = 1117, scale = 2, freq = 120, depth = 8 })
screens = { builtin, dell }
guard.start()
assert(#watchers == 1 and watchers[1].running and #setModes == 0, "start checks only after the settle delay")
assert(timers[1].seconds == 1.5)
timers[1].callback()
assert(#setModes == 1, "only the Dell is changed; the built-in display keeps 120 Hz")
local change = setModes[1]
assert(change.name == "AW3926QW" and change.w == 5120 and change.h == 2160 and change.scale == 1
  and change.freq == 60 and change.depth == 8)
local status = guard.status()
assert(status.running and status.lastFix.from == 165 and status.lastFix.ok)

-- A burst of screen changes is checked once, and 60 Hz is left alone.
watchers[1].callback()
watchers[1].callback()
assert(timers[2].stopped and not timers[3].stopped, "a newer screen change replaces the pending check")
timers[3].callback()
assert(#setModes == 1, "a monitor already at 60 Hz is not touched")

-- The user's scaled mode keeps its scaling.
dell.mode = { w = 2560, h = 1080, scale = 2, freq = 120, depth = 8 }
watchers[1].callback()
timers[#timers].callback()
assert(#setModes == 2 and setModes[2].w == 2560 and setModes[2].scale == 2 and setModes[2].freq == 60)

-- Without the monitor nothing happens.
screens = { builtin }
assert(guard.check() == false and #setModes == 2)

-- Stop removes the watcher and any pending check.
screens = { builtin, dell }
dell.mode.freq = 165
watchers[1].callback()
local pending = timers[#timers]
guard.stop()
assert(not watchers[1].running and pending.stopped and guard.status().running == false)
assert(#setModes == 2, "a stopped guard changes nothing")

return "PASS: caps the AW3926QW at 60 Hz after settling, keeps resolution and scale, ignores other displays, debounces, and stops cleanly"
