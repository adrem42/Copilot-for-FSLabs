if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"
local atsuLog = require "FSL2Lua.FSL2Lua.atsuLog"
local hand = require "FSL2Lua.FSL2Lua.hand"

local trimwheel = {
  control = {inc = 65607, dec = 65615},
  pos = {y = 500, z = 70},
  LVar = "VC_PED_trim_wheel_ind",
}

function trimwheel:getInd()
  util.sleep(1)
  local lvarVal = ipc.readLvar(self.LVar)
  local cgInd
  if FSL:getAcType() == "A320" then
    if lvarVal <= 1800 and lvarVal > 460 then
      cgInd = lvarVal * 0.0482226 - 58.19543
    else
      cgInd = lvarVal * 0.1086252 + 28.50924
    end
  elseif FSL:getAcType() == "A319" then
    if lvarVal <= 1800 and lvarVal > 460 then
      cgInd = lvarVal * 0.04687107 - 53.76288
    else
      cgInd = lvarVal * 0.09844237 + 30.46262
    end
  elseif FSL:getAcType()  == "A321" then
    if lvarVal <= 1800 and lvarVal > 460 then
      cgInd = lvarVal * 0.04228 - 48.11
    else
      cgInd = lvarVal * 0.09516 + 27.97
    end
  end
  return cgInd
end

function trimwheel:_set(CG, step, sleepFunc)

  sleepFunc = sleepFunc or util.sleep
  
  sleepFunc(plusminus(1000))

  repeat

    local CG_ind = self:getInd()
    local dist = math.abs(CG_ind - CG)

    local speed = plusminus(0.2)
    if step then speed = plusminus(0.07) end

    local time = math.ceil(1000 / (dist / speed))
    if time < 40 then 
      time = 40
    elseif time > 1000 then 
      time = 1000 
    end

    if step and time > 70 then 
      time = 70 
    end

    if CG > CG_ind then
      if dist > 3.1 then 
        self:_set(CG_ind + 3, true, sleepFunc) 
        sleepFunc(plusminus(350,0.2)) 
      end
      ipc.control(self.control.inc)
      sleepFunc(time - 5)
    elseif CG < CG_ind then
      if dist > 3.1 then 
        self:_set(CG_ind - 3, true, sleepFunc) 
        sleepFunc(plusminus(350,0.2)) 
      end
      ipc.control(self.control.dec)
      sleepFunc(time - 5)
    end

    local trimIsSet = math.abs(CG - CG_ind) <= (step and 0.5 or 0.2)

  until trimIsSet
end

function trimwheel:set(CG)

  local CG_man
  if CG then 
    CG_man = true 
  else 
    CG = atsuLog:getMACTOW() or ipc.readDBL(0x2EF8) * 100
  end

  if not CG then return
  else CG = tonumber(CG) end

  util.log("Setting the trim. CG: " .. CG, true)

  local sleepFunc = util.sleep

  if copilot.getCallbackStatus and copilot.getCallbackStatus(coroutine.running()) then
    sleepFunc = copilot.suspend
  end

  if FSL.areSequencesEnabled then

    if not CG_man and prob(0.1) then 
      sleepFunc(plusminus(10000, 0.5)) 
    end
    local reachtime = hand:moveTo(self.pos)
    util.log(
      ("Position of the trimwheel: x = %s, y = %s, z = %s")
        :format(math.floor(self.pos.x), math.floor(self.pos.y), math.floor(self.pos.z))
    )
    util.log("Trim wheel reached in " .. math.floor(reachtime) .. " ms")
  end

  self:_set(CG, nil, sleepFunc)

  return CG
end

return trimwheel