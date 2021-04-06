
local beforeTakeoff = Checklist:new(
  "beforeTakeoff",
  "Before Takeoff to the Line",
  VoiceCommand:new "before takeoff checklist"
)

copilot.checklists.beforeTakeoff = beforeTakeoff

local flightControlsEvent = copilot.events.flightControlsChecked:toSingleEvent()

beforeTakeoff:appendItem {
  label = "flightControls",
  displayLabel = "Flight Controls",
  response = VoiceCommand:new "checked",
  acknowledge = "checked",
  onResponse = function(_, _, _, onFailed)
    if Event.waitForEventWithTimeout(0, flightControlsEvent) == Event.TIMEOUT then
      onFailed "Flight controls not checked"
    else
      flightControlsEvent:reset()
    end
  end
}

beforeTakeoff:appendItem {
  label = "flapSetting",
  displayLabel = "Flap Setting",
  response = VoiceCommand:new {
    phrase = Phrase.new():append("config"):append({"1", "2", "3"}, "setting")
  },
  onResponse = function(_, _, recoResult, onFailed, res)
    local flapsSetting = copilot.mcduWatcher:getVar "takeoffFlaps" or FSL:getTakeoffFlapsFromMcdu()
    flapsSetting = tostring(flapsSetting)
    local response = recoResult.props.setting
    local actualPos = FSL.PED_FLAP_LEVER:getPosn()
    if response ~= flapsSetting then
      onFailed(response .. " isn't the planned flaps setting")
    elseif response ~= actualPos then
      onFailed("Flap setting isn't " .. response)
    else
      res.acknowledge = "conf" .. response
    end
  end
}

local takeoffRwy

beforeTakeoff:appendItem {
  label = "briefingAndPerf",
  displayLabel = "Briefing & Perf",
  response = VoiceCommand:new(),
  beforeChallenge = function(item)
    takeoffRwy = copilot.mcduWatcher:getVar "takeoffRwy"
    if not takeoffRwy then
      FSL.CPT.PED_MCDU_KEY_PERF()
      copilot.sleep(1000, 2000)
      takeoffRwy = FSL.MCDU:getString(18, 20)
    end
    if takeoffRwy:sub(1, 1) == " " then
      takeoffRwy = nil
    end
    if not takeoffRwy then 
      item.response.response:removeAllPhrases():addPhrase("... confirmed")
    else
      if #takeoffRwy == 2 then 
        takeoffRwy = takeoffRwy .. " "
      end
      local idents = {L = "left", R = "right", C = "center", [" "] = ""}
      local phraseString = ("%s %s %s"):format(
        takeoffRwy:sub(1, 1),
        takeoffRwy:sub(2, 2),
        idents[takeoffRwy:sub(3, 3)]
      )
      item.response.response
        :removeAllPhrases()
        :addPhrase(
          Phrase.new()
            :append("runway", true)
            :append({"...", phraseString}, "rwy")
            :append("confirmed")
        )
    end
    copilot.recognizer:resetGrammar()
  end,
  onResponse = function(_, _, recoResult, onFailed)
    if recoResult.props.rwy == "..." then
      onFailed "You said the wrong runway"
    end
  end
}

beforeTakeoff:appendItem {
  label = "ecamMemo",
  displayLabel = "ECAM Memo",
  response = VoiceCommand:new "takeoff no blue",
  acknowledge = "takeoffNoBlue",
  onResponse = function(_, _, _, onFailed)
    if FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() == "OFF" then
      onFailed "No smoking switch must be ON or AUTO"
    end
    if FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() ~= "ON" then
      onFailed "Seat belts switch must be ON"
    end
    if FSL.PED_SPD_BRK_LEVER:getPosn() ~= "ARM" then
      onFailed "Spoilers not armed"
    end
    if FSL.PED_FLAP_LEVER:getPosn() == "0" then
      onFailed "Flaps not set"
    end
  end
}

local beforeTakeoffBelow = Checklist:new(
  "beforeTakeoffBelow",
  "Before Takeoff below the Line",
  VoiceCommand:new "before takeoff below the line"
)

copilot.checklists.beforeTakeoffBelow = beforeTakeoffBelow

beforeTakeoffBelow:appendItem {
  label = "takeoffRwy",
  displayLabel = "Takeoff RWY",
  response = VoiceCommand:new "runway ..."
  -- TODO: Verify if on correct runway?
}

beforeTakeoffBelow:appendItem {
  label = "packs",
  displayLabel = "Packs",
  response = {ON = VoiceCommand:new "on", OFF = VoiceCommand:new "OFF"},
  onResponse = function(name, _, _, onFailed)
    local _, atsuTakeoffPacks = FSL.atsuLog:getTakeoffPacks()
    local shouldTurnoffPacks

    if atsuTakeoffPacks then
      shouldTurnoffPacks = atsuTakeoffPacks == "OFF"
    else
      shouldTurnoffPacks = copilot.UserOptions.actions.packs_on_takeoff == copilot.TAKEOFF_PACKS_TURN_OFF
    end

    if shouldTurnoffPacks and name == "ON" then
      onFailed "You wanted the packs off"
    else
      local pack1On = FSL.OVHD_AC_Pack_1_Button:isDown()
      local pack2On = FSL.OVHD_AC_Pack_2_Button:isDown()
      if name == "ON" then
        if not pack1On then onFailed "Pack 1 is off" end
        if not pack2On then onFailed "Pack 2 is off" end
      end
      if name == "OFF" then
        if pack1On then onFailed "Pack 1 is on" end
        if pack2On then onFailed "Pack 2 is on" end
      end
    end
  end
}