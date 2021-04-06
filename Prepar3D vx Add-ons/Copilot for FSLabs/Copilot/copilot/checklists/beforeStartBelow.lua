
local beforeStartBelow = Checklist:new(
  "beforeStartBelow",
  "Before Start below the Line",
  VoiceCommand:new {phrase = "before start below the line", confidence = 0.9}
)

copilot.checklists.beforeStartBelow = beforeStartBelow

local doors = {
  FSLA320_bulk_cargo_door = "Bulk cargo door",
  FSLA320_upper_cargo_door = "Forward cargo door",
  FSLA320_lower_cargo_door = "Aft cargo door",
  FSLA320_pax_door1 = "Left forward pax door",
  FSLA320_pax_door2 = "Right forward pax door",
  FSLA320_pax_door3 = "Left aft pax door",
  FSLA320_pax_door4 = "Right aft pax door",
  FSLA320_pax_door5 = "pax_door5",
  FSLA320_pax_door6 = "pax_door6",
  FSLA320_pax_door7 = "pax_door7",
  FSLA320_pax_door8 = "pax_door8",
}

beforeStartBelow:appendItem {
  label = "windowsDoors",
  displayLabel = "Windows / Doors",
  response = VoiceCommand:new "closed",
  onResponse = function(_, _, _, onFailed)
    if ipc.readLvar("VC_WINDOW_CPT") ~= 0 then
      onFailed "CPT window is open"
    end
    if ipc.readLvar("VC_WINDOW_FO") ~= 0 then
      onFailed "FO window is open"
    end
    if not FSL.PED_ECP_DOOR_Button:isLit() then
      FSL.PED_ECP_DOOR_Button()
      copilot.sleep(1000, 2000)
    end
    for lvar, door in pairs(doors) do
      if ipc.readLvar(lvar) ~= 0 then
        onFailed(door .. " is open")
      end
    end
  end
}

beforeStartBelow:appendItem {
  label = "askidNwStrg",
  displayLabel = "A/SKID & N/W STRG",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(name, _, _, onFailed)
    if FSL.MIP_BRAKES_ASKID_Button:getPosn() ~= name then
      onFailed("A/SKID & N/W STRG isn't " .. name)
    end
  end
}

beforeStartBelow:appendItem {
  label = "beacon",
  displayLabel = "Beacon",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(name, _, _, onFailed)
    if name == "OFF" then
      onFailed "You must say ON"
    elseif FSL.OVHD_EXTLT_Beacon_Switch:getPosn() ~= "ON" then
      onFailed "Beacon switch isn't ON"
    end
  end
}

beforeStartBelow:appendItem {
  label = "thrustLevers",
  displayLabel = "THR Levers",
  response = VoiceCommand:new "idle",
  onResponse = function(_, _, _, onFailed)
    if FSL:getThrustLeversPos() ~= "IDLE" then
      onFailed "Thrust levers aren't idle"
    end
  end
}

beforeStartBelow:appendItem {
  label = "parkingBrake",
  displayLabel = "Parking Brake",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(name, _, _, onFailed)
    if FSL.PED_PARK_BRAKE_Switch:getPosn() ~= name then
      onFailed("Parking brake switch isn't " .. name)
    end
  end
}

beforeStartBelow:appendItem {
  label = "mobileDevices",
  displayLabel = "Mobile Devices",
  response = VoiceCommand:new "off"
}