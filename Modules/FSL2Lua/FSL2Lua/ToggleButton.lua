if false then module "FSL2Lua" end

local Button = require "FSL2Lua.FSL2Lua.Button"

--- Buttons that toggle between their 'up' and 'down' positions, such as most of the overhead buttons.
--
--- Subclass of <a href="#Class_Button">Button</a>
--- @type ToggleButton
local ToggleButton = setmetatable({}, Button)
ToggleButton.__index = ToggleButton
ToggleButton.__call = Button.__call
ToggleButton.__class = "ToggleButton"

function ToggleButton:__pressAndRelease(_, pressClickType, releaseClickType)
  self:_macro(pressClickType)
  self:_macro(releaseClickType)
end

--- Sets the toggle state of the button
---@param state Truthy for 'down', falsy for 'up'
function ToggleButton:setToggleState(state)
  state = state and true or false
  if self:isDown() == state then return end
  for _ = 1, 5 do
    self()
    local ok = checkWithTimeout(1000, function()
      return self:isDown() == state
    end)
    if ok then return end
  end
end

--- Calls `setToggleState`(true)
function ToggleButton:toggleDown() return self:setToggleState(true) end

--- Calls `setToggleState`(false)
function ToggleButton:toggleUp() return self:setToggleState(false) end

return ToggleButton