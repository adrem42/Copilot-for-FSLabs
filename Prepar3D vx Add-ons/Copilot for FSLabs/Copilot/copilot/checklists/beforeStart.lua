
local beforeStart = Checklist:new(
  "beforeStart",
  "Before Start to the Line",
  VoiceCommand:new {phrase = "before start checklist", confidence = 0.9}
)

copilot.checklists.beforeStart = beforeStart

beforeStart:appendItem {
  label = "cockpitPrep",
  displayLabel = "Cockpit Preparation",
  response = VoiceCommand:new "completed"
}

beforeStart:appendItem {
  label = "signs",
  displayLabel = "Signs",
  response = VoiceCommand:new {
    phrase = {"on, auto", "on and auto"}
  },
  onResponse = function(_, _, _, onFailed)
    if FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() == "OFF" then
      onFailed "No smoking switch must be ON or AUTO"
    end
    if FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() ~= "ON" then
      onFailed "Seat belts switch must be ON"
    end
  end
}

beforeStart:appendItem {
  label = "fuelQuantity",
  displayLabel = "Fuel Quantity",
  response = VoiceCommand:new {
    phrase = {"... kilograms", "... pounds"}
  }
}

beforeStart:appendItem {
  label = "toData",
  displayLabel = "TO Data",
  response = VoiceCommand:new(),
  beforeChallenge = function(item)
    FSL.PED_MCDU_KEY_PERF()
    repeat ipc.sleep(1000) 
    until FSL.MCDU:getString():find "TAKE OFF RWY"
    local disp = FSL.MCDU:getArray()
    item.response.response:removeAllPhrases()
      :addPhrase(
        Phrase.new()
        :append("V1")
        :append({"...", ("%s %s %s"):format(disp[49].char, disp[50].char, disp[51].char)}, "V1")
        :append("V2")
        :append({"...", ("%s %s %s"):format(disp[145].char, disp[146].char, disp[147].char)}, "V2")
        :append("FLEX")
        :append(
          {
            "...", 
            disp[215].char .. " " .. disp[216].char,
            disp[215].char .. disp[216].char
          },
          "FLEX"
        )
      )
    copilot.recognizer:resetGrammar()
  end,
  onResponse = function(_, _, recoResult, onFailed)
    if recoResult.props.V1 == "..." then
      onFailed "Wrong V1"
    end
    if recoResult.props.V2 == "..." then
      onFailed "Wrong V2"
    end
    if recoResult.props.FLEX == "..." then
      onFailed "Wrong FLEX"
    end
  end
}

beforeStart:appendItem {
  label = "baroRef",
  displayLabel = "Baro REF",
  response = VoiceCommand:new "... set"
}