----------------------------------------
-- Library for interacting with FSLabs cockpit controls based on Lvars and mouse macros.
-- See @{standalonescripts.md|here} on how to use it outside of Copilot.
-- @module FSL2Lua

local file = require "FSL2Lua.FSL2Lua.file"

local function parseTimeoutArgs(...)
  local block, firstArgIdx, interval
  local timeout = ipc.elapsedtime() + select(1, ...)
  local secondArg = select(2, ...)
  if type(secondArg) == "function" then 
    block = secondArg
    firstArgIdx = 3
  else
    interval = secondArg
    block = select(3, ...)
    firstArgIdx = 4
  end
  return block, timeout, interval, firstArgIdx
end

--- Executes the callback until it signals a truthy value or the timeout elapses.
--@int timeout Timeout in milliseconds
--@tparam function block A callback that should return a truthy first value to signal the condition.
--@param ... Arguments to forward to block.
--@treturn bool True + the rest of the values returned by block if the condition was signaled, false if the timeout has elapsed.
function checkWithTimeout(...)
  local block, timeout, interval, firstArgIdx = parseTimeoutArgs(...)
  repeat 
    local res = {block(select(firstArgIdx, ...))}
    if res[1] then return true, unpack(res, 2) end
    if interval then ipc.sleep(interval) end
  until ipc.elapsedtime() > timeout
  return false
end

---<span>
---@function checkWithTimeout
--@int timeout Timeout in milliseconds
--@int interval Interval to sleep between checks
--@tparam function block A callback that should return a truthy first value to signal the condition.
--@param ... Arguments to forward to block.
--@treturn bool True + the rest of the values returned by block if the condition was signaled, false if the timeout has elapsed.

--- Executes the callback until the timeout elapses or the first value returned by the callback is anything other than nil.
--@int timeout Timeout in milliseconds
--@tparam function block
--@param ... Arguments to forward to block.
--@return Either nil if the timeout has elapsed, or the values returned by block.
function withTimeout(...)
  local block, timeout, interval, firstArgIdx = parseTimeoutArgs(...)
  repeat
    local res = {block(select(firstArgIdx, ...))}
    if res[1] ~= nil then return unpack(res) end
    if interval then ipc.sleep(interval) end
  until ipc.elapsedtime() > timeout
end

--- <span>
---@function withTimeout
--@int timeout Timeout in milliseconds
--@int interval Interval to sleep between checks
--@tparam function block
--@param ... Arguments to forward to block.
--@return Either nil if the timeout has elapsed, or the values returned by block.

--- Repeats the callback until the timeout elapses
--@int timeout Timeout in milliseconds
--@tparam function block
--@param ... Arguments to forward to block.
function repeatWithTimeout(...)
  local block, timeout, interval, firstArgIdx = parseTimeoutArgs(...)
  repeat 
    block(select(firstArgIdx, ...)) 
    if interval then ipc.sleep(interval) end
  until ipc.elapsedtime() > timeout
end

--- <span>
---@function repeatWithTimeout
--@int timeout Timeout in milliseconds
--@int interval Interval to sleep between block invocations
--@tparam function block
--@param ... Arguments to forward to block.

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
  FSL2LuaDir = debug.getinfo(1, "S").source:gsub(".(.*\\).*\\.*", "%1")
}

local logFilePath = util.FSL2LuaDir .. "\\FSL2Lua.log"

function util.isFuncTable(obj)
  if type(obj) ~= "table" and type(obj) ~= "userdata" then 
    return false 
  end
  if getmetatable(obj) == nil then 
    return false 
  end
  return type(getmetatable(obj).__call) == "function"
end

function util.isCallable(obj)
  if type(obj) == "function" then 
    return true, "function" 
    end
  if util.isFuncTable(obj) then 
    return true, "funcTable" 
  end
  return false
end

function util.isType(obj, type, considerInheritance)
  if considerInheritance == nil then considerInheritance = true end
  local mt = getmetatable(obj)
  if mt == type then return true end
  if not mt or not considerInheritance then return false end
  return util.isType(mt, type, true)
end

function util.checkType(obj, type, desc, errLevel, considerInheritance)
  util.assert(
    util.isType(obj, type, considerInheritance),
    tostring(obj and obj.name or obj) .. " is not a " .. desc .. ".",  
    (errLevel or 1) + 1
  )
  return o
end

function util.handleError(msg, level, critical)
  level = (level or 1) + 1
  local trace = debug.getinfo(level, "Sl")
  if critical then
    error(msg)
  else
    print(string.format("%s\r\nsource: %s:%s", msg, trace.short_src, trace.currentline))
  end
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
  if time1 and time2 then time = math.random(time1,time2)
  elseif time1 then time = time1
  else time = 100 end
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

function util._wrapDeprecated(name, replacement, func)
  local msg = string.format(
    "%s is deprecated and will be removed in a future version. Use %s instead.",
    name, replacement
  )
  return function(...)
    util.handleError(msg, 2)
    func(...)
  end
end

function util.setOnGCcallback(t, callback)
  local ud = newproxy(true)
  getmetatable(ud).__gc = callback
  t.__gc_ud = ud
end

return util