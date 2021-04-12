
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

copilot.callouts = {}

function copilot.callouts:resetFlags()
  self.noReverseTimeRef = nil
  self.noDecelTimeRef = nil
  self.reverseFuncEndedTime = nil
  self.landedTime = nil
  self.checkingFlightControls = false
  self.brakesChecked = false
  self.flightControlsChecked = false
end

local aicraftDir = ipc.readSTR(0x3C00,256):match("(.+\\).+")

local function getFslV1Option()
  local aircraftCfg = file.read(aicraftDir .. "aircraft.cfg")
  local textureDir = aircraftCfg:match("texture=(.-)\n", aircraftCfg:find(copilot.aircraftTitle, nil, true))
  local fltsimCfg = file.read(string.format("%s\\Texture.%s\\fltsim.cfg", aicraftDir, textureDir)) or ""
  return tonumber(fltsimCfg:match("sdac_v1_call=(%d)"))
end

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
  repeat
    copilot.suspend(plusminus(timeWindow,0.2))
    eng1_N1 = copilot.eng1N1()
    eng2_N1 = copilot.eng2N1()
    local thrustSet = eng1_N1 > 80 and eng2_N1 > 80 and math.abs(eng1_N1 - eng1_N1_prev) < N1_window and math.abs(eng2_N1 - eng2_N1_prev) < N1_window
    local skipThis = not thrustSet and copilot.IAS() > 80
    eng1_N1_prev = eng1_N1
    eng2_N1_prev = eng2_N1
    if thrustSet then
      copilot.playCallout("thrustSet")
    end
  until thrustSet or skipThis
end

function copilot.callouts:waitForOneHundred()
  while true do
    if copilot.radALT() < 10 and copilot.IAS() >= 100 then
      copilot.playCallout("oneHundred", PFD_delay)
      return
    end
    copilot.suspend(100)
  end
end

function copilot.callouts:waitForV1(V1)
  while true do
    copilot.suspend(100)
    if copilot.radALT() < 10 and copilot.IAS() >= V1 then
      copilot.playCallout("V1", PFD_delay)
      return
    end
  end
end

function copilot.callouts:waitForVr(Vr)
  while true do
    if copilot.radALT() < 10 and copilot.IAS() >= Vr then
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
      copilot.sleep(plusminus(800,0.2))
      copilot.playCallout("pressureZero", delay)
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

function copilot.callouts.flightControlsCheck:randomDelay()
  copilot.sleep(plusminus(150))
  if prob(0.2) then copilot.sleep(100) end
end

function copilot.callouts.flightControlsCheck:__call()
  if FSL:getAcType() == "A319" then
    self.fullLeftRudderTravel = 1243
    self.fullRightRudderTravel = 2743
  else
    self.fullLeftRudderTravel = 1499
    self.fullRightRudderTravel = 3000
  end
  copilot.suspend(30000)
  local fullLeft, fullRight, fullLeftRud, fullRightRud, fullUp, fullDown, xNeutral, yNeutral, rudNeutral

  self.checkingFlightControls = false

  repeat
    copilot.suspend(100)
    -- full left aileron
    if not fullLeft and not ((fullUp or fullDown) and not yNeutral) and self:fullLeft() then
      copilot.sleep(ECAM_delay)
      self:randomDelay()
      copilot.playCallout("fullLeft_1")
      fullLeft = true
    end
    -- full right aileron
    if not fullRight and not ((fullUp or fullDown) and not yNeutral) and self:fullRight() then
      copilot.sleep(ECAM_delay)
      self:randomDelay()
      copilot.playCallout("fullRight_1")
      fullRight = true
    end
    -- neutral after full left and full right aileron
    if fullLeft and fullRight and not xNeutral and self:stickNeutral() then
      copilot.sleep(ECAM_delay)
      self:randomDelay()
      copilot.playCallout("neutral_1")
      xNeutral = true
    end
    -- full up
    if not fullUp and not ((fullLeft or fullRight) and not xNeutral) and self:fullUp() then
      copilot.sleep(ECAM_delay)
      self:randomDelay()
      copilot.playCallout("fullUp")
      fullUp = true
    end
    -- full down
    if not fullDown and not ((fullLeft or fullRight) and not xNeutral) and self:fullDown() then
      copilot.sleep(ECAM_delay)
      self:randomDelay()
      copilot.playCallout("fullDown")
      fullDown = true
    end
    -- neutral after full up and full down
    if fullUp and fullDown and not yNeutral and self:stickNeutral() then
      copilot.sleep(ECAM_delay)
      self:randomDelay()
      copilot.playCallout("neutral_3")
      yNeutral = true
    end
    -- full left rudder
    if not fullLeftRud and xNeutral and yNeutral and self:fullLeftRud() then
      copilot.sleep(ECAM_delay)
      self:randomDelay()
      copilot.playCallout("fullLeft_2")
      fullLeftRud = true
    end
    -- full right rudder
    if not fullRightRud and xNeutral and yNeutral and self:fullRightRud() then
      copilot.sleep(ECAM_delay)
      self:randomDelay()
      copilot.playCallout("fullRight_2")
      fullRightRud = true
    end
    -- neutral after full left and full right rudder
    if fullLeftRud and fullRightRud and not rudNeutral and self:rudNeutral() then
      copilot.sleep(ECAM_delay)
      self:randomDelay()
      copilot.playCallout("neutral_2")
      rudNeutral = true
    end

    if fullLeft or fullUp or fullRight or fullLeft or fullDown or fullLeftRud or fullRightRud then
      self.checkingFlightControls = true
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
  end
end

function copilot.callouts:start()

  copilot.events.chocksSet:addAction(function() self:resetFlags() end)

  if copilot.UserOptions.callouts.PM_announces_brake_check == 1 then
    if copilot.isVoiceControlEnabled then

      copilot.events.takeoffCancelled:addAction(function()
        if not self.brakesChecked then
          copilot.voiceCommands.brakeCheck:activate()
        end
      end)

      copilot.voiceCommands.brakeCheck
        :activateOn(copilot.events.enginesStarted)
        :deactivateOn(copilot.events.engineShutdown, copilot.events.takeoffInitiated)
      copilot.voiceCommands.brakeCheck:addAction(function()
        local timedOut = not checkWithTimeout(5000, function()
            copilot.suspend(100)
          return self.brakeCheck:brakeCheckConditions()
        end)
        if timedOut then return end
        if self:brakeCheck() then
          copilot.voiceCommands.brakeCheck:ignore()
        end
        end, Action.COROUTINE):addLogMsg "Brake check"
    else

      copilot.events.enginesStarted:addAction(function()
        repeat copilot.suspend(100) until self:brakeCheck()
        self.brakesChecked = true
      end, Action.COROUTINE)
        :addLogMsg "Waiting for the brake check"
        :stopOn(copilot.events.engineShutdown)
    end
  end

  if copilot.UserOptions.callouts.PM_announces_flightcontrol_check == 1 then

    local flightControlsCheckAction = Action:new(function()
      if not self.flightControlsChecked then self:flightControlsCheck() end
    end, Action.COROUTINE)
      :addLogMsg("Waiting for the flight controls check")
      :stopOn(copilot.events.engineShutdown, copilot.events.takeoffInitiated)

    copilot.events.enginesStarted:addAction(flightControlsCheckAction)
    copilot.events.takeoffCancelled:addAction(flightControlsCheckAction)
    copilot.events.engineShutdown:addAction(function() self.flightControlsChecked = false end)
  end

  copilot.events.takeoffInitiated:addAction(function() self:takeoff() end, Action.COROUTINE)
    :addLogMsg("Takeoff callouts")
    :stopOn(copilot.events.takeoffAborted, copilot.events.takeoffCancelled)

  copilot.events.takeoffAborted:addAction(function()
    self.flightControlsChecked = true
    self.brakesChecked = true
    if copilot.GS() > 60 then
      self:rollout(true)
    end
  end, Action.COROUTINE):addLogMsg "Aborted takeoff callouts"

  copilot.events.touchdown:addAction(function() self:rollout(false) end, Action.COROUTINE)
    :addLogMsg("Rollout callouts")
    :stopOn(copilot.events.goAround)

  copilot.events.landing:addAction(function()
    self.landedTime = copilot.getTimestamp()
  end)
end

return callouts