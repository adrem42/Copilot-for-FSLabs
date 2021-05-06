
local Event = Event
local Action = Action
local VoiceCommand = VoiceCommand
local copilot = copilot
local ipc = ipc

local PFD_delay = 650
local ECAM_delay = 300
local reverserDoorThreshold = 90
local spoilersDeployedThreshold = 200
local reactionTime = 300

copilot.callouts = {
  takeoffFMAreadoutEnabled = copilot.isVoiceControlEnabled and copilot.UserOptions.voice_commands.takeoff_FMA_readout == copilot.UserOptions.ENABLED
}

function copilot.callouts:resetFlags()
  self.noReverseTimeRef = nil
  self.noDecelTimeRef = nil
  self.reverseFuncEndedTime = nil
  self.landedTime = nil
  self.brakeCheck.brakesChecked = false
  self.flightControlsCheck.checkingFlightControls = false
  self.flightControlsCheck.flightControlsChecked = false
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
      copilot.playCallout("oneHundred", PFD_delay)
      return
    end
    copilot.suspend(100)
  end
end

function copilot.callouts:waitForV1(V1)
  while true do
    if copilot.IAS() >= V1 then
      copilot.playCallout("V1", PFD_delay)
      return
    end
    copilot.suspend(100)
  end
end

function copilot.callouts:waitForVr(Vr)
  while true do
    if copilot.IAS() >= Vr then
      copilot.playCallout("rotate", PFD_delay)
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
  local delay = ECAM_delay + reactionTime
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
  local delay = ECAM_delay + reactionTime
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
  if self.flightControlsCheck.checkingFlightControls then return end
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

local flightControlsCheck = {
  __index = callouts,
  elevatorTolerance = 200,
  aileronTolerance = 300,
  spoilerTolerance = 100,
  rudderTolerance = 100,
  spoilerLimit = 1500
}
setmetatable(flightControlsCheck, flightControlsCheck)
copilot.callouts.flightControlsCheck = flightControlsCheck

local ecpButtons = table.map({
  "ENG", "BLEED", "PRESS", "ELEC", "HYD", "FUEL", 
  "APU", "COND", "DOOR", "WHEEL", "STS"
}, function(page)
  return FSL["PED_ECP_" .. page .. "_Button"]
end)

local function confirmFctlEcamPage()
  if FSL.PED_ECP_FCTL_Button:isLit() then return end
  for _, butt in ipairs(ecpButtons) do
    if butt:isLit() then 
      copilot.suspend(1000, 2000)
      butt:pressIfLit() 
    end
  end
end

function copilot.callouts.flightControlsCheck:__call()

  if self.flightControlsChecked then return end

  if FSL:getAcType() == "A319" then
    self.fullLeftRudderTravel = 1243
    self.fullRightRudderTravel = 2743
  else
    self.fullLeftRudderTravel = 1499
    self.fullRightRudderTravel = 3000
  end
  
  if not copilot.isVoiceControlEnabled then
    copilot.suspend(30000)
  end
  local fullLeft, fullRight, fullLeftRud, fullRightRud, fullUp, fullDown, xNeutral, yNeutral, rudNeutral

  self.checkingFlightControls = false
  local cycle = 0
  local timeLastAction = ipc.elapsedtime()

  local stickDelay, rudDelay = 700, 400

  local function onChecked(calloutFile, delay)
    confirmFctlEcamPage() 
    copilot.playCallout(calloutFile, plusminus(delay))
    timeLastAction = ipc.elapsedtime()
    self.checkingFlightControls = true
  end

  repeat
    copilot.suspend(100)
    if copilot.isVoiceControlEnabled then
      cycle = cycle + 1
      if cycle % 10 == 0 then 
        confirmFctlEcamPage() 
        if ipc.elapsedtime() - timeLastAction > 10000 then 
          self.checkingFlightControls = false
          return 
        end
      end
    end
    
    -- full left aileron
    if not fullLeft and not ((fullUp or fullDown) and not yNeutral) and self:fullLeft() then
      onChecked( "fullLeft_1", stickDelay)
      fullLeft = true
    end
    -- full right aileron
    if not fullRight and not ((fullUp or fullDown) and not yNeutral) and self:fullRight() then
      onChecked("fullRight_1", stickDelay)
      fullRight = true
    end
    -- neutral after full left and full right aileron
    if fullLeft and fullRight and not xNeutral and self:stickNeutral() then
      onChecked("neutral_1", stickDelay)
      xNeutral = true
    end
    -- full up
    if not fullUp and not ((fullLeft or fullRight) and not xNeutral) and self:fullUp() then
      onChecked("fullUp", stickDelay)
      fullUp = true
    end
    -- full down
    if not fullDown and not ((fullLeft or fullRight) and not xNeutral) and self:fullDown() then
      onChecked("fullDown", stickDelay)
      fullDown = true
    end
    -- neutral after full up and full down
    if fullUp and fullDown and not yNeutral and self:stickNeutral() then
      onChecked("neutral_2", stickDelay)
      yNeutral = true
    end
    -- full left rudder
    if not fullLeftRud and xNeutral and yNeutral and self:fullLeftRud() then
      onChecked("fullLeft_2", rudDelay)
      fullLeftRud = true
    end
    -- full right rudder
    if not fullRightRud and xNeutral and yNeutral and self:fullRightRud() then
      onChecked("fullRight_2", rudDelay)
      fullRightRud = true
    end
    -- neutral after full left and full right rudder
    if fullLeftRud and fullRightRud and not rudNeutral and self:rudNeutral() then
      onChecked("neutral_2", rudDelay)
      rudNeutral = true
    end

  until xNeutral and yNeutral and rudNeutral

  self.checkingFlightControls = false
  self.flightControlsChecked = true
  copilot.events.flightControlsChecked:trigger()
  return true
end

function copilot.callouts.flightControlsCheck:fullLeft()
  local aileronLeft
  if ipc.readLvar("FSLA320_flap_l_1") == 0 then
    aileronLeft = ipc.readLvar("FSLA320_aileron_l") <= 1499 and 1499 - ipc.readLvar("FSLA320_aileron_l") < self.aileronTolerance
  elseif ipc.readLvar("FSLA320_flap_l_1") > 0 then
    aileronLeft = ipc.readLvar("FSLA320_aileron_l") <= 1199 and 1199 - ipc.readLvar("FSLA320_aileron_l") < self.aileronTolerance
  end
  return
  aileronLeft --and
  --self.spoilerLimit - ipc.readLvar("FSLA320_spoiler_l_2") < self.spoilerTolerance and
  --self.spoilerLimit - ipc.readLvar("FSLA320_spoiler_l_3") < self.spoilerTolerance and
  --self.spoilerLimit - ipc.readLvar("FSLA320_spoiler_l_4") < self.spoilerTolerance and
  --self.spoilerLimit - ipc.readLvar("FSLA320_spoiler_l_5") < self.spoilerTolerance
end

function copilot.callouts.flightControlsCheck:fullRight()
  local aileronRight
  if ipc.readLvar("FSLA320_flap_l_1") == 0 then
    aileronRight = 3000 - ipc.readLvar("FSLA320_aileron_r") < self.aileronTolerance
  elseif ipc.readLvar("FSLA320_flap_l_1") > 0 then
    aileronRight = 2700 - ipc.readLvar("FSLA320_aileron_r") < self.aileronTolerance
  end
  return
  aileronRight -- and
  --self.spoilerLimit - ipc.readLvar("FSLA320_spoiler_r_2") < self.spoilerTolerance and
  --self.spoilerLimit - ipc.readLvar("FSLA320_spoiler_r_3") < self.spoilerTolerance and
  --self.spoilerLimit - ipc.readLvar("FSLA320_spoiler_r_4") < self.spoilerTolerance and
  --self.spoilerLimit - ipc.readLvar("FSLA320_spoiler_r_5") < self.spoilerTolerance
end

function copilot.callouts.flightControlsCheck:fullUp()
  return
  ipc.readLvar("FSLA320_elevator_l") <= 1499 and 1499 - ipc.readLvar("FSLA320_elevator_l") < self.elevatorTolerance and
  ipc.readLvar("FSLA320_elevator_r") <= 1499 and 1499 - ipc.readLvar("FSLA320_elevator_r") < self.elevatorTolerance
end

function copilot.callouts.flightControlsCheck:fullDown()
  return
  3000 - ipc.readLvar("FSLA320_elevator_l") < self.elevatorTolerance and
  3000 - ipc.readLvar("FSLA320_elevator_r") < self.elevatorTolerance
end

function copilot.callouts.flightControlsCheck:fullLeftRud()
  return ipc.readLvar("FSLA320_rudder") <= self.fullLeftRudderTravel and self.fullLeftRudderTravel - ipc.readLvar("FSLA320_rudder") < self.rudderTolerance
end

function copilot.callouts.flightControlsCheck:fullRightRud()
  return self.fullRightRudderTravel - ipc.readLvar("FSLA320_rudder") < self.rudderTolerance
end

function copilot.callouts.flightControlsCheck:stickNeutral()
  local aileronsNeutral
  if ipc.readLvar("FSLA320_flap_l_1") == 0 then
    aileronsNeutral = (ipc.readLvar("FSLA320_aileron_l") < self.aileronTolerance or (ipc.readLvar("FSLA320_aileron_l") >= 1500 and ipc.readLvar("FSLA320_aileron_l") - 1500 < self.aileronTolerance)) and
                (ipc.readLvar("FSLA320_aileron_r") < self.aileronTolerance or (ipc.readLvar("FSLA320_aileron_r") >= 1500 and ipc.readLvar("FSLA320_aileron_r") - 1500 < self.aileronTolerance))
  elseif ipc.readLvar("FSLA320_flap_l_1") > 0 then
    aileronsNeutral = math.abs(ipc.readLvar("FSLA320_aileron_l") - 1980) < self.aileronTolerance and math.abs(ipc.readLvar("FSLA320_aileron_r") - 480) < self.aileronTolerance
  end
  return
  aileronsNeutral and
  --ipc.readLvar("FSLA320_spoiler_l_2") < self.spoilerTolerance and
  --ipc.readLvar("FSLA320_spoiler_l_3") < self.spoilerTolerance and
  --ipc.readLvar("FSLA320_spoiler_l_4") < self.spoilerTolerance and
  --ipc.readLvar("FSLA320_spoiler_l_5") < self.spoilerTolerance and
  --ipc.readLvar("FSLA320_spoiler_r_2") < self.spoilerTolerance and
  --ipc.readLvar("FSLA320_spoiler_r_3") < self.spoilerTolerance and
  --ipc.readLvar("FSLA320_spoiler_r_4") < self.spoilerTolerance and
  --ipc.readLvar("FSLA320_spoiler_r_5") < self.spoilerTolerance and
  (ipc.readLvar("FSLA320_elevator_l") < self.elevatorTolerance or (ipc.readLvar("FSLA320_elevator_l") >= 1500 and ipc.readLvar("FSLA320_elevator_l") - 1500 < self.elevatorTolerance)) and
  (ipc.readLvar("FSLA320_elevator_r") < self.elevatorTolerance or (ipc.readLvar("FSLA320_elevator_r") >= 1500 and ipc.readLvar("FSLA320_elevator_r") - 1500 < self.elevatorTolerance))
end

function copilot.callouts.flightControlsCheck:rudNeutral()
  return (ipc.readLvar("FSLA320_rudder") < self.rudderTolerance or (ipc.readLvar("FSLA320_rudder") >= 1500 and ipc.readLvar("FSLA320_rudder") - 1500 < self.rudderTolerance))
end

function copilot.callouts:setup()
  copilot.events.flightControlsChecked = Event:new{logMsg = "Flight controls checked"}
  copilot.events.brakesChecked = Event:new{logMsg = "Brakes are checked"}
  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.brakeCheck = VoiceCommand:new {phrase = "brake check", persistent = true}
    copilot.voiceCommands.flightControlsCheck = VoiceCommand:new {phrase = "flight control check", persistent = true}
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
          end) then return end
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

    local flightControlsCheckAction = Action:new(function() self:flightControlsCheck() end, Action.COROUTINE)
      :setLogMsg "Flight control check"
      :stopOn(copilot.events.engineShutdown, copilot.events.takeoffInitiated)

    if copilot.isVoiceControlEnabled then
      copilot.events.takeoffCancelled:addAction(function()
        if not self.flightControlsCheck.flightControlsChecked then
          copilot.voiceCommands.flightControlsCheck:activate()
        end
      end)
      copilot.voiceCommands.flightControlsCheck
        :activateOn(copilot.events.enginesStarted)
        :deactivateOn(copilot.events.engineShutdown, copilot.events.takeoffInitiated)
      copilot.voiceCommands.flightControlsCheck:addAction(flightControlsCheckAction)
    else
      copilot.events.enginesStarted:addAction(flightControlsCheckAction)
      copilot.events.takeoffCancelled:addAction(flightControlsCheckAction)
    end
    
    copilot.events.engineShutdown:addAction(function() self.flightControlsCheck.flightControlsChecked = false end):setLogMsg(Event.NOLOGMSG)
  end

  copilot.events.takeoffInitiated:addAction(function() self:takeoff() end, Action.COROUTINE)
    :setLogMsg("Takeoff callouts")
    :stopOn(copilot.events.takeoffAborted, copilot.events.takeoffCancelled)

  copilot.events.takeoffAborted:addAction(function()
    self.flightControlsCheck.flightControlsChecked = true
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
