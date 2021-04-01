if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"
local hand = require "FSL2Lua.FSL2Lua.hand"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

--- Abstract control
--- @type Control

local Control = {}
Control.__index = Control

local timeoutMsg = "\nControl %s isn't responding to mouse macro commands\r\n"

Control.clickTypes = {
  leftPress = 3,
  leftRelease = 13,
  rightPress = 1,
  rightRelease = 11,
  wheelUp = 14,
  wheelDown = 15
}

function Control:new(control)
  control = control or {}
  control._baseCtorCalled = true
  if control.rectangle then
    control.rectangle = tonumber(control.rectangle)
  end
  if not FSL2LUA_STANDALONE and control[FSL:getAcType()].manual then
    control.getLvarValue = self._getLvarValueErr
  end
  return setmetatable(control, self)
end

--- Invokes the mouse macro with the given click type on the control's mouse rectangle.
--- @string clickType One of the following:
--
-- * 'leftPress'
-- * 'leftRelease'
-- * 'rightPress'
-- * 'rightRelease'
-- * 'wheelUp'
-- * 'wheelDown'
function Control:macro(clickType)
  self:_macro(
    Control.clickTypes[clickType] 
      or error("'" .. clickType .. "' is not a valid click type.", 2)
  )
end

function Control:_macro(clickType) 
  ipc.mousemacro(self.rectangle, clickType)
end

function Control:_moveHandHere()
  if not FSL.areSequencesEnabled then return end
  local reachtime = hand:moveTo(self.pos)
  util.log(
    ("Position of control %s : x = %s, y = %s, z = %s")
      :format(self.name , math.floor(self.pos.x), math.floor(self.pos.y), math.floor(self.pos.z)),
    true
  )
  util.log("Control reached in " .. math.floor(reachtime) .. " ms")
end

local function noop() end

function Control:_startInteract(length, yield)

  if not FSL.areSequencesEnabled then return noop end

  local start = ipc.elapsedtime()

  return function()
    local elapsed = ipc.elapsedtime() - start
    length = length or elapsed
    if elapsed < length then
      local rest = length - elapsed
      if yield then repeatWithTimeout(rest, coroutine.yield)
      else util.sleep(rest) end
    end
    util.log("Interaction with the control took " .. math.max(length, elapsed) .. " ms")
  end
end

function Control:_handleTimeout(level) util.handleError(timeoutMsg:format(self.name), level + 1) end

--- Checks if the control's light is on.
--- @usage if not FSL.GSLD_EFIS_CSTR_Button:isLit() then
---   FSL.GSLD_EFIS_CSTR_Button()
--- end
--- @treturn bool True if the control has a light and it's on.
--
--- The control needs to have an Lvar associated with its light - otherwise, this function throws an error!
--
--- Unfortunately, overhead-style square buttons don't have such Lvars.
function Control:isLit()
  if not self.Lt then 
    error("This control has no light Lvar associated with it", 2)
  end
  if type(self.Lt) == "string" then return ipc.readLvar(self.Lt) == 1 end
  return ipc.readLvar(self.Lt.Brt) == 1 or ipc.readLvar(self.Lt.Dim) == 1
end

--- @treturn int
function Control:getLvarValue() return ipc.readLvar(self.LVar) end

function Control:_getLvarValueErr()
  error("The Lvar of control " .. self.name .. " is inoperable: you can't call functions that need to read the Lvar.")
end

function Control:_waitForLvarChange(timeout, initPos)
  initPos = initPos or self:getLvarValue()
  return checkWithTimeout(timeout or 5000, function()
    return self:getLvarValue() ~= initPos 
  end)
end

return Control