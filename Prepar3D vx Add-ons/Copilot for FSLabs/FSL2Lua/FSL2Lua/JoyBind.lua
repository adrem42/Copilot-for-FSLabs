local util = require "FSL2Lua.FSL2Lua.util"

local JoyBind = setmetatable({}, require "FSL2Lua.FSL2Lua.BindMeta")

function JoyBind:new(data)
  self.__index = self
  local bind = setmetatable({}, self)
  bind.data = bind:prepareData(data)
  bind:rebind()
  return bind
end

function JoyBind:prepareData(data)
  util.assert(type(data.btn) == "string", "Wrong joystick button format", 4)
  data.joyLetter = data.btn:sub(1,1)
  data.btnNum = tostring(data.btn:sub(2, #data.btn))
  data.btn = nil
  util.assert(data.joyLetter:find("%A") == nil, "Wrong joystick button format", 4)
  util.assert(tostring(data.btnNum):find("%D") == nil, "Wrong joystick button format", 4)
  return data
end

function JoyBind:registerOnPressEvents()
  if self.data.Repeat then
    self.data.timerFuncName = self:addGlobalFunc(function()
      self.data.onPress()
    end)
    event.button(self.data.joyLetter, self.data.btnNum, 1, self:addGlobalFunc(function()
      event.timer(20, self.data.timerFuncName)
      self.isPressed = true
      self.data.onPress()
    end))
  else
    event.button(self.data.joyLetter, self.data.btnNum, 1, self:addGlobalFunc(self.data.onPress))
  end
end

function JoyBind:registerOnReleaseEvents()
  local funcName
  if self.data.Repeat and not self.data.onRelease then
    funcName = self:addGlobalFunc(function()
      self.isPressed = false
      event.cancel(self.data.timerFuncName)
    end)
  elseif self.data.Repeat and self.data.onRelease then
    funcName = self:addGlobalFunc(function()
      self.isPressed = false
      self.data.onRelease()
    end)
  elseif self.data.onRelease then
    funcName = self:addGlobalFunc(self.data.onRelease)
  end
  event.button(self.data.joyLetter, self.data.btnNum, 2, funcName)
end

return JoyBind