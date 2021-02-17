if false then module "FSL2Lua" end

local Switch = require "FSL2Lua.FSL2Lua.Switch"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

--- @type EngineMasterSwitch
local EngineMasterSwitch = setmetatable({}, Switch)
EngineMasterSwitch.__index = EngineMasterSwitch
EngineMasterSwitch.__call = Switch.__call
EngineMasterSwitch.__class = "EngineMasterSwitch"

function EngineMasterSwitch:increase()
  self:macro "rightPress"
  self:_waitForLvarChange()
  if FSL.areSequencesEnabled then
    self:_interact(100)
  end
  self:macro "leftPress"
  self:_waitForLvarChange()
  if FSL.areSequencesEnabled then
    self:_interact(100)
  end
  self:macro "rightRelease"
  self:macro "leftRelease"
  self:_waitForLvarChange()
end

EngineMasterSwitch.decrease = EngineMasterSwitch.increase

function EngineMasterSwitch:_set(targetPos)
  local lvar = self:getLvarValue()
  if lvar == 10 or lvar == 20 then
    self:macro "rightRelease"
    self:macro "leftRelease"
    self:_waitForLvarChange()
  end
  Switch._set(self, targetPos)
end

return EngineMasterSwitch