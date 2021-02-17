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
  local CG_ind = ipc.readLvar(self.LVar)
  if FSL:getAcType()  == "A320" then
    if CG_ind <= 1800 and CG_ind > 460 then
      CG_ind = CG_ind * 0.0482226 - 58.19543
    else
      CG_ind = CG_ind * 0.1086252 + 28.50924
    end
  elseif FSL:getAcType() == "A319" then
    if CG_ind <= 1800 and CG_ind > 460 then
      CG_ind = CG_ind * 0.04687107 - 53.76288
    else
      CG_ind = CG_ind * 0.09844237 + 30.46262
    end
  elseif FSL:getAcType()  == "A321" then
    if CG_ind <= 1800 and CG_ind > 460 then
      CG_ind = CG_ind * 0.04228 - 48.11
    else
      CG_ind = CG_ind * 0.09516 + 27.97
    end
  end
  return CG_ind
end

function trimwheel:_set(CG, step)
  
  util.sleep(plusminus(1000))

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
        self:_set(CG_ind + 3, 1) 
        util.sleep(plusminus(350,0.2)) 
      end
      ipc.control(self.control.inc)
      util.sleep(time - 5)
    elseif CG < CG_ind then
      if dist > 3.1 then 
        self:_set(CG_ind - 3, 1) 
        util.sleep(plusminus(350,0.2)) 
      end
      ipc.control(self.control.dec)
      util.sleep(time - 5)
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
  if not CG then 
    return
  else 
    CG = tonumber(CG) 
  end

  util.log("Setting the trim. CG: " .. CG, 1)

  if FSL.areSequencesEnabled then

    if not CG_man and prob(0.1) then 
      util.sleep(plusminus(10000, 0.5)) 
    end

    local reachtime = hand:moveTo(self.pos)

    util.log(("Position of the trimwheel: x = %s, y = %s, z = %s"):format(math.floor(self.pos.x), math.floor(self.pos.y), math.floor(self.pos.z)))
    util.log("Trim wheel reached in " .. math.floor(reachtime) .. " ms")
  end

  self:_set(CG)

  return CG

end

return trimwheel