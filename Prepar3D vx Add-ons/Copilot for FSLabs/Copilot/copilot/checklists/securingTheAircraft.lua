local securingTheAircraft = Checklist:new(
  "securingTheAircraft",
  "Securing the Aircraft",
  VoiceCommand:new "securing the aircraft checklist"
)

copilot.checklists.securingTheAircraft = securingTheAircraft

securingTheAircraft:appendItem {
  label = "adirs",
  displayLabel = "ADIRS",
  response = VoiceCommand:new {phrase = "off", dummy = "on"},
  onResponse = function(_, _, _, onFailed)
    if FSL.OVHD_ADIRS_1_Knob:getPosn() ~= "OFF" then
      onFailed "ADIRS 1 knob isn't off"
    end
    if FSL.OVHD_ADIRS_21_Knob:getPosn() ~= "OFF" then
      onFailed "ADIRS 2 knob isn't off"
    end
    if FSL.OVHD_ADIRS_3_Knob:getPosn() ~= "OFF" then
      onFailed "ADIRS 3 knob isn't off"
    end
  end
}

securingTheAircraft:appendItem {
  label = "oxygen",
  displayLabel = "Oxygen",
  response = {OFF = VoiceCommand:new "off", ON = VoiceCommand:new "on"},
  onResponse = function(label, _, _, onFailed)
    if label ~= "OFF" then
      onFailed "The correct response is 'OFF'"
    elseif FSL.OVHD_OXY_CREW_SUPPLY_Button:isDown() then
      onFailed "Oxygen isn't off"
    end
  end
}

securingTheAircraft:appendItem {
  label = "apuBleed",
  displayLabel = "APU Bleed",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(label, _, _, onFailed)
    if label ~= "OFF" then
      onFailed "The correct response is 'OFF'"
    elseif FSL.OVHD_AC_Eng_APU_Bleed_Button:isDown() then
      onFailed "APU bleed isn't off"
    end
  end
}

securingTheAircraft:appendItem {
  label = "emerExitLights",
  displayLabel = "EMER Exit Lights",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off", ARM = VoiceCommand:new "arm"},
  onResponse = function(label, _, _, onFailed)
    if label ~= "OFF" then
      onFailed "The correct response is 'OFF'"
    elseif FSL.OVHD_SIGNS_EmerExitLight_Switch:getPosn() ~= "OFF" then
      onFailed "EMER EXIT LT switch isn't off"
    end
  end
}

securingTheAircraft:appendItem {
  label = "signs",
  displayLabel = "Signs",
  response = VoiceCommand:new {phrase = "off", dummy = "on"},
  onResponse = function(_, _, _, onFailed)
    if FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() ~= "OFF" then
      onFailed "No smoking switch isn't off"
    end
    if FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() ~= "OFF" then
      onFailed "Seat belts switch isn't off"
    end
  end
}

securingTheAircraft:appendItem {
  label = "apuAndBat",
  displayLabel = "APU and BAT",
  response = VoiceCommand:new {phrase = "off", dummy = "on"},
  onResponse = function(_, _, _, onFailed)
    if FSL.OVHD_APU_Master_Button:isDown() then
      onFailed "APU isn't off"
    end
    if FSL.OVHD_ELEC_BAT_1_Button:isDown() then
      onFailed "BAT 1 isn't off"
    end
    if FSL.OVHD_ELEC_BAT_2_Button:isDown() then
      onFailed "BAT 2 isn't off"
    end
  end
}
