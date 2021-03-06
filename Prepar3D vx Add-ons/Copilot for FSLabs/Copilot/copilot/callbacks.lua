if false then module "copilot" end

local util = require "FSL2Lua.FSL2Lua.util"

local callbacks = {}
local callbackNames = {}
local activeCallbacks = {}
local suspendedCallbacks = {}
local threadEvents = setmetatable({}, {__mode = "k"})

copilot.THREAD_REMOVED = setmetatable({}, {__tostring = function() return "copilot.THREAD_REMOVED" end})
copilot.INDEFINITE = {}

copilot.getTimestamp = ipc.elapsedtime
function copilot.getThreadEvent(thread) return threadEvents[thread] end
function copilot.await(thread) return Event.waitForEvent(copilot.getThreadEvent(thread)) end

local function getCallbackProps(callback) return callbacks[callback] end
local function findCallback(key)
  return callbacks[key] and key or callbackNames[key]
end

--- Adds a callback to the main callback loop.
--- Dead coroutines are removed automatically.
--- @param callback A function, callable table or thread. It will be called with a timestamp (milliseconds) taken from copilot.getTimestamp() as the first and itself as the seconds parameters.
--- @string[opt] name Can be used later to remove the callback with `removeCallback`.
--- @int[opt] interval Interval in milliseconds
--- @int[opt] delay Initial delay in milliseconds
--- @return The callback that was passed in.
--- @return An <a href="#Class_Event">Event</a> that will be signaled when the coroutine:
---
--- 1. Finishes its execution normally. In this case, the event's payload will be the values returned by the coroutine.
---
--- 2. Is removed with `removeCallback`. The payload will be copilot.THREAD_REMOVED
---
--- See `copilot_events_example.lua`.
function copilot.addCallback(callback, name, interval, delay)

  local alreadyAdded = findCallback(callback)
  if alreadyAdded and getCallbackProps(alreadyAdded).name ~= name then
    error("This callback was already added under a different name", 2)
  elseif not alreadyAdded and name and findCallback(name) then
    error("A different callback with this name was already added", 2)
  end

  local nextExecTime = copilot.getTimestamp() + (delay or 0)

  if alreadyAdded then
    local props = getCallbackProps(alreadyAdded)
    props.interval = interval
    if delay > 0 then copilot.setCallbackTimeout(callback, delay) end
    return callback, threadEvents[callback]
  end
  
  local type = type(callback) == "thread" and "thread" 
    or util.isCallable(callback) and "function"
    or error("Bad callback parameter", 2)
  
  local logName = name or tostring(callback)

  callbacks[callback] = {
    type = type,
    name = name,
    interval = interval,
    nextExecTime = nextExecTime,
    logName = logName,
    status = "suspended"
  }

  local threadEvent 
  if type == "thread" then
    threadEvent = SingleEvent:new {logMsg = "Copilot coroutine finished: " .. logName}
    threadEvents[callback] = threadEvent
  end

  activeCallbacks[callback] = true
  if name then callbackNames[name] = callback end
  return callback, threadEvent
end

function copilot.getCallbackStatus(callback)
  local props = getCallbackProps(callback)
  return props and props.status
end

--- Adds callback to the main callback loop. The callback will be removed after being called once.
--- It doesn't matter whether you use `addCallback` or callOnce with coroutines as the former removes dead
--- coroutines anyway.
--- @param callback Same as `addCallback`
--- @int[opt] delay Same as `addCallback`
--- @return The same values as `addCallback`
function copilot.callOnce(callback, delay)
  local deletthis
  if util.isCallable(callback) then
    deletthis = function(...)
      callback(...)
      copilot.removeCallback(deletthis)
    end
  elseif type(callback) == "thread" then
    deletthis = callback
  end
  return copilot.addCallback(deletthis, nil, nil, delay)
end

function copilot.setCallbackTimeout(callback, timeout)
  local props = getCallbackProps(callback)
  props.status = "suspended"
  if timeout == copilot.INDEFINITE then
    activeCallbacks[callback] = nil
    suspendedCallbacks[callback] = true
  else
    props.nextExecTime = copilot.getTimestamp() + timeout
  end
  if coroutine.running() == callback then
    coroutine.yield()
  end
end

function copilot.cancelCallbackTimeout(callback)
  if suspendedCallbacks[callback] then
    activeCallbacks[callback] = true
    suspendedCallbacks[callback] = nil
  else
    local props = getCallbackProps(callback)
    if props.status == "suspended" then
      props.nextExecTime = copilot.getTimestamp()
    end
  end
end

local function removeCallback(callback)
  local props = getCallbackProps(callback)
  local name = props.name
  if name then callbackNames[name] = nil end
  activeCallbacks[callback] = nil
  suspendedCallbacks[callback] = nil
  callbacks[callback] = nil
end

--- Removes a previously added callback.
--- @param key Either the callable itself or the name passed to @{addCallback}
function copilot.removeCallback(key)
  local callback = findCallback(key)
  if callback then
    if type(callback) == "thread" then
      threadEvents[callback].removed = true
      threadEvents[callback]:trigger(copilot.THREAD_REMOVED)
    end
    removeCallback(callback)
  end
end

local function runThreadCallback(thread, props, ...)
  props.status = "active"
  if not props.coroutineStarted then
    props.coroutineStarted = true
    copilot.logger:debug("Starting Copilot coroutine: " .. props.logName)
  end
  local ret = {coroutine.resume(thread, ...)}
  if not ret[1] then
    copilot.pause()
    error(ret[2])
  end
  if coroutine.status(thread) == "dead" then
    removeCallback(thread)
    threadEvents[thread]:trigger(unpack(ret, 2))
    return false
  end
  return true
end

local function runFuncCallback(callback, props, ...)
  props.status = "active"
  callback(...)
end

local function checkCallbackTiming(timestamp, props)
  if props.interval and props.nextExecTime < timestamp  then
    props.nextExecTime = timestamp + props.interval
    return true
  end
  return props.nextExecTime < timestamp
end

local function runCallback(callback, props, timestamp)
  local shouldRun = checkCallbackTiming(timestamp, props)
  if shouldRun then
    local type = props.type
    if type == "function" then
      runFuncCallback(callback, props, timestamp, callback)
    elseif type == "thread" then
      runThreadCallback(callback, props, timestamp, callback)
    end
  end
  return shouldRun
end

function copilot.update()
  local timestamp = copilot.getTimestamp()
  local numCallbacks = 0
  for callback in pairs(activeCallbacks) do
    if runCallback(callback, getCallbackProps(callback), timestamp) then
      numCallbacks = numCallbacks + 1
    end
  end
  --copilot.logger:trace(string.format("Ran %d callbacks in %d ms", numCallbacks, copilot.getTimestamp() - timestamp))
end

function copilot._initActionThread(thread, ...) 
  runThreadCallback(thread, getCallbackProps(thread), ...) 
end