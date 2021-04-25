
local beforeTakeoff = Checklist:new(
  "beforeTakeoff",
  "Before Takeoff to the Line",
  VoiceCommand:new {"before takeoff checklist", "before takeoff to the line"}
)

copilot.checklists.beforeTakeoff = beforeTakeoff

local flightControlsChecked
copilot.events.flightControlsChecked:addAction(function() flightControlsChecked = true end)
copilot.events.engineShutdown:addAction(function() flightControlsChecked = false end)

beforeTakeoff:appendItem {
  label = "flightControls",
  displayLabel = "Flight Controls",
  response = VoiceCommand:new "checked",
  acknowledge = "checklists.checked",
  onResponse = function(check) check(flightControlsChecked, "Flight controls not checked") end
}

beforeTakeoff:appendItem {
  label = "flapSetting",
  displayLabel = "Flap Setting",
  response = VoiceCommand:new (
    PhraseBuilder.new():append("config"):append({"1", "2", "3"}, "flapsSetting"):build()
  ),
  onResponse = function(check, recoResult, _, res)
    local plannedSetting = copilot.mcduWatcher:getVar "takeoffFlaps" or FSL:getTakeoffFlapsFromMcdu()
    plannedSetting = tostring(plannedSetting)
    local responseSetting = recoResult:getProp "flapsSetting"
    local actualSetting = FSL.PED_FLAP_LEVER:getPosn()
    if responseSetting ~= plannedSetting then
      check(("MCDU flap setting is %s (you said %s)"):format(plannedSetting, responseSetting))
    elseif responseSetting ~= actualSetting then
      check(("The actual flap setting is %s (you said %s)"):format(actualSetting, responseSetting))
    else
      res.acknowledge = "conf" .. responseSetting
    end
  end
}

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

local takeoffRwyPhraseBase = PhraseBuilder.new()
  :appendOptional "runway"
  :append(PhraseUtils.getPhrase "runwayId", "takeoffRwy")
  :build()

beforeTakeoff:appendItem {
  label = "briefingAndPerf",
  displayLabel = "Briefing & Perf",
  response = VoiceCommand:new(
    PhraseBuilder.new()
      :append(takeoffRwyPhraseBase)
      :appendOptional "confirmed"
      :build()
  ),
  beforeChallenge = initFindRunwayInMcdu,
  onResponse = takeoffRwyOnResponse,
  onResponseCoroutine = true
}

beforeTakeoff:appendItem {
  label = "ecamMemo",
  displayLabel = "ECAM Memo",
  response = VoiceCommand:new "takeoff no blue",
  acknowledge = "takeoffNoBlue",
  onResponse = function(check)
    check(FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() ~= "OFF", "No smoking switch must be ON or AUTO")
    check(FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() == "ON",  "Seat belts switch must be ON")
    check(FSL.PED_SPD_BRK_LEVER:getPosn() == "ARM",           "Spoilers not armed")
    check(FSL.PED_FLAP_LEVER:getPosn() ~= "0",                "Flaps not set")
  end
}

local beforeTakeoffBelow = Checklist:new(
  "beforeTakeoffBelow",
  "Before Takeoff below the Line",
  VoiceCommand:new({"before takeoff below the line", "below the line"}, 0.9)
)

copilot.checklists.beforeTakeoffBelow = beforeTakeoffBelow

beforeTakeoffBelow:appendItem {
  label = "takeoffRwy",
  displayLabel = "Takeoff RWY",
  response = VoiceCommand:new(takeoffRwyPhraseBase),
  beforeChallenge = initFindRunwayInMcdu,
  onResponse = takeoffRwyOnResponse,
  onResponseCoroutine = true
}

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