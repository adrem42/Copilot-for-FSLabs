if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"

--- Abstract control
--- @type Control

local Control = {
  clickTypes = {
    leftPress = 3,
    leftRelease = 13,
    rightPress = 1,
    rightRelease = 11,
    wheelUp = 14,
    wheelDown = 15
  },
  FSL_VC_control = true
}
Control.__index = Control

function Control:new(control)
  control = control or {}
  if control.rectangle then
    control.rectangle = tonumber(control.rectangle)
  end
  if not FSL2LUA_STANDALONE then
    if control[util.macroAcType].manual and not FSL2LUA_IGNORE_FAULTY_LVARS then
      control.getLvarValue = self._getLvarValueErr
    end
  end
  return setmetatable(control, self)
end

--- Invokes the mouse macro of the control
--- @string clickType One of the following:
--
-- * 'leftPress'
-- * 'leftRelease'
-- * 'rightPress'
-- * 'rightRelease'
-- * 'wheelUp'
-- * 'wheelDown'
function Control:macro(clickType)
  ipc.mousemacro(self.rectangle, self.clickTypes[clickType])
end

function Control:_moveHandHere()
  local reachtime = hand:moveTo(self.pos)
  util.log(("Position of control %s : x = %s, y = %s, z = %s"):format(self.name , math.floor(self.pos.x), math.floor(self.pos.y), math.floor(self.pos.z)), 1)
  util.log("Control reached in " .. math.floor(reachtime) .. " ms")
end

function Control:_interact(time)
  util.sleep(time)
  util.log("Interaction with the control took " .. time .. " ms")
end

function Control:_handleTimeout(level)
  util.handleError ("\nControl " .. self.name .. " isn't responding to mouse macro commands\r\n" ..
              "Most likely its macro is invalid\r\n" ..
              "FSL2Lua version: " .. _FSL2LUA_VERSION ..
              "\r\nCheck compatibility at https://forums.flightsimlabs.com/index.php?/topic/25298-copilot-lua-script/&tab=comments#comment-194432", level + 1)
end

--- Checks if the control's light is on.
--- @usage if not FSL.GSLD_EFIS_CSTR_Button:isLit() then
---   FSL.GSLD_EFIS_CSTR_Button()
--- end
--- @treturn bool True if the control has a light and it's on.
--
--- The control needs to have an LVar associated with its light for this to work.
--
--- Unfortunately, overhead-style square buttons don't have such LVars.
function Control:isLit()
  if not self.Lt then return end
  if type(self.Lt) == "string" then return ipc.readLvar(self.Lt) == 1 end
  return ipc.readLvar(self.Lt.Brt) == 1 or ipc.readLvar(self.Lt.Dim) == 1
end

--- @treturn int
function Control:getLvarValue() return ipc.readLvar(self.LVar) end

function Control:_getLvarValueErr()
  error("The Lvar of control " .. self.name .. " is inoperable: you can't call functions that need to read the Lvar.")
end

function Control:_waitForLvarChange(timeout, startPos, errLevel)
  startPos = startPos or self:getLvarValue()
  return checkWithTimeout(timeout or 5000, function() 
    return self:getLvarValue() ~= startPos 
  end)
end

return Control