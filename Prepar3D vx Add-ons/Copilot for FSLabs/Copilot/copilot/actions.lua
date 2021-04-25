
local firstFlight = true
local flapsLimits = copilot.flapsLimits

if copilot.isVoiceControlEnabled then

  local function isFlightPhrase(name)
    return copilot.getFlightPhase() == copilot.flightPhases[name]
  end

  local function isExtendFlightPhase()
    return isFlightPhrase "belowTenThousand" or isFlightPhrase "flyingCircuits"
  end

  local function isRetractFlightPhase()
    return isFlightPhrase "climbout" or isFlightPhrase "flyingCircuits"
  end

  copilot.voiceCommands.flapsUp = VoiceCommand:new {
    phrase = {"flaps up", "flaps zero"},
    confidence = 0.94,
    action = function()
      if not isRetractFlightPhase() then return end
      if FSL.PED_FLAP_LEVER:getPosn() ~= "1" then return end
      local Vs = copilot.mcduWatcher:getVar("Vs")
      if Vs and copilot.IAS() < Vs then 
        copilot.playCallout "speedTooLow"
        return 
      end
      VoiceCommand:react(500)
      copilot.playCallout "flapsZero"
      FSL.PED_FLAP_LEVER "0"
    end,
    persistent = true
  }
  
  copilot.voiceCommands.flapsOne = VoiceCommand:new {
    phrase = "flaps one",
    confidence = 0.94,
    action = function()
      local flaps = FSL.PED_FLAP_LEVER:getPosn()
      if isRetractFlightPhase() and flaps == "2" or flaps == "3" then
        local Vf = copilot.mcduWatcher:getVar "Vf"
        if Vf and copilot.IAS() < Vf then
          copilot.playCallout "speedTooLow"
          return
        end
      elseif isExtendFlightPhase() and flaps == "0" then
        if copilot.IAS() > flapsLimits.flapsOne then
          copilot.playCallout "speedTooHigh"
          return
        end
      else return end
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
      if not isExtendFlightPhase() then return end
      if FSL.PED_FLAP_LEVER:getPosn() ~= "1" then return end
      if copilot.IAS() > flapsLimits.flapsTwo then
        copilot.playCallout "speedTooHigh"
        return
      end
      VoiceCommand:react(500)
      copilot.playCallout "flapsTwo"
      FSL.PED_FLAP_LEVER "2"
    end,
    persistent = true
  }

  copilot.voiceCommands.flapsThree = VoiceCommand:new {
    phrase = "flaps three",
    confidence = 0.94,
    action = function()
      if not isExtendFlightPhase() then return end
      if FSL.PED_FLAP_LEVER:getPosn() ~= "2" then return end
      if copilot.IAS() > flapsLimits.flapsThree then
        copilot.playCallout "speedTooHigh"
      end
      VoiceCommand:react(500)
      copilot.playCallout "flapsThree"
      FSL.PED_FLAP_LEVER "3"
    end,
    persistent = true
  }

  copilot.voiceCommands.flapsFull = VoiceCommand:new {
    phrase = "flaps full",
    confidence = 0.94,
    action = function()
      if not isExtendFlightPhase() then return end
      if FSL.PED_FLAP_LEVER:getPosn() ~= "3" then return end
      if copilot.IAS() > flapsLimits.flapsFull then
        copilot.playCallout "speedTooHigh"
      end
      VoiceCommand:react(500)
      copilot.playCallout "flapsFull"
      FSL.PED_FLAP_LEVER "FULL"
    end,
    persistent = true
  }

  copilot.voiceCommands.gearUp = VoiceCommand:new {
    phrase = "gear up",
    action = function()
      if copilot.onGround() then return end
      if not copilot.airborneTime then return end
      if copilot.getTimestamp() - copilot.airborneTime > 60000 and not isFlightPhrase "flyingCircuits" then return end
      VoiceCommand:react()
      FSL.MIP_GEAR_Lever "UP"
      if isFlightPhrase "flyingCircuits" then
        copilot.voiceCommands.gearDown:activate()
      end
    end,
    persistent = true
  }
    :deactivateOn(copilot.events.takeoffCancelled, copilot.events.takeoffAborted)
    :activateOn(copilot.events.goAround, copilot.events.takeoffInitiated)

  copilot.voiceCommands.gearDown = VoiceCommand:new {
    phrase = "gear down",
    confidence = 0.94,
    dummy = "... gear ...",
    action = function(vc)
      vc:ignore()
      VoiceCommand:react()
      FSL.MIP_GEAR_Lever("DN")
      FSL.PED_SPD_BRK_LEVER("ARM")
    end,
    persistent = true
  }

  copilot.voiceCommands.goAroundFlaps = VoiceCommand:new {
    phrase = "go around, flaps!",
    action = function()
      local flaps = FSL.PED_FLAP_LEVER:getPosn()
      VoiceCommand:react()
      if flaps == "FULL" then
        FSL.PED_FLAP_LEVER("3")
      elseif flaps == "3" then
        FSL.PED_FLAP_LEVER("2")
      elseif flaps == "2" then
        FSL.PED_FLAP_LEVER("1")
      end
    end
  }

  copilot.voiceCommands.taxiLightOff = VoiceCommand:new {
    phrase = {"taxi light off", "taxilightoff"},
    action = function() FSL.OVHD_EXTLT_Nose_Switch("OFF") end
  }

end

copilot.actions.airborne = copilot.events.airborne:addAction(function()
  copilot.voiceCommands.lineup:deactivate()
  copilot.voiceCommands.takeoff:deactivate()
  copilot.voiceCommands.gearDown:ignore()
  copilot.voiceCommands.flapsUp:activate()
  copilot.voiceCommands.flapsOne:activate()
  copilot.voiceCommands.flapsTwo:activate()
  copilot.voiceCommands.flapsThree:activate()
  copilot.voiceCommands.flapsFull:activate()
  firstFlight = false
end)

copilot.actions.goAround = copilot.events.goAround:addAction(function()
  copilot.voiceCommands.goAroundFlaps:activate()
  copilot.suspend(20000)
  copilot.voiceCommands.goAroundFlaps:deactivate()
end, Action.COROUTINE)

copilot.events.takeoffInitiated2 = Event:new {logMsg = "Starting takeoff actions"}

copilot.actions.preflight = copilot.events.chocksSet:addAction(function()
  if not firstFlight then
    copilot.suspend(1 * 60000, 3 * 60000)
    FSL.MIP_CHRONO_ELAPS_SEL_Switch("RST")
    if copilot.UserOptions.actions.after_landing == copilot.UserOptions.ENABLED
      and copilot.UserOptions.actions.takeoff_sequence == copilot.UserOptions.ENABLED then 
      FSL.GSLD_Chrono_Button()
    end
  end

  if copilot.UserOptions.actions.preflight == copilot.UserOptions.ENABLED then
    repeat copilot.suspend(5000) until copilot.mcduWatcher:getVar("isFmgcSetup")
    copilot.logger:info("FMGC is set up")
    if prob(0.05) then
      copilot.suspend(0, 20000)
    else
      copilot.suspend(20000, 2 * 60000)
      if prob(0.5) then copilot.suspend(0, 60000) end
    end

    if copilot.UserOptions.actions.PM_clears_scratchpad == copilot.UserOptions.TRUE then
      copilot.scratchpadClearer.setMessages(copilot.scratchpadClearer.ANY)
    end

    copilot.sequences:checkFmgcData()
    copilot.suspend(0,10000)

    if prob(0.2) then copilot.suspend(10000, 20000) end
    copilot.sequences:setupEFIS()

  end
end, "runAsCoroutine")
  :addLogMsg "Preflight"
  :stopOn(copilot.events.enginesStarted)
  

if copilot.UserOptions.actions.after_start == copilot.UserOptions.ENABLED then
  copilot.actions.afterStart = copilot.events.enginesStarted:addAction(function() copilot.sequences:afterStart() end, "runAsCoroutine")
    :addLogMsg "After start"
end

if copilot.UserOptions.actions.during_taxi == copilot.UserOptions.ENABLED then

  copilot.actions.taxi = copilot.events.enginesStarted:addAction(function()
    Event.waitForEvents({copilot.events.brakesChecked, copilot.events.flightControlsChecked}, true)
    copilot.suspend(plusminus(5000))
    copilot.callOnce(copilot.sequences.taxiSequence)
  end, "runAsCoroutine")
    :addLogMsg "Taxi"
    :stopOn(copilot.events.chocksSet, copilot.events.takeoffInitiated2)
    
end

if copilot.UserOptions.actions.lineup == copilot.UserOptions.ENABLED then
  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.lineup = VoiceCommand:new {
      phrase = "lineup procedure",
      persistent = "ignore",
      confidence = 0.94
    }
      :activateOn(copilot.events.enginesStarted)
      :deactivateOn(copilot.events.takeoffInitiated2, copilot.events.engineShutdown)
    copilot.actions.lineup = copilot.voiceCommands.lineup:addAction(function()
      if copilot.UserOptions.actions.takeoff_sequence == copilot.UserOptions.ENABLED then
        copilot.voiceCommands.takeoff:activate()
      end
      copilot.sequences.lineUpSequence()
    end)
  else
    copilot.actions.lineup = copilot.events.enginesStarted:addAction(function()
      copilot.sequences:waitForLineup()
      copilot.callOnce(copilot.sequences.lineUpSequence)
    end, "runAsCoroutine")
      :addLogMsg "Lineup"
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
    if copilot.isVoiceControlEnabled and copilot.UserOptions.actions.lineup == copilot.UserOptions.ENABLED then
      copilot.voiceCommands.lineup:deactivate()
    end
    if copilot.UserOptions.actions.takeoff_sequence == copilot.UserOptions.ENABLED then
      copilot.sequences.takeoffSequence()
    end
  end):addLogMsg "Takeoff"

  if copilot.UserOptions.actions.after_takeoff == copilot.UserOptions.ENABLED then
    copilot.actions.afterTakeoff = copilot.events.airborne:addAction(function()
      repeat copilot.suspend(1000) until FSL:getThrustLeversPos() == "CLB"
      copilot.suspend(plusminus(2000))
      copilot.sequences.afterTakeoffSequence()
    end, "runAsCoroutine")
      :addLogMsg "After takeoff"
      :stopOn(copilot.events.landing)
  end

  copilot.actions.noVoiceTakeoffTrigger = copilot.events.enginesStarted:addAction(function()
    repeat copilot.suspend(1000)
    until copilot.thrustLeversSetForTakeoff() and FSL.OVHD_EXTLT_Land_L_Switch:getPosn() == "ON" and FSL.OVHD_EXTLT_Land_R_Switch:getPosn() == "ON"
    if copilot.isVoiceControlEnabled then
      copilot.voiceCommands.takeoff:deactivate()
    end
    copilot.events.takeoffInitiated2:trigger()
  end, "runAsCoroutine"):addLogMsg "No voice takeoff trigger"

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
  if copilot.UserOptions.actions.ten_thousand_dep == copilot.UserOptions.ENABLED then
    copilot.sequences.tenThousandDep()
  end
end, "runAsCoroutine"):addLogMsg "Above 10'000"

copilot.actions.belowTenThousand = copilot.events.belowTenThousand:addAction(function()
  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.flapsUp:activate()
    copilot.voiceCommands.flapsOne:activate()
    copilot.voiceCommands.flapsTwo:activate()
    copilot.voiceCommands.flapsThree:activate()
    copilot.voiceCommands.flapsFull:activate()
    copilot.voiceCommands.gearDown:activate()
    copilot.voiceCommands.gearUp:ignore()
  end
  if copilot.UserOptions.actions.ten_thousand_arr == copilot.UserOptions.ENABLED then
    copilot.sequences:tenThousandArr()
  end
end, "runAsCoroutine"):addLogMsg "Below 10'000"

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
  if copilot.UserOptions.actions.after_landing == copilot.UserOptions.ENABLED then
    if copilot.isVoiceControlEnabled 
      and copilot.UserOptions.actions.after_landing_trigger == copilot.AFTER_LANDING_TRIGGER_VOICE then
      repeat copilot.suspend(1000) until copilot.GS() < 40
      copilot.voiceCommands.afterLanding:activate()
      copilot.voiceCommands.afterLandingNoApu:activate()
    else
      repeat copilot.suspend(1000) until (copilot.GS() < 30 and FSL.PED_SPD_BRK_LEVER:getPosn() ~= "ARM") or not copilot.enginesRunning()
      if copilot.isVoiceControlEnabled then
        copilot.voiceCommands.noApu:activate()
      end
      copilot.sleep(plusminus(5000, 0.5))
      if copilot.enginesRunning() then
        copilot.sequences:afterLanding()
      end
    end
  end
  
  repeat copilot.suspend(1000) until copilot.GS() < 30
  if copilot.isVoiceControlEnabled then
    copilot.voiceCommands.taxiLightOff:activate()
  end
end, "runAsCoroutine"):addLogMsg "Landing"

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