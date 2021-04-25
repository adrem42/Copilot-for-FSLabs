
local parking = Checklist:new(
  "parking",
  "Parking",
  VoiceCommand:new "parking checklist"
)

copilot.checklists.parking = parking

parking:appendItem {
  label = "radarAndPws",
  displayLabel = "Radar and PWS",
  response = VoiceCommand:new {phrase = "off", dummy = "on"},
  onResponse = function(check)
    check(FSL.PED_WXRadar_SYS_Switch:getPosn() == "OFF", "Radar isn't off")
    check(FSL.PED_WXRadar_PWS_Switch:getPosn() == "OFF", "PWS isn't off")
  end
}

parking:appendItem {
  label = "engines",
  displayLabel = "Engines",
  response = VoiceCommand:new {phrase = "off", dummy = "on"},
  onResponse = function(check)
    check(FSL.PED_ENG_1_MSTR_Switch:getPosn() ~= "ON", "ENG 1 isn't off")
    check(FSL.PED_ENG_2_MSTR_Switch:getPosn() ~= "ON", "ENG 2 isn't off")
  end
}

parking:appendItem {
  label = "seatBelts",
  displayLabel = "Seat Belts",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, _, label)
    if check(label == "OFF", "The correct response is 'off'") then
      check(FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() == "OFF", "The seat belts switch isn't off")
    end
  end
}

parking:appendItem {
  label = "brakeTemp",
  displayLabel = "Brake Temperature",
  response = VoiceCommand:new "checked"
}

parking:appendItem {
  label = "externalLights",
  displayLabel = "External Lights",
  response = VoiceCommand:new "checked",
}

parking:appendItem  {
  label = "fuelPumps",
  displayLabel = "Fuel Pumps",
  response = VoiceCommand:new {phrase = "off", dummy = "on"},
  onResponse = function(check)
    local function checkButt(butt, label)
      check(not butt:isDown(), label .. " is on")
    end
    checkButt(FSL.OVHD_FUEL_L_TK_1_PUMP_Button, "Left tank 1 pump")
    checkButt(FSL.OVHD_FUEL_L_TK_2_PUMP_Button, "Left tank 2 pump")
    if FSL:getAcType() == "A321" then
      checkButt(FSL.OVHD_FUEL_CTR_TK_1_VALVE_Button, "Center tank 1 valve")
      checkButt(FSL.OVHD_FUEL_CTR_TK_2_VALVE_Button, "Center tank 2 valve")
    else
      checkButt(FSL.OVHD_FUEL_CTR_TK_1_PUMP_Button, "Center tank 1 pump")
      checkButt(FSL.OVHD_FUEL_CTR_TK_2_PUMP_Button, "Center tank 2 pump")
    end
    checkButt(FSL.OVHD_FUEL_R_TK_1_PUMP_Button, "Right tank 1 pump")
    checkButt(FSL.OVHD_FUEL_R_TK_2_PUMP_Button, "Right tank 2 pump")
  end
}

parking:appendItem {
  label = "adirs",
  displayLabel = "ADIRS",
  response = VoiceCommand:new "checked"
}

parking:appendItem {
  label = "park",
  displayLabel = "Park BRK / Chocks",
  response = VoiceCommand:new "checked"
}
