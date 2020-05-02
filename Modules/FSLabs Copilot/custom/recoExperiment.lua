
local EAI_ON = VoiceCommand:new{phrase = "engine antiice on", confidence = 0.9, persistent = "ignore"}
  :activateOn(copilot.events.enginesStarted)
  :deactivateOn(copilot.events.engineShutdown)

--[[ EAI_ON:addAction(function()
  copilot.sleep(500, 1000)
  if not FSL.OVHD_AI_Eng_1_Anti_Ice_Button:isDown() then
    FSL.OVHD_AI_Eng_1_Anti_Ice_Button()
  end
  if not FSL.OVHD_AI_Eng_2_Anti_Ice_Button:isDown() then
    FSL.OVHD_AI_Eng_2_Anti_Ice_Button()
  end
end) ]]

local EAI_OFF = VoiceCommand:new{phrase = "engine antiice off", confidence = 0.9, persistent = "ignore"}
  :activateOn(EAI_ON)
  :deactivateOn(copilot.events.engineShutdown)

EAI_ON:activateOn(EAI_OFF)

--[[ EAI_OFF:addAction(function()
  copilot.sleep(500, 1000)
  if FSL.OVHD_AI_Eng_1_Anti_Ice_Button:isDown() then
    FSL.OVHD_AI_Eng_1_Anti_Ice_Button()
  end
  if FSL.OVHD_AI_Eng_2_Anti_Ice_Button:isDown() then
    FSL.OVHD_AI_Eng_2_Anti_Ice_Button()
  end
end) ]]

local WAI_ON = VoiceCommand:new{phrase = "wing antiice on", confidence = 0.9, persistent = "ignore"}
  :activateOn(copilot.events.airborne)
  :deactivateOn(copilot.events.landing)

--[[ WAI_ON:addAction(function()
  copilot.sleep(500, 1000)
  if not FSL.OVHD_AI_Wing_Anti_Ice_Button:isDown() then
    FSL.OVHD_AI_Wing_Anti_Ice_Button()
  end
end) ]]

local WAI_OFF = VoiceCommand:new{phrase = "wing antiice off", confidence = 0.9, persistent = "ignore"}
  :activateOn(WAI_ON)
  :deactivateOn(copilot.events.landing)

WAI_ON:activateOn(WAI_OFF)

--[[ WAI_OFF:addAction(function()
  copilot.sleep(500, 1000)
  if FSL.OVHD_AI_Wing_Anti_Ice_Button:isDown() then
    FSL.OVHD_AI_Wing_Anti_Ice_Button()
  end
end) ]]

for _, voiceCommand in pairs(Event.voiceCommands) do
  for _, phrase in ipairs(voiceCommand:getPhrases()) do
    voiceCommand:removePhrase(phrase)
    voiceCommand:addPhrase(phrase:gsub("%S+", function(word) 
      return "+" .. word
    end))
  end
end