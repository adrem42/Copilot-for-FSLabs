if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"
local Switch = require "FSL2Lua.FSL2Lua.Switch"

---Knobs with no fixed positions
--@type RotaryKnob
local RotaryKnob = setmetatable({}, Switch)

RotaryKnob.__index = RotaryKnob
RotaryKnob.__class = "RotaryKnob"

function RotaryKnob:new(control)
  if not control.range then error("wtf " .. control.LVar) end
  return setmetatable(Switch:new(control), self)
end

--- @function __call
--- @number targetPos Relative position from 0-100.
--- @usage FSL.OVHD_INTLT_Integ_Lt_Knob(42)
RotaryKnob.__call = getmetatable(RotaryKnob).__call

function RotaryKnob:_rotateLeft()   self:macro "wheelDown" end
function RotaryKnob:_rotateRight()  self:macro "wheelUp" end

--- Rotates the knob left by 1 tick.
function RotaryKnob:rotateLeft()
  self:_rotateLeft()
  hideCursor() 
end

--- Rotates the knob right by 1 tick.
function RotaryKnob:rotateRight()
  self:_rotateRight()
  hideCursor()
end

function RotaryKnob:_getTargetLvarVal(targetPos)
  if type(targetPos) ~= "number" then 
    return nil, ("The position for control '%s' must be a number"):format(self.name)
  end
  if targetPos > 100 then targetPos = 100
  elseif targetPos < 0 then targetPos = 0 end
  return self.range / 100 * targetPos
end

function RotaryKnob:_set(targetPos)
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
        self:_rotateRight()
        wasLower = true
      elseif currPos > targetPos then
        if wasLower then break end
        self:_rotateLeft()
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

--- This function is made for keyboard and joystick bindings.
--- It divides the knob in n steps and cycles back and forth between them.
--- @usage
--- Bind {key = "A", onPress = {FSL.OVHD_INTLT_Integ_Lt_Knob, "cycle", 5}}
--- @int steps In how many steps to divide the knob.
function RotaryKnob:cycle(steps)
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
function RotaryKnob:getPosn()
  local val = self:getLvarValue()
  return (val / self.range) * 100
end

--- Rotates the knob by amount of ticks.
--- @number ticks positive to rotate right, negative to rotate left
--- @number[opt=70] pause milliseconds to sleep between each tick
function RotaryKnob:rotateBy(ticks, pause)
  pause = pause or 70
  if FSL.areSequencesEnabled then
    self:_moveHandHere()
    self:_interact(300)
  end
  local startTime = ipc.elapsedtime()
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
  if FSL.areSequencesEnabled then
    util.log("Interaction with the control took " .. (ipc.elapsedtime() - startTime) .. " ms")
  end
  hideCursor()
end

--- Sets the knob to random position between lower and upper.
--- @number[opt=0] lower
--- @number[opt=100] upper
function RotaryKnob:random(lower, upper)
  self(math.random(lower or 0, upper or 100))
end

return RotaryKnob