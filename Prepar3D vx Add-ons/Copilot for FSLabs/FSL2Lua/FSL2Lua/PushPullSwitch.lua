if false then module "FSL2Lua" end

local Control = require "FSL2Lua.FSL2Lua.Control"

local ButtonImpl = setmetatable({}, require "FSL2Lua.FSL2Lua.Button")
ButtonImpl.__index = ButtonImpl

function ButtonImpl:_hasBeenPressed() return self:getLvarValue() == self._targetLvarVal end

function ButtonImpl:push()
  self._targetLvarVal = 10
  self:_pressAndRelease(false, self.clickTypes.leftPress, self.clickTypes.leftRelease) 
end
 
function ButtonImpl:pull()
  self._targetLvarVal = 20
  self:_pressAndRelease(false, self.clickTypes.rightPress, self.clickTypes.rightRelease) 
end

---<span>
--- @type PushPullSwitch
local PushPullSwitch = setmetatable({}, Control)

PushPullSwitch.__index = PushPullSwitch
PushPullSwitch.__class = "PushPullSwitch"

function PushPullSwitch:new(control)
  local button = {}
  for k, v in pairs(control) do button[k] = v end
  control._button = ButtonImpl:new(button)
  control = getmetatable(self):new(control)
  return setmetatable(control, self)
end

--- <span>
function PushPullSwitch:push() self._button:push() end

--- <span>
function PushPullSwitch:pull() self._button:pull() end

return PushPullSwitch