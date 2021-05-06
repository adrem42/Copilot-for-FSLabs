if false then module "Event" end

local Event = Event or require "copilot.Event"

--- An Event that can be signaled only once
--- @type SingleEvent 
SingleEvent = setmetatable({}, Event)
SingleEvent.__index = SingleEvent

--- Same as `Event:addAction`, but if the event has already been signaled, the action will execute immediately.
function SingleEvent:addAction(...)
  local action = Event.addAction(self, ...)
  if self.payload then
    self:_runAction(action, self.payload)
  end
  return action
end

function SingleEvent:_trigger(payload)
  if self.payload then return end
  self.payload = payload
  return Event._trigger(self, payload)
end

--- Same as `Event:trigger`, but does nothing after being called once.
--- @function trigger
--- @param ...

function SingleEvent:reset()
  self.payload = nil
end

function Event:toSingleEvent(...)
  local e = SingleEvent:new(...)
  self.children[e] = true
  return e
end

return SingleEvent