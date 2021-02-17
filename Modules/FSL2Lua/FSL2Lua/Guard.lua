if false then module "FSL2Lua" end

local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"
local Control = require "FSL2Lua.FSL2Lua.Control"

--- @type Guard

local Guard = setmetatable({}, Control)
Guard.__index = Guard
Guard.__class = "Guard"

--- <span>
function Guard:open()
  if FSL.areSequencesEnabled then
    self:_moveHandHere()
  end
  if not self:isOpen() then
    self:macro "rightPress"
    checkWithTimeout(5000, function() return self:isOpen() end)
  end
  if FSL.areSequencesEnabled then
    self:_interact(plusminus(1000))
  end
end

--- Alias for `open`.
--- @function lift
Guard.lift = Guard.open

--- <span>
function Guard:close()
  if FSL.areSequencesEnabled then
    self:_moveHandHere()
  end
  if self:isOpen() then
    self:macro(self.toggle and "rightPress" or "rightRelease")
  end
  if FSL.areSequencesEnabled then
    self:_interact(plusminus(500))
  end
end

--- @treturn bool
function Guard:isOpen() return self:getLvarValue() == 10 end

return Guard