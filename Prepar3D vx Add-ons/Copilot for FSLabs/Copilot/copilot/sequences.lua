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
  local flapsMessage
  if flapsSetting then
    flapsMessage = "Setting the takeoff flaps using the setting from the MCDU: %s"
  else
    flapsSetting = FSL.atsuLog:getTakeoffFlaps()
    if flapsSetting then
      flapsMessage = "No takeoff flaps setting found in the MCDU, taking the F/L setting from the latest ATSU performance request: %s"
    else
      flapsMessage = "Unable to set takeoff flaps: no setting found in the MCDU, no performance request found in the ATSU log."
    end
  end
  copilot.logger:info(flapsMessage:format(flapsSetting))
  if flapsSetting then
    FSL.PED_FLAP_LEVER(tostring(flapsSetting))
  end

  repeat copilot.suspend(1000) until not copilot.GSX_pushback()
  
  local CG = FSL.atsuLog:getMACTOW()
  local trimMessage
  if CG then
    trimMessage = "Setting the takeoff trim using the MACTOW from the latest ATSU loadsheet: %.2f%%"
  else
    CG = copilot.CG()
    trimMessage = "No ATSU loadsheet found, setting the takeoff trim using the simulator CG variable: %.2f%%"
  end
  copilot.logger:info(trimMessage:format(CG))

  FSL.trimwheel:set(CG)

end

function copilot.sequences:taxiSequence()
  FSL.PED_WXRadar_SYS_Switch(FSL:getPilot() == 1 and "2" or "1")
  FSL.PED_WXRadar_PWS_Switch "AUTO"
  copilot.sleep(100)
  FSL.PED_WXRadar_PWS_Switch "AUTO"
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
      if count == 0 then countStartTime = copilot.getTimestamp() end
    end
    if countStartTime and copilot.getTimestamp() - countStartTime > 2000 then
      count = 0
      countStartTime = nil
    end
    prevSwitchPos = switchPos
    copilot.suspend(100)
  until count == 4
end

function copilot.sequences:lineUpSequence()
  
  FSL.PED_ATCXPDR_ON_OFF_Switch "ON"
  FSL.PED_ATCXPDR_MODE_Switch "TARA"

  local _, atsuTakeoffPacks = FSL.atsuLog:getTakeoffPacks()
  local shouldTurnoffPacks, logMsg

  if atsuTakeoffPacks then
    shouldTurnoffPacks = atsuTakeoffPacks == "OFF"
    if shouldTurnoffPacks then
      logMsg = "Switching the packs off as per the latest ATSU performance request."
    else
      logMsg = "'PACKS ON' found in the latest ATSU performance request, leaving the packs at the current setting."
    end
  else
    shouldTurnoffPacks = copilot.UserOptions.actions.packs_on_takeoff == copilot.TAKEOFF_PACKS_TURN_OFF
    if shouldTurnoffPacks then
      logMsg = ("No ATSU performance request found, packs_on_takeoff=%d: switching the packs off.")
        :format(copilot.TAKEOFF_PACKS_TURN_OFF)
    else
      logMsg = ("No ATSU performance request found, packs_on_takeoff=%d: leaving the packs at the current setting.")
        :format(copilot.TAKEOFF_PACKS_LEAVE_ALONE)
    end
  end

  copilot.logger:info(logMsg)

  if shouldTurnoffPacks then
    FSL.OVHD_AC_Pack_1_Button:toggleUp()
    FSL.OVHD_AC_Pack_2_Button:toggleUp()
  end

end

function copilot.sequences:takeoffSequence()
  firstFlight = false
  FSL.MIP_CHRONO_ELAPS_SEL_Switch "RUN"
  if copilot.UserOptions.actions.after_landing == copilot.UserOptions.ENABLED  then 
    FSL.GSLD_Chrono_Button() 
  end
end

function copilot.sequences.afterTakeoffCommon()
  FSL.PED_SPD_BRK_LEVER "RET"
  FSL.OVHD_EXTLT_Nose_Switch "OFF"
  FSL.OVHD_EXTLT_RwyTurnoff_Switch "OFF"
end

copilot.sequences.afterGoAround = copilot.sequences.afterTakeoffCommon

function copilot.sequences:afterTakeoffSequence()

  FSL.OVHD_AC_Pack_1_Button:toggleDown()
  copilot.suspend(9000, 15000)
  FSL.OVHD_AC_Pack_2_Button:toggleDown()

  repeat copilot.suspend(1000) until ipc.readLvar "FSLA320_slat_l_1" == 0

  copilot.suspend(1000, 3000)

  copilot.sequences.afterTakeoffCommon()

  FSL.PED_ATCXPDR_MODE_Switch "TARA"

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

  local function clear(field, lsk)
    if not field then return end
    while FSL.MCDU:getScratchpad():sub(6,8) ~= "CLR" do
      FSL.PED_MCDU_KEY_CLR()
      copilot.sleep(100)
    end
    local display = FSL.MCDU:getString()
    FSL["PED_MCDU_LSK_" .. lsk]()
    checkWithTimeout(5000, function() 
      ipc.sleep(100)
      return FSL.MCDU:getString() ~= display
    end)
  end

  clear(VOR1, "L1")
  clear(VOR2, "R1")
  clear(ADF1, "L5")
  clear(ADF2, "R5")

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
  if copilot.UserOptions.actions.takeoff_sequence == copilot.UserOptions.ENABLED then 
    FSL.GSLD_Chrono_Button() 
  end

  FSL.OVHD_EXTLT_Strobe_Switch "AUTO"
  FSL.OVHD_EXTLT_RwyTurnoff_Switch "OFF"
  moveTwoSwitches(FSL.OVHD_EXTLT_Land_L_Switch, "RETR", FSL.OVHD_EXTLT_Land_R_Switch, "RETR", 0.9)
  FSL.OVHD_EXTLT_Nose_Switch "TAXI"

  FSL.PED_WXRadar_SYS_Switch "OFF"
  FSL.PED_WXRadar_PWS_Switch "OFF"

  local shouldFDsBeOn = copilot.UserOptions.actions.FDs_off_after_landing == copilot.UserOptions.FALSE

  FSL.PF.GSLD_EFIS_FD_Button:pressForLightState(shouldFDsBeOn)
  FSL.PF.GSLD_EFIS_LS_Button:pressIfLit()

  if FSL.FCU:get().isBirdOn then 
    FSL.GSLD_FCU_HDGTRKVSFPA_Button() 
  end

  FSL.GSLD_EFIS_LS_Button:pressIfLit()
  FSL.GSLD_EFIS_FD_Button:pressForLightState(shouldFDsBeOn)

  if copilot.UserOptions.actions.pack2_off_after_landing == copilot.UserOptions.TRUE then 
    FSL.OVHD_AC_Pack_2_Button:toggleUp()
  end

  copilot.suspend() -- yield to check if the no apu voice command was spoken

  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.noApu:deactivate()
  end
  self.isRunning = false

  if not self.noApu then
    FSL:startTheApu()
  end

  self.noApu = false

end

local function extPwrAvail() return ipc.readLvar "FSLA320_GndPwr" == 1 end
local function extPwrButtonPressed(rect, action)
  return rect == FSL.OVHD_ELEC_EXT_PWR_Button.rectangle and action == "leftPress"
end

function copilot.sequences.parking()

  local extPwrConnectedByPF

  local extPwrButtMonitor = copilot.mouseMacroEvent():addAction(function(_, rect, action)
    if extPwrAvail() and extPwrButtonPressed(rect, action) then
      extPwrConnectedByPF = true
    end
  end)

  copilot.events.enginesStarted:addOneOffAction(function()
    copilot.mouseMacroEvent():removeAction(extPwrButtMonitor)
  end)

  FSL.OVHD_AI_Eng_1_Anti_Ice_Button:toggleUp()
  FSL.OVHD_AI_Eng_2_Anti_Ice_Button:toggleUp()
  FSL.OVHD_AI_Wing_Anti_Ice_Button:toggleUp()

  FSL.OVHD_AC_Eng_APU_Bleed_Button:toggleDown()

  FSL.OVHD_FUEL_L_TK_1_PUMP_Button:toggleUp()
  FSL.OVHD_FUEL_L_TK_2_PUMP_Button:toggleUp()
  if FSL:getAcType() == "A321" then
    FSL.OVHD_FUEL_CTR_TK_1_VALVE_Button:toggleUp()
    FSL.OVHD_FUEL_CTR_TK_2_VALVE_Button:toggleUp()
  else
    FSL.OVHD_FUEL_CTR_TK_1_PUMP_Button:toggleUp()
    FSL.OVHD_FUEL_CTR_TK_2_PUMP_Button:toggleUp()
  end
  FSL.OVHD_FUEL_R_TK_1_PUMP_Button:toggleUp()
  FSL.OVHD_FUEL_R_TK_2_PUMP_Button:toggleUp()

  if copilot.checklists and copilot.checklists.parking then
    Event.waitForEvent(copilot.checklists.parking:doneEvent())
  end

  repeat copilot.suspend(1000) until extPwrAvail()

  copilot.suspend(1000, 10000)

  if not extPwrConnectedByPF then
    FSL.OVHD_ELEC_EXT_PWR_Button:_moveHandHere()
    FSL.OVHD_ELEC_EXT_PWR_Button:macro "leftPress"
    copilot.sleep(1000, 2000)
    FSL.OVHD_ELEC_EXT_PWR_Button:macro "leftRelease"
    FSL.OVHD_AC_Eng_APU_Bleed_Button:toggleUp()
    FSL.OVHD_APU_Master_Button:toggleUp()
  end

end

function copilot.sequences.securingTheAircraft()

  FSL.OVHD_OXY_CREW_SUPPLY_Button:toggleUp()

  FSL.OVHD_EXTLT_Strobe_Switch "OFF"
  FSL.OVHD_EXTLT_Beacon_Switch "OFF"
  FSL.OVHD_EXTLT_Wing_Switch "OFF"
  FSL.OVHD_EXTLT_NavLogo_Switch "OFF"
  FSL.OVHD_EXTLT_RwyTurnoff_Switch "OFF"
  FSL.OVHD_EXTLT_Land_L_Switch "RETR"
  FSL.OVHD_EXTLT_Land_R_Switch "RETR"
  FSL.OVHD_EXTLT_Nose_Switch "OFF"

  FSL.OVHD_SIGNS_EmerExitLight_Switch "OFF"
  FSL.OVHD_SIGNS_NoSmoking_Switch "OFF"
  FSL.OVHD_SIGNS_SeatBelts_Switch "OFF"

  FSL.OVHD_AC_Eng_APU_Bleed_Button:toggleUp()
  FSL.OVHD_APU_Master_Button:toggleUp()

  FSL.OVHD_ELEC_BAT_1_Button:toggleUp()
  FSL.OVHD_ELEC_BAT_2_Button:toggleUp()
end