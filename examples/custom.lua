-- An example of adding actions and voice commands to Copilot.
-- Copilot will auto-load a file named 'custom.lua' 
-- in the FSLabs Copilot directory

local FSL = FSL
local copilot = copilot

local voiceCommand1 = VoiceCommand:new {phrase = "please stop"}

copilot.events.enginesStarted:addAction(function()
  -- wait a random amount of time between 30 and 60 seconds
  copilot.suspend(30000, 60000) 
  voiceCommand1:activate()

  FSL.OVHD_WIPER_KNOB_LEFT_Knob("FAST")
  FSL.OVHD_GPWS_TERR_Button()
  FSL.OVHD_GPWS_SYS_Button()
  FSL.OVHD_GPWS_GS_MODE_Button()
  FSL.OVHD_GPWS_FLAP_MODE_Button()
  FSL.OVHD_GPWS_LDG_FLAP_3_Button()
  FSL.OVHD_ELAC_1_Button()
  FSL.OVHD_SEC_1_Button()
  FSL.OVHD_FAC_1_Button()
  FSL.OVHD_ADIRS_1_Knob("OFF")
  FSL.OVHD_ADIRS_2_Knob("OFF")
  FSL.OVHD_ADIRS_3_Knob("OFF")
  FSL.OVHD_AC_Cockpit_Knob(0)
  FSL.OVHD_AC_Fwd_Cabin_Knob(0)
  FSL.OVHD_AC_Aft_Cabin_Knob(0)
  FSL.OVHD_ELEC_BAT_1_Button()
  FSL.OVHD_ELEC_BAT_2_Button()
  FSL.OVHD_FUEL_L_TK_1_PUMP_Button()
  FSL.OVHD_FUEL_L_TK_2_PUMP_Button()
  FSL.OVHD_FUEL_CTR_TK_1_VALVE_Button()
  FSL.OVHD_FUEL_CTR_TK_2_VALVE_Button()
  FSL.OVHD_FUEL_R_TK_1_PUMP_Button()
  FSL.OVHD_FUEL_R_TK_2_PUMP_Button()
  FSL.OVHD_INTLT_AnnLt_Switch("TEST")
  FSL.OVHD_WIPER_KNOB_RIGHT_Knob("SLOW")
  FSL.MIP_DU_PNL_PFD_BRT_Knob(0)
  FSL.MIP_DU_PNL_ND_BRT_Knob(0)
  FSL.PF.MIP_DU_PNL_PFD_BRT_Knob(0)
  FSL.PF.MIP_DU_PNL_ND_BRT_Knob(0)

end, "runAsCoroutine")
  :stopOn(voiceCommand1)

local voiceCommand2 = VoiceCommand:new {

  phrase = {"fetch me some weather, would you?"},
  action = function()
    copilot.sleep(500, 1000)
    if not FSL.MCDU:getString():find("MCDU MENU") then
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
  end,

  persistent = true -- don't auto-deactivate after recognition event

}

voiceCommand2:activate()

