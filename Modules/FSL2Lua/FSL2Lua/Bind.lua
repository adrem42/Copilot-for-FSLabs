if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"
local KeyBind = require "FSL2Lua.FSL2Lua.KeyBind"
local JoyBind = require "FSL2Lua.FSL2Lua.JoyBind"

local Bind = {
  binds = {},
  funcCount = 0
}

setmetatable(Bind, Bind)

--- @section Bind

--- This function is a wrapper around event.key and event.button from the FSUIPC Lua library.
--
--- @function Bind
--- @tparam table data A table containing the following fields: 
--- @tparam function data.onPress (see usage below)
--
--- @tparam function data.onPressRepeat (see usage below)
--
--- **Warning**: for buttons, onPressRepeat uses event.timer. There is only one timer available in a lua script so don't use onPressRepeat with buttons if you need a timer for something else.<br><br>
--- @tparam function data.onRelease (see usage below)
--- @string data.btn Define this field for a joystick button bind. It should be a string containing the FSUIPC joystick letter and button number. Example: 'A42'.
--- @string data.key Define this field for a key bind. The following values for are accepted:<br><br>
--
-- * Alphanumeric character keys
-- * Escaped keycode for weird characters like 'ö' (key = '\222'). 
-- The keycodes can be looked up in the FSUIPC console after enabling the 'Button and key operations' logging facility.
-- * Enter
-- * Pause
-- * CapsLock
-- * Esc
-- * Escape
-- * Space
-- * PageUp
-- * PageDown
-- * End
-- * Home 
-- * LeftArrow
-- * UpArrow
-- * RightArrow 
-- * DownArrow
-- * PrintScreen
-- * Ins
-- * Insert
-- * Del
-- * Delete
-- * NumpadEnter
-- * NumpadPlus
-- * NumpadMinus
-- * NumpadDot 
-- * NumpadDel
-- * NumpadDiv
-- * NumpadMult
--
-- You can combine one key with one or more of the following modifier keys using + as the delimiter:<br><br>
--
-- * Tab
-- * Shift
-- * Ctrl
-- * LeftAlt
-- * RightAlt
-- * Windows
-- * Apps
--
--- @usage Bind {key = "SHIFT+A", onPress = FSL.MIP_ISIS_BARO_Button}
--- Bind {
---   key = "NumpadEnter",
---   onPressRepeat = {FSL.OVHD_INTLT_Integ_Lt_Knob, "rotateLeft"}
--- }
--- Bind {
---   btn = "C5",
---   onPress = {FSL.PED_COMM_INT_RAD_Switch, "RAD"}, 
---   onRelease = {FSL.PED_COMM_INT_RAD_Switch, "OFF"}
--- }
--- Bind {key = "NumpadMinus", onPress = {FSL.GSLD_EFIS_Baro_Switch, "push"}}
--- Bind {key = "NumpadPlus", onPress = {FSL.GSLD_EFIS_Baro_Switch, "pull"}}
--- Bind {key = "Backspace", onPress = function () ipc.control(66807) end}
function Bind:__call(data)
  util.assert(data.key or data.btn, "You need to specify a key and/or button", 2)
  data = self:prepareData(data)
  local _keyBind = data.key and KeyBind:new(data)
  local _joyBind = data.btn and JoyBind:new(data)
  if _keyBind then
    self.binds[#self.binds+1] = _keyBind
  end
  if _joyBind then
    self.binds[#self.binds+1] = _joyBind
  end
end

function Bind:prepareData(data)
  
  if data.onPressRepeat then
    data.onPress = data.onPressRepeat
    data.Repeat = true
  end
  
  if data.onPress then
    data.onPress = self:makeSingleFunc(data.onPress)
    if data.cond then
      local onPress = data.onPress
      data.onPress = function()
        if data.cond() then
          onPress()
        end
      end
    end
  end
  data.onRelease = data.onRelease and self:makeSingleFunc(data.onRelease)
  return data
end

local bindArg = {}

function Bind.asArg(func)
  util.assert(type(func) == "function", "The argument must be a function.")
  return setmetatable({f = func}, bindArg)
end

local function isCallable(elem, nextElem)
  if type(elem) == "function" then
    return "func"
  elseif type(elem) == "table" then
    if type(elem[nextElem]) == "function" then
      return "method"
    else
      local mt = getmetatable(elem)
      if mt == bindArg then
        elem = elem.f
      elseif type(mt) == "table" and type(mt.__call) == "function" then
        return "__call"
      end
    end
  end
end

local function checkFSLcontrol(callableType, elem, args, errLevel)
  if callableType == "__call" and elem.FSL_VC_control then
    local class = getmetatable(elem)
    local arg = args[1]
    if not arg and (class == KnobWithoutPositions or class == Switch) then
      error("A position must be specified for control " .. elem.name .. ".", errLevel + 1)
    end
    if class == KnobWithoutPositions then
      util.assert(
        type(arg) == "number",
        "The position for control " .. elem.name .. " must be a number.", errLevel + 1
      )
    end
    if class == Switch then
      util.assert(
        type(arg) == "string",
        "The position for control " .. elem.name .. " must be a string.", errLevel + 1
      )
      util.assert(
        elem.posn[arg:upper()] ~= nil,
        arg .. " is not a valid position of control " .. elem.name .. ".",
        errLevel + 1
      )
    end
  end
end

local parseCallableArgs, makeFuncFromCallable

makeFuncFromCallable = function(i, elem, callableType, candidates, funcs, errLevel)

  local args = {}

  if i < #candidates then
    if callableType == "method" then
      args[1] = elem
      parseCallableArgs(i+2, candidates, funcs, args)
    else
      parseCallableArgs(i+1, candidates, funcs, args)
    end
  end

  checkFSLcontrol(callableType, elem, args, errLevel)

  if callableType == "method" then 
    elem = elem[candidates[i+1]]
  end

  if #args == 0 then
    return elem
  elseif #args == 1 then 
    local arg = args[1]
    return function() elem(arg) end
  else
    return function() elem(unpack(args)) end
  end
  
end

parseCallableArgs = function(i, candidates, funcs, prevArgs)

  funcs = funcs or {}

  local errLevel = 5
  local callableType, elem

  while i <= #candidates do
    elem = candidates[i]
    callableType = isCallable(elem, candidates[i+1])
    if callableType then
      break
    elseif i == 1 then
      error("The first element in the table must be callable", errLevel + 1)
    else 
      prevArgs[#prevArgs+1] = elem
    end
    i = i + 1
  end

  if callableType then
    local func = makeFuncFromCallable(
      i, elem, callableType, candidates, funcs, errLevel
    )
    funcs[#funcs+1] = func
  end

  return funcs
end

function Bind:makeSingleFunc(args)

  if type(args) == "function" then return args end

  if type(args) ~= "table" then 
    error("Invalid callback arguments", 4) 
  end

  if args.__call or (getmetatable(args) and getmetatable(args).__call) then
    return args
  end

  local funcs = parseCallableArgs(1, args)
  if #funcs == 1 then return funcs[1] end
  return function()
    for i = #funcs, 1, -1 do
      funcs[i]()
    end
  end
end

function Bind:addGlobalFuncs(...)
  local funcNames = {}
  for _, func in ipairs {...} do
    self.funcCount = self.funcCount + 1
    local funcName = "FSL2LuaGFunc" .. self.funcCount
    if type(func) == "table" and (func.__call or getmetatable(func).__call) then
      _G[funcName] = function() func() end
    else
      _G[funcName] = func
    end
    funcNames[#funcNames+1] = funcName
  end
  if #funcNames == 1 then
    return funcNames[1]
  else return funcNames end
end

Bind.shift = {}
function Bind.shift:__call(data)
  return setmetatable({data = data}, Bind.shift)
end

return Bind