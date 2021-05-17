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
  self:macro(pressClickType)
  self:macro(releaseClickType)
end

--- Sets the toggle state of the button
---@param state Truthy for 'down', falsy for 'up'
function ToggleButton:setToggleState(state)
  state = state and true or false
  local function success() return self:isDown() == state end
  if success() then return end
  for _ = 1, 5 do
    self()
    if checkWithTimeout(1000, success) then return end
  end
end

--- Calls `setToggleState`(true)
function ToggleButton:toggleDown() self:setToggleState(true) end

--- Calls `setToggleState`(false)
function ToggleButton:toggleUp() self:setToggleState(false) end

return ToggleButton