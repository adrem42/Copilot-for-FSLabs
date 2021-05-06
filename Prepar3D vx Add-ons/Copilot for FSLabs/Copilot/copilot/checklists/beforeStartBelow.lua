
local beforeStartBelow = Checklist:new(
  "beforeStartBelow",
  "Before Start below the Line",
  VoiceCommand:new({"before start below the line", "below the line"}, 0.9)
)

copilot.checklists.beforeStartBelow = beforeStartBelow

local ecpButtons = table.map({
  "ENG", "BLEED", "PRESS", "ELEC", "HYD", "FUEL", 
  "APU", "COND", "FCTL", "WHEEL", "STS"
}, function(page)
  return FSL["PED_ECP_" .. page .. "_Button"]
end)

local function confirmDoorEcamPage()
  if FSL.PED_ECP_DOOR_Button:isLit() then return end
  for _, butt in ipairs(ecpButtons) do
    if butt:isLit() then 
      butt:pressIfLit() 
      return
    end
  end
end

beforeStartBelow:appendItem {
  label = "windowsDoors",
  displayLabel = "Windows / Doors",
  response = VoiceCommand:new "closed",
  beforeChallenge = confirmDoorEcamPage,
  acknowledge = "closed",
  onResponse = function(check)
    confirmDoorEcamPage()
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
  end
}

beforeStartBelow:appendItem {
  label = "beacon",
  displayLabel = "Beacon",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, _, label)
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
  response = {ON = VoiceCommand:new {"on", "set"}, OFF = VoiceCommand:new {"off", "released"}},
  onResponse = function(check, _, label)
    check(FSL.PED_PARK_BRAKE_Switch:getPosn() == label, "Parking brake switch isn't " .. label)
  end
}