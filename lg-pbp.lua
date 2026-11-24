local M = {}

local EXECUTABLE = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
-- Machine-specific: replace both UUIDs with this Mac's values (README: "Find your display UUIDs").
local DISPLAY_UUID = "00000000-0000-4000-8000-0000000000A1"
local GUARD_UUID = "00000000-0000-4000-8000-0000000000B2"
local TIMEOUT = 5

local activeTask = nil
local deadline = nil
local retryTimer = nil
local generation = 0
local busy = false
local label = "PBP"

local function updateLabel(value)
  label = value
  if M.onChange then M.onChange() end
end

local function cancel(continuation)
  generation = generation + 1
  if deadline then deadline:stop(); deadline = nil end
  if retryTimer then retryTimer:stop(); retryTimer = nil end
  local previousTask = activeTask
  if previousTask and previousTask:isRunning() then
    local function stopped()
      if activeTask ~= previousTask then return end
      if deadline then deadline:stop(); deadline = nil end
      activeTask = nil
      if continuation then
        local nextStep = continuation
        continuation = nil
        nextStep()
      end
    end
    previousTask:setCallback(stopped)
    deadline = hs.timer.doAfter(2, function()
      if activeTask ~= previousTask then return end
      if not previousTask:isRunning() then stopped(); return end
      continuation = nil
      deadline = nil
      busy = false
      updateLabel("PBP ERR")
      hs.alert.show("PBP: previous command did not stop; use the monitor joystick to disable PBP")
    end)
    previousTask:terminate()
  else
    activeTask = nil
    if continuation then continuation() end
  end
end

local function finish(mode, message)
  busy = false
  updateLabel(mode == 5 and "PBP ON" or mode == 1 and "FULL" or "PBP ERR")
  if message then hs.alert.show("PBP: " .. message) end
end

local function request(operation, value, callback)
  generation = generation + 1
  local currentGeneration = generation
  local arguments = { operation, "-UUID=" .. DISPLAY_UUID, "-ddc", "-vcp=0xD7" }
  if value then arguments[#arguments + 1] = "-value=" .. value end
  activeTask = hs.task.new(EXECUTABLE, function(exitCode, stdout, stderr)
    if generation ~= currentGeneration then return end
    if deadline then deadline:stop(); deadline = nil end
    activeTask = nil
    local response = (stdout or ""):match("^%s*(.-)%s*$")
    if exitCode ~= 0 then
      callback(false, "BetterDisplay failed: " .. (stderr or ""):sub(1, 160), true)
    elseif operation == "set" and response ~= "" and response ~= "true" then
      callback(false, "display did not accept the PBP command")
    else
      callback(true, response)
    end
  end, arguments)
  if not activeTask then
    callback(false, "BetterDisplay could not start")
    return
  end
  deadline = hs.timer.doAfter(TIMEOUT, function()
    if generation ~= currentGeneration then return end
    cancel(function() callback(false, "display command timed out") end)
  end)
  if not activeTask:start() then
    cancel(function() callback(false, "BetterDisplay could not start") end)
  end
end

local function observedMode()
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:getUUID() == DISPLAY_UUID then
      local mode = screen:currentMode()
      if mode and mode.w and mode.h and mode.h > 0 then
        local aspect = mode.w / mode.h
        if math.abs(aspect - 5120 / 2160) < 0.015 then return 1 end
        if math.abs(aspect - 2560 / 2160) < 0.015 then return 5 end
      end
    end
  end
end

local function readMode(callback, expectedMode, remaining)
  remaining = remaining or 24
  local mode = observedMode()
  if mode and (not expectedMode or mode == expectedMode) then
    callback(mode)
  elseif remaining > 1 then
    local currentGeneration = generation
    retryTimer = hs.timer.doAfter(0.5, function()
      if generation ~= currentGeneration then return end
      retryTimer = nil
      readMode(callback, expectedMode, remaining - 1)
    end)
  else
    callback(nil, "LG display mode is unknown or still reconnecting")
  end
end

local writeMode
writeMode = function(mode, recoveryReason)
  local function failed(message)
    if mode == 5 then
      writeMode(1, message)
    else
      finish(nil, message .. "; use the monitor joystick to disable PBP")
    end
  end
  request("set", mode, function(ok, response)
    if not ok then failed(response); return end
    readMode(function(actualMode, message)
      if actualMode ~= mode then
        failed(message or "PBP readback did not match the requested mode")
        return
      end
      finish(actualMode, recoveryReason and (recoveryReason .. "; full-screen restored"))
    end, mode)
  end)
end

function M.label()
  return label
end

function M.toggle()
  if busy or activeTask then return false end
  local guardPresent = false
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:getUUID() == GUARD_UUID then guardPresent = true end
  end
  if not guardPresent then
    finish(nil, "connect MX PBP Keepalive in BetterDisplay before switching")
    return false
  end
  busy = true
  updateLabel("PBP ...")
  readMode(function(mode, message)
    if not mode then
      writeMode(1, message)
      return
    end
    writeMode(mode == 1 and 5 or 1)
  end)
  return true
end

function M.off()
  busy = true
  updateLabel("PBP ...")
  cancel(function() writeMode(1) end)
end

function M.stop()
  cancel()
  busy = false
  updateLabel("PBP")
end

return M