local events = copilot.events
local flightPhases = copilot.flightPhases
local Event = Event
local ipc = ipc

local FlightPhaseProcessor = {}

function FlightPhaseProcessor:init()
  if self.initialFlightPhase then
    self:setFlightPhase(self.initialFlightPhase)
  elseif not copilot.enginesRunning() then
    self:setFlightPhase(flightPhases.engineShutdown)
  elseif copilot.onGround() then
    self:setFlightPhase(flightPhases.taxi:setCtxEvent(events.enginesStarted))
  else
    self:setFlightPhase(flightPhases.airborne)
  end
end

events.chocksSet = Event:new{logMsg = "Chocks set"}
events.chocksReleased = Event:new{logMsg = "Chocks released"}
events.enginesStarted = Event:new{logMsg = "Engines started"}
events.takeoffInitiated = Event:new{logMsg = "Takeoff initiated"}
events.takeoffCancelled = Event:new{logMsg = "Takeoff cancelled"}
events.takeoffAborted = Event:new{logMsg = "Takeoff aborted"}
events.airborne = Event:new{logMsg = "Airborne"}
events.aboveTenThousand = Event:new{logMsg = "Climbing above 10'000"}
events.belowTenThousand = Event:new{logMsg = "Descending below 10'000"}
events.touchdown = Event:new{logMsg = "Touchdown"}
events.landing = Event:new{logMsg = "Landing"}
events.goAround = Event:new{logMsg = "Go around"}
events.engineShutdown = Event:new{logMsg = "Engine shutdown"}

function FlightPhaseProcessor:setFlightPhase(newFlightPhase)
  self.currFlightPhase = newFlightPhase
  local name = self.currFlightPhase.name
  if name then
    copilot.logger:debug("Flight phase: " .. name)
  end
  if newFlightPhase.event then
    newFlightPhase.event:trigger()
  elseif newFlightPhase.ctxEvent then
    newFlightPhase.ctxEvent:trigger()
    newFlightPhase.ctxEvent = nil
  end
end

function FlightPhaseProcessor:setInitialFlightPhase(flightPhase)
  self.initialFlightPhase = flightPhase
end

function FlightPhaseProcessor:update()
  self:init()
  while true do
    local newFlightPhase
    repeat
      newFlightPhase = self.currFlightPhase:update()
      copilot.suspend()
    until newFlightPhase
    self:setFlightPhase(newFlightPhase)
  end
end

local FlightPhase = {}

function FlightPhase:new(name, event)
  self.__index = self
  return setmetatable({name = name, event = event}, self)
end

flightPhases.engineShutdown = FlightPhase:new("Engines shutdown", events.engineShutdown)
flightPhases.onChocks = FlightPhase:new("On chocks", events.chocksSet)
flightPhases.taxi = FlightPhase:new("Taxi")
flightPhases.takeoff = FlightPhase:new("Takeoff", events.takeoffInitiated)

flightPhases.airborne = FlightPhase:new()
flightPhases.climbout = flightPhases.airborne:new("Climbout")
flightPhases.flyingCircuits = flightPhases.airborne:new("Circuit flying")
flightPhases.aboveTenThousand = flightPhases.airborne:new(nil, events.aboveTenThousand)
flightPhases.belowTenThousand = flightPhases.airborne:new(nil, events.belowTenThousand)

function FlightPhase:setCtxEvent(event)
  self.ctxEvent = event
  return self
end

local function waitForEngineStart()
  local chocksReleased = ipc.readLvar("FSLA320_Wheel_Chocks") == 0
  repeat
    if not chocksReleased and ipc.readLvar("FSLA320_Wheel_Chocks") == 0 then
      chocksReleased = true
      events.chocksReleased:trigger()
    end
    local enginesStarted = copilot.enginesRunning() and FSL.PED_ENG_MODE_Switch:getPosn() == "NORM"
    if enginesStarted then
      copilot.suspend(4000)
      enginesStarted = copilot.enginesRunning() and FSL.PED_ENG_MODE_Switch:getPosn() == "NORM"
    end
    copilot.suspend()
  until enginesStarted
  return flightPhases.taxi:setCtxEvent(events.enginesStarted)
end

function flightPhases.engineShutdown:update()
  local waitForEngineStart = coroutine.wrap(waitForEngineStart)
  local newFlightPhase
  repeat
    if ipc.readLvar("FSLA320_Wheel_Chocks") == 1 then
      newFlightPhase = flightPhases.onChocks
    end
    newFlightPhase = newFlightPhase or waitForEngineStart()
    copilot.suspend()
  until newFlightPhase
  return newFlightPhase
end

function flightPhases.onChocks:update()
  return waitForEngineStart()
end

function flightPhases.taxi:update()
  if copilot.thrustLeversSetForTakeoff() then
    while true do
      local eng1_N1 = ipc.readDBL(0x2010)
      local eng2_N1 = ipc.readDBL(0x2110)
      if eng1_N1 > 50 and eng2_N1 > 50 then
        return flightPhases.takeoff
      elseif not copilot.thrustLeversSetForTakeoff() then
        break
      end
    end
  elseif not copilot.enginesRunning() then
    return flightPhases.engineShutdown
  end
end

function flightPhases.takeoff:update()
  local waitUntilCancel = 10000
  local cancelCountDownStart
  repeat
    if not copilot.thrustLeversSetForTakeoff() then
      if ipc.readDBL(0x2010) > 80 and ipc.readDBL(0x2110) > 80 then
        local aborted = copilot.GS() > 10 and (FSL:getThrustLeversPos() == "IDLE" or copilot.reverseThrustSelected())
        if aborted then
          cancelCountDownStart = nil
          return flightPhases.taxi:setCtxEvent(events.takeoffAborted)
        end
        if not cancelCountDownStart then
          cancelCountDownStart = ipc.elapsedtime()
        elseif ipc.elapsedtime() - cancelCountDownStart > waitUntilCancel then
          return flightPhases.taxi:setCtxEvent(events.takeoffCancelled)
        end
      else
        return flightPhases.taxi:setCtxEvent(events.takeoffCancelled)
      end
    elseif cancelCountDownStart then
      cancelCountDownStart = nil
    end
    copilot.suspend()
  until not copilot.onGround()
  local flyingCircuits = copilot.mcduWatcher:getVar("flyingCircuits")
  copilot.mcduWatcher:resetVars()
  events.airborne:trigger()
  copilot.airborneTime = ipc.elapsedtime()
  flightPhases.airborne.takeoffCompleted = false
  return flyingCircuits and flightPhases.flyingCircuits or flightPhases.climbout
end

function flightPhases.airborne:update()
  if not flightPhases.airborne.takeoffCompleted then
    flightPhases.airborne.takeoffCompleted = ipc.readLvar("VC_PED_TL_1") < 30 and ipc.readLvar("VC_PED_TL_1") < 30
  elseif copilot.onGround() then
    events.touchdown:trigger()
    local touchdownTime = ipc.elapsedtime()
    local landed
    while true do
      if not copilot.onGround() then
        touchdownTime = nil
        if FSL:getThrustLeversPos() == "TOGA" then
          events.goAround:trigger()
          flightPhases.airborne.triggeredGoAround = true
          return flightPhases.flyingCircuits
        end
      elseif not touchdownTime then
        touchdownTime = ipc.elapsedtime()
      elseif ipc.elapsedtime() - touchdownTime > 500 and not landed then
        events.landing:trigger()
        landed = true
      elseif copilot.GS() < 40 then
        return flightPhases.taxi
      end
      copilot.suspend()
    end
  else
    if self == flightPhases.flyingCircuits or self == flightPhases.belowTenThousand then
      if FSL:getThrustLeversPos() == "TOGA" and not flightPhases.airborne.triggeredGoAround then
        events.goAround:trigger()
        flightPhases.airborne.triggeredGoAround = true
        return flightPhases.flyingCircuits
      elseif FSL:getThrustLeversPos() ~= "TOGA" and flightPhases.airborne.triggeredGoAround then
        flightPhases.airborne.triggeredGoAround = false
      end
    end
    if copilot.ALT() > 10300 and not flightPhases.airborne.triggeredGoAround and self ~= flightPhases.aboveTenThousand then
      return flightPhases.aboveTenThousand
    elseif copilot.ALT() < 9700 and self == flightPhases.aboveTenThousand then
      return flightPhases.belowTenThousand
    end
  end
end

function copilot.getFlightPhase() return FlightPhaseProcessor.currFlightPhase end

return FlightPhaseProcessor