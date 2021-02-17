if false then module "FSL2Lua" end

local Control = require "FSL2Lua.FSL2Lua.Control"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

--- Switches that can be pushed and pulled
--- @type FcuSwitch
local FcuSwitch = setmetatable({}, Control)

FcuSwitch.__index = FcuSwitch
FcuSwitch.__class = "FcuSwitch"

--- <span>
function FcuSwitch:push()
  if FSL.areSequencesEnabled then
    self:_moveHandHere()
  end
  self:macro "leftPress"
  ipc.sleep(100)
  self:macro "leftRelease"
  if FSL.areSequencesEnabled then
    self:_interact(plusminus(200))
  end
end

--- <span>
function FcuSwitch:pull()
  if FSL.areSequencesEnabled then
    self:_moveHandHere()
  end
  self:macro "rightPress"
  ipc.sleep(100)
  self:macro "rightRelease"
  if FSL.areSequencesEnabled then
    self:_interact(plusminus(200))
  end
end

return FcuSwitch