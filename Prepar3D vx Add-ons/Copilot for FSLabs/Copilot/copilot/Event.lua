if false then module "Event" end

local Ouroboros = require "Copilot.libs.ouroboros"
local copilot = copilot
local util = require "FSL2Lua.FSL2Lua.util"

Event = {
  logPrefix = "Event",
  events = {},
  voiceCommands = {}, 
  dispatchQueue = {},
  queueMin = 1,
  queueMax = 0,
  NOLOGMSG = {}
}
Action = Action or require "copilot.Action"

--- @type Event

--- Constructor
--- @tparam[opt] table args A table containing the following fields:
-- @param[opt] args.action Function or <a href="#Class_Action">Action</a> or array of either that will be executed when the event is triggered.  
-- If it's an array of functions, each function can optionally be followed by string 'runAsCoroutine'.  
-- Actions can also be added to an existing event via @{Event.Event.addAction}.
-- @string[opt] args.logMsg Message that will be logged when the event is triggered.
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

function Event:new(args)
  self.__index = self
  local event = setmetatable(args or {}, self)
  event.actions = Ouroboros.new()
  event.sortedActions = {}
  event.coroDepends = {}
  event.areActionsSorted = true
  event.runOnce = {}
  event.children = setmetatable({}, {__mode = "k"})
  if event.action then
    if type(event.action) == "function" then
      event:addAction(event.action)
    elseif type(event.action) == "table" then
      if util.isType(event.action, Action) then
        event:addAction(event.action)
      else
        for i, v in ipairs(event.action) do
          if type(v) == "function" then
            local flags = event.action[i+1]
            if type(flags) == "function" then
              flags = nil
            end
            event:addAction(v, flags)
          elseif type(v) == "table" and util.isType(v, Action) then
            event:addAction(v)
          end
        end
      end
    end
    event.action = nil
  end
  util.setOnGCcallback(event, function() 
    copilot.logger:trace("Event gc: " .. event:toString()) 
  end)
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
--- @param ... Either a function with the optional flag 'runAsCoroutine' as the second argument or an <a href="#Class_Action">Action</a>.
--- @usage
-- myEvent:addAction(function() end, 'runAsCoroutine')
--- @return The added <a href="#Class_Action">Action</a>.
function Event:addAction(...)
  local args = {...}
  local action
  if util.isType(args[1], Action) then
    action = args[1]
  elseif util.isCallable(args[1]) then
    action = Action:new(...)
  end
  util.assert(util.isType(action, Action), "Failed to create action", 2)
  self.actions.nodes[action] = {}
  if self.areActionsSorted then
    self.sortedActions[#self.sortedActions+1] = action
  end
  self.coroDepends[action] = {}
  action:_onAddedToEvent(self)
  return action
end

--- Same as @{addAction} but the action will be removed from event's action list after it's executed once.
function Event:addOneOffAction(...)
  local action = self:addAction(...)
  self.runOnce[action] = true
  return action
end

function Event:sortActions()
  if self.inDispatch then
    error("Can't sort actions while actions are running", 2)
  end
  self.sortedActions = self.actions:sort()
  if self.sortedActions == nil then
    error("Unable to sort actions in event '" .. self:toString() .. "' due to cyclic dependencies.", 2)
  end
  self.areActionsSorted = true
end

--- <span>
--- @param action An <a href="#Class_Action">Action</a> that was added to this event.
--- @usage
-- local myAction = myEvent:addAction(function() end)
-- myEvent:removeAction(myAction)
---@return self
function Event:removeAction(action)
  if self.inDispatch then
    self.actionsToRemove[#self.actionsToRemove+1] = action
    return self
  end
  for i, a in ipairs(self.sortedActions) do
    if action == a then
      table.remove(self.sortedActions, i)
      break
    end
  end
  self.actions.nodes[action] = nil
  self.runOnce[action] = nil
  self.coroDepends[action] = nil
  action:_onRemovedFromEvent(self)
  return self
end

function Event:getActionCount() 
  if not self.areActionsSorted then self:sortActions() end
  return #self.sortedActions
end

function Event:_runCoroutineAction(action, ...)
  if action:isThreadRunning() then return false end
  action:_initNewThread(
    #self.coroDepends[action] > 0 and self.coroDepends[action] or nil,
    ...
  )
  return true
end

function Event:_runAction(action, ...)
  if action.isEnabled then
    if action.runAsCoroutine then self:_runCoroutineAction(action, self, ...)
    else action:_runFuncCallback(self, ...) end
    return true
  end
  return false
end

function Event.processEventQueue()
  local oldMax = Event.queueMax
  for i = Event.queueMin, Event.queueMax do
    local e = Event.dispatchQueue[i]
    e.event:dispatch(unpack(e.payload))
    Event.dispatchQueue[i] = nil
  end
  Event.queueMin = Event.queueMax
  if oldMax == Event.queueMax then
    copilot.removeCallback(Event.processEventQueue)
  end
end

function Event:enqueue(...)
  local queueIdx = Event.queueMax + 1
  Event.queueMax = queueIdx
  Event.dispatchQueue[queueIdx] = {event = self, payload = {...}}
  if Event.queueMin == Event.queueMax then
    copilot.addCallback(Event.processEventQueue)
  end
end

function Event:dispatch(...)
  self.inDispatch = true
  if self.logMsg ~= self.NOLOGMSG then
    copilot.logger:debug(("%s: %s"):format(self.logPrefix, self:toString()))
  end
  if not self.areActionsSorted then self:sortActions() end
  self.actionsToRemove = {}
  for _, action in ipairs(self.sortedActions) do
    if self:_runAction(action, ...) and self.runOnce[action] then
      self.actionsToRemove[#self.actionsToRemove+1] = action
    end
  end
  self.inDispatch = false
  for _, action in ipairs(self.actionsToRemove) do 
    self:removeAction(action)  
  end
  self.actionsToRemove = nil
end

--- Triggers the event which in turn executes all actions (if they are enabled). 
--- @param ... Any number of arguments that will be passed to each listener as the event's payload (following the first argument, which is always the event itself)
function Event:trigger(...)
  if self.inDispatch then
    self:enqueue(...)
  else
    self:dispatch(...)
  end
  for child in pairs(self.children) do
    child:trigger()
  end
end

Event.TIMEOUT = setmetatable({}, {__tostring = function() return "Event.TIMEOUT" end})
Event.INFINITE = {}
local NO_PAYLOAD = {}

---Waits for an event or returns a function that tells whether the event was signaled.
---@static
---@param event <a href="#Class_Event">Event</a>
---@bool[opt=false] returnFunction 
---@usage Event.waitForEvent(copilot.events.landing)
---@return If returnFunction is false, waitForEvent waits for the event itself and returns you its payload.
--- If returnFunction is true, waitForEvent returns a function that returns:<br>
--- 1. Boolean that indicates whether the event was signaled<br>
--- 2. Function that returns the event's payload.
function Event.waitForEvent(event, returnFunction)

  if not returnFunction then 
    local _, getPayload = Event.waitForEventWithTimeout(Event.INFINITE, event)
    return getPayload()
  end

  local getPayload

  local a = event:addOneOffAction(function(_, ...) 
    local payload = {...}
    getPayload = function() return unpack(payload) end
  end)

  a:addLogMsg("waitForEvent signal for event: " .. event:toString())
  
  local checkEvent = setmetatable({}, {
    __call = function ()
      if getPayload then return true, getPayload end
      return false
    end
  })

  util.setOnGCcallback(checkEvent, function() event:removeAction(a) end)
  return checkEvent
end

local function checkCallingThread()
  local thread = coroutine.running()
  if not copilot.getCallbackStatus(thread) then
    error "waitForEvent functions must be called from a Copilot-managed coroutine"
  end
  return thread
end

--- Waits for the event or until the timeout is elapsed.
---@static
---@int timeout Timeout in milliseconds
---@param event <a href="#Class_Event">Event</a>
---@return True if the event was signaled or Event.TIMEOUT
---@return Function that returns the event's payload.
function Event.waitForEventWithTimeout(timeout, event)

  local callingThread = checkCallingThread()
  local getPayload
  local action = event:addOneOffAction(function(_, ...) 
    local payload = {...}
    getPayload = function() return unpack(payload) end
    copilot.cancelCallbackTimeout(callingThread)
  end)

  copilot.getThreadEvent(callingThread):addOneOffAction(function(_, res)
    if res == copilot.THREAD_REMOVED then
      event:removeAction(action)
    end
  end)

  if not getPayload and (type(timeout) ~= "number" or timeout > 0)  then
    copilot.setCallbackTimeout(
      callingThread,
      timeout == Event.INFINITE and copilot.INFINITE or timeout
    )
  end

  if getPayload then return true, getPayload end
  
  event:removeAction(action)
  return Event.TIMEOUT
end

---Same as `waitForEvent` but for multiple events
---@static
---@tparam table events Array of <a href="#Class_Event">Event</a>'s.
---@bool[opt=false] waitForAll
---@bool[opt=false] returnFunction 
---@return If returnFunction is false:
---
--- * If waitForall is true: Table with events as keys and functions that return their payload as values.
--- * If waitForAll is false: The first event that was signaled.
---
---If returnFunction is true, a function that returns the following values: 
---
--- * If waitForall is true:
---     1. Boolean that indicates whether all events were signaled.
---     2. Table with events as keys and functions that return their payload as values.
---  * If waitForAll is false:
---     1. An event that was signaled or nil.
---     2. Function that returns the signaled event's payload.
---@return Only when returnFunction and waitForAll are false: Function that returns the signaled event's payload.
function Event.waitForEvents(events, waitForAll, returnFunction)

  if not returnFunction then
    if waitForAll then
      local _, payloadGetters = Event.waitForEventsWithTimeout(Event.INFINITE, events, true) 
      return payloadGetters
    else
      return Event.waitForEventsWithTimeout(Event.INFINITE, events, false) 
    end
  end

  local payloadGetters = setmetatable({}, {__mode = "k"})
  local actions = setmetatable({}, {__mode = "k"})

  for _, event in ipairs(events) do
    payloadGetters[event] = NO_PAYLOAD
    actions[event] = event:addOneOffAction(function(_, ...)
      local payload = {...}
      payloadGetters[event] = function() return unpack(payload) end
    end)
    actions[event]:addLogMsg("waitForEvents signal for event: " .. event:toString())
  end

  local checkEvents = setmetatable({}, {})

  util.setOnGCcallback(checkEvents, function()
    for e, a in pairs(actions) do e:removeAction(a) end
  end)

  if waitForAll then
    getmetatable(checkEvents).__call = function()
      for _, getPayload in pairs(payloadGetters) do
        if getPayload == NO_PAYLOAD then return false end
      end
      return true, payloadGetters
    end
  else
    getmetatable(checkEvents).__call = function()
      for event, getPayload in pairs(payloadGetters) do
        if getPayload ~= NO_PAYLOAD then
          payloadGetters[event] = NO_PAYLOAD
          return event, getPayload
        end
      end
    end
  end

  return checkEvents
end

--- Waits for multiple events or until the timeout is elapsed.
---@static
---@int timeout Timeout in milliseconds
---@param events Array of <a href="#Class_Event">Event</a>'s
---@bool[opt=false] waitForAll Whether to wait for any event or all events to be signaled.
---@return If waitForAll is true: Table with events as keys and functions that return their payload as values or Event.TIMEOUT<br>
--- If waitForAll is false: The first event that was signaled or Event.TIMEOUT
---@return If waitForAll is false: Function that returns the signaled event's payload.
function Event.waitForEventsWithTimeout(timeout, events, waitForAll)

  local payloadGetters = {}
  local actions = {}
  local numEvents, numSignaled = 0, 0
  local singleEvent, singleEventIdx

  local callingThread = checkCallingThread()

  copilot.getThreadEvent(callingThread):addOneOffAction(function(_, res)
    if res == copilot.THREAD_REMOVED then
      for e, a in pairs(actions) do e:removeAction(a) end
    end
  end)

  for i, event in ipairs(events) do

    numEvents = numEvents + 1
    payloadGetters[event] = NO_PAYLOAD

    actions[event] = event:addOneOffAction(function(_, ...)
      local payload = {...}
      payloadGetters[event] = function() return unpack(payload) end
      numSignaled = numSignaled + 1
      if not waitForAll or numSignaled == numEvents then
        copilot.cancelCallbackTimeout(callingThread)
      end
      if not waitForAll and not singleEvent then 
        singleEvent = event
        singleEventIdx = i
      end
    end)

    actions[event]:addLogMsg("waitForEvents signal for event: " .. event:toString())
  end

  local alreadySignaled =
    (not waitForAll and numSignaled > 0) or
    (waitForAll and numSignaled == numEvents)

  if not alreadySignaled and (type(timeout) ~= "number" or timeout > 0)  then
    copilot.setCallbackTimeout(
      callingThread,
      timeout == Event.INFINITE and copilot.INFINITE or timeout
    )
  end

  for e, a in pairs(actions) do e:removeAction(a) end
  
  if waitForAll and numSignaled == numEvents then
    return true, payloadGetters 
  elseif not waitForAll and singleEvent then 
    return singleEvent, payloadGetters[singleEvent], singleEventIdx
  end

  return Event.TIMEOUT
end

---Constructs an event from a key press.
---@static
---@param key See `FSL2Lua.Bind`
---@return <a href="#Class_Event">Event</a>
function Event.fromKeyPress(key)
  local e = Event:new {logMsg = Event.NOLOGMSG}
  local weakRef = setmetatable({e = e}, {__mode = "v"})
  e._keyBind = Bind {
    key = key, 
    dispose = true,
    onPress = function(...) if weakRef.e then weakRef.e:trigger(...) end end,
  }
  return e
end

require "copilot.SingleEvent"

--- Constructs an event from a TextMenu. The menu is shown immediately.
--- @static
--- @string title The title of the menu
--- @string prompt The message that is displayed between the title and the items. Empty string is allowed.
--- @tparam table items Array of strings representing the menu items
--- @int[opt=0] timeout The menu's timeout. 0 means infinite timeout.
--- @return An <a href="#Class_SingleEvent">SingleEvent</a>. The event will produce the following payload values:  
---
--- 1. The result. One of these:<br>
---    * TextMenuResult.OK
---    * TextMenuResult.Replaced
---    * TextMenuResult.Removed
---    * TextMenuResult.Timeout
--- 2. The index of the selected item.
--- 3. The selected item as a string.
function Event.fromTextMenu(title, prompt, items, timeout)
  timeout = timeout or 0
  local e = SingleEvent:new {logMsg = Event.NOLOGMSG}
  local function callback(res, itemIdx, item)
    e:trigger(res, itemIdx, item)
  end
  local menu = TextMenu.new(title, prompt, items, timeout, callback)
  menu:show()
  return e
end

require "copilot.ActionOrderSetter"
return Event