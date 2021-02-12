if false then module "FSL2Lua" end

local Control = require "FSL2Lua.FSL2Lua.Control"
local util = require "FSL2Lua.FSL2Lua.util"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

--- @type Button
local Button = setmetatable({}, Control)
Button.__index = Button
Button.__class = "Button"

function Button:new(control)
  control = getmetatable(self):new(control)
  if control.LVar and control.LVar:find("MCDU") then control.interactionLength = 50 end
  self.__index = self
  return setmetatable(control, self)
end

function Button:_pressAndReleaseInternal(twoSwitches, pressClickType, releaseClickType)
  pressClickType = pressClickType or 3
  releaseClickType = releaseClickType or 13
  if FSL.areSequencesEnabled and not twoSwitches then
    self:_moveHandHere()
  end
  local startTime = ipc.elapsedtime()
  local sleepAfterPress
  local LVarbefore = self:getLvarValue()
  ipc.mousemacro(self.rectangle, pressClickType)
  if self.toggle then
    sleepAfterPress = 0
    ipc.mousemacro(self.rectangle, releaseClickType)
  else
    local FPS = util.frameRate()
    sleepAfterPress = FPS > 30 and 100 or FPS > 20 and 150 or 200
    local timeout = 1000
    if twoSwitches then
      checkWithTimeout(timeout, function()
        coroutine.yield()
        return self:getLvarValue() ~= LVarbefore
      end)
      repeatWithTimeout(sleepAfterPress, coroutine.yield)
    else
      checkWithTimeout(timeout, function()
        return self:getLvarValue() ~= LVarbefore
      end)
      util.sleep(sleepAfterPress)
    end
    ipc.mousemacro(self.rectangle, releaseClickType)
  end
  if FSL.areSequencesEnabled then
    local interactionLength = plusminus(self.interactionLength or 150) - ipc.elapsedtime() + startTime
    if twoSwitches then
      repeatWithTimeout(interactionLength, coroutine.yield)
    else
      util.sleep(interactionLength)
    end
    util.log("Interaction with the control took " .. interactionLength .. " ms")
  end
end

--- Presses the button.
--- @function __call
--- @usage FSL.OVHD_ELEC_BAT_1_Button()
function Button:__call()
  return self:_pressAndReleaseInternal()
end

--- Simulates a click of the right mouse button on the VC button.
function Button:rightClick() 
  return self:_pressAndReleaseInternal(false, 1, 11) 
end

--- @treturn bool True if the button is depressed.
function Button:isDown() return self:getLvarValue() == 10 end

return Button