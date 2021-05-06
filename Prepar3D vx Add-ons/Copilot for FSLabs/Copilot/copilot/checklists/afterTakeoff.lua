
local afterTakeoff = Checklist:new(
  "afterTakeoff",
  "After Takeoff / Climb",
  VoiceCommand:new ("after takeoff climb checklist", 0.9)
)

copilot.checklists.afterTakeoff = afterTakeoff

afterTakeoff:appendItem {
  label = "landingGear",
  displayLabel = "Landing Gear",
  response = VoiceCommand:new "up",
  onResponse = function(check)
    local noseGearUp = ipc.readUD(0x0BEC) == 0
    local rightGearUp = ipc.readZD(0x0BF0) == 0
    local leftGearUp = ipc.readUD(0x0BF4) == 0
    check(noseGearUp, "Nose gear not up")
    check(rightGearUp, "Right gear not up")
    check(leftGearUp, "Left gear not up")
  end
}

afterTakeoff:appendItem {
  label = "flaps",
  displayLabel = "Flaps",
  response = VoiceCommand:new "retracted",
  onResponse = function(check)
    local slatsRetracted = ipc.readLvar "FSLA320_slat_l_1" == 0
    local flapsRetracted = ipc.readUD(0x0BE0) == 0 and ipc.readUD(0x0BE4) == 0
    check(flapsRetracted, "Flaps are not retracted")
    check(slatsRetracted, "Slats are not retracted")
  end
}

afterTakeoff:appendItem {
  label = "packs",
  displayLabel = "Packs",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, label)
    if not check(label == "ON", "The correct response is 'on'") then return end
    check(FSL.OVHD_AC_Pack_1_Button:isDown(), "Left pack is off")
    check(FSL.OVHD_AC_Pack_2_Button:isDown(), "Right pack is off")
  end
}