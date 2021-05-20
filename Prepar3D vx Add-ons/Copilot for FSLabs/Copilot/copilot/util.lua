
if false then  module("copilot")end

local flapsLimits = {}

copilot.flapsLimits = flapsLimits

if FSL:getAcType() == "A321" then
  flapsLimits.flapsOne = 235
  flapsLimits.flapsTwo = 215
  flapsLimits.flapsThree = 195
  flapsLimits.flapsFull = 190
else
  flapsLimits.flapsOne = 230
  flapsLimits.flapsTwo = 200
  flapsLimits.flapsThree = 185
  flapsLimits.flapsFull = 177
end

local optionToSequenceNames = {
  preflight = "preflight",
  after_start = "afterStart",
  during_taxi = "taxiSequence",
  lineup = "lineUpSequence",
  takeoff_sequence = "takeoffSequence",
  after_takeoff = "afterTakeoffSequence",
  ten_thousand_dep = "tenThousandDep",
  ten_thousand_arr = "tenThousandArr",
  after_landing = "afterLanding",
  parking = "parking",
  securing_the_aircraft = "securingTheAircraft"
}

local function getSequence(name)
  if not copilot.sequences[name] then
    if not optionToSequenceNames[name] then
      error("No such sequence: '" .. name .. "'", 3)
    end
    return copilot.sequences[optionToSequenceNames[name]], optionToSequenceNames[name]
  end
  return copilot.sequences[name], name
end

local function replaceSequence(name, func)
  if type(copilot.sequences[name]) == "table" and copilot.sequences[name].__call then
    copilot.sequences[name] = func
  elseif type(copilot.sequences[name]) == "function" then
    copilot.sequences[name].__call = func
  end
end

--- Appends a function to a default sequence
---@string name Name of the sequence in in options.ini or in the code
---@tparam function func The function to append
---@usage
--- copilot.appendSequence("lineup", function()
---   FSL.OVHD_EXTLT_Nose_Switch "TO"
---   FSL.OVHD_EXTLT_Strobe_Switch "AUTO"
--- end)
function copilot.appendSequence(name, func)
  local old, _name = getSequence(name)
  replaceSequence(_name, function(...)
    func(...)
    old(...)
  end)
end

--- Prepends a function to a default sequence
---@string name  Name of the sequence in in options.ini or in the code
---@tparam function func The function to prepend
function copilot.prependSequence(name, func)
  local old, _name = getSequence(name)
  replaceSequence(_name, function(...)
    old(...)
    func(...)
  end)
end

--- Replaces a default sequence
---@string name  Name of the sequence in in options.ini or in the code
---@tparam function func New sequence
function copilot.replaceSequence(name, func)
  replaceSequence(select(2, getSequence(name)), func)
end