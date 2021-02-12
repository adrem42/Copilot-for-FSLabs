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
  PageUp = 33,
  PageDown = 34,
  End = 35,
  Home = 36,
  LeftArrow = 37,
  UpArrow = 38,
  RightArrow = 39,
  DownArrow = 40,
  PrintScreen = 44,
  Ins = 45,
  Insert = 45,
  Del = 46,
  Delete  = 46,
  NumpadEnter = 135,
  NumpadPlus = 107,
  NumpadMinus = 109,
  NumpadDot = 110,
  NumpadDel = 110,
  NumpadDiv = 111,
  NumpadMult = 106
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

local KeyBind = {}

function KeyBind:new(data)
  self.__index = self
  local bind = setmetatable({}, self)
  bind.data = bind:prepareData(data)
  if bind.data.onPress then
    bind:registerOnPressEvents()
  end
  if bind.data.onRelease then
    bind:registerOnReleaseEvents()
  end
  return bind
end

function KeyBind:prepareData(data)
  util.assert(type(data.key) == "string", "The key combination must be a string", 4)
  local keys = {}
  local shifts = {}
  local keyCount = 0
  for key in data.key:gmatch("[^(%+)]+") do
    keyCount = keyCount + 1
    local isShift
    for shift, data in pairs(shiftsList) do
      if shift:lower() == key:lower() then
        shifts[#shifts+1] = data
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

function KeyBind:registerOnPressEvents()
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
    event.key(key, shiftsVal, downup, Bind:addGlobalFuncs(function()
      self.isPressedWithShifts = true
      self.data.onPress()
    end))
  else
    if not shifts and self.data.onRelease then
      event.key(key, shiftsVal, downup, Bind:addGlobalFuncs(function()
        self.isPressedPlain = true
        self.data.onPress()
      end))
    else
      event.key(key, shiftsVal, downup, Bind:addGlobalFuncs(self.data.onPress))
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

function KeyBind:registerOnReleaseEvents()
  local key = self.data.keys.key
  local shifts = self.data.keys.shifts
  if shifts then
    local funcName = Bind:addGlobalFuncs(function()
      if self.isPressedWithShifts then
        self.isPressedWithShifts = false
        self.data.onRelease()
      end
    end)
    local shiftsVal = 0
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
      event.key(key, nil, 1, Bind:addGlobalFuncs(function()
        self.isPressedPlain = true
      end))
    end
    event.key(key, nil, 2, Bind:addGlobalFuncs(function()
      if self.isPressedPlain then
        self.isPressedPlain = false
        self.data.onRelease()
      end
    end))
  end
end

return KeyBind