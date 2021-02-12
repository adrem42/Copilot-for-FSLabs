if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

--- All controls that have named positions
--- @type Switch

local Control = require "FSL2Lua.FSL2Lua.Control"

local Switch = setmetatable({}, Control)
Switch.__index = Switch
Switch.__class = "Switch"

function Switch:new(control)
  control.toggle = nil
  control = getmetatable(self):new(control)
  if control.orientation == 2 then -- right click to decrease, left click to increase
    control.incClickType = 3
    control.decClickType = 1
  else -- left click to decrease, right click to increase (most of the switches)
    control.incClickType = 1
    control.decClickType = 3
  end
  control.toggleDir = 1
  control.springLoaded = {}
  if control.posn then
    control.LVarToPosn = {}
    for k, v in pairs(control.posn) do
      if type(v) == "table" then
        v = v[1]
        control.springLoaded[v] = true
        control.posn[k] = v
      end
      control.LVarToPosn[v] = k:upper()
    end
  end
  return setmetatable(control, self)
end

function Switch:_moveInternal(targetPos, twoSwitches)
  local _targetPos, err = self:_getTargetLvarVal(targetPos)
  if not _targetPos then error(err, 2) end
  if FSL.areSequencesEnabled and not twoSwitches then
    self:_moveHandHere()
  end
  local currPos = self:getLvarValue()
  if currPos ~= _targetPos then
    if FSL.areSequencesEnabled and not twoSwitches then
      self:interact(plusminus(100))
    end
    return self:_set(_targetPos, twoSwitches)
  end
end

--- @function __call
--- @usage FSL.GSLD_EFIS_VORADF_1_Switch("VOR")
--- @string targetPos

function Switch:__call(targetPos)
  return self:_moveInternal(targetPos)
end

function Switch:_getTargetLvarVal(targetPos)
  if type(targetPos) ~= "string" then
    return nil, "targetPos must be a string"
  end
  local _targetPos = self.posn[tostring(targetPos):upper()]
  if not _targetPos then
    return nil, "Invalid targetPos: '" .. targetPos .. "'."
  end
  return _targetPos
end

function Switch:_set(targetPos, twoSwitches)
  while true do
    local currPos = self:getLvarValue()
    if currPos < targetPos then
      self:increase()
    elseif currPos > targetPos then
      self:decrease()
    else
      if self.springLoaded[targetPos] then self.letGo = true end
      hideCursor()
      break
    end
    if FSL.areSequencesEnabled then
      local interactionLength = plusminus(self.interactionLength or 100)
      if twoSwitches then
        repeatWithTimeout(interactionLength, coroutine.yield)
        util.log("Interaction with the control took " .. interactionLength .. " ms")
      else
        self:interact(interactionLength)
      end
    end
    if not self:_waitForLvarChange(1000, currPos) then
      self:_handleTimeout(4)
    end
  end
  if FSL.areSequencesEnabled and not twoSwitches then
    self:interact(plusminus(100))
  end
end

--- @treturn string Current position of the switch in uppercase.

function Switch:getPosn()
  return self.LVarToPosn[self:getLvarValue()]
end

function Switch:decrease()
  if self.FSControl then
    ipc.control(self.FSControl.dec)
  elseif self.letGo then
    ipc.mousemacro(self.rectangle, 13)
    ipc.mousemacro(self.rectangle, 11)
    self.letGo = false
  else
    ipc.mousemacro(self.rectangle, self.decClickType)
  end
end

function Switch:increase()
  if self.FSControl then
    ipc.control(self.FSControl.inc)
  elseif self.letGo then
    ipc.mousemacro(self.rectangle, 13)
    ipc.mousemacro(self.rectangle, 11)
    self.letGo = false
  else
    ipc.mousemacro(self.rectangle, self.incClickType)
  end
end

--- Cycles the switch back and forth.
--- @usage FSL.OVHD_EXTLT_Land_L_Switch:toggle()

function Switch:toggle()
  if self.maxLVarVal then
    local pos = self:getLvarValue()
    if pos == self.maxLVarVal then self.toggleDir = -1
    elseif pos == 0 then self.toggleDir = 1 end
    if self.toggleDir == 1 then self:increase()
    else self:decrease() end
  end
  hideCursor()
end

Switch.cycle = Switch.toggle

return Switch