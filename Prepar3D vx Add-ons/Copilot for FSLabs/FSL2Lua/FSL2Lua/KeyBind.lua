local util = require "FSL2Lua.FSL2Lua.util"

local keyList, shiftList

do
  local lists = require "key_list"
  keyList = lists.keyList
  shiftList = lists.shiftList
end

local KeyBindWrapper = {}

function KeyBindWrapper:new(data)
  self.__index = self
  local bind = setmetatable({}, self)
  bind.data = bind:prepareData(data)
  bind:rebind()
  return bind
end

function KeyBindWrapper:prepareData(data)
  util.assert(type(data.key) == "string", "The key combination must be a string", 4)
  local mainKeyCode
  local shifts = {}
  local keyCount = 0
  for key in data.key:gmatch("[^(%+)]+") do
    keyCount = keyCount + 1
    local isShift
    for shift, keyCode in pairs(shiftList) do
      if shift:lower() == key:lower() then
        shifts[#shifts+1] = keyCode
        isShift = true
      end
    end
    if not isShift then
      for _key, keycode in pairs(keyList) do
        if key:lower() == _key:lower() then
          mainKeyCode = keycode
        end
      end
      if not mainKeyCode then
        util.assert(#key == 1, "Invalid key", 4)
        mainKeyCode = util.assert(string.byte(key:upper()), "Invalid key", 4)
      end
    end
  end
  util.assert(keyCount ~= #shifts, "Can't have only modifier keys", 4)
  util.assert(keyCount - #shifts == 1, "Can't have more than one non-modifier key", 4)
  self.keyBind = {key = (mainKeyCode + (data.extended and 0xFF or 0)), shifts = shifts}
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