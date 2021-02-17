---- Copilot's event library.
-- @module Event

local Ouroboros = require "FSLabs Copilot.libs.ouroboros"
local coroutine = coroutine
local copilot = copilot

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

Action = {threads = {}}
local Action = Action

--- Constructor
--- @tparam function callback
--- @string[opt] flags 'runAsCoroutine'

function Action:new(callback, flags)
  self.__index = self
  if not (type(callback) == "function" or getmetatable(callback) and getmetatable(callback).__call) then
    error("Action callback must be a callable", 2)
  end
  return setmetatable ({
    callback = type(callback) == "function" and callback or function(...) getmetatable(callback).__call(callback, ...) end,
    isEnabled = true,
    runAsCoroutine = flags == "runAsCoroutine",
    eventRefs = {stop = {}}
  }, self)
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
--- @param ... one or more <a href="#Class_Event">Event</a> object
--- @usage copilot.actions.preflight:removeEventRef('stop', copilot.events.enginesStarted)

Action.removeEventRef = removeEventRef

--- If the action was configured to be run as a coroutine, stops the execution of the currently running coroutine immediately.

function Action:stopCurrentThread()
  if self.currentThread then
    self:removeThread()
    copilot.logger:debug("Stopping action: " .. self:toString())
    if self.cleanUpCallback then self.cleanUpCallback() end
  end
end

Action.makeEventRef = makeEventRef

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

--- @type Event

Event = {events = {}, voiceCommands = {}, runningThreads = {}}

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
  event.actions = Ouroboros.new()
  event.sortedActions = {}
  event.coroDepends = {}
  event.areActionsSorted = true
  event.runOnce = {}
  if event.action then
    if type(event.action) == "function" then
      event:addAction(event.action)
    elseif type(event.action) == "table" then
      if getmetatable(event.action) == Action then
        event:addAction(event.action)
      else
        for i, v in ipairs(event.action) do
          if type(v) == "function" then
            local flags = event.action[i+1]
            if type(flags) == "function" then
              flags = nil
            end
            event:addAction(v, flags)
          elseif type(v) == "table" and getmetatable(v) == Action then
            event:addAction(v)
          end
        end
      end
    end
    event.action = nil
  end
  Event.events[event] = event
  return event
end

function Event:toString()
  return self.logMsg or tostring(self):gsub("table: 0+", "")
end

function Event:getActions()
  if not self.areActionsSorted then self:sortActions() end
  local copy = {}
  for i, action in ipairs(self.sortedActions) do
    copy[i] = action
  end
  return copy
end

--- <span>
--- @param ... Either a function with the optional flag 'runAsCoroutine' as the second argument or an <a href="#Class_Action">Action</a> object.
--- @usage
-- myEvent:addAction(function() end, 'runAsCoroutine')
--- @return The added <a href="#Class_Action">Action</a> object.

function Event:addAction(...)
  local args = {...}
  local action
  if type(args[1]) == "table" and getmetatable(args[1]) == Action then
    action = args[1]
  elseif type(args[1]) == "function" or (type(args[1]) == "table" and getmetatable(args[1]).__call) then
    action = Action:new(...)
  end
  if action == nil then
    error("Failed to create action", 2)
  end
  self.actions.nodes[action] = {}
  if self.areActionsSorted then
    self.sortedActions[#self.sortedActions+1] = action
  end
  self.coroDepends[action] = {}
  return action
end

function Event:sortActions()
  if (self.runningActions) then
    error("Can't sort actions while actions are running", 2)
  end
  self.sortedActions = self.actions:sort()
  if self.sortedActions == nil then
    error("Unable to sort actions in event '" .. self:toString() .. "' due to cyclic dependencies.", 2)
  end
  self.areActionsSorted = true
end

local OrderSetter = {}

function OrderSetter._checkCoro(action)
  if not action.runAsCoroutine then
    error("Action " .. action:toString() .. " needs to be a coroutine in order to wait for other coroutines to complete", 3)
  end
end

function OrderSetter:front(wait)
  local nodes = self.event.actions.nodes
  for otherAction in pairs(nodes) do
    if otherAction ~= self.anchor then
      nodes[otherAction][self.anchor] = true
      if wait ~= false and self.anchor.runAsCoroutine then
        self._checkCoro(otherAction)
        local depends = self.event.coroDepends[otherAction]
        depends[#depends+1] = self.anchor
      end
    end
  end
  self.event.areActionsSorted = false
end

function OrderSetter:back(wait)
  local nodes = self.event.actions.nodes
  for otherAction in pairs(nodes) do
    if otherAction ~= self.anchor then
      nodes[self.anchor][otherAction] = true
      if wait ~= false and otherAction.runAsCoroutine then
        self._checkCoro(self.anchor)
        local depends = self.event.coroDepends[self.anchor]
        depends[#depends+1] = otherAction
      end
    end
  end
  self.event.areActionsSorted = false
end

function OrderSetter:before(...)
  local nodes = self.event.actions.nodes
  local args = {...}
  local lastArg = args[#args]
  for _, otherAction in ipairs {...} do
    if getmetatable(otherAction) == Action then
      nodes[otherAction][self.anchor] = true
      if lastArg ~= false and self.anchor.runAsCoroutine then
        self._checkCoro(otherAction)
        local depends = self.event.coroDepends[otherAction]
        depends[#depends+1] = self.anchor
      end
    end
  end
  self.event.areActionsSorted = false
  return self
end

function OrderSetter:after(...)
  local node = self.event.actions.nodes[self.anchor]
  local args = {...}
  local lastArg = args[#args]
  for _, otherAction in ipairs {...} do
    if getmetatable(otherAction) == Action then
      node[otherAction] = true
      if lastArg ~= false and otherAction.runAsCoroutine then
        self._checkCoro(self.anchor)
        local depends = self.event.coroDepends[self.anchor]
        depends[#depends+1] = otherAction
      end
    end
  end
  self.event.areActionsSorted = false
  return self
end

--- Sets order of the event's actions relative to each other.
---@param action An action object which will serve as an anchor for positioning other actions in front or after it.
---@return A table with four functions: 'front', 'back', 'before' and 'after. 'Before' and 'after' take a variable
---number of Action objects. All four functions optionally take a boolean as the last parameter which defaults to true
-- if omitted. If the last parameter is true and both the anchor action and the other actions are coroutines,
-- the coroutines will not be run simultaneously.
--
-- An error will be thrown if there is a cycle in the ordering.
--- 
--- @usage
--local event = Event:new()
--
--local second = event:addAction(function() print "second" end)
--local first = event:addAction(function() print "first" end)
--local fourth = event:addAction(function() print "fourth" end)
--local third = event:addAction(function() print "third" end)
--
--event:trigger()
-- -- second
-- -- first
-- -- fourth
-- -- third
--
--print "--------------------------------------------------"
--
--event:setActionOrder(first):before(second)
--event:setActionOrder(second):before(third)
--event:setActionOrder(third):before(fourth)
--
-- --[[ 
--Another possibility:
--
--event:setActionOrder(first):front()
--event:setActionOrder(fourth):back()
--event:setActionOrder(second):after(first):before(third)
--
--]]
--
--event:trigger()
--
-- -- first
-- -- second
-- -- third
-- -- fourth
--
--print "--------------------------------------------------"
--
--event = event:new()
--
--second = event:addAction(function()
--  for _ = 1, 4 do coroutine.yield() end
--  print "second"
--end, "runAsCoroutine")
--
--first = event:addAction(function()
--  for _ = 1, 5 do coroutine.yield() end
--  print "first"
--end, "runAsCoroutine")
--
--fourth = event:addAction(function()
--  print "fourth"
--end, "runAsCoroutine")
--
--third = event:addAction(function()
--  for _ = 1, 3 do coroutine.yield() end
--  print "third"
--end, "runAsCoroutine")
--
--event:setActionOrder(second):before(third):after(first)
--event:setActionOrder(third):before(fourth)
--
--event:trigger()
--
-- -- first
-- -- second
-- -- third
-- -- fourth
--

function Event:setActionOrder(action)
  OrderSetter.__index = OrderSetter
  return setmetatable({event = self, anchor = action}, OrderSetter)
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
---@return self
function Event:removeAction(action)
  if self.runningActions then
    self.actionsToRemove[#self.actionsToRemove+1] = action
    return self
  end
  for i, _action in ipairs(self.sortedActions) do
    if action == _action then
      table.remove(self.sortedActions, i)
      break
    end
  end
  self.actions.nodes[action] = nil
  self.runOnce[action] = nil
  self.coroDepends[action] = nil
  return self
end

function Event:getActionCount() 
  if not self.areActionsSorted then self:sortActions() end
  return #self.sortedActions
end

--- Triggers the event which in turn executes all actions (if they are enabled). 
--- @param ... Any number of arguments that will be passed to each callback. The callbacks will also receive the event as the first parameter.
function Event:trigger(...)
  copilot.logger:debug("Event: " .. self:toString())
  if not self.areActionsSorted then
    self:sortActions()
  end
  self.actionsToRemove = {}
  self.runningActions = true
  for _, action in ipairs(self.sortedActions) do
    if action.isEnabled then
      if action.runAsCoroutine then
        local depends = self.coroDepends[action]
        if action:createThread(#depends == 0 and nil or depends) and action:resumeThread(self, ...) then
          Event.runningThreads[action] = action
        end
      else
        action:runCallback(self, ...)
      end
      if self.runOnce[action] then
        self.actionsToRemove[#self.actionsToRemove+1] = action
      end
    end
  end
  self.runningActions = false
  for _, action in ipairs(self.actionsToRemove) do
    self:removeAction(action)
  end
  self.actionsToRemove = nil
end

function Event.fetchRecoResults()
  for _, ruleID in ipairs(copilot.recoResultFetcher:getResults()) do
    Event.voiceCommands[ruleID]:trigger()
  end
end

function Event.resumeThreads()
  for action in pairs(Event.runningThreads) do
    if not action:resumeThread() then
      Event.runningThreads[action] = nil
    end
  end
end

---<span>
---@static
---@param event an <a href="#Class_Event">Event</a> object
---@bool returnFunction If true, waitForEvent returns a function that returns true once the event gets triggered, else waitForEvent returns when the event is triggered.
---@usage Event.waitForEvent(copilot.events.landing)
function Event.waitForEvent(event, returnFunction)
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

Event.TIMEOUT = {}
Event.INFINITE = {}

function Event.fromKeyPress(key, ...)
  local event = Event:new(...)
  Bind {key = key, onPress = function() event:trigger() end}
  return event
end

function Event.waitForEventWithTimeout(timeout, event)
  if timeout == Event.INFINITE then
    return Event.waitForEvent(event)
  end
  local isEventSignaled = Event.waitForEvent(event, true)
  local timedOut = not checkWithTimeout(timeout, function()
    copilot.suspend()
    return isEventSignaled()
  end)
  if timedOut then return 
    Event.TIMEOUT 
  end
end

function Event.waitForEventsWithTimeout(timeout, events, waitForAll)
  if timeout == Event.INFINITE then
    return Event.waitForEvents(events, waitForAll, false)
  end
  local checkEvents = Event.waitForEvents(events, waitForAll, true)
  local res = withTimeout(timeout, function()
    copilot.suspend()
    return checkEvents() or nil
  end)
  return res or Event.TIMEOUT
end

---Same as @{waitForEvent} but for multiple events
---@static
---@tparam table events array of <a href="#Class_Event">Event</a> objects
---@bool[opt=false] waitForAll
---@treturn function if waitForAll is true, this function works the same as the one returned by @{waitForEvent} and returns true once all events have been triggered
--
-- Otherwise, for every event that has been triggered, it returns the event object

function Event.waitForEvents(events, waitForAll, returnFunction)

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
    if returnFunction then return areEventsTriggered end
    repeat copilot.suspend() until areEventsTriggered()
  else
    local function checkEvents()
      for event, flag in pairs(flags) do
        if flag == true then
          flags[event] = false
          return event
        end
      end
    end
    if returnFunction then return checkEvents end
    while true do
      copilot.suspend()
      local event = checkEvents()
      if event then return event end
    end
  end
end

local recognizer = copilot.recognizer

--- VoiceCommand is a subclass of <a href="#Class_Event">Event</a>.
--
-- A voice command can be in one of these  states:
--
-- * Active
--
-- * Inactive
--
-- * Ignore mode: the phrases are active in the recognizer but recognition events don't trigger the voice command.
--
-- If you only have a couple of phrases active in the recognizer at a given time, especially short ones, the accuracy will be low and
-- the recognizer will recognize just about anything as those phrases. On the other hand, having a lot of active phrases
-- will also degrade the quality of recognition.<br>
--
--- @type VoiceCommand
VoiceCommand = {DefaultConfidence = 0.93}
setmetatable(VoiceCommand, {__index = Event})

local PersistenceMode = {
  ignore = RulePersistenceMode.Ignore,
  [true] = RulePersistenceMode.Persistent,
  [false] = RulePersistenceMode.NonPersistent
}

local function _persistenceMode(persistence)
  if persistence == nil then
    return RulePersistenceMode.NonPersistent
  else
    return PersistenceMode[persistence] or error("Invalid persistence mode", 3)
  end
end

--- Constructor
--- @param data A table containing the following fields (also the fields taken by @{Event:new|the parent constructor}):
--  @param data.phrase string or array of strings. @{addPhrase|You can modify the required confidence of each word in the phrase}
--  @param data.dummy string or array of strings. One or multiple dummy phrase variants which will activated and deactivated 
-- synchronously with the voice command's actual phrase variants to help the recognizer discriminate between them and similarly 
-- sounding phrases. For example, the default 'takeoff' voice command has a 'takeoff runway' dummy phrase which is an item on the
-- standard takeoff checklist. 
--  @number[opt=0.93] data.confidence between 0 and 1
--  @param[opt=false] data.persistent
-- * omitted or false: the voice command will be deactivated after being triggered.
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
  voiceCommand.confidence = data.confidence or VoiceCommand.DefaultConfidence
  voiceCommand.phrase = type(data.phrase) == "table" and data.phrase or {data.phrase}
  if copilot.isVoiceControlEnabled then
    voiceCommand.ruleID = recognizer:addRule(voiceCommand.phrase,
                                             voiceCommand.confidence,
                                             _persistenceMode(data.persistent))
    voiceCommand.persistent = nil
    Event.voiceCommands[voiceCommand.ruleID] = voiceCommand
  end
  voiceCommand.phrase = nil
  voiceCommand.eventRefs = {activate = {}, deactivate = {}, ignore = {}}
  self.__index = self
  voiceCommand = setmetatable(Event:new(voiceCommand), self)
  if data.dummy then
    voiceCommand:addPhrase(data.dummy, true)
    voiceCommand.dummy = nil
  end
  return voiceCommand
end

--- Call this static function inside a plugin lua file before activating or deactivating voice commands.
---@static
function VoiceCommand.resetGrammar()
  if not VoiceCommand.isGrammarReset then
    recognizer:resetGrammar()
    VoiceCommand.isGrammarReset = true
  end
end

--- Returns all phrase variants of a voice command.
---@bool dummy True to return dummy phrase variants, omitted or false to return actual phrase variants.
---@return Array of strings.
function VoiceCommand:getPhrases(dummy)
  return recognizer:getPhrases(self.ruleID, dummy == true and true or false)
end

--- Sets persistence mode of a voice command.
---@param persistenceMode
-- * omitted or false: the voice command will be deactivated after being triggered.
-- * 'ignore': the voice command will be put into ignore mode after being triggered.
-- * true: the voice command will stay active after being triggered.
---@return self
function VoiceCommand:setPersistence(persistenceMode)
  recognizer:setRulePersistence(_persistenceMode(persistenceMode), self.ruleID)
  return self
end

--- Adds phrase variants to a voice command.
--
---The SAPI recognizer has two confidence metrics - a float from 0-1 and another one that has three states: low, normal and high.
---If a word is preceded by a '+' or '-', its required confidence is set to 'high' or 'low', respectively, otherwise, it has the default required confidence 'normal'.
---@param phrase string or array of strings
---@bool dummy True to add dummy phrase variants, omitted or false to add actual phrase variants.
---@return self
function VoiceCommand:addPhrase(phrase, dummy)
  phrase = type(phrase) == "table" and phrase or {phrase}
  recognizer:addPhrases(phrase, self.ruleID, dummy == true and true or false)
  return self
end

local function trimPhrase(phrase) return phrase:gsub("[%+%-]+(%S+)", "%1") end

--- Removes phrase variants from a voice command.
--- + and - in front of a word are ignored. For example, removePhrase("hello world") will remove both "+hello -world" and "hello world".
---@param phrase string or array of strings
---@bool dummy True to remove dummy phrase variants, omitted or false to remove actual phrase variants.
---@return self
function VoiceCommand:removePhrase(phrase, dummy)
  local phrasesToRemove = type(phrase) == "table" and phrase or {phrase}
  local deletthis = {}
  for _, phraseToRemove in ipairs(phrasesToRemove) do
   phraseToRemove = trimPhrase(phraseToRemove)
    for _, _phrase in ipairs(self:getPhrases(dummy == true and true or false)) do
      if phraseToRemove == _phrase then
        deletthis[#deletthis+1] = _phrase
      end
    end
  end
  recognizer:removePhrases(deletthis, self.ruleID, dummy == true and true or false)
  return self
end

--- Removes all phrase variants from a voice command.
---@bool dummy True to remove dummy phrase variants, omitted or false to remove actual phrase variants.
---@return self
function VoiceCommand:removeAllPhrases(dummy)
  recognizer:removeAllPhrases(self.ruleID, dummy == true and true or false)
  return self
end

--- Sets required confidence of a voice command.
--- @number confidence A number from 0-1
---@return self
function VoiceCommand:setConfidence(confidence)
  recognizer:setConfidence(confidence, self.ruleID)
  return self
end

---<span>
---@return self
function VoiceCommand:activate()
  if copilot.isVoiceControlEnabled then
    recognizer:activateRule(self.ruleID)
  end
  return self
end

---<span>
---@return self
function VoiceCommand:ignore()
  if copilot.isVoiceControlEnabled then
    recognizer:ignoreRule(self.ruleID)
  end
  return self
end

---<span>
---@return self
function VoiceCommand:deactivate()
  if copilot.isVoiceControlEnabled then
    recognizer:deactivateRule(self.ruleID)
  end
  return self
end

---Deactivates the voice command and makes successive calls to @{activate} and @{ignore} have no effect.
function VoiceCommand:disable()
  recognizer:disableRule(self.ruleID)
  return self
end

---If the voice command has only one action, returns that action. All default voice commands have only one action.
function VoiceCommand:getAction()
  if self:getActionCount() ~= 1 then
    error(string.format("Cannot get action of voice command %s - action count isn't 1", self:getPhrases()[1]), 2)
  end
  for action in pairs(self.actions.nodes) do return action end
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

--- Disables the effect of @{activateOn}, @{deactivateOn} or @{ignore} for the default voice commands in @{copilot.voiceCommands}
--- @function removeEventRef
--- @string refType 'activate', 'deactivate' or 'ignore'
--- @param ... one or more <a href="#Class_Event">Event</a> objects
--- @usage copilot.voiceCommands.gearUp:removeEventRef('activate',
--copilot.events.goAround, copilot.events.takeoffInitiated)

VoiceCommand.removeEventRef = removeEventRef
