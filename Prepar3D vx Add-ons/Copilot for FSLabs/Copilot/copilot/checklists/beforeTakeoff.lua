
local beforeTakeoff = Checklist:new(
  "beforeTakeoff",
  "Before Takeoff to the Line",
  VoiceCommand:new {phrase = {"before takeoff checklist", "before takeoff to the line"}}
)

copilot.checklists.beforeTakeoff = beforeTakeoff

local flightControlsEvent = copilot.events.flightControlsChecked:toSingleEvent()
beforeTakeoff:appendItem {
  label = "flightControls",
  displayLabel = "Flight Controls",
  response = VoiceCommand:new "checked",
  acknowledge = "checklists.checked",
  onResponse = function(check)
    if check(Event.waitForEventWithTimeout(0, flightControlsEvent) ~= Event.TIMEOUT, "Flight controls not checked") then
      flightControlsEvent:reset()
    end
  end
}

beforeTakeoff:appendItem {
  label = "flapSetting",
  displayLabel = "Flap Setting",
  response = VoiceCommand:new {
    phrase = Phrase.new():append("config"):append({"1", "2", "3"}, "flapsSetting")
  },
  onResponse = function(check, _, recoResult, res)
    local plannedSetting = copilot.mcduWatcher:getVar "takeoffFlaps" or FSL:getTakeoffFlapsFromMcdu()
    plannedSetting = tostring(plannedSetting)
    local responseSetting = recoResult:getProp "flapsSetting"
    local actualSetting = FSL.PED_FLAP_LEVER:getPosn()
    if responseSetting ~= plannedSetting then
      check(responseSetting .. " isn't the planned flaps setting")
    elseif responseSetting ~= actualSetting then
      check("Flap setting isn't " .. responseSetting)
    else
      res.acknowledge = "conf" .. responseSetting
    end
  end
}

local takeoffRwyPhrase

local function makeTakeoffRwyPhrase()
  local takeoffRwy = copilot.mcduWatcher:getVar "takeoffRwy"
  if not takeoffRwy then
    FSL.CPT.PED_MCDU_KEY_PERF()
    copilot.sleep(1000, 2000)
    takeoffRwy = FSL.MCDU:getString(18, 21)
  end
  if takeoffRwy:sub(1, 1) == " " then
    takeoffRwyPhrase = nil
    return
  end
  local phraseString = takeoffRwy:sub(1, 1) .. " " .. takeoffRwy:sub(2, 2)
  if takeoffRwy:sub(3, 3) ~= " " then
    phraseString = phraseString .. " " .. ({L = "left", R = "right", C = "center"})[takeoffRwy:sub(3, 3)]
  end
  takeoffRwyPhrase = Phrase.new():appendOptional("runway"):append({"...", phraseString}, "rwy")
end

local function takeoffRwyOnResponse(check, _, recoResult)
  if takeoffRwyPhrase then
    check(recoResult:getProp "rwy" ~= "...", "You said the wrong runway")
  end
end

beforeTakeoff:appendItem {
  label = "briefingAndPerf",
  displayLabel = "Briefing & Perf",
  response = VoiceCommand:new(),
  beforeChallenge = function(item)
    makeTakeoffRwyPhrase()
    item.response.response:removeAllPhrases():addPhrase(
      takeoffRwyPhrase and takeoffRwyPhrase:append "confirmed" or "confirmed"
    )
    VoiceCommand.resetGrammar()
  end,
  onResponse = takeoffRwyOnResponse
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
  VoiceCommand:new {phrase = {"before takeoff below the line", "below the line"}, confidence = 0.9}
)

copilot.checklists.beforeTakeoffBelow = beforeTakeoffBelow

beforeTakeoffBelow:appendItem {
  label = "takeoffRwy",
  displayLabel = "Takeoff RWY",
  response = VoiceCommand:new(),
  beforeChallenge = function(item)
    makeTakeoffRwyPhrase()
    item.response.response:removeAllPhrases():addPhrase(takeoffRwyPhrase and takeoffRwyPhrase or "confirmed")
    VoiceCommand.resetGrammar()
  end,
  onResponse = takeoffRwyOnResponse
}

beforeTakeoffBelow:appendItem {
  label = "packs",
  displayLabel = "Packs",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "off"},
  onResponse = function(check, label)
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