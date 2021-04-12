
local afterStart = Checklist:new(
  "afterStart",
  "After start",
  VoiceCommand:new {phrase = "after start checklist", confidence = 0.8}
)

copilot.checklists.afterStart = afterStart

afterStart:appendItem {
  label = "antiIce",
  displayLabel = "Anti-Ice",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, label)
    local on1, on2 = FSL.OVHD_AI_Eng_1_Anti_Ice_Button:isDown(), FSL.OVHD_AI_Eng_2_Anti_Ice_Button:isDown()
    if label == "ON" then
      check(on1, "ENG 1 anti-ice is off")
      check(on2, "ENG 2 anti-ice is off")
    elseif label == "OFF" then
      check(not on1, "ENG 1 anti-ice is on")
      check(not on2, "ENG 2 anti-ice is on")
    end
  end
}

afterStart:appendItem {
  label = "askidNwStrg",
  displayLabel = "A/SKID & N/W STRG",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, label)
    if check(label == "ON", "The correct response is 'on'") then
      check(FSL.MIP_BRAKES_ASKID_Button:getPosn() == "ON", "A/SKID & N/W STRG isn't on")
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
  response = VoiceCommand:new "... zero"
}