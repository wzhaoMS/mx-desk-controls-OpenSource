local M = {}

local QUIET_SECONDS = 3

local lgInput = require("lg-input")

local watcher, timer, lastMoved, lastApps
local stopped = true

function M.overlapArea(a, b)
  local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
  local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
  if w <= 0 or h <= 0 then return 0 end
  return w * h
end

local function clamp(value, low, high)
  return math.max(low, math.min(value, high))
end

function M.placement(frame, from, to)
  local w, h = math.min(frame.w, to.w), math.min(frame.h, to.h)
  return {
    x = clamp(to.x + (frame.x - from.x), to.x, to.x + to.w - w),
    y = clamp(to.y + (frame.y - from.y), to.y, to.y + to.h - h),
    w = w,
    h = h,
  }
end

local function screens()
  local display, guard
  for _, screen in ipairs(hs.screen.allScreens()) do
    local uuid = screen:getUUID()
    if uuid == lgInput.DISPLAY_UUID then display = screen end
    if uuid == lgInput.GUARD_UUID then guard = screen end
  end
  return display, guard
end

local function stranded(win, guard)
  if not win:isStandard() or not win:isVisible() or win:isFullScreen() then return false end
  local screen = win:screen()
  if not screen or screen:getUUID() ~= lgInput.GUARD_UUID then return false end
  -- hs.window:screen() falls back to the nearest screen when a window overlaps none.
  return M.overlapArea(win:frame(), guard:fullFrame()) > 0
end

local function appName(win)
  local ok, name = pcall(function() return win:application():name() end)
  return ok and name or "?"
end

function M.rescue()
  local display, guard = screens()
  if not display or not guard then return 0 end
  local from, to, apps = guard:frame(), display:frame(), {}
  for _, win in ipairs(hs.window.allWindows()) do
    local ok, moved = pcall(function()
      if not stranded(win, guard) then return false end
      win:setFrame(M.placement(win:frame(), from, to), 0)
      return true
    end)
    if ok and moved then apps[#apps + 1] = appName(win) end
  end
  lastMoved, lastApps = #apps, apps
  if #apps > 0 then
    hs.alert.show(string.format("LG: moved %d window(s) back", #apps))
    print("[lg-window-rescue] moved " .. table.concat(apps, ", "))
  end
  return #apps
end

function M.status()
  return { pending = timer ~= nil, lastMoved = lastMoved, lastApps = lastApps }
end

local arm

-- Only the current timer may run a check; stop() and re-arming clear or replace it.
local function check()
  if lgInput.status().busy then arm(); return end
  M.rescue()
end

arm = function()
  if timer then timer:stop() end
  local armed
  armed = hs.timer.doAfter(QUIET_SECONDS, function()
    if timer ~= armed then return end
    timer = nil
    check()
  end)
  timer = armed
end

function M.start()
  if not stopped then return end
  stopped = false
  watcher = hs.screen.watcher.new(function()
    if not stopped then arm() end
  end)
  watcher:start()
  arm()
end

function M.stop()
  stopped = true
  if watcher then watcher:stop(); watcher = nil end
  if timer then timer:stop(); timer = nil end
end

return M
