if false then module "Event" end

local Event = Event or require "copilot.Event"

--- @type SingleEvent An Event that can only be signaled once
SingleEvent = setmetatable({}, Event)
SingleEvent.__index = SingleEvent

--- Same as `Event:addAction`, but if the event has already been signaled, the action will execute immediately.
function SingleEvent:addAction(...)
  local action = Event.addAction(self, ...)
  if self.payload then
    self:_runAction(action, unpack(self.payload))
  end
  return action
end

--- Same as `Event:trigger`, but does nothing after being called once.
function SingleEvent:trigger(...)
  if self.payload then return end
  self.payload = {...}
  return Event.trigger(self, ...)
end

function SingleEvent:reset()
  self.payload = nil
end

function Event:toSingleEvent(...)
  local e = SingleEvent:new(...)
  self.children[e] = true
  return e
end

return SingleEvent