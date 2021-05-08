
local beforeTakeoff = Checklist:new(
  "beforeTakeoff",
  "Before Takeoff to the Line",
  VoiceCommand:new "before takeoff checklist"
)

copilot.checklists.beforeTakeoff = beforeTakeoff

local flightControlsChecked
copilot.events.flightControlsChecked:addAction(function() flightControlsChecked = true end)
copilot.events.engineShutdown:addAction(function() flightControlsChecked = false end)

beforeTakeoff:appendItem {
  label = "flightControls",
  displayLabel = "Flight Controls",
  response = VoiceCommand:new "checked",
  acknowledge = "checked1",
  onResponse = function(check) 
    check(flightControlsChecked, "Flight controls not checked") 
  end
}

beforeTakeoff:appendItem {
  label = "flightInstruments",
  displayLabel = "Flight Instruments",
  response = VoiceCommand:new "checked",
  acknowledge = "checked2"
}

beforeTakeoff:appendItem {
  label = "briefing",
  displayLabel = "Briefing",
  response = VoiceCommand:new "confirmed"
}

beforeTakeoff:appendItem {
  label = "flapSetting",
  displayLabel = "Flap Setting",
  response = VoiceCommand:new (
    PhraseBuilder.new()
    :append "config"
    :append {
      propName = "flapsSetting",
      choices = {
        "1",
        {propVal = "1", choice = "1 plus f"},
        "2",
        "3"
      }
    } 
    :build()
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

beforeTakeoff:appendItem {
  label = "takeoffSpeedsFlexTemp",
  displayLabel = "V1, Vr, V2 / FLEX Temp",
  response = VoiceCommand:new {
    confidence = 0.9, 
    phrase = PhraseBuilder.new()
      :append {
        PhraseBuilder.new()
          :append "V one"
          :append(PhraseUtils.getPhrase("spelledNumber", 3), "V1")
          :append "V r"
          :append(PhraseUtils.getPhrase("spelledNumber", 3), "Vr")
          :append "V two"
          :append(PhraseUtils.getPhrase("spelledNumber", 3), "V2")
          :build(),
        PhraseBuilder.new()
          :append(PhraseUtils.getPhrase("spelledNumber", 3), "V1")
          :append(PhraseUtils.getPhrase("spelledNumber", 3), "Vr")
          :append(PhraseUtils.getPhrase("spelledNumber", 3), "V2")
          :build()
      }
      :append {
        "TOGA",
        {
          propVal = "TOGA",
          choice = PhraseBuilder.new():append"no flex":appendOptional"temp":build()
        },
        PhraseBuilder.new()
          :append "FLEX"
          :appendOptional "temp"
          :append {
            propName = "flexTemp",
            asString = "FLEX temp",
            choices = table.init(40, 80, 1, tostring)
          }
          :build()
      }
      :build()
  },
  beforeChallenge = FSL.PED_MCDU_KEY_PERF,
  onResponseCoroutine = true,
  onResponse = function(check, res)
    local disp
    while true do
      if checkWithTimeout(1000, function()
        disp = FSL.MCDU:getString()
        if disp:find "TAKE OFF RWY" then return true end
        copilot.suspend(100) -- this allows the user to open the menu and skip the checklist item if the loop is stuck for whatever reason
      end) then break end
      FSL.PED_MCDU_KEY_PERF()
    end
    local selectedV1 = disp:match("^%d%d%d", 49)
    local selectedVr = disp:match("^%d%d%d", 97)
    local selectedV2 = disp:match("^%d%d%d", 145)
    local selectedFlexTemp = disp:match("^%d%d", 215)
    if not check(selectedV1 and selectedVr and selectedV2, "Takeoff speeds not entered") then return end 
    local responseV1 = PhraseUtils.getPhraseResult("spelledNumber", res, "V1")
    local responseVr = PhraseUtils.getPhraseResult("spelledNumber", res, "Vr")
    local responseV2 = PhraseUtils.getPhraseResult("spelledNumber", res, "V2")
    check(responseV1 == selectedV1, ("MCDU V1 is %s (you said %s)"):format(selectedV1, responseV1))
    check(responseVr == selectedVr, ("MCDU Vr is %s (you said %s)"):format(selectedVr, responseVr))
    check(responseV2 == selectedV2, ("MCDU V2 is %s (you said %s)"):format(selectedV2, responseV2))
    local responseFlex = res:getProp "flexTemp"
    if selectedFlexTemp then
      check(
        responseFlex == selectedFlexTemp, 
        ("MCDU FLEX temp is %s (you said %s)"):format(selectedFlexTemp, responseFlex or "TOGA")
      )
    else
      check(not responseFlex, "No FLEX temp was entered into the MCDU")
    end
  end
}

beforeTakeoff:appendItem {
  label = "ATC",
  displayLabel = "ATC",
  response = VoiceCommand:new "set"
}

beforeTakeoff:appendItem {
  label = "ecamMemo",
  displayLabel = "ECAM Memo",
  response = VoiceCommand:new "takeoff no blue",
  onResponse = function(check)
    check(FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() ~= "OFF", "No smoking switch must be ON or AUTO")
    check(FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() == "ON",  "Seat belts switch must be ON")
    check(FSL.PED_SPD_BRK_LEVER:getPosn() == "ARM",           "Spoilers not armed")
    check(FSL.PED_FLAP_LEVER:getPosn() ~= "0",                "Flaps not set")
  end
}
