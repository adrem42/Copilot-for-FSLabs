local mcduRunway

local function initFindRunwayInMcdu()
  mcduRunway = copilot.mcduWatcher:getVar "takeoffRwy"
  if not mcduRunway then FSL.PED_MCDU_KEY_PERF() end
end

local function findRunwayInMcdu()
  while true do
    local rwy = withTimeout(1000, function()
      local disp = FSL.MCDU:getString()
      if disp:find "TAKE OFF RWY" then  
        return disp:sub(18, 20)
      end
      copilot.suspend(100)
    end)
    if rwy then return rwy end
    FSL.PED_MCDU_KEY_PERF()
  end
end

local function checkTakeoffRwyResponse(check, res, firstTry)
  mcduRunway = mcduRunway or findRunwayInMcdu()
  local selectedRunway
  local function secondTry() 
    mcduRunway = nil
    FSL.PED_MCDU_KEY_PERF()
    return checkTakeoffRwyResponse(check, res, false)
  end
  if mcduRunway:sub(1, 1) == " " then
    if firstTry then return secondTry() end
    return check "No takeoff runway in the MCDU"
  elseif mcduRunway:sub(3, 3) == " " then
    selectedRunway = mcduRunway:sub(1, 2)
  else
    selectedRunway = mcduRunway
  end
  local responseRwy = PhraseUtils.getPhraseResult("runwayId", res, "takeoffRwy")
  if responseRwy ~= selectedRunway then 
    if firstTry then return secondTry() end
    check(("MCDU takeoff runway is %s (you said %s)"):format(selectedRunway, responseRwy))
  end
end

local function takeoffRwyOnResponse(check, res)
  checkTakeoffRwyResponse(check, res, true)
end

local beforeTakeoffBelow = Checklist:new(
  "beforeTakeoffBelow",
  "Before Takeoff below the Line",
  VoiceCommand:new({"before takeoff below the line", "below the line"}, 0.9)
)

copilot.checklists.beforeTakeoffBelow = beforeTakeoffBelow

beforeTakeoffBelow:appendItem {
  label = "takeoffRwy",
  displayLabel = "Takeoff RWY",
  response = VoiceCommand:new(
    PhraseBuilder.new()
      :appendOptional "runway"
      :append(PhraseUtils.getPhrase "runwayId", "takeoffRwy")
      :appendOptional "confirmed"
      :build()
  ),
  beforeChallenge = initFindRunwayInMcdu,
  onResponse = takeoffRwyOnResponse,
  onResponseCoroutine = true
}

beforeTakeoffBelow:appendItem {
  label = "cabinCrew",
  displayLabel = "Cabin Crew",
  response = VoiceCommand:new "advised"
}

beforeTakeoffBelow:appendItem {
  label = "tcas",
  displayLabel = "TCAS",
  response = {TA = VoiceCommand:new "t a", TARA = VoiceCommand:new "t a r a"},
  onResponse = function(check, _, label)
    check(
      FSL.PED_ATCXPDR_MODE_Switch:getPosn() == label,
      "ATC mode switch position isn't " .. label
    )
  end
}

beforeTakeoffBelow:appendItem(require"copilot.checklists.common".engModeSelector)

beforeTakeoffBelow:appendItem {
  label = "packs",
  displayLabel = "Packs",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, _, label)
    local _, atsuTakeoffPacks = FSL.atsuLog:getTakeoffPacks()
    local packsShouldBeOff
    if atsuTakeoffPacks then
      packsShouldBeOff = atsuTakeoffPacks == "OFF"
    else
      packsShouldBeOff = copilot.UserOptions.actions.packs_on_takeoff == copilot.TAKEOFF_PACKS_TURN_OFF
    end
    if packsShouldBeOff and label == "ON" then
      check "You wanted the packs off"
    else
      local pack1On = FSL.OVHD_AC_Pack_1_Button:isDown()
      local pack2On = FSL.OVHD_AC_Pack_2_Button:isDown()
      if label == "ON" then
        check(pack1On, "Pack 1 is off")
        check(pack2On, "Pack 2 is off")
      else
        check(not pack1On, "Pack 1 is on")
        check(not pack2On, "Pack 2 is on")
      end
    end
  end
}