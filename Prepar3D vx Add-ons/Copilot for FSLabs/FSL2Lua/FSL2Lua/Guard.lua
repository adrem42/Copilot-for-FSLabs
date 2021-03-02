if false then module "FSL2Lua" end

local Control = require "FSL2Lua.FSL2Lua.Control"

--- @type Guard

local Guard = setmetatable({}, Control)
Guard.__index = Guard
Guard.__class = "Guard"

--- <span>
function Guard:open()
  self:_moveHandHere()
  if not self:isOpen() then
    local endInteract = self:_startInteract(plusminus(1000))
    self:macro "rightPress"
    checkWithTimeout(5000, self.isOpen, self)
    endInteract()
  end
end

--- Alias for `open`.
--- @function lift
Guard.lift = Guard.open

--- <span>
function Guard:close()
  self:_moveHandHere()
  if self:isOpen() then self:macro(self.toggle and "rightPress" or "rightRelease") end
  self:_startInteract(plusminus(500))()
end

--- @treturn bool
function Guard:isOpen() return self:getLvarValue() == 10 end

return Guard