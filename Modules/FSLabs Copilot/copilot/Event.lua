----
-- @module Event

local function removeEventRef(self, refType, ...)
  if refType == "all" then
    for _, refTable in pairs(self.eventRefs) do
      for event, action in pairs(refTable) do
        event:removeAction(action)
      end
    end
  else
    for _, event in ipairs {...} do
      event:removeAction(self.eventRefs[refType][event])
    end
  end
end

local function makeEventRef(self, func, refType, ...)
  for _, event in ipairs {...}  do
    self.eventRefs[refType][event] = event:addAction(func)
  end
end

--- @type Action

Action = {}
local Action = Action

--- Constructor
--- @tparam function callback
--- @string[opt] flags 'runAsCoroutine'

function Action:new(callback, flags)
  self.__index = self
  return setmetatable ({
    callback = callback,
    isEnabled = true,
    isAction = true,
    runAsCoroutine = flags == "runAsCoroutine",
    eventRefs = {stop = {}}
  }, self)
end

--- Enables or disables the action.
--- @bool value True to enable the action, false to disable.

function Action:setEnabled(value)
  self.isEnabled = value
end

function Action:runCallback(...)
  if self.logMsg then
    copilot.logger:debug("Starting action: " .. self.logMsg)
  end
  self.callback(...)
end

function Action:createThread()
  if not self.activeThread then
    if self.logMsg then
      copilot.logger:debug("Starting action: " .. self.logMsg)
    end
    self.activeThread = coroutine.create(self.callback)
    return true
  end
end

function Action:resumeActiveThread(...)
  if not self.activeThread then return false end
  local _, err = coroutine.resume(self.activeThread, ...)
  if err then copilot.exit(err) end
  if coroutine.status(self.activeThread) == "dead" then
    self.activeThread = nil
    return false
  end
  return true
end

--- Use this you want to disable the effect of @{stopOn} for one of the predefined actions in @{copilot.actions}
--- @function removeEventRef
--- @string refType 'stop'
--- @param ... one or more <a href="#Class_Event">Event</a> object
--- @usage copilot.actions.preflight:removeEventRef('stop', copilot.events.enginesStarted)

Action.removeEventRef = removeEventRef

--- If the 'runAsCoroutine' flag was passed to the constructor, stops the execution of the currently running coroutine immediately.

function Action:stopCurrent()
  if self.activeThread then
    self.activeThread = nil
    if self.logMsg then
      copilot.logger:debug("Stopping action: " .. self.logMsg)
    end
    if self.cleanUp then self.cleanUp() end
  end
end

Action.makeEventRef = makeEventRef

--- <span>
--- @param ... One or more events. If the 'runAsCoroutine' flag was passed to the constructor, the callback coroutine will be stopped when these events are triggered. 
--- @usage myAction:stopOn(copilot.events.takeoffAborted, copilot.events.takeoffCancelled)
--- @return self

function Action:stopOn(...)
  self:makeEventRef(function() self:stopCurrent() end, "stop", ...)
  return self
end

--- Can be used when the action can be stopped - function func will be executed when the action is stopped.
--- @tparam function func
--- @return self

function Action:addCleanup(func)
  self.cleanUp = func
  return self
end

--- Add log info that will be logged when the action is started or stopped
--- @string msg
--- @return self

function Action:addLogMsg(msg)
  self.logMsg = msg
  return self
end

--- @type Event

Event = {events = {}, voiceCommands = {}}

--- Constructor
--- @tparam[opt] table data A table containing the following fields:
-- @param[opt] data.action Function or <a href="#Class_Action">Action</a> object or array of functions or <a href="#Class_Action">Action</a> objects that will be executed when the event is triggered.  
-- If it's an array of functions, each function can optionally be followed by string 'runAsCoroutine'.  
-- Actions can also be added to an existing event via @{Event.Event.addAction}.
-- @string[opt] data.logMsg Message that will be logged when the event is triggered.
--- @usage
-- local event1 = Event:new {
--  action = function() print "test action" end,
--  logMsg = "test event"
-- }
--
-- local event2 = Event:new {
--  action = {
--    function() while true do print "coroutine 1" coroutine.yield() end, 'runAsCourutine',
--    function() while true do print "coroutine 2" coroutine.yield() end, 'runAsCourutine'
--  },
--  logMsg = "test event with coroutine actions"
-- }

function Event:new(data)
  self.__index = self
  local event = setmetatable(data or {}, self)
  event.actions = {}
  event.runOnce = {}
  event.activeThreads = {}
  if event.action then
    if type(event.action) == "function" then
      event:addAction(event.action)
    elseif type(event.action) == "table" then
      if event.action.isAction then
        event:addAction(event.action)
      else
        for i, v in ipairs(event.action) do
          if type(v) == "function" then
            local flags = event.action[i+1]
            if type(flags) == "function" then
              flags = nil
            end
            event:addAction(v, flags)
          elseif type(v) == "table" and v.isAction then
            event:addAction(event.action)
          end
        end
      end
    end
    event.action = nil
  end
  Event.events[event] = event
  return event
end

--- <span>
--- @param ... Either a function with the optional flag 'runAsCoroutine' as the second argument or an <a href="#Class_Action">Action</a> object.
--- @usage
-- myEvent:addAction(function() end, 'runAsCoroutine')
--- @return The added <a href="#Class_Action">Action</a> object.

function Event:addAction(...)
  local args = {...}
  local action
  if type(args[1]) == "table" then
    if args[1].isAction then
      action = args[1]
    end
  elseif type(args[1]) == "function" then
    action = Action:new(...)
  end
  self.actions[action] = action
  return action
end

--- Same as @{addAction} but the action will be removed from event's action list after it's executed once.

function Event:addOneOffAction(...)
  local action = self:addAction(...)
  self.runOnce[action] = action
  return action
end

--- <span>
--- @param action An <a href="#Class_Action">Action</a> object that was added to this event.
--- @usage
-- local myAction = myEvent:addAction(function() end)
-- myEvent:removeAction(myAction)

function Event:removeAction(action)
  self.actions[action] = nil
  self.runOnce[action] = nil
end

function Event:getActionCount() 
  local count = 0
  for action in pairs(self.actions) do
    if type(action) == "table" and getmetatable(action) == Action then
      count = count + 1
    end
  end
  return count
end

--- Triggers the event which in turn executes all actions (if they are enabled). 
--- @param ... Any number of arguments that will be passed to each callback. The callbacks will also receive the event as the first parameter.

function Event:trigger(...)
  if self.logMsg then copilot.logger:debug("Event: " .. self.logMsg) end
  for action in pairs(self.actions) do
    if action.isEnabled then
      if action.runAsCoroutine then
        if action:createThread() then
          self.activeThreads[action] = action
          self:resumeThread(action, ...)
        end
      else
        action:runCallback(self, ...)
      end
      if self.runOnce[action] then
        self:removeAction(action)
      end
    end
  end
end

function Event:resumeThread(action, ...)
  if not action:resumeActiveThread(self, ...) then
    self.activeThreads[action] = nil
  end
end

function Event:processThreads()
  for action in pairs(self.activeThreads) do
    self:resumeThread(action)
  end
end

function Event:stopCurrentActions()
  for action in pairs(self.actions) do
    action:stopCurrent()
  end
end

function Event:fetchRecoResult()
  local ruleID = copilot.recoResultFetcher:getResult()
  if ruleID then
    self.voiceCommands[ruleID]:trigger()
  end
end

function Event:runThreads()
  for event in pairs(self.events) do
    event:processThreads()
  end
end

---static method
---@param event an <a href="#Class_Event">Event</a> object
---@bool returnFunction If true, returns a function that returns true once the event gets triggered, else waits for that event itself.
---@usage
-- Event.waitForEvent(copilot.events.landing)

function Event:waitForEvent(event, returnFunction)
  local isEventTriggered = false
  event:addOneOffAction(function()
    isEventTriggered = true
  end)
  if returnFunction then
    return function() return isEventTriggered end
  else
    repeat copilot.suspend() until isEventTriggered
  end
end

--- Static method - same as @{waitForEvent} but for multiple events
---@tparam table events array of <a href="#Class_Event">Event</a> objects
---@bool[opt=false] waitForAll
---@treturn function if waitForAll is true, this function works the same as the one returned by @{waitForEvent} and returns true once all events have been triggered
--
-- Otherwise, for every event that has been triggered, it returns the event object

function Event:waitForEvents(events, waitForAll, returnFunction)

  local flags = {}

  for _, event in ipairs(events) do
    flags[event] = false
    event:addOneOffAction(function()
      flags[event] = true
    end)
  end

  if waitForAll then
    local function areEventsTriggered()
      for _, flag in pairs(flags) do
        if flag == false then return false end
      end
      return true
    end
    if returnFunction then
      return areEventsTriggered
    else
      repeat copilot.suspend() until areEventsTriggered()
    end
  else
    return function()
      for event, flag in pairs(flags) do
        if flag == true then
          flags[event] = false
          return event
        end
      end
    end
  end

end

local recognizer = copilot.recognizer

--- VoiceCommand is a subclass of <a href="#Class_Event">Event</a>.
--
-- A voice command can be in one of these  states:
--
-- 1. Deactivated: the phrases aren't in the recognizer's grammar.
--
-- 2. Ignore mode: the phrases are in the recognizer's grammar but recognition events don't trigger the voice command.
--
-- 3. Active: the phrases are in the recognizer's grammar and Copilot triggers the voice command.
--
-- If you only have a couple of phrases in the recognizer, especially short ones, the accuracy will be low and
-- the recognizer will recognize just about anything as those phrases. On the other hand, having a lot of phrases
-- will also degrade the accuracy.
--
--- @type VoiceCommand
VoiceCommand = {Status = {active = 1, ignore = 2, inactive = 3}}
setmetatable(VoiceCommand, {__index = Event})

--- Constructor
--- @param data A table containing the following fields (also the fields taken by @{Event:new|the parent constructor}):
--  @param data.phrase string or array of strings
--  @number[opt=0.93] data.confidence between 0 and 1
--  @param[opt=false] data.persistent
-- * ommited or false: the voice command will be deactivated after being triggered.
-- * 'ignore': the voice command will be put into ignore mode after being triggered.
-- * true: the voice command will stay active after being triggered.
--- @usage
-- local myVoiceCommand = VoiceCommand:new {
--  phrase = "hello",
--  confidence = 0.95,
--  action = function() print "hi there" end
-- }

function VoiceCommand:new(data)
  local voiceCommand = data
  voiceCommand.confidence = (voiceCommand.confidence or 0.93) * copilot.UserOptions.voice_control.confidence_coefficient
  voiceCommand.phrase = type(data.phrase) == "table" and data.phrase or {data.phrase}
  voiceCommand.ruleID = recognizer:addRule(voiceCommand.phrase, voiceCommand.confidence)
  voiceCommand.status = self.Status.inactive
  Event.voiceCommands[voiceCommand.ruleID] = voiceCommand
  voiceCommand.eventRefs = {activate = {}, deactivate = {}, ignore = {}}
  self.__index = self
  return setmetatable(Event:new(voiceCommand), self)
end

---<span>
---@return self

function VoiceCommand:activate()
  if self.status ~= self.Status.active then
    copilot.logger:debug("Activating voice command: " .. self.phrase[1])
    recognizer:activateRule(self.ruleID)
    self.status = self.Status.active
  end
  return self
end

---<span>
---@return self

function VoiceCommand:ignore()
  if self.status ~= self.Status.ignore then
    copilot.logger:debug("Starting ignore mode for voice command: " .. self.phrase[1])
    recognizer:ignoreRule(self.ruleID)
    self.status = self.Status.ignore
  end
  return self
end

---<span>
---@return self

function VoiceCommand:deactivate()
  if self.status ~= self.Status.inactive then
    copilot.logger:debug("Deactivating voice command: " .. self.phrase[1])
    recognizer:deactivateRule(self.ruleID)
    self.status = self.Status.inactive
  end
  return self
end

function VoiceCommand:trigger()
  Event.trigger(self)
  if not self.persistent then
    self:deactivate()
  elseif self.persistent == "ignore" then
    self:ignore()
  end
end

function VoiceCommand:react(plus)
  ipc.sleep(math.random(80, 120) * 0.01 * (500 + (plus or 0)))
end

VoiceCommand.makeEventRef = makeEventRef

--- The voice command will become active when the events passed as parameters are triggered.
--
--- Adds an 'activate' event reference that can be removed from the event via @{removeEventRef}
--- @param ...  one or more events

function VoiceCommand:activateOn(...)
  self:makeEventRef(function() self:activate() end, "activate", ...)
  return self
end

--- The voice command will be deactivated when the events passed as parameters are triggered.
--
--- Adds a 'deactivate' event reference that can be removed from the event via @{removeEventRef}
--- @param ...  one or more events

function VoiceCommand:deactivateOn(...)
  self:makeEventRef(function() self:deactivate() end, "deactivate", ...)
  return self
end

--- The voice command will go into ignore mode when the events passed as parameters
--
--- are triggered.
--
--- Adds a 'ignore' event reference that can be removed from the event via @{removeEventRef}
--- @param ...  one or more events

function VoiceCommand:ignoreOn(...)
  self:makeEventRef(function() self:ignore() end, "ignore", ...)
  return self
end

--- Use this you want to disable the effect of @{activateOn}, @{deactivateOn} or @{ignore} for one of the predefined voice commands in @{copilot.voiceCommands}
--- @function removeEventRef
--- @string refType 'activate', 'deactivate' or 'ignore'
--- @param ... one or more <a href="#Class_Event">Event</a> objects
--- @usage copilot.voiceCommands.gearUp:removeEventRef('activate',
--copilot.events.goAround, copilot.events.takeoffInitiated)

VoiceCommand.removeEventRef = removeEventRef
