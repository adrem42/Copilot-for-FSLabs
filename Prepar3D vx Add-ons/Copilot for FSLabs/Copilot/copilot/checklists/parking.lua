local parking = Checklist:new(
  "parking",
  "Parking",
  VoiceCommand:new "parking checklist"
)

copilot.checklists.parking = parking

parking:appendItem {
  label = "radarAndPws",
  displayLabel = "Radar and PWS",
  response = {OFF = VoiceCommand:new "OFF", AUTO = VoiceCommand:new "AUTO"},
  onResponse = function(label, _, _, onFailed)
    if label ~= "OFF" then
      onFailed "The correct response is 'OFF'"
    elseif FSL.PED_WXRadar_PWS_Switch:getPosn() ~= "OFF" then
      onFailed "PWS Switch isn't off"
    end
  end
}

parking:appendItem {
  label = "engines",
  displayLabel = "Engines",
  response = VoiceCommand:new {phrase = "off", dummy = "on"},
  onResponse = function(_, _, _, onFailed)
    if FSL.PED_ENG_1_MSTR_Switch:getPosn() ~= "OFF" then
      onFailed "ENG 1 isn't off"
    end
    if FSL.PED_ENG_2_MSTR_Switch:getPosn() ~= "OFF" then
      onFailed "ENG 2 isn't off"
    end
  end
}

parking:appendItem {
  label = "seatBelts",
  displayLabel = "Seat Belts",
  response = {ON = VoiceCommand:new "ON", OFF = VoiceCommand:new "OFF"},
  onResponse = function(label, _, _, onFailed)
    if label ~= "OFF" then 
      onFailed "The correct response is 'OFF'"
    elseif FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() ~= "OFF" then
      onFailed "The seat belts switch isn't off"
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
  onResponse = function(_, _, _, onFailed)
    if FSL.OVHD_FUEL_L_TK_1_PUMP_Button:isDown() then
      onFailed "Left tank pump 1 is on"
    end
    if FSL.OVHD_FUEL_L_TK_2_PUMP_Button:isDown() then
      onFailed "Left tank pump 2 is on"
    end

    if FSL:getAcType() == "A321" then
      if FSL.OVHD_FUEL_CTR_TK_1_VALVE_Button:isDown() then
        onFailed "Center tank 1 valve is on"
      end
      if FSL.OVHD_FUEL_CTR_TK_2_VALVE_Button:isDown() then
        onFailed "Center tank 2 valve is on"
      end
    else
      if FSL.OVHD_FUEL_CTR_TK_1_PUMP_Button:isDown() then
        onFailed "Center tank 1 pump is on"
      end
      if FSL.OVHD_FUEL_CTR_TK_2_PUMP_Button:isDown() then
        onFailed "Center tank 2 pump is on"
      end
    end

    if FSL.OVHD_FUEL_R_TK_1_PUMP_Button:isDown() then
      onFailed "Right tank pump 1 is on"
    end
    if FSL.OVHD_FUEL_R_TK_2_PUMP_Button:isDown() then
      onFailed "Right tank pump 2 is on"
    end
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


