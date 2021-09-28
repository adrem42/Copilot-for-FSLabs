
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

copilot.getTimestamp = ipc.elapsedtime
copilot.__dummy = function() end

function copilot.await(thread) 
  return Event.waitForEvent(copilot.getThreadEvent(thread)) 
end

local keyMappingIniPath = os.getenv("APPDATA") .. "\\Virtuali\\KeyMapping.ini"

local gsxKeyToCopilotKey = {
  Caps_Lock = "CapsLock",
  Escape = "Esc",
  Num_0 = "Ins",
  Num_1 = "End",
  Num_2 = "DownArrow",
  Num_3 = "PageDown",
  Num_4 = "LeftArrow",
  Num_5 = "Clear",
  Num_6 = "RightArrow",
  Num_7 = "Home",
  Num_8 = "UpArrow",
  Num_9 = "PageUp"
}

local function getGsxKeymapping()
  local file = require "FSL2Lua.FSL2Lua.file"
  local iniContent = file.read(keyMappingIniPath)
  local shortcut = iniContent:match("shortcut=(%C*)")
  local keys = {}
  for key in shortcut:gmatch("[^(%+)]+") do
    keys[#keys+1] = key
  end
  keys[#keys] = gsxKeyToCopilotKey[keys[#keys]] or keys[#keys]
  return keys
end

function copilot.toggleGsxMenu()
  local keys = getGsxKeymapping()
  local concat = table.concat(keys, "+")
  if #keys == 1 then
    copilot.sendKeyToFsWindow(concat)
  else
    copilot.keypress(concat)
  end
end

local coxpcall = require "Copilot.libs.coxpcall"

pcall = coxpcall.pcall
xpcall = coxpcall.xpcall
coroutine.running = coxpcall.running

local file = require "FSL2Lua.FSL2Lua.file"

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

local setCallbackTimeout = copilot.setCallbackTimeout
function copilot.setCallbackTimeout(...)
  if setCallbackTimeout(...) then
    coroutine.yield()
  end
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
  repeat 
    coroutine.yield() 
    ipc.sleep(1)
  until copilot.getTimestamp() > timeoutEnd
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
--- Returns the sim CG variable
function copilot.CG() return ipc.readDBL(0x2EF8) * 100 end

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
  local eng1_running = ipc.readDBL(0x2020) > 0 -- fuel flow
  local eng2_running = ipc.readDBL(0x2120) > 0
  if both then return eng1_running and eng2_running end
  return eng1_running or eng2_running
end

function copilot.trimIpcString(offset, length)
  local s = ipc.readSTR(offset, length or 256)
  return s:sub(1, s:find "\0" - 1)
end

copilot.aircraftTitle = copilot.trimIpcString(0x3D00)
local aircraftDir = ipc.readSTR(0x3C00,256):match("(.+\\).+")
local aircraftCfg = file.read(aircraftDir .. "aircraft.cfg")
local textureDir = aircraftCfg:match("texture=(.-)\n", aircraftCfg:find(copilot.aircraftTitle, nil, true))
local fltsimCfgPath = string.format("%s\\Texture.%s\\fltsim.cfg", aircraftDir, textureDir)

--- Reads the fltsim.cfg (the FSLabs airframe config file) and returns it as a string
--- @treturn string The content of the file. An empty string is returned if the file couldn't be read.
function copilot.getFltSimCfg() return file.read(fltsimCfgPath) or "" end