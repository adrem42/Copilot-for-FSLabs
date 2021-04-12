
local beforeStartBelow = Checklist:new(
  "beforeStartBelow",
  "Before Start below the Line",
  VoiceCommand:new {
    phrase = {"before start below the line", "below the line"}, 
    confidence = 0.9
  }
)

copilot.checklists.beforeStartBelow = beforeStartBelow

local doorPageWasOpen
beforeStartBelow:appendItem {
  label = "windowsDoors",
  displayLabel = "Windows / Doors",
  response = VoiceCommand:new "closed",
  beforeChallenge = function()
    doorPageWasOpen = FSL.PED_ECP_DOOR_Button:isLit()
    if not doorPageWasOpen then
      FSL.PED_ECP_DOOR_Button()
    end
  end,
  onResponse = function(check, _, _, res)
    check(ipc.readLvar("VC_WINDOW_CPT") == 0, "CPT window is open")
    check(ipc.readLvar("VC_WINDOW_FO") == 0, "FO window is open")
    local function checkDoor(lvar, door)
      check(ipc.readLvar(lvar) == 0, door .. " is open")
    end
    checkDoor("FSLA320_bulk_cargo_door", "Bulk cargo door")
    checkDoor("FSLA320_upper_cargo_door", "Forward cargo door")
    checkDoor("FSLA320_lower_cargo_door", "Aft cargo door")
    checkDoor("FSLA320_pax_door1", "Left forward pax door")
    checkDoor("FSLA320_pax_door2", "Right forward pax door")
    checkDoor("FSLA320_pax_door3", "Left aft pax door")
    checkDoor("FSLA320_pax_door4", "Right aft pax door")
    checkDoor("FSLA320_pax_door5", "FSLA320_pax_door5")
    checkDoor("FSLA320_pax_door6", "FSLA320_pax_door6")
    checkDoor("FSLA320_pax_door7", "FSLA320_pax_door7")
    checkDoor("FSLA320_pax_door8", "FSLA320_pax_door8")
    copilot.sleep(0, 1000)
    if not res.didFail() and not doorPageWasOpen then
      FSL.PED_ECP_DOOR_Button:pressIfLit()
    end
  end
}

beforeStartBelow:appendItem {
  label = "askidNwStrg",
  displayLabel = "A/SKID & N/W STRG",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, label)
    check(FSL.MIP_BRAKES_ASKID_Button:getPosn() == label, "A/SKID & N/W STRG isn't " .. label)
  end
}

beforeStartBelow:appendItem {
  label = "beacon",
  displayLabel = "Beacon",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, label)
    if check(label == "ON", "The correct response is 'on'") then
      check(FSL.OVHD_EXTLT_Beacon_Switch:getPosn() == "ON", "Beacon switch isn't on")
    end
  end
}

beforeStartBelow:appendItem {
  label = "thrustLevers",
  displayLabel = "THR Levers",
  response = VoiceCommand:new "idle",
  onResponse = function(check)
    check(FSL:getThrustLeversPos() == "IDLE", "Thrust levers aren't idle")
  end
}

beforeStartBelow:appendItem {
  label = "parkingBrake",
  displayLabel = "Parking Brake",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, label)
    check(FSL.PED_PARK_BRAKE_Switch:getPosn() == label, "Parking brake switch isn't " .. label)
  end
}

beforeStartBelow:appendItem {
  label = "mobileDevices",
  displayLabel = "Mobile Devices",
  response = VoiceCommand:new "off"
}