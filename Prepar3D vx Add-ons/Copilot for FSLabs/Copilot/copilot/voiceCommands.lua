
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

copilot.voiceCommands.brakeCheck = VoiceCommand:new {phrase = "brake check", persistent = true}