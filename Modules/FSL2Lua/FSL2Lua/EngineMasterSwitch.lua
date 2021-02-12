if false then module "FSL2Lua" end

local Switch = require "FSL2Lua.FSL2Lua.Switch"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

--- @type EngineMasterSwitch
local EngineMasterSwitch = setmetatable({}, Switch)
EngineMasterSwitch.__index = EngineMasterSwitch
EngineMasterSwitch.__call = Switch.__call
EngineMasterSwitch.__class = "EngineMasterSwitch"

function EngineMasterSwitch:increase()
  ipc.mousemacro(self.rectangle, 1)
  self:_waitForLvarChange()
  if FSL.areSequencesEnabled then
    self:interact(100)
  end
  ipc.mousemacro(self.rectangle, 3)
  self:_waitForLvarChange()
  if FSL.areSequencesEnabled then
    self:interact(100)
  end
  ipc.mousemacro(self.rectangle, 11)
  ipc.mousemacro(self.rectangle, 13)
  self:_waitForLvarChange()
end

EngineMasterSwitch.decrease = EngineMasterSwitch.increase

function EngineMasterSwitch:_set(targetPos)
  local lvarVal = self:getLvarValue()
  if lvarVal == 10 or lvarVal == 20 then
    ipc.mousemacro(self.rectangle, 11)
    ipc.mousemacro(self.rectangle, 13)
    self:_waitForLvarChange()
  end
  Switch.set(self, targetPos)
end

return EngineMasterSwitch