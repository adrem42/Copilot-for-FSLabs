local util = require "FSL2Lua.FSL2Lua.util"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"
local maf = require "FSL2Lua.libs.maf"

local function think(dist)
  local time = 0
  if dist > 200 and prob(0.2) then
    time = time + plusminus(300)
  end
  if prob(0.2) then time = time + plusminus(300) end
  if prob(0.05) then time = time + plusminus(1000) end
  if time > 0 then
    util.log("Thinking for " .. time .. " ms. Hmmm...")
    util.sleep(time)
  end
end

local hand = {}

function hand:init()
  if FSL:getPilot() == 1 then self.home = maf.vector(-70,420,70)
  elseif FSL:getPilot() == 2 then self.home = maf.vector(590,420,70) end
  self.pos = self.home
  self.timeOfLastMove = ipc.elapsedtime()
end

function hand:getSpeed(dist)
  util.log("Distance: " .. math.floor(dist) .. " mm")
  if dist < 80 then dist = 80 end
  local speed = 5.54785 + (-218.97685 / (1 + (dist / (3.62192 * 10^-19))^0.0786721))
  speed = plusminus(speed, 0.1) * 0.8
  util.log("Speed: " .. math.floor(speed * 1000) .. " mm/s")
  return speed
end

function hand:moveTo(newpos)
  if self.timeOfLastMove and ipc.elapsedtime() - self.timeOfLastMove > 5000 then
    self.pos = self.home
  end
  local dist = (newpos - self.pos):length()
  if self.pos ~= self.home and newpos ~= self.home and dist > 50 then 
    think(dist) 
  end
  local time
  local startTime = ipc.elapsedtime()
  if self.pos ~= newpos then
    time = dist / self:getSpeed(dist)
    if coroutine.running() and time > 100 then
      coroutine.yield()
    end
    util.sleep(time - (ipc.elapsedtime() - startTime))
    self.pos = newpos
    self.timeOfLastMove = ipc.elapsedtime()
  end
  return time or 0
end

return hand