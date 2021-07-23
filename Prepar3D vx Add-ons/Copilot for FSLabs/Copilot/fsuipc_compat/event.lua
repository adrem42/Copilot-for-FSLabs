
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

local function registerPollFunc(pollRate, funcName, readFunc, readFuncArg, callback)
  local val
  local function poll()
    local newVal = readFunc(readFuncArg)
    if newVal ~= val then
      val = newVal
      callback(val)
    end
  end
  callbackRegistry[funcName] = poll 
  poll()
  copilot.addCallback(poll, nil, pollRate)
end

function event.offset(offset, offsetType, funcName)
  local readFunc = ipc["read" .. offsetType]
  if not readFunc then
    error("Invalid offset type: " .. offsetType, 2)
  end
  local callback = _G[funcName]
  registerPollFunc(offsetPollRate, funcName, readFunc, offset, function(val)
    callback(offset, val)
  end)
end

function event.lvar(lvarName, pollRate, funcName)
  local callback = _G[funcName]
  registerPollFunc(pollRate, funcName, ipc.readLvar, lvarName, function(val)
    callback(lvarName, val)
  end)
end