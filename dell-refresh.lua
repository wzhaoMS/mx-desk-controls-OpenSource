-- Keeps the Alienware AW3926QW at or below MAX_HZ. On its USB-C link in HIGH DATA SPEED
-- mode (2 DisplayPort lanes) every rate above 60 Hz showed a black picture, and macOS
-- restores a saved 165 Hz whenever the lid closes. Raise MAX_HZ only after switching the
-- monitor's USB-C Prioritization to HIGH RESOLUTION and confirming a picture.
local M = {}

local MONITOR_NAME = "AW3926QW"
local MAX_HZ = 60
local SETTLE_SECONDS = 1.5
M.MAX_HZ = MAX_HZ

local watcher, timer, lastFix

function M.check()
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:name() == MONITOR_NAME then
      local mode = screen:currentMode()
      if not mode or not mode.freq or mode.freq <= MAX_HZ + 0.5 then return false end
      local ok = screen:setMode(mode.w, mode.h, mode.scale, MAX_HZ, mode.depth) == true
      lastFix = { at = hs.timer.secondsSinceEpoch(), from = mode.freq, ok = ok }
      print(string.format("[dell-refresh] %s %dx%d@%gx %gHz -> %dHz ok=%s",
        MONITOR_NAME, mode.w, mode.h, mode.scale, mode.freq, MAX_HZ, tostring(ok)))
      return ok
    end
  end
  return false
end

-- Screen changes arrive in bursts while macOS reconfigures; check once they settle.
local function schedule()
  if timer then timer:stop() end
  timer = hs.timer.doAfter(SETTLE_SECONDS, function()
    timer = nil
    M.check()
  end)
end

function M.start()
  if watcher then return end
  watcher = hs.screen.watcher.new(schedule)
  watcher:start()
  schedule()
end

function M.stop()
  if watcher then watcher:stop(); watcher = nil end
  if timer then timer:stop(); timer = nil end
end

function M.status()
  return { running = watcher ~= nil, maxHz = MAX_HZ, lastFix = lastFix }
end

return M
