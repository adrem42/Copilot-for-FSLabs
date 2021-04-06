local afterStart = Checklist:new(
  "afterStart",
  "After start",
  VoiceCommand:new {phrase = "after start checklist", confidence = 0.8}
)

copilot.checklists.afterStart = afterStart

afterStart:appendItem {
  label = "antiIce",
  displayLabel = "Anti-Ice",
  response = {ON = VoiceCommand:new "ON", OFF = VoiceCommand:new "OFF"},
  onResponse = function(label, _, _, onFailed)
    local on1, on2 = FSL.OVHD_AI_Eng_1_Anti_Ice_Button:isDown(), FSL.OVHD_AI_Eng_2_Anti_Ice_Button:isDown()
    if label == "ON" then
      if not on1 then onFailed "ENG 1 anti-ice is OFF" end
      if not on2 then onFailed "ENG 2 anti-ice is OFF" end
    elseif label == "OFF" then
      if on1 then onFailed "ENG 1 anti-ice is ON" end
      if on2 then onFailed "ENG 2 anti-ice is ON" end
    end
  end
}

afterStart:appendItem {
  label = "askidNwStrg",
  displayLabel = "A/SKID & N/W STRG",
  response = {ON = VoiceCommand:new "ON", OFF = VoiceCommand:new "OFF"},
  onResponse = function(label, _, _, onFailed)
    if label == "OFF" then
      onFailed "The correct response is 'ON'"
    elseif FSL.MIP_BRAKES_ASKID_Button:getPosn() ~= "ON" then
      onFailed "A/SKID & N/W STRG isn't on"
    end
  end
}

afterStart:appendItem {
  label = "ecamStatus",
  displayLabel = "ECAM Status",
  response = VoiceCommand:new "checked"
}

afterStart:appendItem {
  label = "trim",
  displayLabel = "Trim",
  response = VoiceCommand:new "... rudder zero"
}