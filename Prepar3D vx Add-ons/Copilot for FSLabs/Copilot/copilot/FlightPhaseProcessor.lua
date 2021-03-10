local copilot = copilot
local events = copilot.events
local flightPhases = copilot.flightPhases
local Event = Event
local ipc = ipc

local FlightPhaseProcessor = {}

---------------------------------------------------------------
--- These need to be reimplemented for non-FSL aircraft: ------
---------------------------------------------------------------

function FlightPhaseProcessor.chocksOn() 
  return ipc.readLvar("FSLA320_Wheel_Chocks") == 1 
end

FlightPhaseProcessor.enginesRunning = copilot.enginesRunning

function FlightPhaseProcessor.enginesStarted()
  return FlightPhaseProcessor.enginesRunning() 
    and FSL.PED_ENG_MODE_Switch:getPosn() == "NORM"
end

FlightPhaseProcessor.reverseThrustSelected = copilot.reverseThrustSelected

function FlightPhaseProcessor.idleThrustSelected()
  return FSL:getThrustLeversPos() == "IDLE"
end

FlightPhaseProcessor.takeoffThrustSelected = copilot.thrustLeversSetForTakeoff

function FlightPhaseProcessor.climbThrustSelected()
  return ipc.readLvar("VC_PED_TL_1") < 30 and ipc.readLvar("VC_PED_TL_2") < 30
end

function FlightPhaseProcessor.goAroundTriggered()
  return FSL:getThrustLeversPos() == "TOGA"
end

function FlightPhaseProcessor.flyingCircuits()
  return copilot.mcduWatcher:getVar("flyingCircuits")
end

---------------------------------------------------------------
---------------------------------------------------------------
---------------------------------------------------------------

function FlightPhaseProcessor:init()
  if self.initialFlightPhase then
    self:setFlightPhase(self.initialFlightPhase)
  elseif not FlightPhaseProcessor.enginesRunning() then
    self:setFlightPhase(
      FlightPhaseProcessor.chocksOn() 
        and flightPhases.onChocks 
        or flightPhases.engineShutdown
    )
  elseif copilot.onGround() then
    self:setFlightPhase(flightPhases.taxi, events.enginesStarted)
  else
    self:setFlightPhase(flightPhases.airborne)
  end
end

function FlightPhaseProcessor.start()
  copilot.addCallback(
    coroutine.create(function() FlightPhaseProcessor:run() end), 
    "FlightPhaseProcessor"
  )
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

function FlightPhaseProcessor:setFlightPhase(newFlightPhase, ctxEvent)
  self.currFlightPhase = newFlightPhase
  local name = self.currFlightPhase.name
  if name then copilot.logger:info("Flight phase: " .. name) end
  local event = ctxEvent or newFlightPhase.event
  if event then event:trigger() end
end

function FlightPhaseProcessor:setInitialFlightPhase(flightPhase)
  self.initialFlightPhase = flightPhase
end

function FlightPhaseProcessor:run()
  self:init()
  while true do
    self:setFlightPhase(
      self.currFlightPhase:nextFlightPhase()
    )
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

local function checkEngineStart()
  if FlightPhaseProcessor.enginesStarted() then
    copilot.suspend(4000)
    return FlightPhaseProcessor.enginesStarted()
  end
end

local function onEnginesStarted() return flightPhases.taxi, events.enginesStarted end

function flightPhases.engineShutdown:nextFlightPhase()
  while true do
    if FlightPhaseProcessor.chocksOn() then return flightPhases.onChocks end
    if checkEngineStart() then return onEnginesStarted() end
    copilot.suspend(1000)
  end
end

function flightPhases.onChocks:nextFlightPhase()

  local chocksReleased = false

  local function checkChocksReleased()
    if chocksReleased then return true end
    if not FlightPhaseProcessor.chocksOn() then
      events.chocksReleased:trigger()
      chocksReleased = true
      return true
    end
  end

  while true do
    checkChocksReleased()
    if checkEngineStart() then
      if not checkChocksReleased() then
        copilot.addCallback(function (_, thisCallback)
          copilot.events.engineShutdown:addOneOffAction(function ()
            copilot.removeCallback(thisCallback)
          end)
          if checkChocksReleased() then copilot.removeCallback(thisCallback) end
        end, nil,  1000)
      end
      return onEnginesStarted() 
    end
    copilot.suspend(1000)
  end
end

function flightPhases.taxi:nextFlightPhase()
  while true do
    if FlightPhaseProcessor.takeoffThrustSelected() then
      while true do
        if copilot.eng1N1() > 50 and copilot.eng1N1() > 50 then
          return flightPhases.takeoff
        elseif not FlightPhaseProcessor.takeoffThrustSelected() then
          break
        end
        copilot.suspend(1000)
      end
    elseif not FlightPhaseProcessor.enginesRunning() then
      return flightPhases.engineShutdown
    end
    copilot.suspend(1000)
  end
end

function flightPhases.takeoff:nextFlightPhase()
  local waitUntilCancel = 10000
  local cancelCountDownStart
  repeat
    if not FlightPhaseProcessor.takeoffThrustSelected() then
      if copilot.eng1N1() > 80 and copilot.eng2N1() > 80 then
        local aborted = copilot.GS() > 10 
          and (FlightPhaseProcessor.idleThrustSelected() or FlightPhaseProcessor.reverseThrustSelected())
        if aborted then
          cancelCountDownStart = nil
          return flightPhases.taxi, events.takeoffAborted
        end
        if not cancelCountDownStart then
          cancelCountDownStart = copilot.getTimestamp()
        elseif copilot.getTimestamp() - cancelCountDownStart > waitUntilCancel then
          return flightPhases.taxi, events.takeoffCancelled
        end
      else
        return flightPhases.taxi, events.takeoffCancelled
      end
    elseif cancelCountDownStart then
      cancelCountDownStart = nil
    end
    copilot.suspend(1000)
  until not copilot.onGround()
  local flyingCircuits = FlightPhaseProcessor.flyingCircuits()
  copilot.mcduWatcher:resetVars()
  events.airborne:trigger()
  copilot.airborneTime = copilot.getTimestamp()
  flightPhases.airborne.takeoffCompleted = false
  return flyingCircuits and flightPhases.flyingCircuits or flightPhases.climbout
end

function flightPhases.airborne:nextFlightPhase()
  while true do
    if not flightPhases.airborne.takeoffCompleted then
      flightPhases.airborne.takeoffCompleted = FlightPhaseProcessor.climbThrustSelected()
      copilot.suspend(1000)
    elseif copilot.onGround() then
      events.touchdown:trigger()
      local touchdownTime = copilot.getTimestamp()
      local landed
      while true do
        if not copilot.onGround() then
          touchdownTime = nil
          if FlightPhaseProcessor.goAroundTriggered() then
            events.goAround:trigger()
            flightPhases.airborne.triggeredGoAround = true
            return flightPhases.flyingCircuits
          end
        elseif not touchdownTime then
          touchdownTime = copilot.getTimestamp()
        elseif copilot.getTimestamp() - touchdownTime > 500 and not landed then
          events.landing:trigger()
          landed = true
        elseif copilot.GS() < 40 then
          return flightPhases.taxi
        end
        copilot.suspend()
      end
    else
      if self == flightPhases.flyingCircuits or self == flightPhases.belowTenThousand then
        local goAroundTriggered = FlightPhaseProcessor.goAroundTriggered()
        if goAroundTriggered and not flightPhases.airborne.triggeredGoAround then
          events.goAround:trigger()
          flightPhases.airborne.triggeredGoAround = true
          return flightPhases.flyingCircuits
        elseif not goAroundTriggered and flightPhases.airborne.triggeredGoAround then
          flightPhases.airborne.triggeredGoAround = false
        end
      end
      local altitude = copilot.ALT()
      if altitude > 10300 
        and not flightPhases.airborne.triggeredGoAround 
        and self ~= flightPhases.aboveTenThousand then
        return flightPhases.aboveTenThousand
      elseif altitude < 9700 and self == flightPhases.aboveTenThousand then
        return flightPhases.belowTenThousand
      end
      copilot.suspend(copilot.radALT() < 1000 and nil or 1000)
    end
  end
end

function copilot.getFlightPhase() return FlightPhaseProcessor.currFlightPhase end
return FlightPhaseProcessor