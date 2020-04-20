--- @submodule copilot

local ipc = ipc
local coroutine = coroutine

--- if both parameters ommited: ipc.sleep(100)
--- if time1 specified: ipc.sleep(time1)
--- if both are specified: ipc.sleep(math.random(time1, time2))
function copilot.sleep(time1,time2)
  local time
  if time1 and time2 then
    time = math.random(time1,time2)
  elseif time1 then
    time = time1
  else
    time = 100
  end
  ipc.sleep(time)
end

--- if both parameters ommited: coroutine.yield()
--- if time1 specified: couroutine.yield() until time1 milliseconds pass
--- if both are specified: couroutine.yield() a random amount of ms between time1 and time2
function copilot.suspend(time1, time2)
  if time1 then
    local endTime
    if time2 then
      endTime = math.random(time1, time2) + ipc.elapsedtime()
    else
      endTime = time1 + ipc.elapsedtime()
    end
    while ipc.elapsedtime() < endTime do
      coroutine.yield()
    end
  else
    coroutine.yield()
  end
end

function copilot.GSX_pushback() return ipc.readLvar("FSLA320_NWS_Pin") == 1 and not ipc.readLvar("FSDT_GSX_DEPARTURE_STATE") == 6 end

--- returns true if you're on the ground
function copilot.onGround() return ipc.readUB(0x0366) == 1 end
--- returns the ground speed in knots
function copilot.GS() return ipc.readUD(0x02B4) / 65536 * 3600 / 1852 end
--- returns the radio altitude in meters
function copilot.radALT() return ipc.readUD(0x31E4) / 65536 end
--- returns the IAS in knots
function copilot.IAS() return ipc.readUW(0x02BC) / 128 end
--- returns true if the thrust levers are below the IDLE positions
function copilot.reverseThrustSelected() return ipc.readLvar("VC_PED_TL_1") > 100 and ipc.readLvar("VC_PED_TL_2") > 100 end
--- returns the altitude in feet referenced to 1013 hPa
function copilot.ALT() return ipc.readSD(0x3324) end

--- returns true if the thrust levers in the CLB detent or above
function copilot.thrustLeversSetForTakeoff()
  local TL_takeoffThreshold = 26
  local TL_reverseThreshold = 100
  local TL1, TL2 = ipc.readLvar("VC_PED_TL_1"), ipc.readLvar("VC_PED_TL_2")
  return TL1 < TL_reverseThreshold and TL1 >= TL_takeoffThreshold and TL2 < TL_reverseThreshold and TL2 >= TL_takeoffThreshold
end

--- returns true if the engines are running
--- @bool both  if true, will return true if both engines are running. If ommited or false, returns true if either engine is running.
function copilot.enginesRunning(both)
  local eng1_N1 = ipc.readDBL(0x2010)
  local eng2_N1 = ipc.readDBL(0x2110)
  local eng1_running = eng1_N1 > 15
  local eng2_running = eng2_N1 > 15
  if both then return eng1_running and eng2_running
  else return eng1_running or eng2_running end
end

function copilot.exit(msg)
  if msg then 
    copilot.logger:error(msg) 
    copilot.logger:error("Exiting...") 
  end
  ipc.exit()
end