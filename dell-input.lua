-- Alienware AW3926QW input switching for the MX Creative Keypad.
-- Standard DDC/CI input select (VCP 0x60) through the BetterDisplay CLI.
local M = {}

local EXECUTABLE = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
local MONITOR_NAME = "AW3926QW"
-- Dell VCP 0x60 values: 0x0F DisplayPort, 0x11 HDMI 1, 0x12 HDMI 2, 0x1B USB-C.
local INPUTS = { mac = 0x1B, pc = 0x0F }
local TIMEOUT_SECONDS = 5
M.MONITOR_NAME = MONITOR_NAME
M.INPUTS = INPUTS

local activeTask, deadline
local generation = 0
local stopped = true
local phase = "idle"
local lastTarget, lastError

local function changed()
  if M.onChange then M.onChange() end
end

-- macOS gives the monitor a different UUID per cable or port, so look it up on every press.
local function monitorUUID()
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:name() == MONITOR_NAME then return screen:getUUID() end
  end
end

local function finish(message)
  if deadline then deadline:stop(); deadline = nil end
  lastError = message and message:sub(1, 240) or nil
  phase = message and "error" or "idle"
  if message then hs.alert.show("Dell: " .. message) end
  changed()
end

-- One BetterDisplay process at a time; the lock is held until that process exits.
local function run(arguments, accepted, rejected)
  local currentGeneration = generation
  local process
  process = hs.task.new(EXECUTABLE, function(exitCode, stdout, stderr)
    if stopped or generation ~= currentGeneration or activeTask ~= process then return end
    if deadline then deadline:stop(); deadline = nil end
    activeTask = nil
    if exitCode == 0 then
      accepted((stdout or ""):match("^%s*(.-)%s*$"))
    else
      rejected(((stderr or "") .. (stdout or "")):match("^%s*(.-)%s*$"))
    end
  end, arguments)
  if not process then finish("BetterDisplay could not start"); return false end
  activeTask = process
  deadline = hs.timer.doAfter(TIMEOUT_SECONDS, function()
    if stopped or activeTask ~= process then return end
    deadline = nil
    generation = generation + 1
    process:setCallback(function()
      if activeTask == process then activeTask = nil; changed() end
    end)
    finish("BetterDisplay timed out; nothing was retried")
    if process:isRunning() then process:terminate() else activeTask = nil; changed() end
  end)
  if not process:start() then
    activeTask = nil
    finish("BetterDisplay could not start")
    return false
  end
  changed()
  return true
end

local function write(target, uuid)
  phase = "sending"
  return run({ "set", "-UUID=" .. uuid, "-ddc", "-vcp=0x60", string.format("-value=0x%02X", INPUTS[target]) },
    function(response)
      if response ~= "" and response ~= "true" then
        finish("unexpected BetterDisplay reply; use the monitor's input button if needed")
        return
      end
      lastTarget = target
      finish()
    end,
    function(output) finish("input command failed: " .. output:sub(1, 160)) end)
end

local function prepare()
  if stopped or activeTask then return nil end
  local uuid = monitorUUID()
  generation = generation + 1
  if not uuid then
    finish(MONITOR_NAME .. " is not connected to this Mac; use the monitor's input button")
    return nil
  end
  lastError = nil
  return uuid
end

function M.select(target)
  if not INPUTS[target] then return false end
  local uuid = prepare()
  if not uuid then return false end
  return write(target, uuid)
end

function M.swap()
  local uuid = prepare()
  if not uuid then return false end
  phase = "reading"
  -- If the input cannot be read, select the Mac: a no-op when the Mac is already showing.
  local function toMac() write("mac", uuid) end
  return run({ "get", "-UUID=" .. uuid, "-ddc", "-vcp=0x60" }, function(response)
    local value = tonumber(response)
    if not value then toMac(); return end
    -- The monitor reports USB-C as 0x1B1B; the low byte is the input.
    write(value % 256 == INPUTS.mac and "pc" or "mac", uuid)
  end, toMac)
end

function M.status()
  return { phase = phase, busy = activeTask ~= nil, lastTarget = lastTarget, lastError = lastError,
    connected = monitorUUID() ~= nil }
end

function M.subtitle()
  if activeTask then return "WAIT" end
  if phase == "error" then return "RETRY" end
  return ""
end

function M.start()
  if not stopped then return end
  stopped = false
  phase, lastError = "idle", nil
  changed()
end

function M.stop()
  stopped = true
  generation = generation + 1
  if deadline then deadline:stop(); deadline = nil end
  local previous = activeTask
  activeTask = nil
  if previous and previous:isRunning() then previous:terminate() end
end

return M
