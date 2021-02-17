if false then module "FSL2Lua" end

local util = require "FSL2Lua.FSL2Lua.util"
local KeyBind = require "FSL2Lua.FSL2Lua.KeyBind"
local JoyBind = require "FSL2Lua.FSL2Lua.JoyBind"
local Switch = require "FSL2Lua.FSL2Lua.Switch"
local Button = require "FSL2Lua.FSL2Lua.Button"
local ToggleButton = require "FSL2Lua.FSL2Lua.ToggleButton"

local Bind = {
  binds = {},
  funcCount = 0
}

setmetatable(Bind, Bind)

--- @section Bind

--- This function is a convenience wrapper around event.key and event.button from the FSUIPC Lua library.
--
--- @{cockpit_control_binds.lua|Click here for usage examples}
--
--- @function Bind
--- @tparam table data A table that may contain the following fields: 
--- @param data.onPress @{cockpit_control_binds.lua|see the examples}
--- @param data.onPressRepeat @{cockpit_control_binds.lua|see the examples}
--- **Warning**: for buttons, onPressRepeat uses event.timer. There is only one timer available for a given thread so don't use onPressRepeat with buttons if you need a timer for something else.
--- @param data.onRelease @{cockpit_control_binds.lua|see the examples}
--- @param data.bindButton <a href="#Class_Button">Button</a> Binds the press and release actions of a physical key or button to those of a virtual cockpit button.
--- @param data.bindToggleButton <a href="#Class_ToggleButton">ToggleButton</a> Maps the toggle states of a joystick toggle button to those of a virtual cockpit toggle button.
--- @string data.btn Define this field for a joystick button bind. It should be a string containing the FSUIPC joystick letter and button number. Example: 'A42'.
--- @string data.key Define this field for a key bind. The following values for are accepted (case-insensitive):<br><br>
--
-- * Alphanumeric character keys
-- * Escaped keycodes: `key = "\222"`. 
-- The keycodes can be looked up in the FSUIPC console after enabling the 'Button and key operations' logging option.
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

local function makeTable(data)
  return type(data) == "table" and data or {data}
end

function Bind:prepareData(data)

  if data.onPress and data.onPressRepeat then
    error("You can't have both onPress and onPressRepeat in the same bind.", 3)
  end

  if data.bindButton then
    data.onPress = makeTable(data.onPress)
    data.onRelease = makeTable(data.onRelease)
    local onPress, onRelease = Bind._bindButton(data.bindButton)
    data.onPress[#data.onPress+1] = onPress
    data.onRelease[#data.onRelease+1] = onRelease
  end

  if data.bindToggleButton then
    data.onPress = makeTable(data.onPress)
    data.onRelease = makeTable(data.onRelease)
    local onPress, onRelease = Bind._bindToggleButton(data.bindToggleButton)
    data.onPress[#data.onPress+1] = onPress
    data.onRelease[#data.onRelease+1] = onRelease
  end
  
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

function Bind.asArg(arg)
  return setmetatable({arg = arg}, bindArg)
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
        return nil, elem.arg
      elseif type(mt) == "table" and type(mt.__call) == "function" then
        return "__call"
      end
    end
  end
end

local function checkFSLcontrol(elem, callableType, args, errLevel)
  if callableType == "method" then return end
  if util.isType(elem, Switch) then
    local ok, err = elem:_getTargetLvarVal(args[1])
    if not ok then error(err, errLevel + 1) end
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

  checkFSLcontrol(elem, callableType, args, errLevel + 1)

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
    callableType, arg = isCallable(elem, candidates[i+1])
    if callableType then
      break
    elseif i == 1 then
      error("The first element in the table must be callable", errLevel + 1)
    else 
      prevArgs[#prevArgs+1] = arg or elem
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

function Bind._bindButton(butt)
  util.assert(util.isType(butt, Button), tostring(butt.name or butt) .. " is not a button.", 4)
  local onPress, onRelease
  if not butt.guard then
    if getmetatable(butt) == ToggleButton then
      onPress = function() butt() end
      onRelease = function() end
    else
      onPress = function() butt:macro "leftPress" end
      onRelease = function() butt:macro "leftRelease" end
    end
  elseif getmetatable(butt) == ToggleButton then
    onPress = function() butt.guard:open() butt() end
    onRelease = function() butt.guard:close() end
  else
    onPress = function()
      butt.guard:open()
      butt:macro "leftPress"
    end
    onRelease = function()
      butt:macro "leftRelease"
      butt.guard:close()
    end
  end
  return onPress, onRelease
end

local function checkIsToggleButton(butt, errLevel)
  util.assert(
    getmetatable(butt) == ToggleButton,
    tostring(butt and butt.name or butt) .. " is not a toggle button.", 
    errLevel + 1
  )
end

function Bind._bindToggleButton(butt)
  checkIsToggleButton(butt, 4)
  local onPress, onRelease
  if not butt.guard then
    onPress = function() butt:toggleDown() end
    onRelease = function() butt:toggleUp() end
  else
    onPress = function()
      butt.guard:open()
      butt:toggleDown()
      butt.guard:close()
    end
    onRelease = function()
      butt.guard:open()
      butt:toggleUp()
      butt.guard:close()
    end
  end
  return onPress, onRelease
end

function Bind.toggleButtons(...)
  local butts = {...}
  for i = 1, #butts do
    checkIsToggleButton(butts[i], 2)
  end
  return function()
    local toggleState
    for _, butt in ipairs(butts) do
      if toggleState == nil then
        toggleState = not butt:isDown()
      elseif not butt:isDown() then
        toggleState = true
      end
    end
    for _, butt in ipairs(butts) do
      butt:setToggleState(toggleState)
    end
  end
end

function Bind:makeSingleFunc(args)
  if type(args) == "function" then return args end
  if type(args) ~= "table" then 
    error("Invalid callback arguments", 4) 
  end
  if args.__call or (getmetatable(args) and getmetatable(args).__call) then
    args = {args}
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

return Bind