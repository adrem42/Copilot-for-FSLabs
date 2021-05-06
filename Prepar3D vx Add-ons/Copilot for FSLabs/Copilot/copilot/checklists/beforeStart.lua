
local beforeStart = Checklist:new(
  "beforeStart",
  "Before Start to the Line",
  VoiceCommand:new("before start checklist", 0.9)
)

copilot.checklists.beforeStart = beforeStart

beforeStart:appendItem {
  label = "cockpitPrep",
  displayLabel = "Cockpit Prep",
  response = VoiceCommand:new("completed", 0.9),
  acknowledge = "cockpitPrepCompleted"
}

beforeStart:appendItem {
  label = "gearPinsAndCovers",
  displayLabel = "Gear Pins and Covers",
  response = VoiceCommand:new "removed"
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

beforeStart:appendItem {
  label = "adirs",
  displayLabel = "ADIRS",
  response = VoiceCommand:new "nav",
  onResponse = function(check)
    check(FSL.OVHD_ADIRS_1_Knob:getPosn() == "NAV", "ADIRS 1 not NAV")
    check(FSL.OVHD_ADIRS_2_Knob:getPosn() == "NAV", "ADIRS 2 not NAV")
    check(FSL.OVHD_ADIRS_3_Knob:getPosn() == "NAV", "ADIRS 3 not NAV")
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
  response = VoiceCommand:new "set"
}

beforeStart:appendItem(require"copilot.checklists.common".baroRefQNH)