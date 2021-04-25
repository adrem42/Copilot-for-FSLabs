
local beforeStart = Checklist:new(
  "beforeStart",
  "Before Start to the Line",
  VoiceCommand:new({"before start checklist", "before start to the line"}, 0.9)
)

copilot.checklists.beforeStart = beforeStart

beforeStart:appendItem {
  label = "cockpitPrep",
  displayLabel = "Cockpit Preparation",
  response = VoiceCommand:new("completed", 0.9)
}

beforeStart:appendItem {
  label = "signs",
  displayLabel = "Signs",
  response = VoiceCommand:new({"on auto", "on and auto"}, 0.9),
  onResponse = function(check)
    check(FSL.OVHD_SIGNS_NoSmoking_Switch:getPosn() ~= "OFF", "No smoking switch must be ON or AUTO")
    check(FSL.OVHD_SIGNS_SeatBelts_Switch:getPosn() == "ON", "Seat belts switch must be ON")
  end
}

local fuelUnit = copilot.getFltSimCfg():match "unit_weights=(%a+)\n" or "kg"
local LB_TO_KG = 0.453592
local function roundFuelQty(qty) return math.floor(qty / 100 + 0.5) * 100 end
local function simConnectFuelQty() return ipc.readUD(0x126C) * (fuelUnit == "kg" and LB_TO_KG or 1) end
local function atsuLoadsheetFuelQty() return tonumber(FSL.atsuLog:get():match ".*FUEL IN TANKS.-(%d-)\n") end
local function compareQty(qty1, qty2)
  local tolerance = fuelUnit == "kg" and 100 or 200
  return math.abs(qty1 - qty2) <= tolerance
end
local function numRangeElement(max, propName)
  return {propName = propName, asString = "1-" .. max, choices = table.init(max, tostring)}
end

beforeStart:appendItem {
  label = "fuelQuantity",
  displayLabel = "Fuel Quantity",
  response = VoiceCommand:new {
    confidence = 0.9,
    phrase = PhraseBuilder.new()
      :append(numRangeElement(100, "numThousands"))
      :append {
        PhraseBuilder.new()
          :append "thousand"
          :appendOptional(
            PhraseBuilder.new()
              :append(numRangeElement(9, "numHundreds"))
              :append "hundred"
              :build()
          )
          :appendOptional(fuelUnit == "kg" and "kilograms" or "pounds")
          :build(),
        fuelUnit == "kg" and "tonnes" or nil
      }
      :build()
  },
  onResponse = function(check, res)
    local spokenQty = res:getProp "numThousands" * 1000 + (res:getProp "numHundreds" or 0) * 100
    local actualQty = roundFuelQty(simConnectFuelQty())
    if spokenQty ~= actualQty then
      check(("Actual FOB is %s (you said %s)"):format(actualQty, spokenQty))
      return
    end
    local loadsheetQty = atsuLoadsheetFuelQty()
    if not loadsheetQty then return end
    loadsheetQty = roundFuelQty(loadsheetQty)
    check(
      compareQty(actualQty, loadsheetQty), 
      ("Loadsheet fuel weight is %s (actual FOB: %s, you said: %s)"):format(
        loadsheetQty, actualQty, spokenQty
      )
    )
  end
}

beforeStart:appendItem {
  label = "toData",
  displayLabel = "TO Data",
  response = VoiceCommand:new {
    confidence = 0.9, 
    phrase = PhraseBuilder.new()
      :append "V one"
      :append(PhraseUtils.getPhrase("spelledNumber", 3), "V1")
      :append "V two"
      :append(PhraseUtils.getPhrase("spelledNumber", 3), "V2")
      :append {
        "TOGA",
        PhraseBuilder.new()
          :append "FLEX"
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
    local selectedV2 = disp:match("^%d%d%d", 145)
    local selectedFlexTemp = disp:match("^%d%d", 215)
    if not check(selectedV1 and selectedV2, "No V-Speeds entered") then return end 
    local responseV1 = PhraseUtils.getPhraseResult("spelledNumber", res, "V1")
    local responseV2 = PhraseUtils.getPhraseResult("spelledNumber", res, "V2")
    check(responseV1 == selectedV1, ("MCDU V1 is %s (you said %s)"):format(selectedV1, responseV1))
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

beforeStart:appendItem {
  label = "baroRef",
  displayLabel = "Baro REF",
  response = VoiceCommand:new {
    confidence = 0.9, 
    phrase = PhraseBuilder.new()
      :append(PhraseUtils.getPhrase("spelledNumber", 4))
      :appendOptional "set"
      :build()
  }
}