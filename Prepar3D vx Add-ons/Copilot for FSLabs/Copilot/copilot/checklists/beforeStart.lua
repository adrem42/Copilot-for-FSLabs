
local beforeStart = Checklist:new(
  "beforeStart",
  "Before Start to the Line",
  VoiceCommand:new {phrase = {"before start checklist", "before start to the line"}, confidence = 0.9}
)

copilot.checklists.beforeStart = beforeStart

beforeStart:appendItem {
  label = "cockpitPrep",
  displayLabel = "Cockpit Preparation",
  response = VoiceCommand:new {phrase = "completed", confidence = 0.9}
}

beforeStart:appendItem {
  label = "signs",
  displayLabel = "Signs",
  response = VoiceCommand:new {phrase = {"on auto", "on and auto"}, confidence = 0.9},
  onResponse = function(check)
    check(FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() ~= "OFF", "No smoking switch must be ON or AUTO")
    check(FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() == "ON", "Seat belts switch must be ON")
  end
}

beforeStart:appendItem {
  label = "fuelQuantity",
  displayLabel = "Fuel Quantity",
  response = VoiceCommand:new {phrase = {"... kilograms", "... pounds"}, confidence = 0.9}
  -- TODO: create phrase dynamically and do some checking (compare with loadsheet?)
}

local digits = {}
for i = 0, 9 do digits[#digits+1] = tostring(i) end
local V1, V2

beforeStart:appendItem {
  label = "toData",
  displayLabel = "TO Data",
  response = VoiceCommand:new {confidence = 0.9, logMsg = "beforeStart.toData"},
  beforeChallenge = function(item)
    FSL.PED_MCDU_KEY_PERF()
    ipc.sleep(2000)
    local disp = FSL.MCDU:getArray()
    local speedsEntered = disp[49].color == "cyan" and disp[145].color == "cyan"
    if not speedsEntered then
      item.response.response:removeAllPhrases():addPhrase"checked"
    else
      V1 = disp[49].char .. disp[50].char .. disp[51].char
      V2 = disp[145].char .. disp[146].char .. disp[147].char
      local phrase = Phrase.new()
        :append("V1"):append(digits, "V1_1"):append(digits, "V1_2"):append(digits, "V1_3")
        :append("V2"):append(digits, "V2_1"):append(digits, "V2_2"):append(digits, "V2_3")
      local isFLEX = disp[215].char ~= nil
      if isFLEX then
        phrase:append("FLEX"):append({"...", disp[215].char .. disp[216].char}, "FLEX")
      else
        phrase:append({"TOGA", "..."}, "TOGA")
      end
      item.response.response:removeAllPhrases():addPhrase(phrase)
    end
    VoiceCommand.resetGrammar() -- the grammar needs to be recompiled for the modifications to take effect
  end,
  onResponse = function(check, _, recoResult)
    if recoResult.phrase == "checked" then return end
    local props = recoResult.props
    local responseV1 = props.V1_1 .. props.V1_2 .. props.V1_3
    local responseV2 = props.V2_1 .. props.V2_2 .. props.V2_3
    check(responseV1 == V1, "Wrong V1")
    check(responseV2 == V2, "Wrong V2")
    if props.FLEX then
      check(props.FLEX ~= "...", "Weird FLEX (and not OK)")
    elseif props.TOGA then
      check(props.TOGA == "TOGA", "The correct response is 'TOGA'")
    end
  end
}

beforeStart:appendItem {
  label = "baroRef",
  displayLabel = "Baro REF",
  response = VoiceCommand:new "... set"
}