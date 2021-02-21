
local Control = require "FSL2Lua.FSL2Lua.Control"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

local Positionable = setmetatable({}, Control)
Positionable.__index = Positionable

function Positionable:_setPosition(targetPos, twoSwitches)
  local targetLvar, err = self:_getTargetLvarVal(targetPos)
  if not targetLvar then error(err, 3) end
  if FSL.areSequencesEnabled and not twoSwitches then
    self:_moveHandHere()
  end
  local currLvar = self:getLvarValue()
  if currLvar ~= targetLvar then
    if FSL.areSequencesEnabled and not twoSwitches then
      self:_interact(plusminus(100))
    end
    self:_setPositionToLvar(targetLvar, currLvar, twoSwitches)
  end
end

function Positionable:__call(targetPos) self:_setPosition(targetPos) end

return Positionable