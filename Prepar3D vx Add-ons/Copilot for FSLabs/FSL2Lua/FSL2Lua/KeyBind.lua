Bind = Bind or {}

local keyCodes = require "key_list"
local KeyBindWrapper = {}

function KeyBindWrapper:new(data)
  self.__index = self
  local bind = setmetatable({}, self)
  bind.data = bind:prepareData(data)
  bind:rebind()
  return bind
end

function Bind.parseKeys(input, useSendModifiers)
  assert(type(input) == "string", "The key combination must be a string")
  local mainKeyCode
  local shifts = {}
  local keyCount = 0
  for keyString in input:gmatch("[^(%+)]+") do
    keyCount = keyCount + 1
    keyString = keyString:lower()
    local maybeShift = keyCodes.modifiers[keyString]
      or useSendModifiers and keyCodes.sendModifiers[keyString]
    if maybeShift then
      shifts[#shifts+1] = maybeShift
    else
      local maybeKey = keyCodes.keys[keyString]
      if not maybeKey then
        assert(#keyString == 1, "Invalid key: " .. keyString)
        maybeKey = assert(string.byte(keyString:upper()), "Invalid key: " .. keyString)
      end
      assert(mainKeyCode == nil, "Can't have more than one non-modifier key")
      mainKeyCode = maybeKey
    end
  end
  assert(keyCount > 0, "No key specified")
  assert(keyCount ~= #shifts, "Can't have only modifier keys")
  return {keyCode = mainKeyCode, shifts = shifts}
end

function KeyBindWrapper:prepareData(data)
  local _keyCodes = Bind.parseKeys(data.key)
  self.keyBind = {key = (_keyCodes.keyCode + (data.extended and 0xFF or 0)), shifts = _keyCodes.shifts}
  return data
end

function KeyBindWrapper:registerOnReleaseEvents()
  __addKeyBind(self.keyBind.key, KeyEventType.Release, self.data.onRelease, self.keyBind.shifts)
end

function KeyBindWrapper:registerOnPressEvents()
  __addKeyBind(self.keyBind.key, KeyEventType.Press, self.data.onPress, self.keyBind.shifts)
  if self.data.onPressRepeat then
    __addKeyBind(self.keyBind.key, KeyEventType.PressRepeat, self.data.onPressRepeat, self.keyBind.shifts)
  end
end

function KeyBindWrapper:destroy()
  if not self.active then return end
  self.active = false
  local function remove(event, callback)
    __removeKeyBind(self.keyBind.key, event, callback, self.keyBind.shifts)
  end
  if self.data.onPress then
    remove(KeyEventType.Press, self.data.onPress)
  end
  if self.data.onPressRepeat then
    remove(KeyEventType.PressRepeat, self.data.onPressRepeat)
  end
  if self.data.onRelease then
    remove(KeyEventType.Release, self.data.onRelease)
  end
end

function KeyBindWrapper:rebind()
  if self.active then return end
  self.active = true
  if self.data.onPress then self:registerOnPressEvents() end
  if self.data.onRelease then self:registerOnReleaseEvents() end
end

return KeyBindWrapper