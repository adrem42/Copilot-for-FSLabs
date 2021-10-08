
local Event = Event
local Action = Action
local VoiceCommand = VoiceCommand
local copilot = copilot
local ipc = ipc
local frameRate = require("FSL2Lua.FSL2Lua.util").frameRate

local PFD_delay = 650
local ECAM_delay = 300
local reverserDoorThreshold = 90
local spoilersDeployedThreshold = 200
local reactionTime = 300

local function withFrameRateDelay(init)
  return init + math.max(0,  -70 * math.min(frameRate(), 27) + 2080)
end

copilot.callouts = {
  takeoffFMAreadoutEnabled = copilot.isVoiceControlEnabled and copilot.UserOptions.voice_commands.takeoff_FMA_readout == copilot.UserOptions.ENABLED
}

function copilot.callouts:resetFlags()
  self.noReverseTimeRef = nil
  self.noDecelTimeRef = nil
  self.reverseFuncEndedTime = nil
  self.landedTime = nil
  self.brakeCheck.brakesChecked = false
  self.checkingFlightControls = false
  self.flightControlsChecked = false
  self.hasFMABeenRead = not self.takeoffFMAreadoutEnabled
end

if copilot.callouts.takeoffFMAreadoutEnabled then
  copilot.voiceCommands.takeoffFMAreadout = VoiceCommand:new {
    confidence = 0.85,
    persistent = true,
    phrase = PhraseBuilder.new()
      :append "man"
      :append {
        "toga",
        PhraseBuilder.new()
          :append "flex"
          :append(table.init(20, 80, 1, tostring))
          :build "flex"
      }
      :append "ass are ass"
      :appendOptional "runway"
      :append "autothrust blue"
      :build(),
    action = function() copilot.callouts.hasFMABeenRead = true end 
  }
    :deactivateOn(copilot.events.airborne)

  copilot.events.enginesStarted:addAction(function()
    copilot.voiceCommands.takeoffFMAreadout:activate()
    copilot.callouts.hasFMABeenRead = false
    while true do
      copilot.suspend(1000)
      if not copilot.thrustLeversSetForTakeoff() then
        copilot.callouts.hasFMABeenRead = false
      end
    end
  end, Action.COROUTINE)
    :stopOn(copilot.events.engineShutdown, copilot.events.airborne)
    :setLogMsg(Event.NOLOGMSG)
end

local function getFslV1Option() return tonumber(copilot.getFltSimCfg():match"sdac_v1_call=(%d)") end

function copilot.callouts:takeoff()
  local FslV1Option = getFslV1Option()
  copilot.logger:info(string.format("sdac_v1_call=%s", FslV1Option or "not found"))
  local V1 = copilot.mcduWatcher:getVar("V1")
  local Vr = copilot.mcduWatcher:getVar("Vr")
  if not V1 or not Vr then
    FSL.PED_MCDU_KEY_PERF()
    copilot.suspend(1000, 2000)
    local disp = FSL.MCDU:getString()
    V1 = tonumber(disp:sub(49,51))
    Vr = tonumber(disp:sub(97,99))
    FSL.PED_MCDU_KEY_FPLN()
  end
  self:waitForThrustSet()
  self:waitForOneHundred()
  if (FslV1Option == 0 or not FslV1Option) and V1 then
    self:waitForV1(V1)
  end
  if Vr then
    self:waitForVr(Vr)
  end
  self:waitForPositiveClimb()
end

function copilot.callouts:rollout(afterAbortedTakeoff)
  if not afterAbortedTakeoff then self:waitForSpoilers()
  else self.landedTime = copilot.getTimestamp() end
  self:waitForReverseGreen()
  if copilot.GS() > 70 then
    while not self.landedTime do copilot.suspend(100) end
    self.noDecelTimeRef = ipc.elapsedtime()
    self:waitForDecel()
  end
  self:waitForSeventy()
end

function copilot.callouts:waitForThrustSet()
  local eng1_N1
  local eng2_N1
  local eng1_N1_prev = copilot.eng1N1()
  local eng2_N1_prev = copilot.eng2N1()
  local N1_window = 0.5
  local timeWindow = 1000
  local thrustSet
  repeat
    copilot.suspend(plusminus(timeWindow,0.2))
    eng1_N1 = copilot.eng1N1()
    eng2_N1 = copilot.eng2N1()
    thrustSet = eng1_N1 > 80 and eng2_N1 > 80 and math.abs(eng1_N1 - eng1_N1_prev) < N1_window and math.abs(eng2_N1 - eng2_N1_prev) < N1_window
    local skipThis = not thrustSet and copilot.IAS() > 80
    eng1_N1_prev = eng1_N1
    eng2_N1_prev = eng2_N1
  until thrustSet or skipThis
  if thrustSet then
    repeat copilot.suspend(100) until self.hasFMABeenRead or copilot.IAS() > 50
    copilot.playCallout("thrustSet")
  end
end

function copilot.callouts:waitForOneHundred()
  while true do
    if copilot.IAS() >= 100 then
      copilot.playCallout("oneHundred", withFrameRateDelay(PFD_delay))
      return
    end
    copilot.suspend(100)
  end
end

function copilot.callouts:waitForV1(V1)
  while true do
    if copilot.IAS() >= V1 then
      copilot.playCallout("V1", withFrameRateDelay(PFD_delay))
      return
    end
    copilot.suspend(100)
  end
end

function copilot.callouts:waitForVr(Vr)
  while true do
    if copilot.IAS() >= Vr then
      copilot.playCallout("rotate", withFrameRateDelay(PFD_delay))
      return
    end
    copilot.suspend(100)
  end
end

function copilot.callouts:waitForPositiveClimb()
  repeat
    local verticalSpeed = ipc.readSW(0x02C8) * 60 * 3.28084 / 256
    local positiveClimb = copilot.radALT() >= 10 and verticalSpeed >= 500
    local skipThis = not positiveClimb and copilot.radALT() > 150.0
    if positiveClimb then
      copilot.playCallout("positiveClimb")
    end
    copilot.suspend(100)
  until positiveClimb or skipThis
end

function copilot.callouts:waitForSpoilers()
  local delay = withFrameRateDelay(ECAM_delay) + reactionTime
  if prob(0.1) then delay = delay + plusminus(500) end
  repeat
    local spoilers_left = ipc.readLvar("FSLA320_spoiler_l_1") > spoilersDeployedThreshold and ipc.readLvar("FSLA320_spoiler_l_2") > spoilersDeployedThreshold and ipc.readLvar("FSLA320_spoiler_l_3") > spoilersDeployedThreshold and ipc.readLvar("FSLA320_spoiler_l_4") > spoilersDeployedThreshold and ipc.readLvar("FSLA320_spoiler_l_5") > spoilersDeployedThreshold
    local spoilers_right = ipc.readLvar("FSLA320_spoiler_r_1") > spoilersDeployedThreshold and ipc.readLvar("FSLA320_spoiler_r_2") > spoilersDeployedThreshold and ipc.readLvar("FSLA320_spoiler_r_3") > spoilersDeployedThreshold and ipc.readLvar("FSLA320_spoiler_r_4") > spoilersDeployedThreshold and ipc.readLvar("FSLA320_spoiler_r_5") > spoilersDeployedThreshold
    local spoilers = spoilers_left and spoilers_right
    local noSpoilers = not spoilers and self.landedTime and copilot.getTimestamp() - self.landedTime > plusminus(1500)
    if spoilers then
      copilot.playCallout("spoilers", delay)
    elseif noSpoilers then
      copilot.playCallout("noSpoilers", delay)
    end
    copilot.suspend(100)
  until spoilers or noSpoilers
end

function copilot.callouts:waitForReverseGreen()
  local delay = withFrameRateDelay(ECAM_delay) + reactionTime
  if prob(0.1) then delay = delay + plusminus(500) end
  repeat
    local reverseLeftGreen = ipc.readLvar("FSLA320_reverser_left") >= reverserDoorThreshold
    local reverseRightGreen = ipc.readLvar("FSLA320_reverser_right") >= reverserDoorThreshold
    local reverseGreen = reverseLeftGreen and reverseRightGreen
    local noReverse = (not reverseGreen and self.noReverseTimeRef and copilot.getTimestamp() - self.noReverseTimeRef > plusminus(5500,0.2)) or copilot.GS() < 100
    if self.landedTime and copilot.reverseThrustSelected() and not self.noReverseTimeRef then
      self.noReverseTimeRef = copilot.getTimestamp() 
    end
    if reverseGreen then
      copilot.playCallout("reverseGreen", delay)
    elseif noReverse then
      if reverseLeftGreen then
        copilot.playCallout("noReverseLeft", delay)
      elseif reverseRightGreen then
        copilot.playCallout("noReverseRight", delay)
      else
        copilot.playCallout("noReverse", delay)
      end
    end
    copilot.suspend(100)
  until reverseGreen or noReverse
end

function copilot.callouts:waitForDecel()
  local delay = plusminus(1200)
  if prob(0.1) then delay = delay + plusminus(500) end
  repeat
    local accelLateral = ipc.readDBL(0x3070)
    local decel = accelLateral < -3
    local noDecel = (not decel and copilot.getTimestamp() - self.noDecelTimeRef > plusminus(3500)) or copilot.GS() < 70
    if decel then
      copilot.playCallout("decel", delay)
    elseif noDecel then
      copilot.playCallout("noDecel", delay)
    end
    copilot.suspend(100)
  until decel or noDecel
end

function copilot.callouts:waitForSeventy()
  local delay = plusminus(200)
  if prob(0.05) then delay = delay + plusminus(200) end
  repeat
    local seventy = copilot.GS() <= 70
    if seventy then
      copilot.playCallout("seventy", delay)
    end
    copilot.suspend(100)
  until seventy
end

local brakeCheck = {__index = copilot.callouts}
setmetatable(brakeCheck, brakeCheck)
copilot.callouts.brakeCheck = brakeCheck

function copilot.callouts.brakeCheck:brakeCheckConditions()
  local leftBrakeApp = ipc.readUW(0x0BC4) * 100 / 16383
  local rightBrakeApp = ipc.readUW(0x0BC6) * 100 / 16383
  local pushback = ipc.readLvar("FSLA320_NWS_Pin") == 1
  local brakeAppThreshold = 0.5
  local GS = copilot.GS()
  return GS >= 0.2 and GS < 3 and not pushback and leftBrakeApp > brakeAppThreshold and rightBrakeApp > brakeAppThreshold
end

function copilot.callouts.brakeCheck:__call()
  if self.checkingFlightControls then return end
  if self:brakeCheckConditions() then
    local leftPressure = ipc.readLvar("VC_MIP_BrkPress_L")
    local rightPressure = ipc.readLvar("VC_MIP_BrkPress_R")
    if leftPressure == 0 and rightPressure == 0 then
      copilot.playCallout("pressureZero", plusminus(800,0.2))
      copilot.events.brakesChecked:trigger()
      self.brakesChecked = true
      return true
    elseif leftPressure > 0 or rightPressure > 0 then
      return false
    end
  end
end

local FlightControlCheck = require "copilot.FlightControlCheck"

function copilot.callouts:flightControlsCheck()

  if self.flightControlsChecked then return end

  local brakeCheckVcWasActive

  if copilot.isVoiceControlEnabled then
    brakeCheckVcWasActive = copilot.voiceCommands.brakeCheck:getState() == copilot.RuleState.Active
    if brakeCheckVcWasActive then
      copilot.voiceCommands.brakeCheck:ignore()
    end
  end

  self.checkingFlightControls = true
  local check
  if copilot.isVoiceControlEnabled then
    check = FlightControlCheck:new(FlightControlCheck.MODE_ACTIVE_IMMEDIATE)
  else
    check = FlightControlCheck:new(FlightControlCheck.MODE_ACTIVE_AFTER_FIRST_CHECK)
  end
  local res, err = check()
  self.checkingFlightControls = false

  if brakeCheckVcWasActive then
    copilot.voiceCommands.brakeCheck:activate()
  end

  if res == true then
    if copilot.isVoiceControlEnabled then
      copilot.voiceCommands.flightControlsCheck:deactivate()
    end
    self.flightControlsChecked = true
    copilot.events.flightControlsChecked:trigger()
    return true
  elseif err == FlightControlCheck.ERROR_PM_CHECK_TIMEOUT then
    copilot.displayText("Pilot Monitoring: 'Oh no, my sidestick isn't working!'", 10, "print_yellow")
  elseif err == "timeout" then
    print "Flight control check timed out"
  end

  return res
end

function copilot.callouts:setup()
  copilot.events.flightControlsChecked = Event:new{logMsg = "Flight controls checked"}
  copilot.events.brakesChecked = Event:new{logMsg = "Brakes are checked"}
  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.brakeCheck = VoiceCommand:new {phrase = "brake check", persistent = true}
    copilot.voiceCommands.flightControlsCheck = VoiceCommand:new {
      phrase = "flight control check", 
      persistent = true, 
      confidence = 0.9
    }
  end
end

function copilot.callouts:start()

  copilot.events.chocksSet:addAction(function() self:resetFlags() end):setLogMsg(Event.NOLOGMSG)

  if copilot.UserOptions.callouts.PM_announces_brake_check == 1 then
    if copilot.isVoiceControlEnabled then

      copilot.events.takeoffCancelled:addAction(function()
        if not self.brakeCheck.brakesChecked then
          copilot.voiceCommands.brakeCheck:activate()
        end
      end):setLogMsg(Event.NOLOGMSG)

      copilot.voiceCommands.brakeCheck
        :activateOn(copilot.events.enginesStarted)
        :deactivateOn(copilot.events.engineShutdown, copilot.events.takeoffInitiated)
      copilot.voiceCommands.brakeCheck:addAction(function()
          if not checkWithTimeout(5000, function()
            copilot.suspend(100)
            return self.brakeCheck:brakeCheckConditions()
          end) then
            print "Brake check timed out"
            return 
          end
          if self:brakeCheck() then
            copilot.voiceCommands.brakeCheck:ignore()
          end
        end, Action.COROUTINE):setLogMsg "Brake check"
    else

      copilot.events.enginesStarted:addAction(function()
        repeat copilot.suspend(100) until self:brakeCheck()
      end, Action.COROUTINE)
        :setLogMsg "Waiting for the brake check"
        :stopOn(copilot.events.engineShutdown)
    end
  end

  if copilot.UserOptions.callouts.PM_announces_flightcontrol_check == 1 then

    local function flightControlCheckAction(cb)
      local a = Action:new(cb, Action.COROUTINE)
        :setLogMsg "Flight control check"
        :stopOn(copilot.events.engineShutdown, copilot.events.takeoffInitiated)
      return a
    end

    if copilot.isVoiceControlEnabled then
      copilot.events.takeoffCancelled:addAction(function()
        if not self.flightControlsChecked then
          copilot.voiceCommands.flightControlsCheck:activate()
        end
      end)
      copilot.voiceCommands.flightControlsCheck
        :activateOn(copilot.events.enginesStarted)
        :deactivateOn(copilot.events.engineShutdown, copilot.events.takeoffInitiated)
      copilot.voiceCommands.flightControlsCheck:addAction(
        flightControlCheckAction(function() 
          self:flightControlsCheck() 
        end)
      )  
    else
      local action = flightControlCheckAction(function()
        copilot.suspend(30000)
        repeat until self:flightControlsCheck()
      end)
      copilot.events.enginesStarted:addAction(action)
      copilot.events.takeoffCancelled:addAction(action)
    end
    
    copilot.events.engineShutdown:addAction(function() 
      self.flightControlsChecked = false 
    end):setLogMsg(Event.NOLOGMSG)
  end

  copilot.events.takeoffInitiated:addAction(function() self:takeoff() end, Action.COROUTINE)
    :setLogMsg("Takeoff callouts")
    :stopOn(copilot.events.takeoffAborted, copilot.events.takeoffCancelled)

  copilot.events.takeoffAborted:addAction(function()
    self.flightControlsChecked = true
    self.brakeCheck.brakesChecked = true
    if copilot.GS() > 60 then
      self:rollout(true)
    end
  end, Action.COROUTINE):setLogMsg "Aborted takeoff callouts"

  copilot.events.touchdown:addAction(function() self:rollout(false) end, Action.COROUTINE)
    :setLogMsg("Rollout callouts")
    :stopOn(copilot.events.goAround)

  copilot.events.landing:addAction(function()
    self.landedTime = copilot.getTimestamp()
  end):setLogMsg(Event.NOLOGMSG)
end

copilot.callouts:resetFlags()
