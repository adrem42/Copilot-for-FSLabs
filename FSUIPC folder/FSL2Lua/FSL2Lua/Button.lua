if false then module "FSL2Lua" end

local Control = require "FSL2Lua.FSL2Lua.Control"
local util = require "FSL2Lua.FSL2Lua.util"

--- @type Button
local Button = setmetatable({
  interactionLength = 250,
  sleepMult = 1
}, Control)
Button.__index = Button
Button.__class = "Button"

--- The <a href="#Class_Guard">guard</a> of this button or nil if it doesn't have one.
Button.guard = nil

function Button:new(control)
  control = getmetatable(self):new(control)
  if control.name:find "MCDU" then control.interactionLength = 100 end
  return setmetatable(control, self)
end

function Button:_pressAndRelease(twoSwitches, pressClickType, releaseClickType)
  
  pressClickType = pressClickType or self.clickTypes.leftPress
  releaseClickType = releaseClickType or self.clickTypes.leftRelease

  if not twoSwitches then self:_moveHandHere() end

  local endInteract = self:_startInteract(self.interactionLength, twoSwitches)
  self:__pressAndRelease(twoSwitches, pressClickType, releaseClickType)
  endInteract()
end

function Button:_hasBeenPressed() return self:isDown() end

function Button:__pressAndRelease(twoSwitches, pressClickType, releaseClickType)
  self:_macro(pressClickType)
  -- For the press to register, the button needs to be held down
  -- for a certain amount of time that depends on the framerate.
  local FPS = util.frameRate()
  local sleepAfterPress = (FPS > 30 and 100 or FPS > 20 and 150 or 200) * Button.sleepMult
  local timeout = 1000
  if twoSwitches then
    checkWithTimeout(timeout, function()
      coroutine.yield()
      return self:_hasBeenPressed()
    end)
    repeatWithTimeout(sleepAfterPress, coroutine.yield)
  else
    checkWithTimeout(timeout, self._hasBeenPressed, self)
    util.sleep(sleepAfterPress)
  end
  self:_macro(releaseClickType)
end

--- Presses the button.
--- @function __call
--- @usage FSL.OVHD_ELEC_BAT_1_Button()
function Button:__call() self:_pressAndRelease() end

--- Simulates a click of the right mouse button on this button.
--- This function was written because I know that the PA button on the ACP 
--- has a special function if you click on it with the right mouse button. 
--- I don't think it's useful for anything else.
function Button:rightClick() 
  self:_pressAndRelease(false, self.clickTypes.rightPress, self.clickTypes.rightRelease) 
end

--- @treturn bool True if the button is depressed.
function Button:isDown() return self:getLvarValue() == 10 end

--- Presses the button if its light's current state doesn't match the passed 'state' parameter.
---@param state Truthy for 'the light should be on', falsy for 'the light should be off'.
function Button:pressForLightState(state)
  state = state and true or false
  local function success() return self:isLit() == state end
  if success() then return end
  for _ = 1, 5 do
    self()
    if checkWithTimeout(1000, success) then return end
  end
end

--- <span>
function Button:pressIfLit() self:pressForLightState(false) end

--- <span>
function Button:pressIfNotLit() self:pressForLightState(true) end

return Button