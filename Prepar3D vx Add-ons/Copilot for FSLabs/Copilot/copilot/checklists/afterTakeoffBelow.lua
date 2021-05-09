
local afterTakeoffBelow = Checklist:new(
  "afterTakeoffBelow",
  "After Takeoff / Climb below the Line",
  VoiceCommand:new ({"after takeoff climb below the line", "below the line"}, 0.9)
)

copilot.checklists.afterTakeoffBelow = afterTakeoffBelow

afterTakeoffBelow:appendItem {
  label = "baroRef",
  displayLabel = "Baro REF",
  response = VoiceCommand:new {"standard", "standard set"}
}