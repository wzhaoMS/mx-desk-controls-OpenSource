local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/[^/]+$") or (os.getenv("HOME") .. "/.hammerspoon")
local launches, keys, processes, canvases, alerts, timers = {}, {}, {}, {}, {}, {}
local muted, attached, missingImages = false, true, false
local now = 100
local input = { requests = {}, swaps = 0, starts = 0, stops = 0, busy = false }
function input.select(target)
  if input.busy then return false end
  input.requests[#input.requests + 1] = { kind = "select", target = target }
  return true
end
function input.solo(target)
  if input.busy then return false end
  input.requests[#input.requests + 1] = { kind = "solo", target = target }
  return true
end
function input.pipOn()
  if input.busy then return false end
  input.requests[#input.requests + 1] = { kind = "pip", target = "on" }
  return true
end
function input.pipOff()
  if input.busy then return false end
  input.requests[#input.requests + 1] = { kind = "pip", target = "off" }
  return true
end
function input.swap() input.swaps = input.swaps + 1; return true end
function input.subtitle() return input.busy and "WAIT" or "" end
function input.start() input.starts = input.starts + 1 end
function input.stop() input.stops = input.stops + 1 end

local function timer(seconds, callback)
  local item = { seconds = seconds, callback = callback, stop = function(self) self.stopped = true end }
  timers[#timers + 1] = item
  return item
end

local microphone = {
  transportType = function() return "USB" end,
  inputMuted = function() return muted end,
  setInputMuted = function(_, value) muted = value; return true end,
}
local stub = {
  alert = { show = function(message) alerts[#alerts + 1] = message end },
  application = { launchOrFocusByBundleID = function(bundle) launches[#launches + 1] = bundle end },
  audiodevice = { allInputDevices = function() return { microphone } end },
  fs = { mkdir = function() return true end },
  execute = function() return "0\n", true, "exit", 0 end,
  timer = {
    doAfter = timer, doEvery = timer,
    secondsSinceEpoch = function() return now end,
    absoluteTime = function() return now * 1000000000 end,
  },
  usb = { attachedDevices = function()
    return attached and { { vendorID = 1133, productID = 50004 } } or {}
  end },
  task = { new = function(path, callback, third, arguments)
    local process = { path = path, callback = callback }
    if type(third) == "function" then process.stream = third; process.arguments = arguments
    else process.arguments = third end
    function process:start() self.running = true; return self end
    function process:isRunning() return self.running end
    function process:terminate() self.running = false end
    function process:setInput(value) self.input = value end
    processes[#processes + 1] = process
    return process
  end },
  eventtap = {
    keyStroke = function(modifiers, key) keys[#keys + 1] = { modifiers = modifiers, key = key } end,
    event = {
      newKeyEvent = function(modifiers, key, down)
        return { post = function() keys[#keys + 1] = { modifiers = modifiers, key = key, down = down } end }
      end,
      newScrollEvent = function(offsets)
        return { post = function() keys[#keys + 1] = { offsets = offsets } end }
      end,
    },
  },
  image = {
    imageFromAppBundle = function(bundle) return { bundle = bundle } end,
    imageFromPath = function(path) if not missingImages then return { path = path } end end,
  },
  canvas = { new = function()
    local canvas = {}
    function canvas:imageFromCanvas()
      return { saveToFile = function(_, path) canvas.savedPath = path; return true end }
    end
    function canvas:delete() end
    canvases[#canvases + 1] = canvas
    return canvas
  end },
}
local environment = setmetatable({ hs = stub, require = function(name)
  assert(name == "lg-input", "active keypad must not load the legacy PBP writer")
  return input
end }, { __index = _G })
local keypadModule = assert(loadfile(ROOT .. "/keypad.lua", "t", environment))()
assert(#input.requests == 0, "loading must not switch the display")
keypadModule.start()
assert(input.starts == 1 and #input.requests == 0)
local helper = assert(processes[1])
assert(helper.path == os.getenv("HOME") .. "/.local/libexec/mxcc-helper")
local function send(event) helper.stream(nil, event .. "\n", "") end
local function tap(key, duration)
  send("key " .. key)
  now = now + (duration or 0.1)
  send("key up")
end
local function latestHoldTimer()
  for index = #timers, 1, -1 do
    if timers[index].seconds == 1.2 and not timers[index].stopped then return timers[index] end
  end
  error("missing visual hold timer")
end
local function assertRequest(index, kind, target)
  local request = assert(input.requests[index])
  assert(request.kind == kind and request.target == target,
    "expected " .. kind .. " " .. target .. ", got " .. request.kind .. " " .. request.target)
end

send("key 1")
assert(#input.requests == 0, "corner short action must wait for release")
now = now + 0.1
send("key up")
assertRequest(1, "select", "mac")
tap(1, 0.9)
assertRequest(2, "select", "mac")
local actions = keypadModule.recentActions()
assert(#actions == 2 and actions[2].label == "MAC" and actions[2].gesture == "short")
assert(actions[2].heldMilliseconds == 900 and actions[2].submitted, "record actual press classification and submission")
tap(2)
assert(input.swaps == 1 and #launches == 0, "top-middle swaps instead of opening TIDAL")
tap(3)
assertRequest(3, "select", "pc")
assert(#processes == 1, "top-right must not launch Chrome or GLKVM")

send("key 1")
local staleHold = latestHoldTimer()
now = now + 1.3
staleHold.callback()
assert(#input.requests == 3, "holding displays feedback without issuing a command")
local soloPreview = false
for _, element in ipairs(canvases[#canvases]) do
  if element.type == "text" and element.text == "ONLY MAC" then soloPreview = true end
end
assert(soloPreview, "long-press preview must identify the computer that remains visible")
send("key up")
assertRequest(4, "solo", "mac")
actions = keypadModule.recentActions()
assert(actions[#actions].label == "MAC" and actions[#actions].gesture == "long")
assert(actions[#actions].heldMilliseconds == 1300)
send("key up")
staleHold.callback()
assert(#input.requests == 4, "long press must not also perform short press")
tap(3, 1.3)
assertRequest(5, "solo", "pc")

send("key 1")
send("key 1")
now = now + 0.1
send("key up")
assertRequest(6, "select", "mac")
send("key 1")
send("key 3")
send("key 1")
now = now + 1.3
send("key up")
assert(#input.requests == 6, "mixed key1/key3/key1/up must remain cancelled until all keys release")
tap(1, 11)
assert(#input.requests == 6, "stale holds must be discarded")
send("key 3")
now = now + 1.3
attached = false
send("key up")
assert(#input.requests == 6, "synthetic release after USB removal must not close PIP")
attached = true
send("key 1")
helper.stream(nil, "", "keypad removed\n")
now = now + 1.3
send("key up")
assert(#input.requests == 6, "removal notification must cancel the held action")

tap(5)
tap(5)
assert(#alerts == 2 and alerts[1]:find("not configured", 1, true), "central power is explicitly unconfigured")
assert(#input.requests == 6 and #processes == 1 and #launches == 0, "power placeholder must not send power, source, or launch commands")
for _, binding in ipairs({
  { 7, "com.microsoft.teams2" }, { 8, "com.microsoft.VSCode" }, { 9, "com.apple.Terminal" },
}) do
  tap(binding[1])
  assert(launches[#launches] == binding[2], "preserve the other application keys")
end
tap(6)
assert(muted, "preserve microphone mute")
send("dialkey 1")
assert(launches[#launches] == "com.microsoft.VSCode", "preserve the dialpad's top-left action")
send("dialkey 2")
assert(launches[#launches] == "com.apple.Terminal")
send("dialkey 3")
assert(keys[#keys].key == "return")
send("dialkey 4")
assert(keys[#keys].key == "d" and keys[#keys].down)
send("dialkey 4 up")
assert(keys[#keys].down == false)
send("dial 1 3")
assert(keys[#keys].offsets[2] == -3)
send("dial 0 2")
assert(keys[#keys].offsets[1] == 2)
send("nav left")
assert(keys[#keys].key == "[")
send("nav right")
assert(keys[#keys].key == "]")

local launchCount = #launches
send("key 7")
send("key 8")
send("key up")
assert(#launches == launchCount + 2, "ordinary application-key overlap must preserve both actions")
assert(launches[#launches] == "com.microsoft.VSCode")

local function hasText(canvas, text)
  for _, element in ipairs(canvas) do if element.type == "text" and element.text == text then return true end end
  return false
end
for _, spec in ipairs({
  { 0, "MAC", "mac" }, { 1, "SWAP", "swap" }, { 2, "PC", "pc" },
  { 3, "PIP", "pip" }, { 4, "PC POWER", "power" },
}) do
  keypadModule.repaint(spec[1])
  local canvas = canvases[#canvases]
  assert(hasText(canvas, spec[2]), "keep a stable readable action label")
  local imageFound = false
  for _, element in ipairs(canvas) do
    if element.type == "image" and element.image.path then
      imageFound = element.image.path:find("keypad-icons/lg-" .. spec[3] .. ".png", 1, true) ~= nil
    end
    if element.type == "text" then
      assert(element.frame.y >= 0 and element.frame.y + element.frame.h <= 118, "text must fit the LCD")
    end
  end
  assert(imageFound, "use the locally generated native icon")
end
assert(hasText(canvases[#canvases], "\u{5F85}\u{914D}\u{7F6E}"), "power key must visibly say unconfigured")
assert(type(input.onChange) == "function")
input.busy = true
input.onChange()
for index = #canvases - 3, #canvases do assert(hasText(canvases[index], "WAIT")) end
input.busy = false
missingImages = true
keypadModule.repaint(0)
assert(hasText(canvases[#canvases], "MAC"), "missing icon must degrade to a labeled key")
missingImages = false
input.busy = true
tap(1)
actions = keypadModule.recentActions()
assert(not actions[#actions].submitted and #input.requests == 6, "rejected busy requests must not look accepted in diagnostics")
input.busy = false

local pipBase = #input.requests
tap(4)
assertRequest(pipBase + 1, "pip", "on")
send("key 4")
local pipHold = latestHoldTimer()
now = now + 1.3
pipHold.callback()
assert(#input.requests == pipBase + 1, "holding PIP must preview before issuing a command")
assert(hasText(canvases[#canvases], "PIP OFF"), "PIP hold preview must name the off action explicitly")
send("key up")
assertRequest(pipBase + 2, "pip", "off")
actions = keypadModule.recentActions()
assert(actions[#actions].label == "PIP" and actions[#actions].gesture == "long" and actions[#actions].submitted,
  "PIP belongs in the bounded display-action history")
send("key 4")
send("key 4")
now = now + 0.1
send("key up")
assertRequest(pipBase + 3, "pip", "on")
assert(#input.requests == pipBase + 3, "repeated PIP key-down must not double-fire")
send("key 1")
send("key 4")
send("key 1")
now = now + 1.3
send("key up")
assert(#input.requests == pipBase + 3, "PIP overlapping a source key must stay cancelled until all keys release")
tap(4, 11)
assert(#input.requests == pipBase + 3, "stale PIP holds must be discarded")
send("key 4")
now = now + 1.3
attached = false
send("key up")
assert(#input.requests == pipBase + 3, "synthetic release after USB removal must not toggle PIP")
attached = true
send("key 4")
helper.stream(nil, "", "keypad removed\n")
now = now + 1.3
send("key up")
assert(#input.requests == pipBase + 3, "removal notification must cancel the held PIP action")
input.busy = true
tap(4)
actions = keypadModule.recentActions()
assert(not actions[#actions].submitted and #input.requests == pipBase + 3,
  "rejected busy PIP requests must not look accepted in diagnostics")
input.busy = false

for attempt = 1, 40 do tap(2) end
actions = keypadModule.recentActions()
assert(#actions == 32, "retain only a bounded recent display-key history")
actions[1].label = "changed by caller"
assert(keypadModule.recentActions()[1].label == "SWAP", "return snapshots rather than mutable stored records")
send("key 1")
staleHold = latestHoldTimer()
keypadModule.stop()
assert(input.stops == 1 and input.onChange == nil, "stop must detach and clean up the controller")
assert(not helper.running)
staleHold.callback()
send("key up")
send("key 1")
assert(#input.requests == pipBase + 3 and #alerts == 2, "stopped helper callbacks and stale holds must not trigger actions")

return "PASS: source keys, exclusive solo holds, PIP toggle, native icons, unconfigured power, preserved controls, and shutdown"