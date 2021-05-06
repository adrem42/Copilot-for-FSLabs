
require "copilot.checklists.beforeStart"
require "copilot.checklists.beforeStartBelow"
require "copilot.checklists.afterStart"
require "copilot.checklists.beforeTakeoff"
require "copilot.checklists.landing"
require "copilot.checklists.parking"
require "copilot.checklists.securingTheAircraft"

local checklists = copilot.checklists
local events = copilot.events
local actions = copilot.actions

local function bindToAction(args)
  if copilot.UserOptions.actions.enable == copilot.UserOptions.TRUE
    and copilot.UserOptions.actions[args[1]] == copilot.UserOptions.ENABLED then
    args.ifEnabled() 
  else
    args.ifDisabled()
  end
end

bindToAction {
  "preflight",
  ifEnabled = function()
    checklists.beforeStart.trigger:activateOn(actions.preflight:doneEvent())
  end,
  ifDisabled = function()
    checklists.beforeStart.trigger:activateOn(events.chocksSet)
  end
}

checklists.beforeStartBelow.trigger:activateOn(checklists.beforeStart:doneEvent())

bindToAction {
  "after_start",
  ifEnabled = function()
    checklists.afterStart.trigger:activateOn(actions.afterStart:doneEvent())
  end,
  ifDisabled = function()
    checklists.afterStart.trigger:activateOn(events.enginesStarted)
  end
}

checklists.beforeTakeoff.trigger:activateOn(checklists.afterStart:doneEvent())

bindToAction {
  "lineup",
  ifEnabled = function()
    events.enginesStarted:addAction(function()
      Event.waitForEvents({actions.lineup:doneEvent(), checklists.beforeTakeoff:doneEvent()}, true)
      checklists.beforeTakeoffBelow.trigger:activate()
    end, Action.COROUTINE)
      :stopOn(events.engineShutdown, events.airborne)
      :setLogMsg(Event.NOLOGMSG)
  end,
  ifDisabled = function()
    checklists.beforeTakeoffBelow.trigger:activateOn(checklists.beforeTakeoff:doneEvent())
  end
}

bindToAction {
  "after_takeoff",
  ifEnabled = function ()
    checklists.afterTakeoff.trigger:activateOn(actions.afterTakeoff.doneEvent(), actions.afterGoAround.doneEvent())    
  end,
  ifDisabled = function()
    checklists.afterTakeoff.trigger:activateOn(events.airborne, events.goAround)
  end
}

checklists.afterTakeoffBelow:activateOn(checklists.afterTakeoff:doneEvent())

events.engineShutdown:addAction(function()
  checklists.afterStart.trigger:deactivate()
  checklists.beforeTakeoff.trigger:deactivate()
  checklists.beforeTakeoffBelow.trigger:deactivate()
end):setLogMsg(Event.NOLOGMSG)

events.airborne:addAction(function()
  checklists.beforeStart.trigger:deactivate()
  checklists.beforeStartBelow.trigger:deactivate()
  checklists.afterStart.trigger:deactivate()
  checklists.beforeTakeoff.trigger:deactivate()
  checklists.beforeTakeoffBelow.trigger:deactivate()
end):setLogMsg(Event.NOLOGMSG)

events.belowTenThousand:addAction(function()
  checklists.approach.trigger:activate()
  repeat copilot.suspend(5000) until copilot.IAS() < 200
  checklists.landing.trigger:activate()
  repeat copilot.suspend(5000) until copilot.radALT() < 500 / 3.28084
  checklists.landing.trigger:deactivate()
end, Action.COROUTINE):setLogMsg(Event.NOLOGMSG)

events.landing:addAction(function()
  events.engineShutdown:addOneOffAction(function()
    checklists.parking.trigger:activate()
  end)
end):setLogMsg(Event.NOLOGMSG)

checklists.securingTheAircraft.trigger:activateOn(checklists.parking:doneEvent())

events.enginesStarted:addAction(function()
  checklists.parking.trigger:deactivate()
  checklists.securingTheAircraft.trigger:deactivate()
end):setLogMsg(Event.NOLOGMSG)
