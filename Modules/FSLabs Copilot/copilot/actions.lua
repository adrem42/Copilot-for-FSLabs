
local FSL = FSL
local Event = Event
local VoiceCommand = VoiceCommand
local copilot = copilot
local ipc = ipc

local firstFlight = true

local flapsLimits = {}

if FSL:getAcType() == "A321" then
  flapsLimits.flapsOne = 235
  flapsLimits.flapsTwo = 215
  flapsLimits.flapsThree = 195
  flapsLimits.flapsFull = 190
else
  flapsLimits.flapsOne = 230
  flapsLimits.flapsTwo = 200
  flapsLimits.flapsThree = 185
  flapsLimits.flapsFull = 177
end

if copilot.isVoiceControlEnabled then

  copilot.voiceCommands.flapsOne = VoiceCommand:new {
    phrase = "flaps one",
    confidence = 0.94,
    action = function()
      local flaps = FSL.PED_FLAP_LEVER:getPosn()
      local flyingCircuits = copilot.getFlightPhase() == copilot.flightPhases.flyingCircuits
      if flaps == "2" then
        local Vf = copilot.mcduWatcher:getVar("Vf")
        if Vf and copilot.IAS() < Vf then
          return
        else
          copilot.voiceCommands.flapsUp:activate()
          if flyingCircuits then
            copilot.voiceCommands.flapsTwo:activate()
          end
        end
      elseif not (flaps == "0" and copilot.IAS() <= flapsLimits.flapsOne) then
        return
      else
        copilot.voiceCommands.flapsTwo:activate()
        if flyingCircuits then
          copilot.voiceCommands.flapsUp:activate()
        end
      end
      copilot.voiceCommands.flapsOne:ignore()
      VoiceCommand:react(500)
      copilot.playCallout("flapsOne")
      FSL.PED_FLAP_LEVER("1")
      
    end,
    persistent = true
  }

  copilot.voiceCommands.flapsTwo = VoiceCommand:new {
    phrase = "flaps two",
    confidence = 0.94,
    action = function()
      local flyingCircuits = copilot.getFlightPhase() == copilot.flightPhases.flyingCircuits
      local flaps = FSL.PED_FLAP_LEVER:getPosn()
      if flaps == "3" then
        local Vf = copilot.mcduWatcher:getVar("Vf")
        if Vf and copilot.IAS() < Vf then
          return
        else
          copilot.voiceCommands.flapsOne:activate()
          if flyingCircuits then
            copilot.voiceCommands.flapsThree:activate()
          end
        end
      elseif not (flaps == "1" and copilot.IAS() <= flapsLimits.flapsTwo) then
        return
      else
        copilot.voiceCommands.flapsThree:activate()
        if flyingCircuits then
          copilot.voiceCommands.flapsOne:activate()
        end
      end
      copilot.voiceCommands.flapsTwo:ignore()
      VoiceCommand:react(500)
      copilot.playCallout("flapsTwo")
      FSL.PED_FLAP_LEVER("2")

    end,
    persistent = true
  }

  copilot.voiceCommands.flapsThree = VoiceCommand:new {
    phrase = "flaps three",
    confidence = 0.94,
    action = function()
      if FSL.PED_FLAP_LEVER:getPosn() == "2" and copilot.IAS() <= flapsLimits.flapsThree then
        copilot.voiceCommands.flapsThree:ignore()
        copilot.voiceCommands.flapsFull:activate()
        VoiceCommand:react(500)
        copilot.playCallout("flapsThree")
        FSL.PED_FLAP_LEVER("3")
      end
    end,
    persistent = true
  }

  copilot.voiceCommands.flapsFull = VoiceCommand:new {
    phrase = "flaps full",
    confidence = 0.94,
    action = function()
      if FSL.PED_FLAP_LEVER:getPosn() == "3"then
        if copilot.IAS() <= flapsLimits.flapsFull then
          copilot.voiceCommands.flapsFull:ignore()
          VoiceCommand:react(500)
          copilot.playCallout("flapsFull")
          FSL.PED_FLAP_LEVER("FULL")
        end
      end
    end,
    persistent = true
  }

  copilot.voiceCommands.flapsUp = VoiceCommand:new {
    phrase = {"flaps up", "flaps zero"},
    confidence = 0.94,
    action = function()
      if FSL.PED_FLAP_LEVER:getPosn() == "1" then
        local Vs = copilot.mcduWatcher:getVar("Vs")
        if Vs and copilot.IAS() < Vs then return end
        copilot.voiceCommands.flapsUp:ignore()
        if copilot.getFlightPhase() == copilot.flightPhases.flyingCircuits then
          copilot.voiceCommands.flapsOne:activate()
        end
        VoiceCommand:react(500)
        copilot.playCallout("flapsZero")
        FSL.PED_FLAP_LEVER("0")
        
      end
    end,
    persistent = true
  }

  copilot.voiceCommands.gearUp = VoiceCommand:new {
    phrase = "gear up",
    action = function()
      local flyingCircuits = copilot.getFlightPhase() == copilot.flightPhases.flyingCircuits
      if (copilot.airborneTime and ipc.elapsedtime() - copilot.airborneTime < 60000) or flyingCircuits then
        local flaps = FSL.PED_FLAP_LEVER:getPosn()
        if flaps == "3" then
          copilot.voiceCommands.flapsOne:activate()
          if flyingCircuits then
            copilot.voiceCommands.flapsTwo:activate()
          end
        elseif flaps == "2" then
          copilot.voiceCommands.flapsOne:activate()
          if flyingCircuits then
            copilot.voiceCommands.flapsThree:activate()
          end
        elseif flaps == "1" then
          copilot.voiceCommands.flapsUp:activate()
          if flyingCircuits then
            copilot.voiceCommands.flapsTwo:activate()
          end
        end
        if flyingCircuits then
          copilot.voiceCommands.gearDown:activate()
        end
        copilot.voiceCommands.gearUp:ignore()
        
        VoiceCommand:react()
        FSL.MIP_GEAR_Lever("UP")
      end
    end,
    persistent = true
  }
    :deactivateOn(copilot.events.takeoffCancelled, copilot.events.takeoffAborted)
    :activateOn(copilot.events.goAround, copilot.events.takeoffInitiated)

  copilot.actions.airborne = copilot.events.airborne:addAction(function()
    copilot.voiceCommands.lineup:deactivate()
    copilot.voiceCommands.takeoff:deactivate()
    copilot.voiceCommands.gearDown:ignore()
    copilot.voiceCommands.flapsOne:ignore()
    copilot.voiceCommands.flapsTwo:ignore()
    copilot.voiceCommands.flapsThree:ignore()
    copilot.voiceCommands.flapsFull:ignore()
    copilot.voiceCommands.flapsUp:ignore()
  end)

  copilot.voiceCommands.goAroundFlaps = VoiceCommand:new {
    phrase = "go around, flaps!",
    action = function()
      local flaps = FSL.PED_FLAP_LEVER:getPosn()
      VoiceCommand:react()
      if flaps == "FULL" then
        FSL.PED_FLAP_LEVER("3")
        copilot.voiceCommands.flapsTwo:activate()
      elseif flaps == "3" then
        FSL.PED_FLAP_LEVER("2")
        copilot.voiceCommands.flapsThree:activate()
        copilot.voiceCommands.flapsOne:activate()
      elseif flaps == "2" then
        FSL.PED_FLAP_LEVER("1")
        copilot.voiceCommands.flapsTwo:activate()
        copilot.voiceCommands.flapsUp:activate()
      end
    end
  }

  copilot.events.goAround:addAction(function()
    copilot.voiceCommands.goAroundFlaps:activate()
    copilot.suspend(20000)
    copilot.voiceCommands.goAroundFlaps:deactivate()
  end)

  copilot.voiceCommands.gearDown = VoiceCommand:new {
    phrase = "gear down",
    confidence = 0.94,
    dummy = "... gear ...",
    action = function()
      copilot.voiceCommands.gearDown:ignore()
      VoiceCommand:react()
      FSL.MIP_GEAR_Lever("DN")
      FSL.PED_SPD_BRK_LEVER("ARM")
    end,
    persistent = true
  }

  copilot.voiceCommands.taxiLightOff = VoiceCommand:new {
    phrase = {"taxi light off", "taxilightoff"},
    action = function() FSL.OVHD_EXTLT_Nose_Switch("OFF") end
  }

end

local pauseScratchpadClearerThreads = {}

function copilot.dontClearScratchPad(value, thread)
  pauseScratchpadClearerThreads[thread or coroutine.running()] = not value and nil or true
end

if copilot.UserOptions.actions.PM_clears_scratchpad == 1 then
  copilot.addCallback(coroutine.create(function()
    local clearScratchpadTime, scratchpadMsg

    local function dirtyScratchpad()
      local disp = FSL.MCDU:getString()
      local scratchpad = disp:sub(313, 330)
      return scratchpad:find "%S" and not disp:find "MCDU MENU"
    end

    while true do
      copilot.suspend(1000)
      if dirtyScratchpad() then
        local now = ipc.elapsedtime()
        if not clearScratchpadTime then
          scratchpadMsg = scratchpad
          clearScratchpadTime = now + math.random(1000, 5000)
        elseif scratchpad ~= scratchpadMsg then
          clearScratchpadTime = nil
        elseif now > clearScratchpadTime then
          local okToClear = true
          for thread in pairs(pauseScratchpadClearerThreads) do
            if Action.getActionFromThread(thread) then
              okToClear = false
            else
              copilot.dontClearScratchPad(false, thread)
            end
          end
          if okToClear then
            repeat
              FSL.PED_MCDU_KEY_CLR()
              copilot.sleep(500, 1000)
            until not dirtyScratchpad()
          end
          clearScratchpadTime = nil
        end
      end
    end
  end), "scratchpadClearer")
end

function copilot.sequences:checkFmgcData()

  FSL.PED_MCDU_KEY_DATA()
  copilot.suspend(plusminus(1000))
  FSL.PED_MCDU_LSK_L4()
  copilot.suspend(5000,10000)
  if prob(0.1) then copilot.suspend(5000,10000) end
  FSL.PED_MCDU_KEY_INIT()
  copilot.suspend(5000,10000)
  if prob(0.1) then copilot.suspend(5000,10000) end
  FSL.PED_MCDU_KEY_RIGHT()
  copilot.suspend(5000,10000)
  if prob(0.1) then copilot.suspend(5000,10000) end
  FSL.PED_MCDU_KEY_PERF()
  copilot.suspend(5000,10000)
  if prob(0.1) then copilot.suspend(5000,10000) end
  FSL.PED_MCDU_KEY_FPLN()
  FSL.GSLD_EFIS_CSTR_Button:pressIfNotLit()
  FSL.GSLD_EFIS_ND_Mode_Knob("PLAN")
  FSL.GSLD_EFIS_ND_Range_Knob("20")
  copilot.suspend(0,5000)
  if prob(0.3) then
    copilot.suspend(10000,30000)
  end
  local terminal, wasTerminal = true, true
  local function endOfFPLN(disp) return disp:sub(241,244) == disp:sub(289,292) or disp:sub(193,196) == disp:sub(289,292) end
  repeat
    local disp = FSL.MCDU:getString()
    terminal = disp:sub(126,126) ~= " "
    if terminal and not wasTerminal then
      repeat 
        local disp = FSL.MCDU:getString()
        FSL.PED_MCDU_KEY_UP()
        copilot.suspend(100,300)
      until endOfFPLN(disp)
      if prob(0.5) then
        for i = 1,math.random(3) do
          FSL.PED_MCDU_KEY_UP()
        end
      end
      break
    end
    FSL.PED_MCDU_KEY_UP()
    if not terminal then
      if wasTerminal then
        copilot.sleep(5000,7000)
        FSL.GSLD_EFIS_ND_Range_Knob("80")
        copilot.suspend(2000,3000)
        FSL.PED_MCDU_KEY_UP()
        FSL.PED_MCDU_KEY_UP()
        copilot.suspend(5000,7000)
      end
      copilot.sleep(plusminus(70))
      FSL.PED_MCDU_KEY_UP()
    end
    copilot.suspend(3000,5000)
    if prob(0.1) then
      copilot.suspend(1000,2000)
    end
    wasTerminal = terminal
  until endOfFPLN(disp)
  copilot.suspend(1000,3000)
  FSL.PED_MCDU_KEY_FPLN()
  copilot.suspend(1000,3000)
  FSL.PED_MCDU_KEY_SEC()
  copilot.suspend(plusminus(2000))
  if FSL.MCDU:getString():find("DELETE") then
    FSL.PED_MCDU_LSK_L2()
    copilot.suspend(plusminus(2000))
    repeat
      local disp = FSL.MCDU:getString()
      FSL.PED_MCDU_KEY_UP()
      copilot.sleep(100,300)
    until endOfFPLN(disp)
    copilot.suspend(plusminus(1000))
  end
  FSL.PED_MCDU_KEY_FPLN()
end

function copilot.sequences:setupEFIS()

  FSL.GSLD_EFIS_CSTR_Button:pressIfNotLit()

  FSL.GSLD_EFIS_ND_Range_Knob(prob(0.5) and "10" or "20")
  FSL.GSLD_EFIS_ND_Mode_Knob("ARC")
  FSL.GSLD_EFIS_VORADF_1_Switch("VOR")
  FSL.GSLD_VORADF_2_Switch("VOR")

  FSL.GSLD_EFIS_FD_Button:pressIfNotLit()

end

function copilot.sequences:afterStart()

  FSL.PED_SPD_BRK_LEVER "ARM"

  local flapsSetting = copilot.mcduWatcher:getVar "takeoffFlaps" or FSL:getTakeoffFlapsFromMcdu()
  local msg
  if flapsSetting then
    msg = "Setting the takeoff flaps using the setting found in the MCDU: %s"
  else
    flapsSetting = FSL.atsuLog:getTakeoffFlaps()
    if flapsSetting then
      msg = "No takeoff flaps setting found in the MCDU, taking the setting from the latest ATSU performance request: %s"
    else
      msg = "Unable to set takeoff flaps: no setting found in the MCDU and no performance request found in the ATSU log."
    end
  end
  copilot.logger:info(string.format(msg, flapsSetting))
  if flapsSetting then
    FSL.PED_FLAP_LEVER(tostring(flapsSetting))
  end

  repeat copilot.suspend() until not copilot.GSX_pushback()
  
  local CG = FSL.atsuLog:getMACTOW()
  local msg
  if CG then
    msg = "Setting the takeoff trim using the MACTOW from the latest ATSU loadsheet: %.2f%%"
  else
    CG = ipc.readDBL(0x2EF8) * 100
    msg = "No ATSU loadsheet found, setting the takeoff trim using the simulator CG variable: %.2f%%"
  end
  copilot.logger:info(msg:format(CG))

  FSL.trimwheel:set(CG)
end

function copilot.sequences:taxiSequence()
  FSL.PED_WXRadar_SYS_Switch(FSL:getPilot() == 1 and "2" or "1")
  FSL.PED_WXRadar_PWS_Switch("AUTO")
  copilot.sleep(100)
  FSL.PED_WXRadar_PWS_Switch("AUTO")
  FSL.MIP_BRAKES_AUTOBRK_MAX_Button()
  for _ = 1, 5 do
    FSL.PED_ECP_TO_CONFIG_Button()
    copilot.sleep(50, 100)
  end
end

function copilot.sequences:waitForLineup()
  local countStartTime
  local count = 0
  local prevSwitchPos
  repeat
    local switchPos = FSL.OVHD_SIGNS_SeatBelts_Switch:getLvarValue()
    if prevSwitchPos and prevSwitchPos ~= switchPos then
      count = count + 1
      if count == 0 then countStartTime = ipc.elapsedtime() end
    end
    if countStartTime and ipc.elapsedtime() - countStartTime > 2000 then
      count = 0
      countStartTime = nil
    end
    prevSwitchPos = switchPos
    copilot.suspend()
  until count == 4
end

function copilot.sequences:lineUpSequence()
  
  FSL.PED_ATCXPDR_ON_OFF_Switch "ON"
  FSL.PED_ATCXPDR_MODE_Switch "TARA"

  local packs = FSL.atsuLog:getTakeoffPacks()
  local msgLeaveAlone, msgOff
  if packs then
    msgOff = "Switching the packs off as per the latest ATSU performance request."
    msgLeaveAlone = "'PACKS ON' found in the latest ATSU performance request, leaving the packs at the current setting."
  else
    packs = copilot.UserOptions.actions.packs_on_takeoff
    msgOff = "No ATSU performance request found, packs_on_takeoff=0 — switching the packs off."
    msgLeaveAlone = "No ATSU performance request found, packs_on_takeoff=1 — leaving the packs at the current setting."
  end
  copilot.logger:info(packs == 0 and msgOff or msgLeaveAlone)

  if packs == 0 then
    FSL.OVHD_AC_Pack_1_Button:toggleUp()
    FSL.OVHD_AC_Pack_2_Button:toggleUp()
  end

end

function copilot.sequences:takeoffSequence()

  firstFlight = false

  FSL.MIP_CHRONO_ELAPS_SEL_Switch "RUN"

  if copilot.UserOptions.actions.after_landing == 1 then 
    FSL.GSLD_Chrono_Button() 
  end

end

function copilot.sequences:afterTakeoffSequence()

  FSL.OVHD_AC_Pack_1_Button:toggleDown()
  copilot.suspend(plusminus(10000,0.2))
  FSL.OVHD_AC_Pack_2_Button:toggleDown()

  repeat copilot.suspend() until ipc.readLvar "FSLA320_slat_l_1" == 0

  copilot.suspend(plusminus(2000, 0.5))

  FSL.PED_SPD_BRK_LEVER "RET"
end

function copilot.sequences.tenThousandDep()

  moveTwoSwitches(FSL.OVHD_EXTLT_Land_L_Switch, "RETR", FSL.OVHD_EXTLT_Land_R_Switch,"RETR", 0.9)

  FSL.PED_MCDU_KEY_RADNAV()
  copilot.sleep(plusminus(1000))
  local disp = FSL.MCDU:getArray()
  local VOR1 = disp[49].isBold or disp[54].isBold
  local VOR2 = disp[71].isBold or disp[62].isBold
  local ADF1 = (disp[241].isBold and disp[241].char ~= "[") or (disp[246].isBold and disp[246].char ~= "[")
  local ADF2 = (disp[261].isBold and disp[261].char ~= "[") or (disp[254].isBold and disp[254].char ~= "[")

  if VOR1 or VOR2 or ADF1 or ADF2 then 
    while not (FSL.MCDU:getScratchpad():sub(6,8) == "CLR") do
      FSL.PED_MCDU_KEY_CLR()
      copilot.sleep(100)
    end
    local clr = true
    if VOR1 then
      if not clr then FSL.PED_MCDU_KEY_CLR() end
      FSL.PED_MCDU_LSK_L1()
      if clr then clr = false end
    end
    if VOR2 then
      if not clr then FSL.PED_MCDU_KEY_CLR() end
      FSL.PED_MCDU_LSK_R1() 
      if clr then clr = false end
    end
    if ADF1 then 
      if not clr then FSL.PED_MCDU_KEY_CLR() end
      FSL.PED_MCDU_LSK_L5() 
      if clr then clr = false end
    end
    if ADF2 then 
      if not clr then FSL.PED_MCDU_KEY_CLR() end
      FSL.PED_MCDU_LSK_R5()
    end
  end

  copilot.sleep(plusminus(1000))

  FSL.PED_MCDU_KEY_SEC()
  copilot.sleep(plusminus(1000))
  FSL.PED_MCDU_LSK_L1()

  copilot.sleep(plusminus(2000))

  FSL.PED_MCDU_KEY_FPLN()

  FSL.GSLD_EFIS_ARPT_Button:pressIfNotLit()
  FSL.GSLD_EFIS_ND_Range_Knob "160"
  FSL.GSLD_EFIS_VORADF_1_Switch "VOR"
  FSL.GSLD_VORADF_2_Switch "VOR"

end

function copilot.sequences:tenThousandArr()

  FSL.PED_MCDU_KEY_PERF()
  copilot.sleep(plusminus(500))
  while not FSL.MCDU:getString(1, 48):find "APPR" do
    FSL.PED_MCDU_LSK_R6()
    copilot.sleep(100)
  end
  local disp = FSL.MCDU:getString(49, 71)
  local shouldLSbeOn = disp:find "ILS" or disp:find "LOC"

  moveTwoSwitches(FSL.OVHD_EXTLT_Land_L_Switch, "ON", FSL.OVHD_EXTLT_Land_R_Switch,"ON", 0.9)
  FSL.OVHD_SIGNS_SeatBelts_Switch "ON"

  FSL.GSLD_EFIS_CSTR_Button:pressIfNotLit()
  FSL.GSLD_EFIS_ND_Range_Knob "20"
  FSL.GSLD_EFIS_LS_Button:pressForLightState(shouldLSbeOn)

  FSL.PED_MCDU_KEY_RADNAV()
  copilot.sleep(plusminus(5000))
  FSL.PED_MCDU_KEY_PROG()

end

copilot.sequences.afterLanding = {
  noApu = false,
  isRunning = false
}
setmetatable(copilot.sequences.afterLanding, copilot.sequences.afterLanding)

function copilot.sequences.afterLanding:__call()

  self.isRunning = true

  FSL.PED_FLAP_LEVER "0"
  FSL.PED_ATCXPDR_MODE_Switch "STBY"

  FSL.MIP_CHRONO_ELAPS_SEL_Switch "STP"
  if copilot.UserOptions.actions.takeoff_sequence == 1 then 
    FSL.GSLD_Chrono_Button() 
  end

  FSL.OVHD_EXTLT_Strobe_Switch "AUTO"
  FSL.OVHD_EXTLT_RwyTurnoff_Switch "OFF"
  moveTwoSwitches(FSL.OVHD_EXTLT_Land_L_Switch, "RETR", FSL.OVHD_EXTLT_Land_R_Switch,"RETR", 0.9)
  FSL.OVHD_EXTLT_Nose_Switch "TAXI"

  FSL.PED_WXRadar_SYS_Switch "OFF"
  FSL.PED_WXRadar_PWS_Switch "OFF"

  local shouldFDsBeOn = copilot.UserOptions.actions.FDs_off_after_landing == 0

  FSL.PF.GSLD_EFIS_FD_Button:pressForLightState(shouldFDsBeOn)
  FSL.PF.GSLD_EFIS_LS_Button:pressIfLit()

  if FSL.FCU:get().isBirdOn then 
    FSL.GSLD_FCU_HDGTRKVSFPA_Button() 
  end

  FSL.GSLD_EFIS_LS_Button:pressIfLit()
  FSL.GSLD_EFIS_FD_Button:pressForLightState(shouldFDsBeOn)

  if copilot.UserOptions.actions.pack2_off_after_landing == 1 then 
    FSL.OVHD_AC_Pack_2_Button:toggleUp()
  end

  copilot.suspend()

  copilot.voiceCommands.noApu:deactivate()
  self.isRunning = false

  if not self.noApu then
    FSL:startTheApu()
  end

  self.noApu = false

end

copilot.events.takeoffInitiated2 = Event:new {logMsg = "Starting takeoff actions"}

copilot.actions.preflight = copilot.events.chocksSet:addAction(function()
  if not firstFlight then
    copilot.suspend(1 * 60000, 3 * 60000)
    FSL.MIP_CHRONO_ELAPS_SEL_Switch("RST")
    if copilot.UserOptions.actions.after_landing == 1 and copilot.UserOptions.actions.takeoff_sequence == 1 then 
      FSL.GSLD_Chrono_Button()
    end
  end
  if copilot.UserOptions.actions.preflight == 1 then
    repeat copilot.suspend() until copilot.mcduWatcher:getVar("isFmgcSetup")
    copilot.logger:info("FMGC is set up")
    if prob(0.05) then
      copilot.suspend(0, 20000)
    else
      copilot.suspend(20000, 2 * 60000)
      if prob(0.5) then copilot.suspend(0, 60000) end
    end
    copilot.sequences:checkFmgcData()
    copilot.suspend(0,10000)
    if prob(0.2) then copilot.suspend(10000, 20000) end
    copilot.sequences:setupEFIS()
  end
end, "runAsCoroutine")
  :stopOn(copilot.events.enginesStarted)

if copilot.UserOptions.actions.after_start == 1 then
  copilot.actions.afterStart = copilot.events.enginesStarted:addAction(function() copilot.sequences:afterStart() end, "runAsCoroutine")
end

if copilot.UserOptions.actions.during_taxi == 1 then

  copilot.actions.taxi = copilot.events.enginesStarted:addAction(function()
    Event.waitForEvents({copilot.events.brakesChecked, copilot.events.flightControlsChecked}, true)
    copilot.suspend(plusminus(5000))
    copilot.callOnce(copilot.sequences.taxiSequence)
  end, "runAsCoroutine")
    :stopOn(copilot.events.chocksSet, copilot.events.takeoffInitiated2)

end

if copilot.UserOptions.actions.lineup == 1 then
  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.lineup = VoiceCommand:new {
      phrase = "lineup procedure",
      persistent = "ignore",
      confidence = 0.94,
      action = {function()
        if copilot.UserOptions.actions.takeoff_sequence == 1 then
          copilot.voiceCommands.takeoff:activate()
        end
        copilot.sequences.lineUpSequence()
      end}
    }
      :activateOn(copilot.events.enginesStarted)
      :deactivateOn(copilot.events.takeoffInitiated2, copilot.events.engineShutdown)
  else
    copilot.actions.lineup = copilot.events.enginesStarted:addAction(function()
      copilot.sequences:waitForLineup()
      copilot.callOnce(copilot.sequences.lineUpSequence)
    end, "runAsCoroutine")
      :stopOn(copilot.events.takeoffInitiated2, copilot.events.engineShutdown)
  end
end

do

  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.takeoff = VoiceCommand:new{
      phrase = "takeoff",
      confidence = 0.94,
      dummy = {"... takeoff", "takeoff ...", "takeoffrunway", "takeoff runway", "before takeoff", "beforetakeoff"},
      action = function()
        copilot.actions.noVoiceTakeoffTrigger:stopCurrentThread()
        copilot.events.takeoffInitiated2:trigger()
      end
    }
  end

  copilot.actions.takeoff = copilot.events.takeoffInitiated2:addAction(function()
    if copilot.isVoiceControlEnabled and copilot.UserOptions.actions.lineup == 1 then
      copilot.voiceCommands.lineup:deactivate()
    end
    if copilot.UserOptions.actions.takeoff_sequence == 1 then
      copilot.sequences.takeoffSequence()
    end
  end)

  if copilot.UserOptions.actions.after_takeoff == 1 then
    copilot.actions.afterTakeoff = copilot.events.airborne:addAction(function()
      repeat copilot.suspend() until FSL:getThrustLeversPos() == "CLB"
      copilot.suspend(plusminus(2000))
      copilot.sequences.afterTakeoffSequence()
    end, "runAsCoroutine")
      :stopOn(copilot.events.landing)
  end

  copilot.actions.noVoiceTakeoffTrigger = copilot.events.enginesStarted:addAction(function()
    repeat copilot.suspend()
    until copilot.thrustLeversSetForTakeoff() and FSL.OVHD_EXTLT_Land_L_Switch:getPosn() == "ON" and FSL.OVHD_EXTLT_Land_R_Switch:getPosn() == "ON"
    if copilot.isVoiceControlEnabled then
      copilot.voiceCommands.takeoff:deactivate()
    end
    copilot.events.takeoffInitiated2:trigger()
  end, "runAsCoroutine")

end

copilot.actions.aboveTenThousand = copilot.events.aboveTenThousand:addAction(function()
  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.flapsOne:deactivate()
    copilot.voiceCommands.gearDown:deactivate()
    copilot.voiceCommands.flapsTwo:deactivate()
    copilot.voiceCommands.flapsThree:deactivate()
    copilot.voiceCommands.flapsFull:deactivate()
    copilot.voiceCommands.flapsUp:deactivate()
    copilot.voiceCommands.gearUp:deactivate()
  end
  if copilot.UserOptions.actions.ten_thousand_dep == 1 then
    copilot.dontClearScratchPad(true)
    copilot.sequences.tenThousandDep()
  end
end, "runAsCoroutine")

copilot.actions.belowTenThousand = copilot.events.belowTenThousand:addAction(function()
  if copilot.isVoiceControlEnabled then
    local flapsPos = FSL.PED_FLAP_LEVER:getPosn()
    local flapsVoiceCommand = {
      ["0"] = "flapsOne",
      ["1"] = "flapsTwo",
      ["2"] = "flapsThree",
      ["3"] = "flapsFull",
    }
    if flapsPos ~= "FULL" then
      copilot.voiceCommands[flapsVoiceCommand[flapsPos]]:activate()
    end
    flapsVoiceCommand[flapsPos] = nil
    for _, v in pairs(flapsVoiceCommand) do
      copilot.voiceCommands[v]:ignore()
    end
    copilot.voiceCommands.gearDown:activate()
    copilot.voiceCommands.flapsUp:ignore()
    copilot.voiceCommands.gearUp:ignore()
  end
  if copilot.UserOptions.actions.ten_thousand_arr == 1 then
    copilot.sequences:tenThousandArr()
  end
end, "runAsCoroutine")

copilot.actions.landing = copilot.events.landing:addAction(function()
  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.flapsOne:deactivate()
    copilot.voiceCommands.flapsTwo:deactivate()
    copilot.voiceCommands.flapsThree:deactivate()
    copilot.voiceCommands.flapsFull:deactivate()
    copilot.voiceCommands.flapsUp:deactivate()
    copilot.voiceCommands.gearDown:deactivate()
    copilot.voiceCommands.gearUp:deactivate()
  end
  if copilot.UserOptions.actions.after_landing == 1 then
    if copilot.isVoiceControlEnabled and copilot.UserOptions.actions.after_landing_trigger == 1 then
      repeat copilot.suspend() until copilot.GS() < 40
      copilot.voiceCommands.afterLanding:activate()
      copilot.voiceCommands.afterLandingNoApu:activate()
    else
      repeat copilot.suspend() until (copilot.GS() < 30 and FSL.PED_SPD_BRK_LEVER:getPosn() ~= "ARM") or not copilot.enginesRunning()
      copilot.sleep(plusminus(5000, 0.5))
      if copilot.enginesRunning() then
        if copilot.isVoiceControlEnabled then
          copilot.voiceCommands.noApu:activate()
        end
        copilot.sequences:afterLanding()
      end
    end
  end
  
  repeat copilot.suspend() until copilot.GS() < 30
  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.taxiLightOff:activate()
  end
end, "runAsCoroutine")

if copilot.isVoiceControlEnabled then

  copilot.voiceCommands.afterLanding = VoiceCommand:new {
    phrase = {
      "after landing",
      "check after landing"
    },
    action = {function()
      copilot.sequences.afterLanding.noApu = false
      copilot.voiceCommands.noApu:activate()
      copilot.voiceCommands.afterLandingNoApu:deactivate()
      
      copilot.sequences:afterLanding()
    end, "runAsCoroutine"}
  }

  copilot.voiceCommands.afterLandingNoApu = VoiceCommand:new {
    phrase = {
      "after landing no apu",
      "after landing hold apu",
      "check after landing no apu",
      "check after landing hold apu"
    },
    action = {function()
      copilot.sequences.afterLanding.noApu = true
      copilot.voiceCommands.startApu:activate()
      copilot.voiceCommands.afterLanding:deactivate()
  
      copilot.sequences:afterLanding()
    end, "runAsCoroutine"}
  }

  copilot.voiceCommands.noApu = VoiceCommand:new {
    phrase = {"no apu", "hold apu"},
    confidence = 0.95,
    action = function()
      copilot.sequences.afterLanding.noApu = true
      copilot.voiceCommands.startApu:activate()
    end
  }

  copilot.voiceCommands.startApu = VoiceCommand:new {
    phrase = {
      "start apu",
      "start the apu",
      "staraypeeyou",
      "start the aypeeyou"
    },
    action = function()
      if copilot.sequences.afterLanding.isRunning then
        copilot.sequences.afterLanding.noApu = false
      else
        FSL:startTheApu()
      end
    end
  }

end