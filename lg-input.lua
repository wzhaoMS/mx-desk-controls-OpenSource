local M = {}

local EXECUTABLE = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
local PIP_HELPER = os.getenv("HOME") .. "/.local/libexec/lg-pip-helper"
-- Machine-specific: replace both UUIDs with this Mac's values (README: "Find your display UUIDs").
local DISPLAY_UUID = "00000000-0000-4000-8000-0000000000A1"
local GUARD_UUID = "00000000-0000-4000-8000-0000000000B2"
local INPUTS = { mac = "0xD1", pc = "0xD0" }
M.DISPLAY_UUID = DISPLAY_UUID
M.GUARD_UUID = GUARD_UUID

local activeTask, deadline, settleTimer, watcher, chooser, chooserOperation
local transaction, lastTarget, pipEstablished, lastError
local generation = 0
local stopped = true
local phase = "idle"

local function changed()
  if M.onChange then M.onChange() end
end

local function devices()
  local display, guard
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:getUUID() == DISPLAY_UUID then display = screen end
    if screen:getUUID() == GUARD_UUID then guard = screen end
  end
  return display, guard
end

local function stopTimers()
  if deadline then deadline:stop(); deadline = nil end
  if settleTimer then settleTimer:stop(); settleTimer = nil end
end

local function hideChooser()
  local previous = chooser
  chooser, chooserOperation = nil, nil
  if previous then previous:hide() end
end

local function finish(message)
  stopTimers()
  transaction = nil
  lastError = message and message:sub(1, 240) or nil
  phase = message and "error" or "idle"
  if message then
    lastTarget = nil
    pipEstablished = nil
    hs.alert.show("LG: " .. message)
  end
  changed()
end

local function cancel(message, afterExit)
  generation = generation + 1
  local cancellationGeneration = generation
  stopTimers()
  transaction, lastTarget, pipEstablished = nil, nil, nil
  lastError = message and message:sub(1, 240) or nil
  phase = message and "error" or "idle"
  local function released()
    if afterExit and not stopped and generation == cancellationGeneration then afterExit() end
  end
  local previous = activeTask
  if previous then
    previous:setCallback(function()
      if activeTask ~= previous then return end
      activeTask = nil
      changed()
      released()
    end)
    if previous:isRunning() then previous:terminate() else activeTask = nil; released() end
  else
    released()
  end
  if message then hs.alert.show("LG: " .. message) end
  changed()
end

local function requestProcess(executable, arguments, timeout, accepted)
  local currentGeneration = generation
  local process
  process = hs.task.new(executable, function(exitCode, stdout, stderr)
    if stopped or generation ~= currentGeneration or activeTask ~= process then return end
    if deadline then deadline:stop(); deadline = nil end
    activeTask = nil
    if exitCode ~= 0 then
      finish("command failed: " .. ((stderr or "") .. (stdout or "")):sub(1, 160))
    else
      accepted(stdout or "")
    end
  end, arguments)
  if not process then finish("display helper could not start"); return end
  activeTask = process
  deadline = hs.timer.doAfter(timeout, function()
    if generation ~= currentGeneration or activeTask ~= process then return end
    cancel("command timed out; no recovery command sent. Use the monitor joystick if needed")
  end)
  if not process:start() then
    activeTask = nil
    finish("display helper could not start")
  end
end

local function request(feature, code, value, accepted)
  requestProcess(EXECUTABLE, { "set", "-UUID=" .. DISPLAY_UUID, feature, "-vcp=" .. code, "-value=" .. value }, 5, function(stdout)
    local response = stdout:match("^%s*(.-)%s*$")
    if response ~= "" and response ~= "true" then
      finish("unexpected command response; use the monitor menu if needed")
    else accepted() end
  end)
end

local function connectionSample(requireControl)
  local display, guard = devices()
  if not display or not guard then return nil end
  if requireControl then
    local connected = false
    for _, device in ipairs(hs.usb.attachedDevices()) do
      if device.vendorID == 0x043e and device.productID == 0x9a8a then connected = true; break end
    end
    if not connected then return nil end
  end
  local mode = display:currentMode()
  if not mode or not mode.w or not mode.h or mode.w <= 0 or mode.h <= 0 then return nil end
  return table.concat({ mode.w, mode.h, mode.scale or 0, mode.freq or 0, mode.depth or 0 }, ":")
end

local function settle(continuation, requireControl)
  local currentGeneration = generation
  local remaining, matches, previous = 24, 0, nil
  phase = "settling"
  changed()
  local function sample()
    if stopped or generation ~= currentGeneration then return end
    settleTimer = nil
    local current = connectionSample(requireControl)
    matches = current and (current == previous and matches + 1 or 1) or 0
    previous = current
    remaining = remaining - 1
    if matches >= 3 then
      continuation()
    elseif remaining == 0 then
      finish("display connection did not settle; no recovery command sent")
    else
      settleTimer = hs.timer.doAfter(0.5, sample)
    end
  end
  settleTimer = hs.timer.doAfter(0.5, sample)
end

local function requestOff()
  request("-ddc", "0xD7", "1", function()
    pipEstablished = false
    settle(function() finish() end)
  end)
end

local function requestPip(target)
  local function enableFromOff()
    pipEstablished = false
    settle(function()
      phase = "enabling-pip"
      changed()
      requestProcess(PIP_HELPER, { "--enable" }, 55, function(stdout)
        if not stdout:match("^%s*{") then
          finish("PIP helper returned an invalid result")
          return
        end
        local ok, reply = pcall(hs.json.decode, stdout)
        if not ok or type(reply) ~= "table" or reply.ok ~= true or reply.submittedFrames ~= 9 or reply.layoutValue ~= 0 then
          finish("PIP helper did not confirm the fixed sequence; no source restore sent")
          return
        end
        local function completePip()
          lastTarget, pipEstablished = target, true
          finish()
        end
        settle(function()
          if target == "mac" then completePip(); return end
          phase = "restoring-main"
          changed()
          request("-ddcAlt", "0xF4", INPUTS[target], function() settle(completePip) end)
        end)
      end)
    end)
  end
  phase = "checking-pip"
  changed()
  requestProcess(PIP_HELPER, { "--probe-hid" }, 5, function(stdout)
    if not stdout:match("^%s*{") then
      finish("PIP preflight returned an invalid result; no layout command sent")
      return
    end
    local ok, reply = pcall(hs.json.decode, stdout)
    local function integerInRange(value, maximum)
      return type(value) == "number" and value >= 0 and value <= maximum and value % 1 == 0
    end
    if not ok or type(reply) ~= "table" or reply.ok ~= true or reply.transport ~= "hid"
        or reply.submittedFrames ~= 0 or reply.firmwareValue ~= 774
        or not integerInRange(reply.brightness, 100) or not integerInRange(reply.layoutValue, 255) then
      finish("PIP preflight did not validate the monitor state; no layout command sent")
      return
    end
    if reply.layoutValue == 1 then enableFromOff(); return end
    phase = "preparing-pip"
    changed()
    request("-ddc", "0xD7", "1", enableFromOff)
  end)
end

local function begin(target, operation)
  if not stopped and transaction and transaction.operation == "pip-on" and target == "mac"
      and (operation == "select" or operation == "solo") then
    cancel(nil, function() begin(target, operation) end)
    return true
  end
  if stopped or transaction or activeTask then return false end
  if operation ~= "pip-off" and not INPUTS[target] then return false end
  local display, guard = devices()
  if not guard then finish("connect MX PBP Keepalive before switching"); return false end
  if not display then finish("LG is disconnected; use the monitor joystick to select USB-C"); return false end
  if operation == "pip-on" and hs.fs.attributes(PIP_HELPER, "mode") ~= "file" then
    finish("build lg-pip-helper before enabling PIP")
    return false
  end
  hideChooser()
  generation = generation + 1
  transaction = { target = target, operation = operation }
  lastError = nil
  phase = "sending"
  changed()
  if operation == "pip-off" then requestOff(); return true end
  request("-ddcAlt", "0xF4", operation == "pip-on" and INPUTS.mac or INPUTS[target], function()
    if operation ~= "pip-on" then lastTarget, pipEstablished = target, nil end
    settle(function()
      if operation == "pip-on" then requestPip(target); return end
      if operation ~= "solo" then finish(); return end
      phase = "sending"
      changed()
      requestOff()
    end, operation == "pip-on")
  end)
  return true
end

function M.select(target)
  return begin(target, "select")
end

function M.solo(target)
  return begin(target, "solo")
end

function M.pipOff()
  return begin(nil, "pip-off")
end

local function chooseMain(operation)
  if chooser and chooserOperation == operation then chooser:show(); return true end
  hideChooser()
  local currentGeneration = generation
  local selection
  selection = hs.chooser.new(function(choice)
    if stopped or generation ~= currentGeneration or chooser ~= selection then return end
    hideChooser()
    if choice then begin(choice.target, operation) end
  end)
  chooser = selection
  chooserOperation = operation
  selection:choices({
    { text = "Mac", subText = "USB-C", target = "mac" },
    { text = "PC", subText = "DisplayPort", target = "pc" },
  })
  selection:placeholderText("Main picture")
  selection:rows(2)
  selection:show()
  return true
end

function M.swap()
  if stopped or transaction or activeTask then return false end
  if lastTarget then return M.select(lastTarget == "mac" and "pc" or "mac") end
  return chooseMain("select")
end

function M.pipOn()
  if stopped or transaction or activeTask then return false end
  if lastTarget and pipEstablished then return true end
  if not lastTarget then return chooseMain("pip-on") end
  return begin(lastTarget, "pip-on")
end

function M.status()
  return { phase = phase, busy = transaction ~= nil or activeTask ~= nil,
    lastTarget = lastTarget, pipEstablished = pipEstablished == true, lastError = lastError }
end

function M.subtitle(target)
  if phase == "error" then return "RETRY" end
  if transaction or activeTask then return "WAIT" end
  if (target == "swap" or target == "pip") and not lastTarget then return "CHOOSE" end
  return ""
end

function M.start()
  if not stopped then return end
  stopped = false
  watcher = hs.screen.watcher.new(function()
    if stopped or transaction or activeTask then return end
    local display, guard = devices()
    if not display or not guard then
      generation = generation + 1
      lastTarget = nil
      pipEstablished = nil
      hideChooser()
      changed()
    end
  end)
  watcher:start()
  changed()
end

function M.stop()
  stopped = true
  hideChooser()
  if watcher then watcher:stop(); watcher = nil end
  cancel()
end

return M