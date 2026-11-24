local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/[^/]+$") or (os.getenv("HOME") .. "/.hammerspoon")
local launches, keys, processes, canvases, alerts, timers = {}, {}, {}, {}, {}, {}
local muted, missingImages = false, false
local now = 100
local input = { requests = {}, starts = 0, stops = 0, busy = false }
function input.select(target)
  if input.busy then return false end
  input.requests[#input.requests + 1] = target
  return true
end
function input.swap()
  if input.busy then return false end
  input.requests[#input.requests + 1] = "swap"
  return true
end
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
  usb = { attachedDevices = function() return { { vendorID = 1133, productID = 50004 } } end },
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
local environment = setmetatable({ hs = stub, print = function() end, require = function(name)
  assert(name == "dell-input", "the keypad must load only the Dell input controller, got " .. tostring(name))
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
local function hasText(canvas, text)
  for _, element in ipairs(canvas) do if element.type == "text" and element.text == text then return true end end
  return false
end

-- Top row: MAC, SWAP, PC act once per press on key-down; there is no hold action.
send("key 1")
assert(input.requests[1] == "mac", "MAC requests USB-C on key-down")
now = now + 1.3
send("key up")
assert(#input.requests == 1, "holding MAC must not send a second command")
for _, item in ipairs(timers) do assert(item.seconds ~= 1.2, "display keys arm no hold timer") end
tap(2)
assert(input.requests[2] == "swap", "top-middle swaps the monitor input")
tap(3)
assert(input.requests[3] == "pc" and #processes == 1 and #launches == 0, "top-right selects the PC, not Chrome or GLKVM")
send("key 1")
send("key 1")
send("key up")
assert(#input.requests == 4, "a repeated key-down without release must not double-fire")
local actions = keypadModule.recentActions()
assert(#actions == 4 and actions[1].label == "MAC" and actions[2].label == "SWAP" and actions[3].label == "PC")
assert(actions[1].gesture == "short" and actions[1].submitted)

-- Middle left is Show Desktop again and is not display-input history.
tap(4)
assert(keys[#keys].key == "f11" and keys[#keys].modifiers[1] == "fn", "middle-left shows the desktop")
assert(#keypadModule.recentActions() == 4 and #input.requests == 4, "only the input keys are recorded")

-- The center key opens Chrome again; there is no PC power key.
tap(5)
assert(launches[#launches] == "com.google.Chrome" and #alerts == 0, "center opens or focuses Chrome")
assert(#input.requests == 4 and #processes == 1, "center sends no display command")

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

for _, spec in ipairs({
  { 0, "MAC", "mac" }, { 1, "SWAP", "swap" }, { 2, "PC", "pc" },
}) do
  keypadModule.repaint(spec[1])
  local canvas = canvases[#canvases]
  assert(hasText(canvas, spec[2]), "keep a stable readable action label")
  local imageFound = false
  for _, element in ipairs(canvas) do
    if element.type == "image" and element.image.path then
      imageFound = element.image.path:find("keypad-icons/desk-" .. spec[3] .. ".png", 1, true) ~= nil
    end
    if element.type == "text" then
      assert(element.frame.y >= 0 and element.frame.y + element.frame.h <= 118, "text must fit the LCD")
    end
  end
  assert(imageFound, "use the locally generated native icon")
end
keypadModule.repaint(4)
for _, element in ipairs(canvases[#canvases]) do
  if element.type == "image" then assert(element.image.bundle == "com.google.Chrome", "center uses the Chrome icon") end
  assert(element.type ~= "text" or element.text ~= "PC POWER", "no PC POWER label remains")
end
keypadModule.repaint(3)
assert(hasText(canvases[#canvases], "Desktop"))
for _, element in ipairs(canvases[#canvases]) do
  if element.type == "image" then assert(element.image.bundle == "com.apple.finder", "Desktop uses the Finder icon") end
end

assert(type(input.onChange) == "function")
local painted = #canvases
input.busy = true
input.onChange()
assert(#canvases == painted + 3, "input changes repaint MAC, SWAP and PC only")
for index = painted + 1, painted + 3 do assert(hasText(canvases[index], "WAIT")) end
tap(1)
actions = keypadModule.recentActions()
assert(not actions[#actions].submitted and #input.requests == 4, "rejected busy requests must not look accepted in diagnostics")
input.busy = false
missingImages = true
keypadModule.repaint(0)
assert(hasText(canvases[#canvases], "MAC"), "missing icon must degrade to a labeled key")
missingImages = false

for attempt = 1, 40 do tap(2) end
actions = keypadModule.recentActions()
assert(#actions == 32, "retain only a bounded recent display-key history")
actions[1].label = "changed by caller"
assert(keypadModule.recentActions()[1].label == "SWAP", "return snapshots rather than mutable stored records")

local count = #input.requests
helper.stream(nil, "", "keypad removed\n")
send("key 1")
assert(#input.requests == count, "presses after a removal notice are ignored until release")
send("key up")
tap(1)
assert(#input.requests == count + 1, "the next full press works again")

keypadModule.stop()
assert(input.stops == 1 and input.onChange == nil, "stop must detach and clean up the controller")
assert(not helper.running)
send("key 1")
assert(#input.requests == count + 1, "stopped helper callbacks must not trigger actions")

return "PASS: Dell input keys, Show Desktop, Chrome, native icons, preserved controls, history, and shutdown"
