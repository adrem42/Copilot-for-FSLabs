
event = {}

local offsetPollRate = 100

local events = {}

function copilot.setOffsetPollRate(pollRate)
  offsetPollRate = pollRate
end

function event.cancel(funcName)
  Event.cancelPollEvent(events[funcName])
  events[funcName] = nil
end

local function registerEvent(funcName, event)
  events[funcName] = event 
end

function event.offset(offset, offsetType, funcName)
  local event = Event.fromOffset(offsetType, offset, offsetPollRate)
  local cb = _G[funcName]
  event:addAction(function(_, _, value) cb(offset, value) end)
  registerEvent(funcName, event)
end

function event.lvar(lvar, pollRate, funcName)
  local event = Event.fromLvar(lvar, pollRate)
  local cb = _G[funcName]
  event:addAction(function(_, _, value) cb(lvar, value) end)
  registerEvent(funcName, event)
end