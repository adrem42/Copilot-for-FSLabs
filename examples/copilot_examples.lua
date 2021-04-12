-- A few examples of adding @{Event|actions and voice commands} to Copilot.
-- Drop this file into Copilot for FSLabs/Copilot/custom - Copilot auto-loads
-- any lua files in that directory
-- Read more @{plugins.md|here}

------------------------------------------------------------------------------
-- Adding a simple voice command
------------------------------------------------------------------------------

local getMetar = VoiceCommand:new {

  phrase = {"get the metar please", "get the metar"},

  -- persistent = false can be omitted as voice commands are created 
  -- non-persistent by default, meaning they deactivate after being recognized.
  -- We don't want this voice command to be persistent because it wouldn't make
  -- sense to trigger it again during the execution of the action.
  persistent = false,
  
  action = function(voiceCommand) -- Voice commands and events pass a reference
    -- to themselves as the first argument to their action callbacks.
    copilot.sleep(500, 1000)
    if not FSL.MCDU:getString():find "MCDU MENU" then
      FSL.PED_MCDU_KEY_MENU()
    end
    copilot.sleep(500, 1000)
    FSL.PED_MCDU_LSK_L6()
    copilot.sleep(500, 1000)
    FSL.PED_MCDU_LSK_L6()
    copilot.sleep(500, 1000)
    FSL.PED_MCDU_LSK_R2()
    copilot.sleep(500, 1000)
    FSL.PED_MCDU_LSK_R2()
    copilot.sleep(500, 1000)
    FSL.PED_MCDU_LSK_R6()
    -- Reactivate the voice command
    voiceCommand:activate()
  end

}

--- It's necessary to call this before activating any voice commands here
VoiceCommand.resetGrammar()
getMetar:activate()

------------------------------------------------------------------------------
-- Changing a default sequence
------------------------------------------------------------------------------

-- There's also copilot.prependSequence()

copilot.appendSequence("lineup", function()
  FSL.OVHD_EXTLT_Nose_Switch "TO"
  FSL.OVHD_EXTLT_Strobe_Switch "AUTO"
end)

-- If you want to remove something from a default sequence, add something in the middle of it,
-- you need to replace the default implementation
-- This example shows how to shut off an engine in the middle of the taxi 
-- sequence:

copilot.replaceSequence("during_taxi", function()
  FSL.PED_WXRadar_SYS_Switch(FSL:getPilot() == 1 and "2" or "1")
  FSL.PED_WXRadar_PWS_Switch "AUTO"
  copilot.sleep(100)
  FSL.PED_WXRadar_PWS_Switch "AUTO"
  FSL.MIP_BRAKES_AUTOBRK_MAX_Button()
  FSL.PED_ENG_2_MSTR_Switch "OFF"
  for _ = 1, 5 do
    FSL.PED_ECP_TO_CONFIG_Button()
    copilot.sleep(50, 100)
  end
end)

------------------------------------------------------------------------------
-- Changing a default voice command
------------------------------------------------------------------------------

local startApu = copilot.voiceCommands.startApu
startApu:removeAllPhrases():addPhrase("start apu"):setConfidence(0.90)

------------------------------------------------------------------------------
-- Adding a new action and voice command
------------------------------------------------------------------------------

local pleaseStop = VoiceCommand:new "please stop"

local funAction = copilot.events.enginesStarted:addAction(function()
  -- wait a random amount of time between 5 and 10 seconds
  copilot.suspend(5000, 10000)
  pleaseStop:activate()

  FSL.OVHD_WIPER_KNOB_LEFT_Knob "FAST"
  FSL.OVHD_GPWS_TERR_Button()
  FSL.OVHD_GPWS_SYS_Button()
  FSL.OVHD_GPWS_GS_MODE_Button()
  FSL.OVHD_GPWS_FLAP_MODE_Button()
  FSL.OVHD_GPWS_LDG_FLAP_3_Button()
  FSL.OVHD_ELAC_1_Button()
  FSL.OVHD_SEC_1_Button()
  FSL.OVHD_FAC_1_Button()
  FSL.OVHD_ADIRS_1_Knob "OFF"
  FSL.OVHD_ADIRS_3_Knob "OFF"
  FSL.OVHD_ADIRS_2_Knob "OFF"
  FSL.OVHD_AC_Cockpit_Knob(0)
  FSL.OVHD_AC_Fwd_Cabin_Knob(0)
  FSL.OVHD_AC_Aft_Cabin_Knob(0)
  FSL.OVHD_ELEC_BAT_1_Button()
  FSL.OVHD_ELEC_BAT_2_Button()
  FSL.OVHD_FUEL_L_TK_1_PUMP_Button()
  FSL.OVHD_FUEL_L_TK_2_PUMP_Button()
  if FSL:getAcType() == "A321" then
    FSL.OVHD_FUEL_CTR_TK_1_VALVE_Button()
    FSL.OVHD_FUEL_CTR_TK_2_VALVE_Button()
  else
    FSL.OVHD_FUEL_CTR_TK_1_PUMP_Button()
    FSL.OVHD_FUEL_CTR_TK_2_PUMP_Button()
  end
  FSL.OVHD_FUEL_R_TK_1_PUMP_Button()
  FSL.OVHD_FUEL_R_TK_2_PUMP_Button()
  FSL.OVHD_INTLT_AnnLt_Switch "TEST"
  FSL.OVHD_WIPER_KNOB_RIGHT_Knob "SLOW"
  FSL.MIP_DU_PNL_PFD_BRT_Knob(0)
  FSL.MIP_DU_PNL_ND_BRT_Knob(0)
  FSL.PF.MIP_DU_PNL_PFD_BRT_Knob(0)
  FSL.PF.MIP_DU_PNL_ND_BRT_Knob(0)

end, Action.COROUTINE) -- For this action to be stoppable through a voice
-- command, we need to run it as a coroutine and yield periodically so that 
-- the code that triggers the voice commands has a chance to run.
-- The action will stop when our 'please stop' voice command is triggered.
-- Even though you don't see any coroutine.yield() calls inside the function,
-- FSL2Lua yields automatically in between control interactions when it sees
-- that it's inside a coroutine.
funAction:stopOn(pleaseStop)

-- Since both the newly added action and the default after start sequence are 
-- coroutines, we may want to make sure that the after start sequence ends
-- before we proceed.
copilot.events.enginesStarted:setActionOrder(funAction) 
  :after(copilot.actions.afterStart)
