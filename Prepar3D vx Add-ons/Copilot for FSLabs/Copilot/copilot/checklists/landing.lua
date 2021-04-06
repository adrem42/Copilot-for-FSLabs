local landing = Checklist:new(
  "landing",
  "Landing",
  VoiceCommand:new "landing checklist"
)

copilot.checklists.landing = landing

landing:appendItem {
  label = "ecamMemo",
  displayLabel = "ECAM Memo",
  acknowledge = "landingNoBlue",
  response = VoiceCommand:new "Landing no blue",
  onResponse = function(_, _, _, onFailed)
    if FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() == "OFF" then
      onFailed "No smoking switch must be ON or AUTO"
    end
    if FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() ~= "ON" then
      onFailed "Seat belts switch must be ON"
    end
    if FSL.PED_SPD_BRK_LEVER:getPosn() ~= "ARM" then
      onFailed "Spoilers not armed"
    end
    if FSL.PED_FLAP_LEVER:getPosn() ~= "FULL" then
      onFailed "Flaps not set"
    end
  end
}

landing:appendItem {
  label = "autoThrust",
  displayLabel = "A/THR",
  response = {SPEED = VoiceCommand:new "speed", OFF = VoiceCommand:new "off"},
  onResponse = function(label, _, _, onFailed)
    local athrOn = FSL.GSLD_FCU_ATHR_Switch:isLit()
    if label == "SPEED" and not athrOn then
      onFailed "Auto-thrust is off"
    elseif label == "OFF" and athrOn then
      onFailed "Auto-thrust is on"
    end
  end
}