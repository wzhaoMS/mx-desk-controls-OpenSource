-- Standard mouse buttons for the ROG HARPE II on the monitor's KVM hub:
-- back = hold to talk (Handy's ⌃⌥⌘D), forward = Return (send), middle = region screenshot
-- copied to the clipboard (⌃⌘⇧4).
-- Every mouse that sends these standard buttons is affected; buttons that OpenLogi
-- diverts on the MX Master 4 never reach this tap. Do not run another remapper for these buttons.
local M = {}

local MIDDLE, BACK, FORWARD = 2, 3, 4
local TALK_MODS, TALK_KEY = { "ctrl", "alt", "cmd" }, "d"
local TALK_TIMEOUT = 120

local types = hs.eventtap.event.types
local buttonNumber = hs.eventtap.event.properties.mouseEventButtonNumber
local tap, watchdog
local talking = false

local function stopTalking()
  if watchdog then watchdog:stop(); watchdog = nil end
  if not talking then return end
  talking = false
  hs.eventtap.event.newKeyEvent(TALK_MODS, TALK_KEY, false):post()
end

local function startTalking()
  if talking then return end
  talking = true
  hs.eventtap.event.newKeyEvent(TALK_MODS, TALK_KEY, true):post()
  watchdog = hs.timer.doAfter(TALK_TIMEOUT, stopTalking)
end

local function onEvent(event)
  local button = event:getProperty(buttonNumber)
  if button ~= MIDDLE and button ~= BACK and button ~= FORWARD then return false end
  local down = event:getType() == types.otherMouseDown
  if button == BACK then
    if down then startTalking() else stopTalking() end
  elseif down and button == FORWARD then
    hs.eventtap.keyStroke({}, "return", 0)
  elseif down then
    hs.eventtap.keyStroke({ "ctrl", "cmd", "shift" }, "4", 0)
  end
  return true
end

function M.start()
  if tap then return end
  tap = hs.eventtap.new({ types.otherMouseDown, types.otherMouseUp }, onEvent)
  tap:start()
end

function M.stop()
  if tap then tap:stop(); tap = nil end
  stopTalking()
end

function M.status()
  return { running = tap ~= nil and tap:isEnabled(), talking = talking }
end

return M
