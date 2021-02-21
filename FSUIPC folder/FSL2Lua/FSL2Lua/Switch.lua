if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

--- All controls that have named positions
--- @type Switch

local Positionable = require "FSL2Lua.FSL2Lua.Positionable"

local Switch = setmetatable({}, Positionable)
Switch.__index = Switch
Switch.__class = "Switch"

function Switch:new(control)

  control = Positionable:new(control)

  control.toggle = nil

  if control.reversedOrientation == true then
    control.incClickType = self.clickTypes.leftPress
    control.decClickType = self.clickTypes.rightPress
  else
    control.incClickType = self.clickTypes.rightPress
    control.decClickType = self.clickTypes.leftPress
  end

  util.assert(type(control.posn) == "table", "Failed to create control " .. control.name or control.LVar)

  control.maxLVarVal = 0
  control.LVarToPosn = {}
  control.springLoaded = {}

  local temp = control.posn
  control.posn = {}
  for posName, lvarVal in pairs(temp) do

    posName = posName:upper()

    local isSpringLoaded = type(lvarVal) == "table"
    if isSpringLoaded then
      lvarVal = lvarVal[1] 
      control.springLoaded[lvarVal] = true
    end

    control.posn[posName] = lvarVal
    control.LVarToPosn[lvarVal] = posName
    control.maxLVarVal = math.max(control.maxLVarVal, lvarVal)
  end

  control = setmetatable(control, self)

  control._cycler = Bind.cycleSwitch(control)

  return control
end

--- Moves the switch to the given position.
--- @function __call 
--- @usage FSL.GSLD_EFIS_VORADF_1_Switch "VOR"
--- @string targetPos A valid position for this switch. 
--- You can find the list of positions for a given switch in @{listofcontrols.md|the list of controls}.
Switch.__call = Positionable.__call

function Switch:_getTargetLvarVal(targetPos)
  if targetPos == nil then
    return nil, ("A position must be specified for control '%s'"):format(self.name)
  elseif type(targetPos) ~= "string" then
    return nil, ("The position for control '%s' must be a string"):format(self.name)
  end
  local _targetPos = self.posn[tostring(targetPos):upper()]
  if not _targetPos then
    return nil, ("Invalid position for control '%s': '%s'"):format(self.name, targetPos)
  end
  return _targetPos
end

function Switch:_setPositionToLvar(targetPos, initPos, twoSwitches)
  
  local currPos = initPos or self:getLvarValue()
  while true do
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
        self:_interact(interactionLength)
      end
    end
    if not self:_waitForLvarChange(1000, currPos) then
      self:_handleTimeout(4)
    end
    currPos = self:getLvarValue()
  end
  if FSL.areSequencesEnabled and not twoSwitches then
    self:_interact(plusminus(100))
  end
end

--- @treturn string Current position of the switch in uppercase.
function Switch:getPosn() return self.LVarToPosn[self:getLvarValue()] end

function Switch:decrease()
  if self.FSControl then
    ipc.control(self.FSControl.dec)
  elseif self.letGo then
    self:macro "leftRelease"
    self:macro "rightRelease"
    self.letGo = false
  else
    self:_macro(self.decClickType)
  end
end

function Switch:increase()
  if self.FSControl then
    ipc.control(self.FSControl.inc)
  elseif self.letGo then
    self:macro "leftRelease"
    self:macro "rightRelease"
    self.letGo = false
  else
    self:_macro(self.incClickType)
  end
end

-- Switch.cycle = util._wrapDeprecated("Switch.cycle", "Bind.cycleSwitch", function(self)
--   self._cycler = self._cycler or Bind.cycleSwitch(self)
--   self._cycler()
-- end)

function Switch:cycle() self._cycler() end

Switch.toggle = Switch.cycle

return Switch