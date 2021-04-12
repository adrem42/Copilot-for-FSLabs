
local firstFlight = true
local flapsLimits = copilot.flapsLimits

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
      if (copilot.airborneTime and copilot.getTimestamp() - copilot.airborneTime < 60000) or flyingCircuits then
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

copilot.actions.goAround = copilot.events.goAround:addAction(function()
  copilot.voiceCommands.goAroundFlaps:activate()
  copilot.suspend(20000)
  copilot.voiceCommands.goAroundFlaps:deactivate()
end)

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
      confidence = 0.94,
      action = {function()
        if copilot.UserOptions.actions.takeoff_sequence == copilot.UserOptions.ENABLED then
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