-- MX Creative Keypad + Dialpad。
-- helper 作为 Hammerspoon 的子进程运行：stdin 收命令、stdout 发事件，不经 socket。
-- 这样既省掉一整套 socket 权限问题，也让 helper 崩溃后能被自动拉起。

local M = {}
local lgInput = require("lg-input")

-- 由 ~/.local/src/mx-creative-console（分支 local-patches，fork 自
-- github.com/shensquared/mx-creative-console）编译后安装到这里。
local HELPER = os.getenv("HOME") .. "/.local/libexec/mxcc-helper"
local RENDER_DIR = os.getenv("HOME") .. "/.hammerspoon/keypad-render"
local ICON_DIR = os.getenv("HOME") .. "/.hammerspoon/keypad-icons"
local KEY_PX = 118
local LONG_PRESS_SECONDS = 1.2
local MAX_HOLD_SECONDS = 10
local RESTART_DELAY = 3
local MAX_BACKOFF = 60
local STABLE_UPTIME = 30
local MAX_PENDING = 64 * 1024

local BG = { red = 0.09, green = 0.09, blue = 0.11, alpha = 1 }
local FG = { white = 1, alpha = 0.92 }
local ALERT = { red = 0.85, green = 0.25, blue = 0.25, alpha = 1 }

local DICTATION_MODS = { "ctrl", "alt", "cmd" }
local DICTATION_KEY = "d"
local TALK_TIMEOUT = 120

local task = nil
local pending = ""
local stopping = false
local talking = false
local talkWatchdog = nil
local backoff = RESTART_DELAY
local startedAt = 0
local micPoll = nil
local micState = nil
-- hs.timer.doAfter 返回的定时器不留引用就会被 GC 掉，静默不触发。
local retryTimer = nil
local clearTimer = nil
local readyTimer = nil
local pressedKey, pressedAt, holdTimer
local holdReady = false
local pressPoisoned = false
local pressSequence = 0
local actionHistory = {}

-- 只做激活，不再尝试把光标送进聊天输入框。
-- 曾用 ⌃⌘I (workbench.action.chat.open) 做这件事，实测它会新开 VS Code 窗口。
local function focus(bundleID)
  return function() hs.application.launchOrFocusByBundleID(bundleID) end
end

-- 只算物理输入设备：Teams 的 MSLoopbackDriver 采的是系统输出而非人声，
-- 且 mute/volume 都只读，算进来会让状态判断永远为"未静音"。
local function physicalInputs()
  local out = {}
  for _, dev in ipairs(hs.audiodevice.allInputDevices()) do
    if dev:transportType() ~= "Virtual" and dev:inputMuted() ~= nil then
      out[#out + 1] = dev
    end
  end
  return out
end

local function micMuted()
  local devs = physicalInputs()
  if #devs == 0 then return false end
  for _, dev in ipairs(devs) do
    if not dev:inputMuted() then return false end
  end
  return true
end

local function toggleMic()
  local target = not micMuted()
  local accepted = false
  for _, dev in ipairs(physicalInputs()) do
    if dev:setInputMuted(target) then accepted = true end
  end
  if not accepted then print("[mxcc] 没有输入设备接受静音设置") end
  micState = target
  M.repaint(5)
end

local function stopTalking()
  if not talking then return end
  talking = false
  if talkWatchdog then
    talkWatchdog:stop()
    talkWatchdog = nil
  end
  hs.eventtap.event.newKeyEvent(DICTATION_MODS, DICTATION_KEY, false):post()
end

-- 录音必须与 App 无关：可能在 Outlook / Chrome / Teams 里口述。
-- 这里不做任何聚焦动作 —— 曾经加过，结果 ⌃⌘I 在 VS Code 不在前台时会新开窗口。
local function startTalking()
  if talking then return end
  talking = true
  hs.eventtap.event.newKeyEvent(DICTATION_MODS, DICTATION_KEY, true):post()
  talkWatchdog = hs.timer.doAfter(TALK_TIMEOUT, stopTalking)
end

-- LCD 九宫格。icon "app:<bundleID>" 取该 App 的图标；label 为可选文字。
local KEYS = {
  [0] = {
    label = "MAC", imagePath = ICON_DIR .. "/lg-mac.png",
    accent = { white = 0.78, alpha = 1 },
    subtitle = function() return lgInput.subtitle("mac") end,
    action = function() return lgInput.select("mac") end,
    longAction = function() return lgInput.solo("mac") end,
  },
  [1] = {
    label = "SWAP", imagePath = ICON_DIR .. "/lg-swap.png",
    accent = { red = 0.25, green = 0.79, blue = 0.72, alpha = 1 },
    subtitle = function() return lgInput.subtitle("swap") end,
    action = lgInput.swap,
  },
  [2] = {
    label = "PC", imagePath = ICON_DIR .. "/lg-pc.png",
    accent = { red = 0.24, green = 0.65, blue = 0.99, alpha = 1 },
    subtitle = function() return lgInput.subtitle("pc") end,
    action = function() return lgInput.select("pc") end,
    longAction = function() return lgInput.solo("pc") end,
  },
  [3] = {
    label = "PIP", imagePath = ICON_DIR .. "/lg-pip.png",
    accent = { red = 0.65, green = 0.45, blue = 0.95, alpha = 1 },
    subtitle = function() return lgInput.subtitle("pip") end,
    action = function() return lgInput.pipOn() end,
    -- "ONLY PIP" would read as a mode; the hold turns the second picture off.
    longPreview = "PIP OFF",
    longAction = function() return lgInput.pipOff() end,
  },
  [4] = {
    label = "PC POWER", imagePath = ICON_DIR .. "/lg-power.png", subtitle = "待配置",
    accent = { red = 0.62, green = 0.55, blue = 0.39, alpha = 1 },
    action = function()
      hs.alert.show("PC POWER is not configured: Wi-Fi cold power-on is unverified. No power command sent.")
    end,
  },
  [5] = { label = "MIC", dynamic = true, action = toggleMic },
  [6] = { icon = "app:com.microsoft.teams2", action = focus("com.microsoft.teams2") },
  [7] = { icon = "app:com.microsoft.VSCode", action = focus("com.microsoft.VSCode") },
  [8] = { icon = "app:com.apple.Terminal", action = focus("com.apple.Terminal") },
}

local function activateKey(index, spec, longPress, duration)
  local action = longPress and spec.longAction or spec.action
  local submitted = action()
  if index <= 3 then
    actionHistory[#actionHistory + 1] = {
      at = hs.timer.secondsSinceEpoch(), label = spec.label,
      gesture = longPress and "long" or "short",
      heldMilliseconds = math.floor((duration or 0) * 1000 + 0.5),
      submitted = submitted == true,
    }
    if #actionHistory > 32 then table.remove(actionHistory, 1) end
  end
end

function M.recentActions()
  local snapshot = {}
  for index, entry in ipairs(actionHistory) do
    local copy = {}
    for field, value in pairs(entry) do copy[field] = value end
    snapshot[index] = copy
  end
  return snapshot
end

-- Dialpad 四键，按 helper 的 dialkey 1-4 顺序：左上一、左上二、左下、右下。
local DIAL_KEYS = {
  [1] = focus("com.microsoft.VSCode"),
  [2] = focus("com.apple.Terminal"),
  [3] = function() hs.eventtap.keyStroke({}, "return", 0) end,
  [4] = startTalking,
}

-- 两个滚轮被 divert 后不再产生原生滚动，这里合成回来。
-- roller 1 = 大旋钮 -> 纵向；roller 0 = 小滚轮 -> 横向。固件自带加速，按比例透传。
local DIAL_INVERT = { [0] = 1, [1] = -1 }

local function onDial(roller, delta)
  local d = delta * (DIAL_INVERT[roller] or 1)
  local offsets = roller == 1 and { 0, d } or { d, 0 }
  hs.eventtap.event.newScrollEvent(offsets, {}, "line"):post()
end

local function render(idx, spec)
  local alert = spec.dynamic and micMuted() or false
  local c = hs.canvas.new({ x = 0, y = 0, w = KEY_PX, h = KEY_PX })
  c[1] = { type = "rectangle", action = "fill", fillColor = alert and ALERT or BG }

  local bundle = spec.icon and spec.icon:match("^app:(.+)$")
  local img = bundle and hs.image.imageFromAppBundle(bundle)
  if spec.imagePath then img = hs.image.imageFromPath(spec.imagePath) end
  -- App 没装就取不到图标，退回 bundle ID 末段，否则整颗键只剩一块背景色。
  local label = type(spec.label) == "function" and spec.label() or spec.label
  if bundle and not img and not label then label = bundle:match("([^.]+)$") end
  local hasLabel = label ~= nil
  local compact = spec.subtitle ~= nil
  local subtitle = type(spec.subtitle) == "function" and spec.subtitle() or spec.subtitle
  if pressedKey == idx and holdReady then subtitle = spec.longPreview or ("ONLY " .. label) end

  if spec.accent then
    c[#c + 1] = {
      type = "rectangle", action = "fill", fillColor = spec.accent,
      frame = { x = 17, y = 7, w = 84, h = 3 },
    }
  end

  if img then
    local size = compact and 54 or hasLabel and 66 or 84
    c[#c + 1] = {
      type = "image",
      image = img,
      imageScaling = "scaleProportionally",
      frame = { x = (KEY_PX - size) / 2, y = compact and 17 or hasLabel and 12 or 17, w = size, h = size },
    }
  end
  if hasLabel then
    c[#c + 1] = {
      type = "text",
      text = alert and "MUTED" or label,
      textSize = compact and 15 or img and 15 or 22,
      textColor = FG,
      textAlignment = "center",
      frame = { x = 0, y = compact and (img and 76 or 46) or img and 84 or 46, w = KEY_PX, h = compact and 22 or 28 },
    }
  end
  if subtitle and subtitle ~= "" then
    c[#c + 1] = {
      type = "text", text = subtitle, textSize = 11,
      textColor = spec.accent or FG, textAlignment = "center",
      frame = { x = 4, y = 99, w = KEY_PX - 8, h = 16 },
    }
  end

  local path = string.format("%s/key%d.png", RENDER_DIR, idx)
  local ok = c:imageFromCanvas():saveToFile(path)
  c:delete()
  if not ok then
    print("[mxcc] 第 " .. idx .. " 键写入失败: " .. path)
    return nil
  end
  return path
end

-- setInput 的连续调用会互相覆盖，只有最后一条到达 helper。
-- 所有写入合并到下一个 tick 一次性发出，避免 repaintAll 和单键重绘互相踩。
local outbox = {}
local flushTimer = nil

local function send(line)
  outbox[#outbox + 1] = line
  if flushTimer then return end
  flushTimer = hs.timer.doAfter(0, function()
    flushTimer = nil
    local batch = table.concat(outbox)
    outbox = {}
    if #batch > 0 and task and task:isRunning() then task:setInput(batch) end
  end)
end

function M.repaint(idx)
  local spec = KEYS[idx]
  if not spec then return end
  local path = render(idx, spec)
  if path then send(string.format("paintfile %d %s\n", idx, path)) end
end

function M.repaintAll()
  for idx = 0, 8 do M.repaint(idx) end
end

local function cancelPress()
  local previous = pressedKey
  pressSequence = pressSequence + 1
  if holdTimer then holdTimer:stop(); holdTimer = nil end
  pressedKey, pressedAt = nil, nil
  holdReady, pressPoisoned = false, false
  if previous and not stopping then M.repaint(previous) end
end

local function keypadAttached()
  for _, device in ipairs(hs.usb.attachedDevices()) do
    if device.vendorID == 1133 and device.productID == 50004 then return true end
  end
  return false
end

local function onEvent(line)
  if M.debug then print("[mxcc-ev] " .. line) end
  if line == "key up" then
    local keyIndex = pressedKey
    local spec = keyIndex and KEYS[keyIndex]
    local duration = pressedAt and (hs.timer.absoluteTime() / 1000000000 - pressedAt)
    local allowed = not pressPoisoned and duration and duration >= 0 and duration <= MAX_HOLD_SECONDS
    cancelPress()
    if allowed and spec and spec.longAction and keypadAttached() then
      activateKey(keyIndex, spec, duration >= LONG_PRESS_SECONDS, duration)
    end
    return
  end
  local n = line:match("^key (%d)$")
  if n then
    local keyIndex = tonumber(n) - 1
    local spec = KEYS[keyIndex]
    if not spec or pressPoisoned then return end
    if pressedKey then
      if pressedKey == keyIndex then return end
      local mixedHold = KEYS[pressedKey].longAction or spec.longAction
      cancelPress()
      if mixedHold then pressPoisoned = true; return end
    end
    pressedKey, pressedAt = keyIndex, hs.timer.absoluteTime() / 1000000000
    if spec.longAction then
      local currentSequence = pressSequence
      holdTimer = hs.timer.doAfter(LONG_PRESS_SECONDS, function()
        if stopping or pressPoisoned or pressSequence ~= currentSequence or pressedKey ~= keyIndex then return end
        holdTimer = nil
        holdReady = true
        M.repaint(keyIndex)
      end)
    else
      activateKey(keyIndex, spec, false, 0)
    end
    return
  end
  n = line:match("^dialkey (%d) up$")
  if n then
    -- 只有 4 号是按住说话；同时按两颗时先松开的那颗不该停录音。
    if tonumber(n) == 4 then stopTalking() end
    return
  end
  n = line:match("^dialkey (%d)$")
  if n then
    local fn = DIAL_KEYS[tonumber(n)]
    if fn then fn() end
    return
  end
  local roller, delta = line:match("^dial (%d) (-?%d+)$")
  if roller then
    onDial(tonumber(roller), tonumber(delta))
    return
  end
  if line == "dialkey up" then
    stopTalking()
    return
  end
  -- 这两颗翻页键已被 helper divert，不接就等于按下去毫无反应。
  if line == "nav left" then
    hs.eventtap.keyStroke({ "cmd" }, "[", 0)
    return
  end
  if line == "nav right" then
    hs.eventtap.keyStroke({ "cmd" }, "]", 0)
    return
  end
  if line:match("^ready") then
    cancelPress()
    readyTimer = hs.timer.doAfter(0.4, function()
      readyTimer = nil
      M.repaintAll()
    end)
  end
end

local function onStdout(_, stdout, stderr)
  -- terminate() 之后仍可能来一次收尾回调，缓冲里的事件不该再触发动作。
  if stopping then return true end
  if stderr and #stderr > 0 then
    if stderr:find("keypad removed", 1, true) then
      cancelPress()
      pressPoisoned = true
    end
    for l in stderr:gmatch("[^\n]+") do
      -- helper 每 4 秒重绘一轮并打一行，不过滤一天两万多行。
      if M.debug or not l:match("^refresh %d+ keys$") then print("[mxcc] " .. l) end
    end
  end
  if stdout then
    pending = pending .. stdout
    while true do
      local nl = pending:find("\n")
      if not nl then break end
      local line = pending:sub(1, nl - 1)
      pending = pending:sub(nl + 1)
      if #line > 0 then onEvent(line) end
    end
    -- 一直没换行就一直累积，封顶避免占满内存。
    if #pending > MAX_PENDING then
      print("[mxcc] 丢弃超长残行 " .. #pending .. " 字节")
      pending = ""
    end
  end
  return true
end

local function spawn()
  pending = ""
  -- 二进制缺失或每次秒退时，固定 3 秒重试等于一天两万次启动。
  local function retry()
    if stopping then return end
    retryTimer = hs.timer.doAfter(backoff, function()
      retryTimer = nil
      if not task and not stopping then spawn() end
    end)
    backoff = math.min(backoff * 2, MAX_BACKOFF)
  end
  startedAt = hs.timer.secondsSinceEpoch()
  task = hs.task.new(HELPER, function()
    task = nil
    cancelPress()
    stopTalking() -- helper 死亡时 dialkey up 永远不会到，否则和弦卡住到看门狗超时
    -- 只看 ready 会让"attach 成功之后才崩"的循环永远停在 3 秒重试上。
    if hs.timer.secondsSinceEpoch() - startedAt >= STABLE_UPTIME then
      backoff = RESTART_DELAY
    end
    retry()
  end, onStdout)
  -- 路径不存在时 new() 照样返回对象，失败要到 start() 才看得出来。
  if not task or not task:start() then
    print("[mxcc] helper 起不来: " .. HELPER)
    task = nil
    retry()
  end
end

-- 每次启动先清场：Hammerspoon 崩溃或被强杀时子进程可能存活，多个 helper 会各自
-- 持有设备句柄。先 SIGCONT 再 SIGTERM —— 失去父 shell 的后台进程会因终端 I/O 被
-- SIGTTOU 挂起（ps 显示 T 态），停止态的进程不会处理 SIGTERM。
-- 模式里的 [m] 避免匹配 hs.execute 自己起的那层 sh，否则 pkill 会先杀掉父 shell。
local function killStrays()
  hs.execute("/usr/bin/pkill -CONT -f 'libexec/[m]xcc-helper'; "
    .. "/usr/bin/pkill -TERM -f 'libexec/[m]xcc-helper'")
end

local function strayCount()
  local out = hs.execute("/usr/bin/pgrep -f 'libexec/[m]xcc-helper' | /usr/bin/wc -l")
  return tonumber(out and out:match("%d+") or "") or 0
end

-- 旧 helper 收到 SIGTERM 后要先把 divert 还原再退出。抢在它还原完成之前起新的，
-- 新 helper 刚设好的 divert 会被旧的还原动作抹掉，键和滚轮当场变死。
local function spawnWhenClear(tries)
  if stopping then return end
  if strayCount() > 0 then
    if tries > 0 then
      clearTimer = hs.timer.doAfter(0.25, function()
        clearTimer = nil
        spawnWhenClear(tries - 1)
      end)
      return
    end
    -- 宽限期内没退干净就强杀。被 KILL 的进程跑不了还原流程，也就抹不掉
    -- 新 helper 即将设置的 divert —— 比放它继续跑安全。
    print("[mxcc] 残留 helper 未退出，强制结束")
    hs.execute("/usr/bin/pkill -KILL -f 'libexec/[m]xcc-helper'")
  end
  spawn()
end

function M.start()
  stopping = false
  backoff = RESTART_DELAY
  cancelPress()
  hs.fs.mkdir(RENDER_DIR)
  lgInput.onChange = function() for index = 0, 3 do M.repaint(index) end end
  lgInput.start()
  killStrays()
  -- 系统设置或别的 App 改静音时不会通知我们，只能轮询，变了才重绘。
  micState = micMuted()
  micPoll = hs.timer.doEvery(2, function()
    local now = micMuted()
    if now ~= micState then
      micState = now
      M.repaint(5)
    end
  end)
  spawnWhenClear(12)
end

function M.stop()
  stopping = true
  cancelPress()
  lgInput.onChange = nil
  lgInput.stop()
  stopTalking()
  if micPoll then micPoll:stop() end
  if flushTimer then flushTimer:stop() end
  if retryTimer then retryTimer:stop() end
  if clearTimer then clearTimer:stop() end
  if readyTimer then readyTimer:stop() end
  micPoll, flushTimer, retryTimer, clearTimer, readyTimer = nil, nil, nil, nil, nil
  outbox = {}
  if task then
    local t = task
    task = nil
    t:terminate()
  end
end

M.micMuted = micMuted
M.toggleMic = toggleMic

return M
