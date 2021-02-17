-- A few examples of adding @{Event|actions and voice commands} to Copilot.
-- Drop this file into FSLabs Copilot/custom - Copilot auto-loads
-- any lua files in that directory

local FSL = FSL
local copilot = copilot
copilot.logger:setLevel(1)

------------------------------------------------------------------------------
-- Changing a default sequence
------------------------------------------------------------------------------

-- Let's add something to the default lineup sequence:

local oldLineupSequence = copilot.sequences.lineUpSequence

function copilot.sequences.lineUpSequence()
  oldLineupSequence()
  FSL.OVHD_EXTLT_Nose_Switch "TO"
  FSL.OVHD_EXTLT_Strobe_Switch "AUTO"
end

-- If you want to remove something from a default sequence
-- or add something in the middle of it, you need to reimplement the function.
-- This example shows how to shut off an engine in the middle of the taxi 
-- sequence:

function copilot.sequences.taxiSequence()
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
end

------------------------------------------------------------------------------
-- Changing a default voice command
------------------------------------------------------------------------------

local startApu = copilot.voiceCommands.startApu

copilot.logger:info "Replacing these phrase variants with just 'start apu':"
for _, phrase in ipairs(startApu:getPhrases()) do 
  copilot.logger:info("'" .. phrase .. "'") 
end

startApu:removeAllPhrases():addPhrase("start apu"):setConfidence(0.90)

------------------------------------------------------------------------------
-- Adding a new action and voice command
------------------------------------------------------------------------------

local pleaseStop = VoiceCommand:new {phrase = "please stop"}

local newAction = copilot.events.enginesStarted:addAction(function()
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
  FSL.OVHD_FUEL_CTR_TK_1_VALVE_Button()
  FSL.OVHD_FUEL_CTR_TK_2_VALVE_Button()
  FSL.OVHD_FUEL_R_TK_1_PUMP_Button()
  FSL.OVHD_FUEL_R_TK_2_PUMP_Button()
  FSL.OVHD_INTLT_AnnLt_Switch "TEST"
  FSL.OVHD_WIPER_KNOB_RIGHT_Knob "SLOW"
  FSL.MIP_DU_PNL_PFD_BRT_Knob(0)
  FSL.MIP_DU_PNL_ND_BRT_Knob(0)
  FSL.PF.MIP_DU_PNL_PFD_BRT_Knob(0)
  FSL.PF.MIP_DU_PNL_ND_BRT_Knob(0)

end, "runAsCoroutine") -- For this action to be stoppable through a voice
-- command, we need to run it as a coroutine and yield periodically so that 
-- the code that triggers the voice commands has a chance to run.
-- The action will stop when our 'please stop' voice command is triggered.
-- Even though you don't see any coroutine.yield() calls inside the function,
-- FSL2Lua yields automatically in between control interactions when it sees
-- that it's inside a coroutine.
newAction:stopOn(pleaseStop)

-- Since both the newly added action and the default after start sequence are 
-- coroutines, we may want to make sure that the after start sequence ends
-- before we proceed.
copilot.events.enginesStarted:setActionOrder(newAction) 
  :after(copilot.actions.afterStart)

------------------------------------------------------------------------------
-- Another voice command that triggers an interaction with the MCDU
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
-- Waiting for events
------------------------------------------------------------------------------

local abortWithKey = Event.fromKeyPress "A"
local abortWithVoice = VoiceCommand:new {phrase = "Abort the launch"}
local launchCommand = VoiceCommand:new {phrase = "Launch it"}

local function rocketLaunch()

  copilot.logger:info "Preparing for rocket launch..."
  copilot.suspend(5000, 10000)

  copilot.logger:info "Launching the rocket on your command"
  Event.waitForEvent(launchCommand:activate())

  copilot.logger:info "You have 5 seconds to abort the launch"
  local res = Event.waitForEventsWithTimeout(
    5000, {abortWithKey, abortWithVoice:activate()}
  )

  abortWithVoice:deactivate()
  
  if res == Event.TIMEOUT then
    copilot.logger:info "The rocket has been launched successfully!"
  elseif res == abortWithKey then
    copilot.logger:info "The launch was aborted with a key press"
  elseif res == abortWithVoice then
    copilot.logger:info "The launch was aborted with a voice command"
  end
end

copilot.addCallback(coroutine.create(rocketLaunch))