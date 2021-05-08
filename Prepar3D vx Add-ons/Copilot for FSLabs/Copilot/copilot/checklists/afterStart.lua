
local afterStart = Checklist:new(
  "afterStart",
  "After start",
  VoiceCommand:new ("after start checklist", 0.9)
)

copilot.checklists.afterStart = afterStart

local function takeoffPerfEAIon()
  return FSL.atsuLog:get():match ".*A-ICE%s+(%a+)" ~= "OFF"
end

afterStart:appendItem {
  label = "antiIce",
  displayLabel = "Anti-Ice",
  response = {ON = VoiceCommand:new {"on", "engine anti-ice on"}, OFF = VoiceCommand:new "off"},
  onResponse = function(check, _, label)
    local on1, on2 = FSL.OVHD_AI_Eng_1_Anti_Ice_Button:isDown(), FSL.OVHD_AI_Eng_2_Anti_Ice_Button:isDown()
    if label == "ON" then
      if check(takeoffPerfEAIon(), "The takeoff performance was calculated with EAI off") then 
        check(on1, "ENG 1 anti-ice is off")
        check(on2, "ENG 2 anti-ice is off")
      end
    elseif label == "OFF" then
      check(not on1, "ENG 1 anti-ice is on")
      check(not on2, "ENG 2 anti-ice is on")
    end
  end
}

afterStart:appendItem {
  label = "ecamStatus",
  displayLabel = "ECAM Status",
  response = VoiceCommand:new "checked"
}

local loadsheetCG

afterStart:appendItem {
  label = "pitchTrim",
  displayLabel = "Pitch Trim",
  response = VoiceCommand:new(
    PhraseBuilder.new()
      :append {
        propName = "CG", 
        asString = "CG value", 
        choices = table.init(200, 380, 1, function(i) return tostring(i / 10) end)
      }
      :appendOptional "percent"
      :appendOptional "set"
      :build()
  ),
  beforeChallenge = function() loadsheetCG = FSL.atsuLog:getMACTOW() end,
  onResponse = function(check, res)
    local spokenSetting = tonumber(res:getProp "CG", nil)
    local actualSetting = FSL.trimwheel:getInd()
    if math.abs(spokenSetting - actualSetting) > 1 then
      check(("Actual trim setting is %.1f (you said %.1f)"):format(actualSetting, spokenSetting))
      return
    end
    local function checkCG(CG, prefix)
      check(math.abs(actualSetting - CG) < 1, ("%s is %.1f, current trim setting is %.1f"):format(prefix, CG, actualSetting))
    end
    if loadsheetCG then 
      checkCG(loadsheetCG, "Loadsheet CG")
    else 
      checkCG(copilot.CG(), "SimConnect CG") 
    end
  end
}

afterStart:appendItem {
  label = "rudderTrim",
  displayLabel = "Rudder Trim",
  response = VoiceCommand:new "zero"
}