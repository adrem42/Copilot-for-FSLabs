local file = require "FSL2Lua.FSL2Lua.file"
local config = require "FSL2Lua.config"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

function checkWithTimeout(timeout, condition)
  timeout = ipc.elapsedtime() + (timeout or 5000)
  repeat 
    if condition() then return true end
  until ipc.elapsedtime() > timeout
  return false
end

function withTimeout(timeout, block)
  timeout = ipc.elapsedtime() + (timeout or 5000)
  repeat
    local val = block()
    if val ~= nil then return val end
  until ipc.elapsedtime() > timeout
end

function repeatWithTimeout(timeout, block)
  timeout = ipc.elapsedtime() + (timeout or 5000)
  repeat block() until ipc.elapsedtime() > timeout
end

math.randomseed(os.time())

function prob(prob) return math.random() <= prob end

function plusminus(val, percent)
  percent = (percent or 0.2) * 100
  return val * math.random(100 - percent, 100 + percent) * 0.01
end

function moveTwoSwitches(switch1, pos1, switch2, pos2, chance)
  if prob(chance or 1) then
    hand:moveTo((switch1.pos + switch2.pos) / 2)
    sleep(plusminus(100))
    local co1 = coroutine.create(function() 
      switch1:_moveInternal(pos1, true) 
    end)
    local co2 = coroutine.create(function() 
      sleep(plusminus(30))
      switch1:_moveInternal(pos2, true) 
    end)
    repeat
      local done1 = not coroutine.resume(co1)
      sleep(1)
      local done2 = not coroutine.resume(co2)
    until done1 and done2
  else
    switch1(pos1)
    switch2(pos2)
    sleep(plusminus(100))
  end
end

function pressTwoButtons(butt1, butt2, chance)
  if prob(chance or 1) then
    hand:moveTo((butt1.pos + butt1.pos) / 2)
    sleep(plusminus(200,0.1))
    local co1 = coroutine.create(function() 
      butt1:_pressAndReleaseInternal(true) 
    end)
    local co2 = coroutine.create(function() 
      sleep(1)
      butt1:_pressAndReleaseInternal(true) 
    end)
    repeat
      local done1 = not coroutine.resume(co1)
      sleep(1)
      local done2 = not coroutine.resume(co2)
    until done1 and done2
  else
    butt1()
    butt2()
  end
end

------------------------------------------------------------------
-- End of global functions ---------------------------------------
------------------------------------------------------------------

local util = {
  FSUIPCversion = not FSL2LUA_STANDALONE and ipc.readUW(0x3306),
  FSL2LuaDir = debug.getinfo(1, "S").source:gsub(".(.*\\).*\\.*", "%1")
}

util.macroAcType = FSL:getAcType()
if config.A319_IS_A320 and FSL:getAcType() == "A319" then
  util.macroAcType = "A320"
end

local copilot = type(copilot) == "table" and copilot.logger and copilot
local logFilePath = util.FSL2LuaDir .. "\\FSL2Lua.log"

function util.handleError(msg, level, critical)
  level = level and level + 1 or 2
  msg = "FSL2Lua: " .. msg
  if copilot then
    local logFile = string.format("FSUIPC%s.log", ("%x"):format(FSUIPCversion):sub(1, 1))
    copilot.logger[critical and "error" or "warn"](copilot.logger, "FSL2Lua: something went wrong. Check " .. logFile)
    if critical then copilot.logger:error("Copilot cannot continue") end
  end
  if critical then
    error(msg, level)
  else
    local trace = debug.getinfo(level, "Sl")
    ipc.log(string.format("%s\r\nsource: %s:%s", msg, trace.short_src, trace.currentline))
  end
end

function util.log(msg, drawline, notimestamp)
  if not util._loggingEnabled then return end
  local str = ""
  if drawline == 1 then
    str = "-------------------------------------------------------------------------------------------\n"
  end
  if not notimestamp then
    str = str .. os.date("[%H:%M:%S] - ")
  end
  file.write(logFilePath, str .. msg .. "\n")
end

function util.sleep(time1,time2)
  local time
  if time1 and time2 then
    time = math.random(time1,time2)
  elseif time1 then
    time = time1
  else
    time = 100
  end
  ipc.sleep(time)
end

function util.frameRate() return 32768 / ipc.readUW(0x0274) end

function util.assert(val, msg, level)
  if not val then error(msg, level and level + 1) end
  return val
end

function util.enableLogging(startNewLog)
  util._loggingEnabled = true
  if not ipc.get("FSL2LuaLog") or startNewLog then
    file.create(logFilePath)
    ipc.set("FSL2LuaLog", 1)
  end
end

function util.disableLogging()
  util._loggingEnabled = false
end

return util