
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
  onResponse = function(check)
    check(FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() ~= "OFF", "No smoking switch must be ON or AUTO")
    check(FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() == "ON",  "Seat belts switch must be ON")
    check(FSL.PED_SPD_BRK_LEVER:getPosn() == "ARM",           "Spoilers not armed")
    check(FSL.PED_FLAP_LEVER:getPosn() == "FULL",             "Flaps not set")
  end
}

landing:appendItem {
  label = "autoThrust",
  displayLabel = "A/THR",
  response = {SPEED = VoiceCommand:new "speed", OFF = VoiceCommand:new "off"},
  onResponse = function(check, label)
    local athrOn = FSL.GSLD_FCU_ATHR_Switch:isLit()
    if label == "SPEED" then
      check(athrOn, "Auto-thrust is off")
    elseif label == "OFF" then
      check(not athrOn, "Auto-thrust is on")
    end
  end
}