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
  ipc.mousemacro(self.rectangle, 3)
  ipc.sleep(100)
  ipc.mousemacro(self.rectangle, 13)
  if FSL.areSequencesEnabled then
    self:interact(plusminus(200))
  end
end

--- <span>
function FcuSwitch:pull()
  if FSL.areSequencesEnabled then
    self:_moveHandHere()
  end
  ipc.mousemacro(self.rectangle, 1)
  ipc.sleep(100)
  ipc.mousemacro(self.rectangle, 11)
  if FSL.areSequencesEnabled then
    self:interact(plusminus(200))
  end
end

return FcuSwitch