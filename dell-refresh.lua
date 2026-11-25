-- Keeps the Alienware AW3926QW on a picture it can show over USB-C. With USB-C Prioritization
-- at HIGH DATA SPEED the link has two DisplayPort lanes (UHBR10, about 19.2 Gbps usable), and
-- every signal that needs DSC compression stays black. After 3 minutes without a picture the
-- monitor powers down and drops USB-C (charging, hub, video), so the Mac loses it entirely.
-- Two things need DSC on this link:
--   * any rate above 60 Hz; macOS restores a saved 165 Hz whenever the lid closes;
--   * 10 bits per colour at 5120x2160@60 Hz (about 21.7 Gbps). Since the macOS 27.2.1 update
--     macOS picks 10-bit with DSC on every connect; 8-bit RGB (about 16.9 Gbps) fits uncompressed.
-- So after each screen change or wake the guard caps the refresh rate with hs.screen and then
-- selects the 8-bit RGB connection mode through the BetterDisplay CLI. Raise MAX_HZ or allow 10-bit only
-- after switching the monitor to HIGH RESOLUTION (four lanes) and confirming a picture.
local M = {}

local MONITOR_NAME = "AW3926QW"
local MAX_HZ = 60
local SETTLE_SECONDS = 1.5
local EXECUTABLE = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
local TASK_TIMEOUT_SECONDS = 10
local RETRY_SECONDS = 30
M.MAX_HZ = MAX_HZ

local watcher, wakeWatcher, timer, lastFix, lastDepthFix, lastDepthAttempt
local activeTask, deadline
local schedule

local function log(message)
  print("[dell-refresh] " .. message)
end

-- One BetterDisplay process at a time; a process that hangs is killed and its reply ignored.
local function run(arguments, onExit)
  local task
  task = hs.task.new(EXECUTABLE, function(exitCode, stdout, stderr)
    if task ~= activeTask then return end
    activeTask = nil
    if deadline then deadline:stop(); deadline = nil end
    onExit(exitCode, stdout or "", stderr or "")
  end, arguments)
  if not task then return false end
  activeTask = task
  deadline = hs.timer.doAfter(TASK_TIMEOUT_SECONDS, function()
    deadline = nil
    if activeTask ~= task then return end
    activeTask = nil
    task:terminate()
    log("BetterDisplay timed out: " .. table.concat(arguments, " "))
  end)
  if not task:start() then
    if activeTask == task then activeTask = nil end
    if deadline then deadline:stop(); deadline = nil end
    return false
  end
  return true
end

local function recordDepthFix(from, to, ok, problem)
  lastDepthFix = { at = hs.timer.secondsSinceEpoch(), from = from, to = to, ok = ok, error = problem }
  log(string.format("%s %s -> %s ok=%s%s", MONITOR_NAME, from, to or "?", tostring(ok),
    problem and (" (" .. problem .. ")") or ""))
end

local function selectEightBit(current)
  local timing = current:match("^(%d+x%d+ [%d.]+Hz) ")
  run({ "get", "-name=" .. MONITOR_NAME, "-connectionModeList" }, function(_, listing)
    for line in listing:gmatch("[^\n]+") do
      local id, mode = line:match("^(%d+) %- (.+)$")
      if id and timing and mode:find(timing, 1, true) == 1 and mode:find(" 8bit SDR RGB Full ", 1, true) then
        run({ "set", "-name=" .. MONITOR_NAME, "-connectionMode=" .. id }, function(exitCode, stdout, stderr)
          recordDepthFix(current, mode, exitCode == 0,
            exitCode ~= 0 and (stdout .. stderr):gsub("%s+$", ""):sub(1, 120) or nil)
        end)
        return
      end
    end
    recordDepthFix(current, nil, false, "no 8-bit RGB mode listed")
  end)
end

-- 10-bit SDR needs DSC on two lanes; HDR is left alone because the user turned it on.
local function ensureEightBit()
  if activeTask then return end
  run({ "get", "-name=" .. MONITOR_NAME, "-connectionMode" }, function(exitCode, stdout)
    local current = (stdout:match("[^\n]+") or ""):gsub("^%d+ %- ", "")
    if exitCode ~= 0 or not current:find(" 10bit SDR ", 1, true) then return end
    local now = hs.timer.secondsSinceEpoch()
    if lastDepthAttempt and now - lastDepthAttempt < RETRY_SECONDS then return end
    lastDepthAttempt = now
    selectEightBit(current)
  end)
end

function M.check(followUp)
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:name() == MONITOR_NAME then
      local mode = screen:currentMode()
      if not mode or not mode.freq then return false end
      if mode.freq <= MAX_HZ + 0.5 then
        ensureEightBit()
        return false
      end
      local ok = screen:setMode(mode.w, mode.h, mode.scale, MAX_HZ, mode.depth) == true
      lastFix = { at = hs.timer.secondsSinceEpoch(), from = mode.freq, ok = ok }
      log(string.format("%s %dx%d@%gx %gHz -> %dHz ok=%s",
        MONITOR_NAME, mode.w, mode.h, mode.scale, mode.freq, MAX_HZ, tostring(ok)))
      -- A refresh change does not always raise a screen event; look once more when it settles.
      if ok and not followUp then schedule(true) end
      return ok
    end
  end
  return false
end

-- Screen changes arrive in bursts while macOS reconfigures; check once they settle.
schedule = function(followUp)
  if timer then timer:stop() end
  timer = hs.timer.doAfter(SETTLE_SECONDS, function()
    timer = nil
    M.check(followUp)
  end)
end

function M.start()
  if watcher then return end
  watcher = hs.screen.watcher.new(function() schedule(false) end)
  watcher:start()
  -- A wake repeats macOS's mode choice (10-bit again) without always raising a screen event.
  local power = hs.caffeinate.watcher
  wakeWatcher = power.new(function(event)
    if event == power.systemDidWake or event == power.screensDidWake or event == power.screensDidUnlock then
      schedule(false)
    end
  end)
  wakeWatcher:start()
  schedule(false)
end

function M.stop()
  if watcher then watcher:stop(); watcher = nil end
  if wakeWatcher then wakeWatcher:stop(); wakeWatcher = nil end
  if timer then timer:stop(); timer = nil end
  if deadline then deadline:stop(); deadline = nil end
  if activeTask then
    local task = activeTask
    activeTask = nil
    task:terminate()
  end
end

function M.status()
  return { running = watcher ~= nil, maxHz = MAX_HZ, busy = activeTask ~= nil,
    lastFix = lastFix, lastDepthFix = lastDepthFix }
end

return M
