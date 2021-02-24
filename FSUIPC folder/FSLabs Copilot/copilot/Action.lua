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
    callback = callableType == "function" and callback or function(...) callback(...) end,
    isEnabled = true,
    runAsCoroutine = flags == "runAsCoroutine",
    eventRefs = {stop = {}}
  }, self)
  util.setOnGCcallback(a, function() 
    copilot.logger:trace("Action gc: " .. a:toString()) 
  end)
  return a
end

function Action:toString()
  return self.logMsg or tostring(self):gsub("table: 0+", "")
end

--- Enables or disables the action.
--- @bool value True to enable the action, false to disable.
function Action:setEnabled(value)
  self.isEnabled = value
end

--- Returns true if the callback was configured to be run as a coroutine and is running now.
function Action:isThreadRunning()
  return self.currentThread ~= nil
end

function Action:runCallback(...)
  copilot.logger:debug("Starting action: " .. self:toString())
  self.callback(...)
end

function Action.getActionFromThread(threadID)
  return Action.threads[threadID]
end

function Action:createThread(dependencies)
  if not self.currentThread then
    if dependencies then
      self.currentThread = coroutine.create(function(...)
        for _, dependency in ipairs(dependencies) do
          while dependency:isThreadRunning() do copilot.suspend() end
        end
        copilot.logger:debug("Starting action: " .. self:toString())
        self.callback(...)
      end)
    else
      copilot.logger:debug("Starting action: " .. self:toString())
      self.currentThread = coroutine.create(self.callback)
    end
    Action.threads[self.currentThread] = self
    return true
  end
end

function Action:removeThread()
  Action.threads[self.currentThread] = nil
  self.currentThread = nil
end

function Action:resumeThread(...)
  if not self.currentThread then return false end
  local _, err = coroutine.resume(self.currentThread, ...)
  if err then
    self:removeThread()
    error(err) 
  end
  if coroutine.status(self.currentThread) == "dead" then
    self:removeThread()
    return false
  end
  return true
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
    self:removeThread()
    copilot.logger:debug("Stopping action: " .. self:toString())
    if self.cleanUpCallback then self.cleanUpCallback() end
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