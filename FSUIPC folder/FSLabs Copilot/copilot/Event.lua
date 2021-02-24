if false then module "Event" end

local Ouroboros = require "FSLabs Copilot.libs.ouroboros"
local copilot = copilot
local util = require "FSL2Lua.FSL2Lua.util"

Event = {events = {}, voiceCommands = {}, runningThreads = {}}
Action = Action or require "copilot.Action"

--- @type Event

--- Constructor
--- @tparam[opt] table data A table containing the following fields:
-- @param[opt] data.action Function or <a href="#Class_Action">Action</a> or array of either that will be executed when the event is triggered.  
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
  return action
end

function Event:sortActions()
  if self.runningActions then
    error("Can't sort actions while actions are running", 2)
  end
  self.sortedActions = self.actions:sort()
  if self.sortedActions == nil then
    error("Unable to sort actions in event '" .. self:toString() .. "' due to cyclic dependencies.", 2)
  end
  self.areActionsSorted = true
end

--- Same as @{addAction} but the action will be removed from event's action list after it's executed once.
function Event:addOneOffAction(...)
  local action = self:addAction(...)
  self.runOnce[action] = action
  return action
end

--- <span>
--- @param action An <a href="#Class_Action">Action</a> that was added to this event.
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

-- Copilot receives SAPI recognition event notifications on a background
-- thread, which then tells FSUIPC to notify this lua thread through the
-- LuaToggle command and in turn trigger this callback.
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

Event.TIMEOUT = {}
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

  local getPayload

  local a = event:addOneOffAction(function(_, ...) 
    local payload = {...}
    getPayload = function() return unpack(payload) end
  end)
  a:addLogMsg("waitForEvent event signal: " .. event:toString())
  
  local checkEvent = setmetatable({}, {
    __call = function (self, wait)
      if wait then
        repeat copilot.suspend() until self()
        return getPayload()
      end
      if getPayload then return true, getPayload end
      return false
    end
  })

  util.setOnGCcallback(checkEvent, function() event:removeAction(a) end)

  if returnFunction then return checkEvent end
  return checkEvent(true)
end

--- Waits for the event or until the timeout is elapsed.
---@static
---@int timeout Timeout in milliseconds
---@param event <a href="#Class_Event">Event</a>
---@return True if the event was signaled or Event.TIMEOUT
---@return Function that returns the event's payload.
function Event.waitForEventWithTimeout(timeout, event)

  local checkEvent = Event.waitForEvent(event, true)

  if timeout == Event.INFINITE then return checkEvent(true) end

  local signaled, getPayload = checkWithTimeout(timeout, function()
    copilot.suspend()
    return checkEvent()
  end)
  
  if signaled then return true, getPayload end
  return Event.TIMEOUT
end

---Same as `waitForEvent` but for multiple events
---@static
---@tparam table events Array of <a href="#Class_Event">Event</a>'s.
---@bool[opt=false] returnFunction 
---@bool[opt=false] waitForAll
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

  local payloadGetters = setmetatable({}, {__mode = "k"})
  local actions = setmetatable({}, {__mode = "k"})

  for _, event in ipairs(events) do
    payloadGetters[event] = NO_PAYLOAD
    actions[event] = event:addOneOffAction(function(_, ...)
      local payload = {...}
      payloadGetters[event] = function() return unpack(payload) end
    end)
    actions[event]:addLogMsg("waitForEvents event signal: " .. event:toString())
  end

  local checkEvents = setmetatable({}, {})

  util.setOnGCcallback(checkEvents, function()
    for e, a in pairs(actions) do e:removeAction(a) end
  end)

  if waitForAll then

    getmetatable(checkEvents).__call = function(self, wait)

      if wait then
        repeat copilot.suspend() until self()
        return payloadGetters
      end

      for _, getPayload in pairs(payloadGetters) do
        if getPayload == NO_PAYLOAD then return false end
      end
      return true, payloadGetters
    end
  else

    getmetatable(checkEvents).__call = function(self, wait)

      if wait then
        while true do
          copilot.suspend()
          local event, getPayload = self()
          if event then return event, getPayload end
        end
      end

      for event, getPayload in pairs(payloadGetters) do
        if getPayload ~= NO_PAYLOAD then
          payloadGetters[event] = NO_PAYLOAD
          return event, getPayload
        end
      end
    end
  end

  if returnFunction then return checkEvents end
  return checkEvents(true)
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

  local checkEvents = Event.waitForEvents(events, waitForAll, true)
  if timeout == Event.INFINITE then return checkEvents(true) end

  local function timeoutCallback() copilot.suspend() return checkEvents() end

  if waitForAll then
    local allSignaled, payloadGetters = checkWithTimeout(timeout, timeoutCallback)
    return allSignaled and payloadGetters or Event.TIMEOUT
  end

  local event, getPayload = withTimeout(timeout, timeoutCallback)
  if event then return event, getPayload end
  return Event.TIMEOUT
end

---Constructs an event from a key press.
---@static
---@param key See `FSL2Lua.Bind`
---@param[opt] ... Arguments to forward to the `Event` constructor.
---@return <a href="#Class_Event">Event</a>
function Event.fromKeyPress(key, ...)

  local e = Event:new(...)
  e.logMsg = e.logMsg or ("Key press event: " .. key)

  -- The following is necessary because Bind will make onPress global
  -- Bind internally calls event.key which takes a global function name
  local weakRef = setmetatable({e = e}, {__mode = "v"})
  copilot.callOnce(function() -- event.key and other event library functions don't work when called from coroutines
    e._keyBind = Bind {
      key = key, 
      dispose = true,
      onPress = function(...) if weakRef.e then weakRef.e:trigger(...) end end,
    }
  end)

  return e
end

function Event._simConnectMenuEventHandler(res)
  local e = Event._simConnectMenuEvent
  if not e then return end
  e:trigger(res, e.menu.items[res], e.menu)
  Event._simConnectMenuEvent = nil
end

event.MenuSelect("Event._simConnectMenuEventHandler")

Event.MENU_REPLACED = {}

--- Constructs an event from ipc.SetMenu and event.MenuSelect (FSUIPC library functions)
--- @string title The title of the menu
--- @string prompt The message that is displayed between the title and the items. Set to nil, "", or whitespace if you don't want a prompt.
--- @table items Array of strings representing the menu items
--- @return <a href="#Class_Event">Event</a>. Consumers of the event will receive the following payload values:
--- 1. The index of the item in the array.
--- 2. The item that was selected: string.
--- 3. A table with the fields 'title', 'prompt', and 'items'.
--- @usage 
function Event.fromSimConnectMenu(title, prompt, items)
  if Event._simConnectMenuEvent then 
    Event._simConnectMenuEvent:trigger(Event.MENU_REPLACED) 
  end
  if prompt == nil or prompt == "" then prompt = " " end
  ipc.SetMenu(title, prompt, items) 
  
  Event._simConnectMenuEvent = Event:new {
    menu = {title = title, prompt = prompt, items = items},
    logMsg = "SimConnect menu event: " .. (title or "?")
  }
  return Event._simConnectMenuEvent
end

return Event