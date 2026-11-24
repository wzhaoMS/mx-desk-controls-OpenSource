require("hs.ipc")

-- MX Creative Keypad and Dialpad; the top two rows control the LG monitor's sources and PIP.
keypad = require("keypad")
keypad.start()

-- Moves windows stranded on the invisible "MX PBP Keepalive" screen back to the LG.
lgWindowRescue = require("lg-window-rescue")
lgWindowRescue.start()

hs.shutdownCallback = function()
  lgWindowRescue.stop()
  keypad.stop()
end
