if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"
local Positionable = require "FSL2Lua.FSL2Lua.Positionable"

---<span>
--@type RotaryKnob
local RotaryKnob = setmetatable({}, Positionable)

RotaryKnob.__index = RotaryKnob
RotaryKnob.__class = "RotaryKnob"

function RotaryKnob:new(control)
  control = Positionable:new(control)
  util.assert(type(control.range) == "number", "Failed to create control: " .. control.name or control.LVar)
  return setmetatable(control, self)
end

--- @function __call
--- @number targetPos Relative position from 0-100.
--- @usage FSL.OVHD_INTLT_Integ_Lt_Knob(42)
RotaryKnob.__call = Positionable.__call

function RotaryKnob:_rotateLeft() self:macro "wheelDown" end
function RotaryKnob:_rotateRight() self:macro "wheelUp" end

--- Rotates the knob left by 1 tick.
function RotaryKnob:rotateLeft() self:_rotateLeft() hideCursor() end

--- Rotates the knob right by 1 tick.
function RotaryKnob:rotateRight() self:_rotateRight() hideCursor() end

function RotaryKnob:_getTargetLvarVal(targetPos)
  if type(targetPos) ~= "number" then 
    return nil, ("The position for control '%s' must be a number"):format(self.name)
  end
  if targetPos > 100 then targetPos = 100
  elseif targetPos < 0 then targetPos = 0 end
  return self.range / 100 * targetPos
end

function RotaryKnob:_setPositionToLvar(targetPos, initPos)
  
  local wasLower, wasGreater
  local tick = 1
  local currPos = initPos or self:getLvarValue()
  if self.prevTargetPos and currPos == self.prevPos then
    if targetPos >= self.prevTargetPos and self.wasLower then
      wasLower = self.wasLower
    elseif targetPos < self.prevTargetPos and self.wasGreater then
      wasGreater = self.wasGreater
    end
  end

  local endInteract = self:_startInteract()

  while true do
    if currPos < targetPos then
      if wasGreater then break end
      self:_rotateRight()
      wasLower = true
    elseif currPos > targetPos then
      if wasLower then break end
      self:_rotateLeft()
      wasGreater = true
    else break end
    if not self:_waitForLvarChange(1000, currPos) then return self:_handleTimeout(4) end
    if FSL.areSequencesEnabled and tick % 2 == 0 then util.sleep(1) end
    tick = tick + 1
    currPos = self:getLvarValue()
  end

  self.prevPos = currPos
  self.prevTargetPos = targetPos
  self.wasLower = wasLower
  self.wasGreater = wasGreater
  hideCursor()
  endInteract()
  return currPos / self.range * 100
end

--- @treturn number Relative position from 0-100.
function RotaryKnob:getPosn()
  local val = self:getLvarValue()
  return (val / self.range) * 100
end

--- Rotates the knob by amount of ticks.
--- @number ticks positive to rotate right, negative to rotate left
--- @number[opt=70] pause milliseconds to sleep between each tick
function RotaryKnob:rotateBy(ticks, pause)
  pause = FSL.areSequencesEnabled and 70 or (pause or 70)
  self:_moveHandHere()
  self:_startInteract(300)()
  local endInteract = self:_startInteract()
  if ticks > 0 then
    for _ = 1, ticks do
      self:_rotateRight()
      if pause > 0 then
        util.sleep(plusminus(pause))
      end
    end
  elseif ticks < 0 then
    for _ = 1, -ticks do
      self:_rotateLeft()
      if pause > 0 then
        util.sleep(plusminus(pause))
      end
    end
  end
  endInteract()
  hideCursor()
end

--- Sets the knob to random position between lower and upper.
--- @number[opt=0] lower
--- @number[opt=100] upper
function RotaryKnob:random(lower, upper) self(math.random(lower or 0, upper or 100)) end

return RotaryKnob