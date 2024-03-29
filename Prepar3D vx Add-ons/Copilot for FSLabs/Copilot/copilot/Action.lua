---- Copilot's event library.
-- @module Event

Event = Event or require "copilot.Event"
local util = require "FSL2Lua.FSL2Lua.util"
local EventUtils = require "copilot.EventUtils"

--- @type Action
Action = {threads = {}, COROUTINE = "runAsCoroutine"}
local Action = Action

--- Constructor
--- @tparam function callback
--- @string[opt] flags 'runAsCoroutine'
function Action:new(callback, flags)
  self.__index = self
  local isCallable, callableType = util.isCallable(callback)
  util.assert(isCallable, "Action callback must be a callable", 2)
  local a = setmetatable ({
    callback = callableType == "function" and callback or function(...) return callback(...) end,
    isEnabled = true,
    runAsCoroutine = flags == Action.COROUTINE,
    eventRefs = {stop = {}},
    events = {}
  }, self)
  util.setOnGCcallback(a, function() copilot.logger:trace("Action gc: " .. a:toString()) end)
  return a
end

function Action:removeFromEvent(event)
  if event then
    event:removeAction(self)
  else
    for e in pairs(self.events) do
      e:removeAction(self)
    end
  end
end

function Action:_onAddedToEvent(event)
  self.events[event] = true
end

function Action:_onRemovedFromEvent(event)
  self.events[event] = nil
end

function Action:toString() return self.logMsg or tostring(self):gsub("table: 0+", "") end

--- Enables or disables the action.
--- @bool value True to enable the action, false to disable.
function Action:setEnabled(value) self.isEnabled = value end

--- Returns true if the callback was configured to be run as a coroutine and is running now.
function Action:isThreadRunning() return self.currentThread ~= nil end

function Action:log(msg, logLevel, event)
  if self.logMsg == Event.NOLOGMSG then return end
  if event and event.logMsg == Event.NOLOGMSG then return end
  copilot.logger[logLevel or "debug"](copilot.logger, msg)
end

function Action:_runFuncCallback(e, payload)
  self:log("Action: " .. self:toString(), "debug", e)
  local ret = table.pack(
    xpcall(self.callback, debug.traceback, e, table.unpack(payload, 1, payload.n))
  )
  local status = ret[1]
  if status == false then
    local err = ret[2]
    copilot.logger:error(err)
  elseif self._doneEvent then 
    self._doneEvent:trigger(table.unpack(ret, 2, ret.n)) 
  end
end

function Action:doneEvent()
  self._doneEvent = self._doneEvent or Event:new {logMsg = Event.NOLOGMSG}
  return self._doneEvent
end

function Action:_onThreadFinished(...)
  self:log("Finished coroutine action: " .. self:toString(), "debug")
  self.currentThread = nil
  if self.cleanUpCallback and select(1, ...) == copilot.THREAD_REMOVED then
    self.cleanUpCallback()
  end
  if self._doneEvent then self._doneEvent:trigger(...) end
end

function Action:_initNewThread(dependencies, e, payload)
  if dependencies then
    self.currentThread = coroutine.create(function(...)
      local events = {}
      for _, dependency in ipairs(dependencies) do
        if dependency.currentThread then
          events[#events+1] = dependency:doneEvent()
        end
      end
      if #events > 0 then Event.waitForEvents(events, true) end
      self:log("Coroutine action: " .. self:toString(), "debug", e)
      return self.callback(e, ...)
    end)
  else
    self:log("Coroutine action: " .. self:toString(), "debug", e)
    self.currentThread = coroutine.create(self.callback)
  end

  local _, threadEvent = copilot.addCallback(self.currentThread)
  threadEvent:addOneOffAction(function(_, ...) self:_onThreadFinished(...) end)
  copilot._initActionThread(self.currentThread, e, table.unpack(payload, 1, payload.n))
end

--- Use this you want to disable the effect of @{stopOn} for one of the predefined actions in @{copilot.actions}
--- @function removeEventRef
--- @string refType 'stop'
--- @param ... One or more <a href="#Class_Event">Event</a>'s
--- @usage copilot.actions.preflight:removeEventRef('stop', copilot.events.enginesStarted)

Action.removeEventRef = EventUtils.removeEventRef
Action.makeEventRef = EventUtils.makeEventRef

--- If the action was configured to be run as a coroutine, stops the execution of the currently running coroutine immediately.
function Action:stopCurrentThread()
  if self.currentThread then
    self:log("Stopping coroutine action: " .. self:toString(), "debug")
    copilot.removeCallback(self.currentThread)
  end
end

--- <span>
--- @param ... One or more events. If the 'runAsCoroutine' flag was passed to the constructor, the callback coroutine will be stopped when these events are triggered. 
--- @usage myAction:stopOn(copilot.events.takeoffAborted, copilot.events.takeoffCancelled)
--- @return self
function Action:stopOn(...)
  self:makeEventRef(function() self:stopCurrentThread() end, "stop", ...)
  return self
end

--- Can be used when the action can be stopped - the callback will be executed when the action is stopped.
--- @tparam function callback
--- @return self
function Action:addCleanup(callback)
  self.cleanUpCallback = callback
  return self
end

--- Add log info that will be logged when the action is started or stopped
--- @string msg
--- @return self
function Action:setLogMsg(msg)
  self.logMsg = msg
  return self
end

Action.addLogMsg = Action.setLogMsg

return Action