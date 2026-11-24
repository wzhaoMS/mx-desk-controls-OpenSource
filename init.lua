require("hs.ipc")

-- MX Creative Keypad and Dialpad; the keypad's top row switches the monitor input.
keypad = require("keypad")
keypad.start()

-- Mouse back = hold to talk, forward = Return, middle = region screenshot to the clipboard.
mouseButtons = require("mouse-buttons")
mouseButtons.start()

-- The AW3926QW is black above 60 Hz on its 2-lane USB-C link; macOS restores higher rates on lid close.
dellRefresh = require("dell-refresh")
dellRefresh.start()

hs.shutdownCallback = function()
  dellRefresh.stop()
  mouseButtons.stop()
  keypad.stop()
end
