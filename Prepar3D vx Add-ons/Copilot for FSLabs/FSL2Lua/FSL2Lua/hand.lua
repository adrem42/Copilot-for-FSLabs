local util = require "FSL2Lua.FSL2Lua.util"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"
local maf = require "FSL2Lua.libs.maf"

local function think(dist)
  local time = 0
  if dist > 200 and prob(0.3) then
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

local lookup = {}

table.insert(lookup, {0, 300})
table.insert(lookup, {50, 200})
table.insert(lookup, {100, 200})
table.insert(lookup, {200, 250})
table.insert(lookup, {300, 300})
table.insert(lookup, {500, 500})
table.insert(lookup, {1000, 1000})

local function lerp(x)
  for i = 1, #lookup do
    local x0, x1 = lookup[i][1], lookup[i+1][1]
    if (x >= x0 and x < x1) or i == #lookup - 1 then
      local y0, y1 = lookup[i][2], lookup[i+1][2]
      return (y0 * (x1 - x) + y1 * (x - x0)) / (x1 - x0)
    end
  end
end

function hand:getSpeed(dist)
  util.log("Distance: " .. math.floor(dist) .. " mm")
  local speed = plusminus(lerp(dist), 0.1)
  util.log("Speed: " .. math.floor(speed) .. " mm/s")
  return speed / 1000
end

function hand:moveTo(newpos)
  if self.timeOfLastMove and ipc.elapsedtime() - self.timeOfLastMove > 5000 then
    self.pos = self.home
  end
  local dist = (newpos - self.pos):length()
  if self.pos ~= self.home and newpos ~= self.home then 
    if dist > 100 or prob(0.1) then think(dist) end
  end
  if self.pos ~= newpos then
    local startTime = ipc.elapsedtime()
    local now = startTime
    local time = dist / self:getSpeed(dist)
    if time > 100 and copilot.getCallbackStatus and copilot.getCallbackStatus(coroutine.running()) then
      coroutine.yield()
      now = ipc.elapsedtime()
    end
    util.sleep(time - now + startTime)
    self.pos = newpos
    self.timeOfLastMove = now
    return time
  end
  return 0
end

return hand