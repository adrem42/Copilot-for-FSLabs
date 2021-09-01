local Rx = require "rx"

local CopilotScheduler = {}
CopilotScheduler.__index = CopilotScheduler
CopilotScheduler.__tostring = Rx.util.constant('CopilotScheduler')

function CopilotScheduler.create()
  return setmetatable({}, CopilotScheduler)
end

function CopilotScheduler:schedule(action, delay, ...)
  local args = Rx.util.pack(...)
  local cb = copilot.callOnce(function()
    action(Rx.util.unpack(args))
  end, delay)
  return Rx.Subscription.create(function()
    copilot.removeCallback(cb)
  end)
end

return CopilotScheduler