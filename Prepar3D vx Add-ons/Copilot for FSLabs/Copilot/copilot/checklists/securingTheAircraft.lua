
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
  onResponse = function(check)
    check(FSL.OVHD_ADIRS_1_Knob:getPosn() == "OFF", "ADIRS 1 knob isn't off")
    check(FSL.OVHD_ADIRS_2_Knob:getPosn() == "OFF", "ADIRS 2 knob isn't off")
    check(FSL.OVHD_ADIRS_3_Knob:getPosn() == "OFF", "ADIRS 3 knob isn't off")
  end
}

securingTheAircraft:appendItem {
  label = "oxygen",
  displayLabel = "Oxygen",
  response = {OFF = VoiceCommand:new "off", ON = VoiceCommand:new "on"},
  onResponse = function(check, _, label)
    if check(label == "OFF", "The correct response is 'off'") then
      check(not FSL.OVHD_OXY_CREW_SUPPLY_Button:isDown(), "Oxygen isn't off")
    end
  end
}

securingTheAircraft:appendItem {
  label = "apuBleed",
  displayLabel = "APU Bleed",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, _, label)
    if check(label == "OFF", "The correct response is 'off'") then
      check(not FSL.OVHD_AC_Eng_APU_Bleed_Button:isDown(), "APU bleed isn't off")
    end
  end
}

securingTheAircraft:appendItem {
  label = "emerExitLights",
  displayLabel = "EMER Exit Lights",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off", ARM = VoiceCommand:new "arm"},
  onResponse = function(check, _, label)
    if check(label == "OFF", "The correct response is 'off'") then
      check(FSL.OVHD_SIGNS_EmerExitLight_Switch:getPosn() == "OFF", "EMER EXIT LT switch isn't off")
    end
  end
}

securingTheAircraft:appendItem {
  label = "signs",
  displayLabel = "Signs",
  response = VoiceCommand:new {phrase = "off", dummy = "on"},
  onResponse = function(check)
    check(FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() == "OFF", "No smoking switch isn't off")
    check(FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() == "OFF", "Seat belts switch isn't off")
  end
}

securingTheAircraft:appendItem {
  label = "apuAndBat",
  displayLabel = "APU and BAT",
  response = VoiceCommand:new {phrase = "off", dummy = "on"},
  onResponse = function(check)
    check(not FSL.OVHD_APU_Master_Button:isDown(), "APU isn't off")
    check(not FSL.OVHD_ELEC_BAT_1_Button:isDown(), "BAT 1 isn't off")
    check(not FSL.OVHD_ELEC_BAT_2_Button:isDown(), "BAT 2 isn't off")
  end
}
