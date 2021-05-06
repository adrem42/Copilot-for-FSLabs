
local parking = Checklist:new(
  "parking",
  "Parking",
  VoiceCommand:new "parking checklist"
)

copilot.checklists.parking = parking

parking:appendItem {
  label = "apuBleed",
  displayLabel = "APU Bleed",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, _, label)
    if check(label == "ON", "The correct response is 'on'") then
      check(not FSL.OVHD_AC_Eng_APU_Bleed_Button:isDown(), "APU bleed isn't on")
    end
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
  label = "externalLights",
  displayLabel = "External Lights",
  response = {OFF = VoiceCommand:new "off", NAV_LOGO_ON = VoiceCommand:new "nav logo on"},
  onResponse = function(check, label)
    local lightSwitches = {
      FSL.OVHD_EXTLT_Beacon_Switch,
      FSL.OVHD_EXTLT_Land_L_Switch,
      FSL.OVHD_EXTLT_Land_R_Switch,
      FSL.OVHD_EXTLT_Nose_Switch,
      FSL.OVHD_EXTLT_RwyTurnoff_Switch,
      FSL.OVHD_EXTLT_Strobe_Switch,
      FSL.OVHD_EXTLT_Wing_Switch
    }
    local function checkSwitchesOff()
      for _, switch in ipairs(lightSwitches) do
        if switch:getPosn() ~= "OFF" then
          check "Not all switches are off"
          return
        end
      end
    end
    if label == "OFF" then
      lightSwitches[#lightSwitches+1] = FSL.OVHD_EXTLT_NavLogo_Switch
      checkSwitchesOff()
    elseif label == "NAV_LOGO_ON" then
      check(FSL.OVHD_EXTLT_NavLogo_Switch:getPosn() == "OFF", "The nav/logo switch isn't 'on'")
      checkSwitchesOff()
    end
  end
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
  label = "park",
  displayLabel = "Park BRK / Chocks",
  response = VoiceCommand.new(
    PhraseBuilder.new()
      :append({"ON", "OFF"}, "parkingBrake")
      :append "and"
      :append({"in", "out"}, "chocks")
      :build()
  ),
  onResponse = function(check, _, res)
    check(
      res:getProp "parkingBrake" == FSL.PED_PARK_BRAKE_Switch:getPosn(),
      "Parking brake isn't " .. res:getProp"parkingBrake":lower()
    )
    local chocksResponse = res:getProp "chocks"
    local chocksActual = FlightPhaseProcessor.chocksOn() and "in" or "out"
    check(chocksResponse == chocksActual, "Chocks aren't " .. chocksResponse)
  end
}
