local ROOT = debug.getinfo(1, "S").source:match("^@(.+)/tests/[^/]+$") or (os.getenv("HOME") .. "/.hammerspoon")
local modulePath = ROOT .. "/mouse-buttons.lua"
local posted, strokes, timers, taps = {}, {}, {}, {}
local types = { otherMouseDown = 25, otherMouseUp = 26 }
local stub = {
  eventtap = {
    event = {
      types = types,
      properties = { mouseEventButtonNumber = "button" },
      newKeyEvent = function(mods, key, down)
        return { post = function() posted[#posted + 1] = { mods = mods, key = key, down = down } end }
      end,
    },
    keyStroke = function(mods, key, delay) strokes[#strokes + 1] = { mods = mods, key = key, delay = delay } end,
    new = function(eventTypes, callback)
      local tap = { types = eventTypes, callback = callback, enabled = false }
      function tap:start() self.enabled = true; return self end
      function tap:stop() self.enabled = false; return self end
      function tap:isEnabled() return self.enabled end
      taps[#taps + 1] = tap
      return tap
    end,
  },
  timer = { doAfter = function(seconds, callback)
    local timer = { seconds = seconds, callback = callback }
    function timer:stop() self.stopped = true end
    timers[#timers + 1] = timer
    return timer
  end },
}
local environment = setmetatable({ hs = stub }, { __index = _G })
local buttons = assert(loadfile(modulePath, "t", environment))()
assert(#taps == 0, "loading must not install an event tap")
buttons.start()
local tap = assert(taps[1])
assert(tap.enabled and #tap.types == 2 and tap.types[1] == types.otherMouseDown and tap.types[2] == types.otherMouseUp)
buttons.start()
assert(#taps == 1, "starting twice must not add a second tap")

local function press(button, kind)
  return tap.callback({
    getProperty = function(_, property) assert(property == "button"); return button end,
    getType = function() return types[kind] end,
  })
end

-- Back held = Handy push-to-talk.
assert(press(3, "otherMouseDown") == true, "back press is consumed")
assert(#posted == 1 and posted[1].key == "d" and posted[1].down == true)
assert(table.concat(posted[1].mods, "+") == "ctrl+alt+cmd")
assert(buttons.status().talking)
assert(press(3, "otherMouseDown") == true and #posted == 1, "a repeated back press does not restart the chord")
assert(press(3, "otherMouseUp") == true)
assert(#posted == 2 and posted[2].key == "d" and posted[2].down == false, "release ends the chord")
assert(timers[1].seconds == 120 and timers[1].stopped, "release clears the safety timer")
assert(press(3, "otherMouseUp") == true and #posted == 2, "a stray release sends nothing")

-- Forward = Return once per press.
assert(press(4, "otherMouseDown") == true)
assert(#strokes == 1 and strokes[1].key == "return" and #strokes[1].mods == 0)
assert(press(4, "otherMouseUp") == true and #strokes == 1, "forward release is consumed without a second Return")

-- Middle = region screenshot to the clipboard.
assert(press(2, "otherMouseDown") == true)
assert(#strokes == 2 and strokes[2].key == "4" and table.concat(strokes[2].mods, "+") == "ctrl+cmd+shift")
assert(press(2, "otherMouseUp") == true and #strokes == 2)

-- Other buttons pass through untouched.
assert(press(5, "otherMouseDown") == false and press(5, "otherMouseUp") == false)
assert(#posted == 2 and #strokes == 2)

-- The safety timer releases a lost chord exactly once.
press(3, "otherMouseDown")
assert(#posted == 3 and posted[3].down == true)
timers[#timers].callback()
assert(#posted == 4 and posted[4].down == false and not buttons.status().talking)
press(3, "otherMouseUp")
assert(#posted == 4, "a release after the safety stop sends nothing")

-- Stop releases a held chord and removes the tap.
press(3, "otherMouseDown")
buttons.stop()
assert(#posted == 6 and posted[6].down == false, "stop must not leave the chord held")
assert(not tap.enabled and buttons.status().running == false)

return "PASS: back holds the talk chord with a safety release, forward sends Return, middle copies a region screenshot, other buttons pass through, and stop cleans up"
