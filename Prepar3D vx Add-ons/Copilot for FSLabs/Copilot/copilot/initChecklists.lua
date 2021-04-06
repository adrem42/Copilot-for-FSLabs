
require "copilot.checklists.beforeStart"
require "copilot.checklists.beforeStartBelow"
require "copilot.checklists.afterStart"
require "copilot.checklists.beforeTakeoff"
require "copilot.checklists.landing"
require "copilot.checklists.parking"
require "copilot.checklists.securingTheAircraft"

local checklists = copilot.checklists

local function bindToAction(args)
  if copilot.UserOptions.actions.enable == copilot.UserOptions.TRUE
    and copilot.UserOptions.actions[args[1]] == copilot.UserOptions.ENABLED then
    args.onEnabled() 
  else
    args.onDisabled()
  end
end

bindToAction {
  "preflight",
  onEnabled = function()
    checklists.beforeStart.trigger:activateOn(copilot.actions.preflight.threadFinishedEvent)
  end,
  onDisabled = function()
    checklists.beforeStart.trigger:activateOn(copilot.events.chocksSet)
  end
}

checklists.beforeStartBelow.trigger:activateOn(checklists.beforeStart.doneEvent)

bindToAction {
  "afterStart",
  onEnabled = function()
    checklists.afterStart.trigger:activateOn(copilot.actions.afterStart.threadFinishedEvent)
  end,
  onDisabled = function()
    checklists.afterStart.trigger:activateOn(copilot.events.enginesStarted)
  end
}

checklists.beforeTakeoff.trigger:activateOn(checklists.afterStart.doneEvent)

bindToAction {
  "lineup",
  onEnabled = function()
    checklists.beforeTakeoffBelow.trigger:activateOn(copilot.events.lineUpSequenceCompleted)
  end,
  onDisabled = function()
    checklists.beforeTakeoffBelow.trigger:activateOn(checklists.beforeTakeoff.doneEvent)
  end
}

copilot.events.airborne:addAction(function()
  checklists.beforeStart.trigger:deactivate()
  checklists.beforeStartBelow.trigger:deactivate()
  checklists.afterStart.trigger:deactivate()
  checklists.beforeTakeoff.trigger:deactivate()
  checklists.beforeTakeoffBelow.trigger:deactivate()
end)

copilot.events.belowTenThousand:addAction(function()
  repeat copilot.suspend(5000) until copilot.IAS() < 200
  copilot.checklists.landing.trigger:activate()
  repeat copilot.suspend(5000) until copilot.radALT() < 500
  copilot.checklists.landing.trigger:deactivate()
end, Action.COROUTINE)

copilot.events.landing:addAction(function()
  copilot.events.engineShutdown:addOneOffAction(function()
    checklists.parking.trigger:activate()
  end)
end)

checklists.securingTheAircraft.trigger:activateOn(checklists.parking.doneEvent)

copilot.events.enginesStarted:addAction(function()
  checklists.parking.trigger:deactivate()
  checklists.securingTheAircraft.trigger:deactivate()
end)