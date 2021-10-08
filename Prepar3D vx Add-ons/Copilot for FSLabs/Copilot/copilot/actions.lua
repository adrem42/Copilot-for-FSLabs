
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

  local function executeFlapsCommand(pos, callout)
    FSL:skipHand()
    copilot.sleep(0, 1000)
    copilot.playCallout(callout .. "_speedChecked")
    copilot.sleep(0, 700)
    FSL.PED_FLAP_LEVER(pos)
    copilot.playCallout(callout, math.random(0, 1000))
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
      executeFlapsCommand("0", "flapsZero")
    end,
    persistent = true
  }
  
  copilot.voiceCommands.flapsOne = VoiceCommand:new {
    phrase = "flaps one",
    confidence = 0.94,
    action = function()
      local flaps = FSL.PED_FLAP_LEVER:getPosn()
      if isRetractFlightPhase() and (flaps == "2" or flaps == "3") then
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
      executeFlapsCommand("1", "flapsOne")
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
      executeFlapsCommand("2", "flapsTwo")
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
        return
      end
      executeFlapsCommand("3", "flapsThree")
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
        return
      end
      executeFlapsCommand("FULL", "flapsFull")
    end,
    persistent = true
  }

  copilot.voiceCommands.gearUp = VoiceCommand:new {
    phrase = "gear up",
    action = function()
      if copilot.onGround() then return end
      if not copilot.airborneTime then return end
      if copilot.getTimestamp() - copilot.airborneTime > 60000 and not isFlightPhrase "flyingCircuits" then return end
      FSL:skipHand()
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
      FSL.MIP_GEAR_Lever("DN")
      FSL.PED_SPD_BRK_LEVER("ARM")
    end,
    persistent = true
  }

  copilot.voiceCommands.goAroundFlaps = VoiceCommand:new {
    phrase = "go around, flaps!",
    action = function()
      local flaps = FSL.PED_FLAP_LEVER:getPosn()
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
  firstFlight = false
  if copilot.isVoiceControlEnabled then
    if copilot.voiceCommands.lineup then
      copilot.voiceCommands.lineup:deactivate()
    end
    copilot.voiceCommands.brakeCheck:deactivate()
    copilot.voiceCommands.takeoff:deactivate()
    copilot.voiceCommands.gearDown:ignore()
    copilot.voiceCommands.flapsUp:activate()
    copilot.voiceCommands.flapsOne:activate()
    copilot.voiceCommands.flapsTwo:activate()
    copilot.voiceCommands.flapsThree:activate()
    copilot.voiceCommands.flapsFull:activate()
  end
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
  :setLogMsg "Preflight"
  :stopOn(copilot.events.enginesStarted)
  

if copilot.UserOptions.actions.after_start == copilot.UserOptions.ENABLED then
  copilot.actions.afterStart = copilot.events.enginesStarted:addAction(function(_, payload)
    if not payload.isInitialEvent then 
      copilot.sequences:afterStart()
    end
  end, "runAsCoroutine")
    :setLogMsg "After start"
    :stopOn(copilot.events.engineShutdown)
end

if copilot.UserOptions.actions.during_taxi == copilot.UserOptions.ENABLED then

  copilot.actions.taxi = copilot.events.enginesStarted:addAction(function()
    Event.waitForEvents({copilot.events.brakesChecked, copilot.events.flightControlsChecked}, true)
    copilot.suspend(plusminus(5000))
    copilot.callOnce(function() 
      copilot.sequences.taxiSequence()
    end)
  end, "runAsCoroutine")
    :setLogMsg "Taxi"
    :stopOn(copilot.events.chocksSet, copilot.events.takeoffInitiated2)
    
end

if copilot.UserOptions.actions.lineup == copilot.UserOptions.ENABLED then

  if copilot.isVoiceControlEnabled 
    and copilot.UserOptions.actions.lineup_trigger == copilot.LINEUP_TRIGGER_VOICE then

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
      if copilot.isVoiceControlEnabled 
        and copilot.UserOptions.actions.takeoff_sequence == copilot.UserOptions.ENABLED then
        copilot.voiceCommands.takeoff:activate()
      end
      copilot.callOnce(function() 
        copilot.sequences.lineUpSequence() 
      end)
    end, "runAsCoroutine")
      :setLogMsg "Wait for lineup"
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
    if copilot.voiceCommands.lineup then
      copilot.voiceCommands.lineup:deactivate()
    end
    if copilot.UserOptions.actions.takeoff_sequence == copilot.UserOptions.ENABLED then
      copilot.sequences.takeoffSequence()
    end
  end):setLogMsg "Takeoff"

  if copilot.UserOptions.actions.after_takeoff == copilot.UserOptions.ENABLED then
    copilot.actions.afterTakeoff = copilot.events.airborne:addAction(function()
      repeat copilot.suspend(1000) until FSL:getThrustLeversPos() == "CLB"
      copilot.suspend(plusminus(2000))
      copilot.sequences.afterTakeoffSequence()
    end, "runAsCoroutine")
      :setLogMsg(Event.NOLOGMSG)
      :stopOn(copilot.events.landing)

    copilot.actions.afterGoAround = copilot.events.goAround:addAction(function()
      repeat copilot.suspend(1000) until FSL:getThrustLeversPos() == "CLB"
      copilot.suspend(plusminus(2000))
      copilot.sequences.afterGoAround()
    end, "runAsCoroutine")
      :setLogMsg(Event.NOLOGMSG)
      :stopOn(copilot.events.landing)
  end

  copilot.actions.noVoiceTakeoffTrigger = copilot.events.enginesStarted:addAction(function()
    repeat copilot.suspend(1000)
    until copilot.thrustLeversSetForTakeoff() and FSL.OVHD_EXTLT_Land_L_Switch:getPosn() == "ON" and FSL.OVHD_EXTLT_Land_R_Switch:getPosn() == "ON"
    if copilot.isVoiceControlEnabled then
      copilot.voiceCommands.takeoff:deactivate()
    end
    copilot.events.takeoffInitiated2:trigger()
  end, "runAsCoroutine"):setLogMsg "No voice takeoff trigger"

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
end, "runAsCoroutine"):setLogMsg "Above 10'000"

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
end, "runAsCoroutine"):setLogMsg "Below 10'000"

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
      repeat copilot.suspend(1000) 
      until copilot.GS() < 30 and FSL.PED_SPD_BRK_LEVER:getPosn() ~= "ARM" or not copilot.enginesRunning()
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
end, "runAsCoroutine"):setLogMsg "Landing"

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

  local noApuPhrase = PhraseBuilder.new()
    :append {
      "hold aypeeyou", 
      "delay aypeeyou", 
      "holdaypeeyou",
      "delayapeeyou"
    }
    :build()

  copilot.voiceCommands.afterLandingNoApu = VoiceCommand:new {
    phrase = PhraseBuilder.new()
      :appendOptional "check"
      :append "after landing"
      :append(noApuPhrase)
      :build(),
    action = {function()
      copilot.sequences.afterLanding.noApu = true
      copilot.voiceCommands.startApu:activate()
      copilot.voiceCommands.afterLanding:deactivate()
      copilot.sequences:afterLanding()
    end, "runAsCoroutine"},
    confidence = 0.9
  }

  copilot.voiceCommands.noApu = VoiceCommand:new {
    phrase = noApuPhrase,
    confidence = 0.90,
    action = function()
      copilot.sequences.afterLanding.noApu = true
      copilot.voiceCommands.startApu:activate()
    end
  }

  copilot.voiceCommands.startApu = VoiceCommand:new {
    phrase = {
      "staraypeeyou",
      "start aypeeyou"
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

if copilot.UserOptions.actions.parking == copilot.UserOptions.ENABLED then

  copilot.events.landing:addOneOffAction(function()

    copilot.events.engineShutdown:addAction(function()
      copilot.suspend(3000, 15000)
      copilot.sequences.parking()
    end, "runAsCoroutine")
      :stopOn(copilot.events.enginesStarted)
      :setLogMsg(Event.NOLOGMSG)

  end):setLogMsg(Event.NOLOGMSG)
    
end

if copilot.UserOptions.actions.securing_the_aircraft == copilot.UserOptions.ENABLED then

  local function adirsAreOff()
    return 
      FSL.OVHD_ADIRS_1_Knob:getPosn() == "OFF" and
      FSL.OVHD_ADIRS_2_Knob:getPosn() == "OFF" and
      FSL.OVHD_ADIRS_3_Knob:getPosn() == "OFF"
  end

  copilot.events.landing:addOneOffAction(function()
  
    copilot.events.engineShutdown:addAction(function()
      repeat copilot.suspend(1000) until adirsAreOff()
      copilot.suspend(1000, 5000)
      copilot.callOnce(function()
        copilot.sequences.securingTheAircraft()
      end)
    end, "runAsCoroutine")
      :stopOn(copilot.events.enginesStarted)
      :setLogMsg(Event.NOLOGMSG)

  end):setLogMsg(Event.NOLOGMSG)

end