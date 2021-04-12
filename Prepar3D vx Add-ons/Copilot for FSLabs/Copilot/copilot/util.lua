

if false then 
  module("copilot")
  ---Simulates a key press
  ---@string keys @{list_of_keys.md|See the list of keys here}
  ---@usage copilot.keypress "CONTROL+SHIFT+F12"
  function copilot.keypress(keys) end

  --- Display a SimConnect text message
  --- @string text Text to be displayed. May include line breaks.
  --- @int[opt=0] duration Duration in seconds. 0 means infinite.
  --- @string[opt="print_white"] type "type\_black", "type\_white", "type\_red", "type\_green", "type\_blue", "type\_yellow", "type\_magenta", "type\_cyan" where *type* is either *print* or *scroll*
  ---@usage copilot.displayText("hello", 10, "print_cyan")
  function copilot.displayText(text, duration, color) end
end

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

local ipc = ipc
local coroutine = coroutine

copilot.exit = ipc.exit

--- If both parameters omitted: `ipc.sleep`(100)<br><br>
--- If time1 specified: `ipc.sleep(time1)`<br><br>
--- If both are specified: `ipc.sleep(math.random(time1, time2))`
---@int[opt] time1
---@int[optchain] time2
function copilot.sleep(time1,time2)
  local time
  if time1 and time2 then time = math.random(time1, time2)
  elseif time1 then time = time1
  else time = 100 end
  ipc.sleep(time)
end

--- If both parameters omitted: `coroutine.yield()`<br><br>
--- Otherwise, suspend the execution of this coroutine for:<br><br>
--- If time1 specified: time1 milliseconds<br><br>
--- If time1 and time2 specified: random amount of milliseconds between time1 and time2
---@int[opt] time1
---@int[optchain] time2
function copilot.suspend(time1, time2)
  if not time1 then return coroutine.yield() end
  local timeout = time2 and math.random(time1, time2) or time1
  local thisThread = coroutine.running()
  if copilot.getCallbackStatus(thisThread) then
    copilot.setCallbackTimeout(thisThread, timeout)
    return
  end
  local timeoutEnd = copilot.getTimestamp() + timeout
  repeat coroutine.yield() until copilot.getTimestamp() > timeoutEnd
end

function copilot.GSX_pushback() 
  return ipc.readLvar("FSLA320_NWS_Pin") == 1 and ipc.readLvar("FSDT_GSX_DEPARTURE_STATE") ~= 6 
end

--- Returns true if you're on the ground.
function copilot.onGround() return ipc.readUB(0x0366) == 1 end
--- Returns the ground speed in knots.
function copilot.GS() return ipc.readUD(0x02B4) / 65536 * 3600 / 1852 end
--- Returns the radio altitude in meters.
function copilot.radALT() return ipc.readUD(0x31E4) / 65536 end
--- Returns the IAS in knots.
function copilot.IAS() return ipc.readUW(0x02BC) / 128 end
--- Returns true if the thrust levers are below the IDLE position.
function copilot.reverseThrustSelected() return ipc.readLvar("VC_PED_TL_1") > 100 and ipc.readLvar("VC_PED_TL_2") > 100 end
--- Returns the altitude in feet referenced to 1013 hPa.
function copilot.ALT() return ipc.readSD(0x3324) end

--- Returns true if the thrust levers in the CLB detent or above.
function copilot.thrustLeversSetForTakeoff()
  local TL_takeoffThreshold = 26
  local TL_reverseThreshold = 100
  local TL1, TL2 = ipc.readLvar("VC_PED_TL_1"), ipc.readLvar("VC_PED_TL_2")
  return TL1 < TL_reverseThreshold and TL1 >= TL_takeoffThreshold and TL2 < TL_reverseThreshold and TL2 >= TL_takeoffThreshold
end

function copilot.eng1N1() return ipc.readDBL(0x2010) end
function copilot.eng2N1() return ipc.readDBL(0x2110) end

--- Returns true if the engines are running.
--- @bool both If true, will return true if both engines are running. If omitted or false, returns true if either engine is running.
function copilot.enginesRunning(both)
  local eng1_running = copilot.eng1N1() > 15
  local eng2_running = copilot.eng2N1() > 15
  if both then return eng1_running and eng2_running end
  return eng1_running or eng2_running
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
  after_landing = "afterLanding" 
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
  copilot.sequences[_name] = function(...)
    func(...)
    old(...)
  end
end

--- Prepends a function to a default sequence
---@string name  Name of the sequence in in options.ini or in the code
---@tparam function func The function to prepend
function copilot.prependSequence(name, func)
  local old = getSequence(name)
  copilot.sequences[name] = function(...)
    old(...)
    func(...)
  end
end

--- Replaces a default sequence
---@string name  Name of the sequence in in options.ini or in the code
---@tparam function func New sequence
function copilot.replaceSequence(name, func)
  copilot.sequences[select(2, getSequence(name))] = func
end

function pairsByKeys (t, f)
  local a = {}
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, f)
  local i = 0      -- iterator variable
  local iter = function ()   -- iterator function
    i = i + 1
    if a[i] == nil then return nil
    else return a[i], t[a[i]]
    end
  end
  return iter
end