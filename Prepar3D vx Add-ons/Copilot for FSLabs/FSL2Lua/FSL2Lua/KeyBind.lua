if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"

local keyList = {
  Backspace = 8,
  Enter = 13,
  Pause = 19,
  CapsLock = 20,
  Esc = 27,
  Escape = 27,
  Space = 32,
  PageUp = not _COPILOT and 33 or (33 + 0xFF),
  PageDown = not _COPILOT and 34 or (34 + 0xFF),
  End = not _COPILOT and 35 or (35 + 0xFF),
  Home = not _COPILOT and 36 or (36 + 0xFF),
  LeftArrow = not _COPILOT and 37 or (37 + 0xFF),
  UpArrow = not _COPILOT and 38 or (38 + 0xFF),
  RightArrow = not _COPILOT and 39 or (39 + 0xFF),
  DownArrow = not _COPILOT and 40 or (40 + 0xFF),
  PrintScreen = not _COPILOT and 44 or (44 + 0xFF),
  Ins = not _COPILOT and 45 or (45 + 0xFF),
  Insert = not _COPILOT and 45 or (45 + 0xFF),
  Del = not _COPILOT and 46 or (46 + 0xFF),
  Delete  = not _COPILOT and 46 or (46 + 0xFF),
  NumpadEnter = not _COPILOT and 135 or (13 + 0xFF),
  NumpadPlus = 107,
  NumpadMinus = 109,
  NumpadDot = 110,
  NumpadDel = not _COPILOT and 110 or 46,
  NumpadDiv = not _COPILOT and 111 or (111 + 0xFF),
  NumpadMult = 106,
  NumpadIns = _COPILOT and 45,
  NumpadHome = _COPILOT and 36,
  NumpadEnd = _COPILOT and 35,
  NumpadPageUp = _COPILOT and 33,
  NumpadPageDown = _COPILOT and 34,
  NumpadLeftArrow = _COPILOT and 37,
  NumpadRightArrow = _COPILOT and 39,
  NumpadUpArrow = _COPILOT and 38,
  NumpadDownArrow = _COPILOT and 40,
  Clear = _COPILOT and 12,
  Numpad1 = _COPILOT and 97,
  Numpad2 = _COPILOT and 98,
  Numpad3 = _COPILOT and 99,
  Numpad4 = _COPILOT and 100,
  Numpad5 = _COPILOT and 101,
  Numpad6 = _COPILOT and 102,
  Numpad7 = _COPILOT and 103,
  Numpad8 = _COPILOT and 104,
  Numpad9 = _COPILOT and 105,
}

for i = 1, 22 do
  keyList["F" .. i] = i +  111
end
for i = 0, 9 do
  keyList["NumPad" .. i] = i +  96
end

local shiftsList = {
  Tab = {key = 9, shift = 16},
  Shift = {key = 16, shift = 1},
  Ctrl = {key = 17, shift = 2},
  LeftAlt = {key = 18, shift = 4},
  RightAlt = {key = 18, shift = 6},
  Windows = {key = 92, shift = 32},
  Apps = {key = 93, shift = 64}
}

local copilotShifts = {
  Tab = 9,
  Shift = 16,
  Ctrl = 17,
  RightCtrl = 17 + 0xFF,
  Alt = 18,
  RightAlt = 18 + 0xFF ,
  Windows = 92,
  RightWindows = 92 + 0xFF,
  Apps = 93,
  RightApps = 93 + 0xFF
}

local KeyBindWrapper = setmetatable({}, require "FSL2Lua.FSL2Lua.BindMeta")

function KeyBindWrapper:new(data)
  self.__index = self
  local bind = setmetatable({}, self)
  if _COPILOT then 
    bind.data = bind:prepareDataNew(data)
  else
    bind.data = bind:prepareDataOld(data)
  end
  bind:rebind()
  return bind
end

local function findKeyCode(str, keys)
  keys = keys or keyList
  for k, v in pairs(keys) do
    if k:lower() == str:lower() then
      return v
    end
  end
  return (#str == 1 and string.byte(str:upper())) or nil
end

function KeyBindWrapper:prepareDataNew(data)
  local key
  local keys = {}
  local shifts = {}
  for _key in data.key:gmatch("[^(%+)]+") do
    keys[#keys+1] = _key
  end
  local function onError()
    error("Invalid key combination: " .. data.key, 5)
  end
  for i, _key in ipairs(keys) do
    if i == #keys then
      key =_key
    else
      shifts[#shifts+1] = findKeyCode(_key, copilotShifts) or onError()
    end
  end
  self.keyBind = {key = findKeyCode(key) or onError(), shifts = shifts}
  return data
end

function KeyBindWrapper:prepareDataOld(data)
  util.assert(type(data.key) == "string", "The key combination must be a string", 4)
  local keys = {}
  local shifts = {}
  local keyCount = 0
  for key in data.key:gmatch("[^(%+)]+") do
    keyCount = keyCount + 1
    local isShift
    for shift, shiftData in pairs(shiftsList) do
      if shift:lower() == key:lower() then
        shifts[#shifts+1] = shiftData
        isShift = true
      end
    end
    if not isShift then
      for _key, keycode in pairs(keyList) do
        if key:lower() == _key:lower() then
          keys.key = keycode
        end
      end
      if not keys.key then
        util.assert(#key == 1, "Invalid key", 4)
        keys.key = util.assert(string.byte(key:upper()), "Invalid key", 4)
      end
    end
  end
  util.assert(keyCount ~= #shifts, "Can't have only modifier keys", 4)
  util.assert(keyCount - #shifts == 1, "Can't have more than one non-modifier key", 4)
  if #shifts > 0 then
    keys.shifts = shifts
  end
  data.key = nil
  data.keys = keys
  return data
end

if not _COPILOT then

  function KeyBindWrapper:registerOnPressEvents()
    local key = self.data.keys.key
    local shifts = self.data.keys.shifts
    local shiftsVal = 0
    if shifts then
      for _, shift in ipairs(shifts) do
        shiftsVal = shiftsVal + shift.shift
      end
    end
    local downup = self.data.Repeat and 4 or 1
    if shifts and self.data.onRelease then
      event.key(key, shiftsVal, downup, self:addGlobalFunc(function()
        self.isPressedWithShifts = true
        self.data.onPress()
      end))
    else
      if not shifts and self.data.onRelease then
        event.key(key, shiftsVal, downup, self:addGlobalFunc(function()
          self.isPressedPlain = true
          self.data.onPress()
        end))
      else
        event.key(key, shiftsVal, downup, self:addGlobalFunc(self.data.onPress))
      end
    end
  end

  local function subsetSums(arr, l, r, sum, sums)
    sums = sums or {}
    sum = sum or 0
    if l > r then
      sums[#sums+1] = sum
      return
    end
    subsetSums(arr, l + 1, r, sum + arr[l], sums)
    subsetSums(arr, l + 1, r, sum, sums)
    return sums
  end

  function KeyBindWrapper:registerOnReleaseEvents()
    local key = self.data.keys.key
    local shifts = self.data.keys.shifts
    if shifts then
      local funcName = self:addGlobalFunc(function()
        if self.isPressedWithShifts then
          self.isPressedWithShifts = false
          self.data.onRelease()
        end
      end)
      local shiftsValArr = {}
      for _, v in pairs(shifts) do
        shiftsValArr[#shiftsValArr+1] = v.shift
      end
      local shiftCombinations = subsetSums(shiftsValArr, 1, #shiftsValArr)
      for _, v in pairs(shifts) do
        for _, _v in pairs(shiftCombinations) do
          if _v > 0 then
            event.key(v.key, _v, 2, funcName)
          end
        end
      end
      for _, v in pairs(shiftCombinations) do
        if v > 0 then
          event.key(key, v, 2, funcName)
        end
      end
    else
      if not self.data.onPress then
        event.key(key, nil, 1, self:addGlobalFunc(function() self.isPressedPlain = true end))
      end
      event.key(key, nil, 2, self:addGlobalFunc(function()
        if self.isPressedPlain then
          self.isPressedPlain = false
          self.data.onRelease()
        end
      end))
    end
  end

else

  function KeyBindWrapper:registerOnReleaseEvents()
    __addKeyBind(self.keyBind.key, KeyEventType.Release, self.data.onRelease, self.keyBind.shifts)
  end

  function KeyBindWrapper:registerOnPressEvents()
    __addKeyBind(self.keyBind.key, KeyEventType.Press, self.data.onPress, self.keyBind.shifts)
    if self.data.onPressRepeat then
      __addKeyBind(self.keyBind.key, KeyEventType.PressRepeat, self.data.onPressRepeat, self.keyBind.shifts)
    end
  end

end

return KeyBindWrapper