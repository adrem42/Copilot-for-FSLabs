if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"
local Switch = require "FSL2Lua.FSL2Lua.Switch"

---Knobs with no fixed positions
--@type KnobWithoutPositions

local KnobWithoutPositions = setmetatable({}, Switch)
KnobWithoutPositions.__index = KnobWithoutPositions
KnobWithoutPositions.__class = "KnobWithoutPositions"

--- @function __call
--- @number targetPos Relative position from 0-100.
--- @usage FSL.OVHD_INTLT_Integ_Lt_Knob(42)
KnobWithoutPositions.__call = getmetatable(KnobWithoutPositions).__call

function KnobWithoutPositions:_rotateLeftInternal()
  ipc.mousemacro(self.rectangle, 15)
end

function KnobWithoutPositions:_rotateRightInternal()
  ipc.mousemacro(self.rectangle, 14)
end

--- Rotates the knob left by 1 tick.
function KnobWithoutPositions:rotateLeft()
  self:_rotateLeftInternal()
  hideCursor() 
end

--- Rotates the knob right by 1 tick.
function KnobWithoutPositions:rotateRight()
  self:_rotateRightInternal()
  hideCursor()
end

function KnobWithoutPositions:_getTargetLvarVal(targetPos)
  if type(targetPos) ~= "number" then 
    return nil, "targetPos must be a number"
  end
  if targetPos > 100 then targetPos = 100
  elseif targetPos < 0 then targetPos = 0 end
  return self.range / 100 * targetPos
end

function KnobWithoutPositions:_set(targetPos)
  local timeStarted = ipc.elapsedtime()
  --local tolerance = (targetPos == 0 or targetPos == self.range) and 0 or 5
  local tolerance = 0
  local wasLower, wasGreater
  local tick = 1
  local currPos = self:getLvarValue()
  if self.prevTargetPos and currPos == self.prevPos then
    if targetPos >= self.prevTargetPos and self.wasLower then
      wasLower = self.wasLower
    elseif targetPos < self.prevTargetPos and self.wasGreater then
      wasGreater = self.wasGreater
    end
  end
  while true do
    if math.abs(currPos - targetPos) > tolerance then
      if currPos < targetPos then
        if wasGreater then break end
        self:_rotateRightInternal()
        wasLower = true
      elseif currPos > targetPos then
        if wasLower then break end
        self:_rotateLeftInternal()
        wasGreater = true
      end
      if not self:_waitForLvarChange(1000, currPos, 3) then
        self:_handleTimeout(4)
        return
      end
    else
      break
    end
    if FSL.areSequencesEnabled and tick % 2 == 0 then
      util.sleep(1)
    end
    tick = tick + 1
    currPos = self:getLvarValue()
  end
  self.prevPos = currPos
  self.prevTargetPos = targetPos
  self.wasLower = wasLower
  self.wasGreater = wasGreater
  hideCursor()
  if FSL.areSequencesEnabled then 
    util.log("Interaction with the control took " .. ipc.elapsedtime() - timeStarted .. " ms") 
  end
  return currPos / self.range * 100
end

function KnobWithoutPositions:cycle(steps)
  steps = math.floor(steps)
  local step = 100 / steps
  local cycleVal = self.cycleVal or 0
  local curr = self:getPosn()
  if curr ~= self.prev then
    cycleVal = curr
  end
  if cycleVal == 100 then 
    self.cycleDir = false
  elseif cycleVal == 0 then 
    self.cycleDir = true 
  end
  if self.cycleDir then
    cycleVal = math.min(cycleVal + step, 100)
  else
    cycleVal = math.max(cycleVal - step, 0)
  end
  cycleVal = cycleVal - cycleVal % step
  self.prev = self(cycleVal) or self.prev
  self.cycleVal = cycleVal
end

--- @treturn number Relative position from 0-100.

function KnobWithoutPositions:getPosn()
  local val = self:getLvarValue()
  return (val / self.range) * 100
end

--- Rotates the knob by amount of ticks.
--- @number ticks positive to rotate right, negative to rotate left
--- @number[opt=70] pause milliseconds to sleep between each tick

function KnobWithoutPositions:rotateBy(ticks, pause)
  pause = pause or 70
  if FSL.areSequencesEnabled then
    self:_moveHandHere()
    self:interact(300)
  end
  local startTime = ipc.elapsedtime()
  if ticks > 0 then
    for _ = 1, ticks do
      self:_rotateRightInternal()
      if pause > 0 then
        util.sleep(plusminus(pause))
      end
    end
  elseif ticks < 0 then
    for _ = 1, -ticks do
      self:_rotateLeftInternal()
      if pause > 0 then
        util.sleep(plusminus(pause))
      end
    end
  end
  if FSL.areSequencesEnabled then
    util.log("Interaction with the control took " .. (ipc.elapsedtime() - startTime) .. " ms")
  end
  hideCursor()
end

--- Sets the knob to random position between lower and upper.
--- @number[opt=0] lower
--- @number[opt=100] upper

function KnobWithoutPositions:random(lower, upper)
  self(math.random(lower or 0, upper or 100))
end

return KnobWithoutPositions