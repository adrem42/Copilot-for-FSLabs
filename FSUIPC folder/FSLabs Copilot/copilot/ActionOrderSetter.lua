if false then module "Event" end

Event = Event or require "copilot.Event"
Action = Action or require "copilot.Action"
local util = require "FSL2Lua.FSL2Lua.util"

local OrderSetter = {}

function OrderSetter._checkCoro(action)
  if not action.runAsCoroutine then
    error("Action " .. action:toString() .. " needs to be a coroutine to be able to wait for other coroutines to complete", 3)
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
    if util.isType(otherAction, Action) then
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
    if util.isType(otherAction, Action) then
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

--- @type Event

--- Sets order of the event's actions relative to each other.
---@param action An <a href="#Class_Action">Action</a> which will serve as an anchor for positioning other actions in front or after it.
---@return A table with four functions: 'front', 'back', 'before' and 'after. 'Before' and 'after' take a variable
---number of <a href="#Class_Action">Action</a>'s. All four functions optionally take a boolean as the last parameter which defaults to true
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