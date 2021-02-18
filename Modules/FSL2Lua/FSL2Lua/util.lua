----------------------------------------
-- Library for interacting with FSLabs cockpit controls based on Lvars and mouse macros.
-- See @{standalonescripts.md|here} on how to use it outside of Copilot.
-- @module FSL2Lua

local file = require "FSL2Lua.FSL2Lua.file"
local config = require "FSL2Lua.config"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

--- Executes the condition callback until it signals the condition or the timeout elapses.
--@int[opt=5000] timeout Timeout in milliseconds
--@tparam function condition A callback that should return a truthy value to signal the condition.
--@treturn bool True if the condition was signaled, false if the timeout has elapsed.
function checkWithTimeout(timeout, condition)
  timeout = ipc.elapsedtime() + (timeout or 5000)
  repeat 
    if condition() then return true end
  until ipc.elapsedtime() > timeout
  return false
end

--- Executes the callback until the timeout elapses or the callback returns any value other than nil.
--@int[opt=5000] timeout Timeout in milliseconds
--@tparam function block
--@return Either nil  if the timeout has elapsed, or the value returned by block.
function withTimeout(timeout, block)
  timeout = ipc.elapsedtime() + (timeout or 5000)
  repeat
    local val = block()
    if val ~= nil then return val end
  until ipc.elapsedtime() > timeout
end

--- Repeats the callback until the timeout elapses
--@int[opt=5000] timeout Timeout in milliseconds
--@tparam function block
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

------------------------------------------------------------------
-- End of global functions ---------------------------------------
------------------------------------------------------------------

local util = {
  FSUIPCversion = not FSL2LUA_STANDALONE and ipc.readUW(0x3306),
  FSL2LuaDir = debug.getinfo(1, "S").source:gsub(".(.*\\).*\\.*", "%1")
}

local copilot = type(copilot) == "table" and copilot.logger and copilot
local logFilePath = util.FSL2LuaDir .. "\\FSL2Lua.log"

function util.isType(o, _type)
  local mt = getmetatable(o)
  if mt == _type then return true end
  if not mt then return false end
  return util.isType(mt, _type)
end

function util.checkType(o, type, desc, errLevel)
  util.assert(
    util.isType(o, type),
    tostring(o and o.name or o) .. " is not a " .. desc .. ".",  
    (errLevel or 1) + 1
  )
  return o
end

function util.handleError(msg, level, critical)
  level = (level or 1) + 1
  msg = "FSL2Lua: " .. msg
  if copilot then
    local logFile = string.format("FSUIPC%s.log", ("%x"):format(util.FSUIPCversion):sub(1, 1))
    copilot.logger[critical and "error" or "warn"](copilot.logger, "FSL2Lua: something went wrong. Check " .. logFile)
    if critical then copilot.logger:error("Copilot cannot continue") end
  end
  if critical then
    error(msg, level)
  end
  local trace = debug.getinfo(level, "Sl")
  ipc.log(string.format("%s\r\nsource: %s:%s", msg, trace.short_src, trace.currentline))
end

function util.log(msg, drawline, notimestamp)
  if not util._loggingEnabled then return end
  local str = ""
  if drawline == true then
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