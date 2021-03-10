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
    eventRefs = {stop = {}}
  }, self)
  if a.runAsCoroutine then
    a.threadFinishedEvent = Event:new()
    a.threadFinishedEvent:addAction(function(_, ...) a:_onThreadFinished(...) end)
  end
  util.setOnGCcallback(a, function() copilot.logger:trace("Action gc: " .. a:toString()) end)
  return a
end

function Action:toString() return self.logMsg or tostring(self):gsub("table: 0+", "") end

--- Enables or disables the action.
--- @bool value True to enable the action, false to disable.
function Action:setEnabled(value) self.isEnabled = value end

--- Returns true if the callback was configured to be run as a coroutine and is running now.
function Action:isThreadRunning() return self.currentThread ~= nil end

function Action:_runFuncCallback(...)
  copilot.logger:debug("Action: " .. self:toString())
  self.callback(...)
end

function Action:_onThreadFinished(payload)
  copilot.logger:debug("Finished coroutine action: " .. self:toString())
  self.currentThread = nil
  if self.cleanUpCallback and payload == copilot.THREAD_REMOVED then
    self.cleanUpCallback()
  end
end

function Action:_initNewThread(dependencies, ...)

  if dependencies then
    self.currentThread = coroutine.create(function(...)
      local events = {}
      for _, dependency in ipairs(dependencies) do
        if dependency.currentThread then
          events[#events+1] = dependency.threadFinishedEvent
        end
      end
      if #events > 0 then Event.waitForEvents(events, true) end
      copilot.logger:debug("Coroutine action: " .. self:toString())
      return self.callback(...)
    end)
  else
    copilot.logger:debug("Coroutine action: " .. self:toString())
    self.currentThread = coroutine.create(self.callback)
  end

  local _, threadEvent = copilot.addCallback(
    self.currentThread, ("%s of Action '%s'"):format(tostring(self.currentThread), self:toString())
  )
  threadEvent:addOneOffAction(function(_, ...) self.threadFinishedEvent:trigger(...) end)
  copilot._initActionThread(self.currentThread, ...)
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
    copilot.logger:debug("Stopping coroutine action: " .. self:toString())
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
function Action:addLogMsg(msg)
  self.logMsg = msg
  return self
end

return Action