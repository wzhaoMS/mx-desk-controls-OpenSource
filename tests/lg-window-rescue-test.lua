local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/[^/]+$") or (os.getenv("HOME") .. "/.hammerspoon")
local modulePath = ROOT .. "/lg-window-rescue.lua"
local LG = "00000000-0000-4000-8000-00000000000A"
local KEEPALIVE = "00000000-0000-4000-8000-00000000000B"

local function screen(uuid, full, usable)
  return {
    getUUID = function() return uuid end,
    fullFrame = function() return full end,
    frame = function() return usable end,
  }
end

local lgScreen = screen(LG, { x = 0, y = 0, w = 3840, h = 1620 }, { x = 0, y = 30, w = 3840, h = 1590 })
local keepScreen = screen(KEEPALIVE, { x = -2560, y = 0, w = 2560, h = 1440 },
  { x = -2560, y = 30, w = 2560, h = 1410 })

-- Like hs.screen.find, report the keepalive for any window centred left of the LG,
-- even one that overlaps no screen at all.
local function window(app, frame, options)
  options = options or {}
  local win = { app = app, current = frame, moves = {} }
  function win:isStandard() return options.standard ~= false end
  function win:isVisible() return options.visible ~= false end
  function win:isFullScreen() return options.fullScreen == true end
  function win:screen() return self.current.x + self.current.w / 2 < 0 and keepScreen or lgScreen end
  function win:frame() return self.current end
  function win:setFrame(target, duration)
    if options.setFails then error("AX setFrame failed") end
    self.moves[#self.moves + 1] = { frame = target, duration = duration }
    self.current = target
    return self
  end
  function win:application() return { name = function() return app end } end
  return win
end

local function teamsWindow()
  return window("Microsoft Teams", { x = -2058, y = 30, w = 3840, h = 1410 })
end

local function fixture(windows)
  local state = { busy = false, screens = { lgScreen, keepScreen }, windows = windows or {} }
  local timers, alerts, watchers = {}, {}, {}
  local lgInput = {
    DISPLAY_UUID = LG,
    GUARD_UUID = KEEPALIVE,
    status = function() return { busy = state.busy } end,
  }
  local stub = {
    screen = {
      allScreens = function() return state.screens end,
      watcher = { new = function(callback)
        local watcher = { callback = callback }
        function watcher:start() self.running = true; return self end
        function watcher:stop() self.running = false end
        watchers[#watchers + 1] = watcher
        return watcher
      end },
    },
    window = { allWindows = function() return state.windows end },
    timer = { doAfter = function(seconds, callback)
      local timer = { seconds = seconds, callback = callback }
      function timer:stop() self.stopped = true end
      timers[#timers + 1] = timer
      return timer
    end },
    alert = { show = function(message) alerts[#alerts + 1] = message end },
  }
  local environment = setmetatable({
    hs = stub,
    print = function() end,
    require = function(name)
      assert(name == "lg-input", "unexpected require: " .. tostring(name))
      return lgInput
    end,
  }, { __index = _G })
  local rescue = assert(loadfile(modulePath, "t", environment))()
  return rescue, state, timers, alerts, watchers
end

local function fire(timer)
  assert(not timer.stopped and not timer.fired, "timer is not live")
  timer.fired = true
  timer.callback()
end

local function live(timers)
  local result = {}
  for _, timer in ipairs(timers) do
    if not timer.stopped and not timer.fired then result[#result + 1] = timer end
  end
  return result
end

local function sameRect(actual, expected)
  return actual.x == expected.x and actual.y == expected.y and actual.w == expected.w and actual.h == expected.h
end

do
  local rescue = fixture()
  local from, to = keepScreen:frame(), lgScreen:frame()
  assert(sameRect(rescue.placement({ x = -2058, y = 30, w = 3840, h = 1410 }, from, to),
    { x = 0, y = 30, w = 3840, h = 1410 }), "Teams lands at the LG's top-left usable corner")
  assert(sameRect(rescue.placement({ x = -3220, y = 251, w = 1280, h = 690 }, from, to),
    { x = 0, y = 251, w = 1280, h = 690 }), "TIDAL is clamped onto the LG and keeps its height offset")
  assert(sameRect(rescue.placement({ x = -2560, y = 30, w = 4000, h = 1700 }, from, to),
    { x = 0, y = 30, w = 3840, h = 1590 }), "an oversize window shrinks to the LG's usable area")
  assert(sameRect(rescue.placement({ x = -2000, y = 400, w = 800, h = 600 }, from, to),
    { x = 560, y = 400, w = 800, h = 600 }), "a window that fits keeps its offset")
  assert(rescue.overlapArea({ x = -3220, y = 251, w = 1280, h = 690 }, keepScreen:fullFrame()) == 620 * 690,
    "partial overlap is measured")
  assert(rescue.overlapArea({ x = -6000, y = 100, w = 800, h = 600 }, keepScreen:fullFrame()) == 0,
    "disjoint rects do not overlap")
  assert(rescue.overlapArea({ x = -2560, y = 0, w = 100, h = 100 }, { x = -2460, y = 0, w = 100, h = 100 }) == 0,
    "touching edges do not overlap")
end

do
  local teams = teamsWindow()
  local onLG = window("Code", { x = -200, y = 100, w = 800, h = 600 })
  local minimized = window("Mail", { x = -2000, y = 100, w = 800, h = 600 }, { visible = false })
  local panel = window("Panel", { x = -2000, y = 100, w = 800, h = 600 }, { standard = false })
  local full = window("Movie", { x = -2560, y = 0, w = 2560, h = 1440 }, { fullScreen = true })
  local parked = window("Parked", { x = -6000, y = 100, w = 800, h = 600 })
  local rescue, state, timers, alerts = fixture({ teams, onLG, minimized, panel, full, parked })
  state.busy = true
  assert(rescue.rescue() == 1, "manual rescue ignores busy and needs no start")
  assert(#timers == 0, "manual rescue arms nothing")
  assert(#teams.moves == 1 and teams.moves[1].duration == 0, "the stranded window moves once without animation")
  assert(sameRect(teams.moves[1].frame, { x = 0, y = 30, w = 3840, h = 1410 }), "Teams lands on the LG")
  for _, other in ipairs({ onLG, minimized, panel, full, parked }) do
    assert(#other.moves == 0, other.app .. " must not move")
  end
  assert(#alerts == 1 and alerts[1] == "LG: moved 1 window(s) back", "one alert names the count")
  local status = rescue.status()
  assert(status.pending == false and status.lastMoved == 1, "status records the run")
  assert(#status.lastApps == 1 and status.lastApps[1] == "Microsoft Teams", "status names the moved app")
end

do
  local broken = window("Hung", { x = -2400, y = 100, w = 800, h = 600 }, { setFails = true })
  local teams = teamsWindow()
  local rescue, _, _, alerts = fixture({ broken, teams })
  assert(rescue.rescue() == 1, "only successful moves count")
  assert(#teams.moves == 1 and alerts[1] == "LG: moved 1 window(s) back", "a failing window does not stop the rest")
  assert(rescue.status().lastApps[1] == "Microsoft Teams", "the failed window is not listed")
end

do
  local odd = window("Odd", { x = -2400, y = 100, w = 800, h = 600 })
  function odd:application() return nil end
  local rescue = fixture({ odd })
  assert(rescue.rescue() == 1 and rescue.status().lastApps[1] == "?", "unknown app names are listed as ?")
end

do
  local onLG = window("Code", { x = 100, y = 100, w = 800, h = 600 })
  local rescue, _, _, alerts = fixture({ onLG })
  assert(rescue.rescue() == 0 and #alerts == 0, "nothing stranded means no alert")
  local status = rescue.status()
  assert(status.lastMoved == 0 and type(status.lastApps) == "table" and #status.lastApps == 0,
    "a completed empty run is recorded")
end

do
  local teams = teamsWindow()
  local rescue, state, _, alerts = fixture({ teams })
  local initial = rescue.status()
  assert(initial.pending == false and initial.lastMoved == nil and initial.lastApps == nil, "status starts empty")
  assert(rescue.rescue() == 1, "first run moves Teams")
  local tidal = window("TIDAL", { x = -3220, y = 251, w = 1280, h = 690 })
  state.windows = { tidal }
  for _, remaining in ipairs({ { keepScreen }, { lgScreen } }) do
    state.screens = remaining
    assert(rescue.rescue() == 0 and #tidal.moves == 0, "a rescue needs both screens")
  end
  assert(#alerts == 1, "a skipped run shows no alert")
  local status = rescue.status()
  assert(status.lastMoved == 1 and status.lastApps[1] == "Microsoft Teams", "a skipped run keeps the previous status")
end

do
  local teams = teamsWindow()
  local rescue, _, timers, alerts, watchers = fixture({ teams })
  assert(#timers == 0 and #alerts == 0 and #watchers == 0 and #teams.moves == 0,
    "loading must not watch, arm, alert, or move")
  rescue.start()
  rescue.start()
  assert(#watchers == 1 and watchers[1].running, "start creates one running watcher")
  assert(#timers == 1 and timers[1].seconds == 3, "start arms one 3 s check")
  assert(rescue.status().pending == true, "the first check is pending")
  fire(timers[1])
  assert(#teams.moves == 1 and #alerts == 1, "the start-up check rescues stranded windows")
  assert(rescue.status().pending == false and #live(timers) == 0, "a fired check is no longer pending")
end

do
  local rescue, _, timers, _, watchers = fixture()
  rescue.start()
  watchers[1].callback()
  assert(timers[1].stopped and #timers == 2 and #live(timers) == 1, "a screen change restarts the quiet period")
  watchers[1].callback()
  assert(timers[2].stopped and #timers == 3 and #live(timers) == 1, "only one check is ever pending")
end

do
  local teams = teamsWindow()
  local rescue, _, timers, _, watchers = fixture({ teams })
  rescue.start()
  watchers[1].callback()
  timers[1].callback()
  assert(#teams.moves == 0 and rescue.status().pending == true, "a superseded check does nothing")
end

for _, remaining in ipairs({ { keepScreen }, { lgScreen } }) do
  local teams = teamsWindow()
  local rescue, state, timers, alerts = fixture({ teams })
  state.screens = remaining
  rescue.start()
  fire(timers[1])
  assert(#teams.moves == 0 and #alerts == 0 and #live(timers) == 0, "a missing screen means no rescue and no retry")
  assert(rescue.status().lastMoved == nil, "an incomplete run leaves status unchanged")
end

do
  local teams = teamsWindow()
  local rescue, state, timers, alerts = fixture({ teams })
  state.busy = true
  rescue.start()
  fire(timers[1])
  assert(#teams.moves == 0 and #timers == 2 and #live(timers) == 1, "wait while lg-input is switching")
  assert(timers[2].seconds == 3, "the retry uses the same quiet period")
  state.busy = false
  fire(timers[2])
  assert(#teams.moves == 1 and #alerts == 1, "rescue once lg-input is idle")
end

do
  local teams = teamsWindow()
  local rescue, _, timers, _, watchers = fixture({ teams })
  rescue.start()
  rescue.stop()
  assert(not watchers[1].running and timers[1].stopped, "stop releases the watcher and the pending check")
  assert(rescue.status().pending == false, "nothing is pending after stop")
  timers[1].callback()
  watchers[1].callback()
  assert(#teams.moves == 0 and #timers == 1, "late callbacks after stop do nothing")
end

return "PASS: LG window rescue geometry, eligibility, failures, status, debounce, busy wait, and lifecycle"
