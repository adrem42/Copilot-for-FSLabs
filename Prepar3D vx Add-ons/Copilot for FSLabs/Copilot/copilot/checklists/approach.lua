
local approach = Checklist:new(
  "approach",
  "Approach",
  VoiceCommand:new "approach checklist"
)

copilot.checklists.approach = approach

approach:appendItem {
 label = "briefing",
 displayLabel = "Briefing",
 response = VoiceCommand:new "confirmed" 
}

approach:appendItem {
  label = "ecamStatus",
  displayLabel = "ECAM Status",
  response = VoiceCommand:new "checked"
}

approach:appendItem {
  label = "seatBelts",
  displayLabel = "Seat Belts",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, _, label)
    if check(label == "ON", "The correct response is 'on'") then
      check(FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() == "ON", "The seat belts switch isn't on")
    end
  end
}

approach:appendItem(require"copilot.checklists.common".baroRefQNH)

approach:appendItem {
  label = "minimum",
  displayLabel = "Minimum",
  response = VoiceCommand:new "... set"
}

approach:appendItem(require"copilot.checklists.common".engModeSelector)