
event = {}

local offsetPollRate = 100

local callbackRegistry = {}

function copilot.setOffsetPollRate(pollRate)
  offsetPollRate = pollRate
end

function event.cancel(funcName)
  local pollFunc = callbackRegistry[funcName]
  callbackRegistry[funcName] = nil
  copilot.removeCallback(pollFunc)
end

local function registerPollFunc(pollRate, funcName, poll)
  callbackRegistry[funcName] = poll 
  copilot.addCallback(poll, nil, pollRate)
end

function event.offset(offset, offsetType, funcName)
  local event, poll = Event.offsetEvent(offsetType, offset)
  local cb = _G[funcName]
  event:addAction(function(_, _, value) cb(offset, value) end)
  registerPollFunc(offsetPollRate, funcName, poll)
end

function event.lvar(lvar, pollRate, funcName)
  local event, poll = Event.lvarEvent(lvar)
  local cb = _G[funcName]
  event:addAction(function(_, _, value) cb(lvar, value) end)
  registerPollFunc(pollRate, funcName, poll)
end