
local landing = Checklist:new(
  "landing",
  "Landing",
  VoiceCommand:new "landing checklist"
)

copilot.checklists.landing = landing

landing:appendItem {
  label = "cabinCrew",
  displayLabel = "Cabin Crew",
  response = VoiceCommand:new "advised"
}

landing:appendItem {
  label = "autoThrust",
  displayLabel = "A/THR",
  response = {SPEED = VoiceCommand:new "speed", OFF = VoiceCommand:new("off", 0.95)},
  onResponse = function(check, _, label)
    local athrOn = FSL.GSLD_FCU_ATHR_Switch:isLit()
    if label == "SPEED" then
      check(athrOn, "Auto-thrust is off")
    elseif label == "OFF" then
      check(not athrOn, "Auto-thrust is on")
    end
  end
}

landing:appendItem {
  label = "autoBrake",
  displayLabel = "Auto-brake",
  response = VoiceCommand:new {"low", "medium"}
}

landing:appendItem {
  label = "ecamMemo",
  displayLabel = "ECAM Memo",
  response = VoiceCommand:new "Landing no blue",
  onResponse = function(check)
    check(FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() ~= "OFF", "No smoking switch must be ON or AUTO")
    check(FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() == "ON", "Seat belts switch must be ON")
    check(FSL.PED_SPD_BRK_LEVER:getPosn() == "ARM", "Spoilers not armed")
    local flapsPos = FSL.PED_FLAP_LEVER:getPosn()
    local flap3Landing = FSL.OVHD_GPWS_LDG_FLAP_3_Button:isDown()
    check(flapsPos == (flap3Landing and "3" or "FULL"), "Flaps not set")
  end
}