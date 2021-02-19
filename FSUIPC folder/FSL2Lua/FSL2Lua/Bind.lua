
if false then module "FSL2Lua" end

local RotaryKnob = require "FSL2Lua.FSL2Lua.RotaryKnob"
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"
local util = require "FSL2Lua.FSL2Lua.util"
local KeyBind = require "FSL2Lua.FSL2Lua.KeyBind"
local JoyBind = require "FSL2Lua.FSL2Lua.JoyBind"
local Switch = require "FSL2Lua.FSL2Lua.Switch"
local PushPullSwitch = require "FSL2Lua.FSL2Lua.PushPullSwitch"
local Button = require "FSL2Lua.FSL2Lua.Button"
local ToggleButton = require "FSL2Lua.FSL2Lua.ToggleButton"

local Bind = {
  binds = {},
  funcCount = 0
}

setmetatable(Bind, Bind)

--- Convenience wrapper around event.key and event.button from the FSUIPC Lua library.
--- For joystick buttons, consider @{hid_joysticks.lua|using} the `Joystick` library instead. 
--
--- @{cockpit_control_binds.lua|Click here for usage examples}
--
--- Accepted values for onPress, onRelease, and onPressRepeat are:
--
--- * A function or callable table.
--
--- * An array in the following format: `{**callable1**, arg1, arg2, ..., argn, **callable2**, arg1, arg2, ..., argn, ...}`
--- where a callable can be either a function, callable table, or object followed by a method name: `FSL.OVHD_INTLT_Integ_Lt_Knob, "rotateLeft"`.
--- @function Bind
--- @tparam table data A table that may contain the following fields: 
--- @param data.onPress See above.
--- @param data.onPressRepeat See above.
--- **Warning**: for buttons, onPressRepeat uses event.timer. There is only one timer available for a given thread so don't use onPressRepeat with buttons if you need a timer for something else.
--- @param data.onRelease See above.
--- @param data.bindButton <a href="#Class_Button">Button</a> Binds the press and release actions of a physical key or button to those of a virtual cockpit button.
--- @param data.bindToggleButton <a href="#Class_ToggleButton">ToggleButton</a> Maps the toggle states of a joystick toggle button to those of a virtual cockpit toggle button.
--- @param data.bindPush <a href="#Class_PushPullSwitch">PushPullSwitch</a> Same as `bindButton` — for pushing the switch.
--- @param data.bindPull <a href="#Class_PushPullSwitch">PushPullSwitch</a> Same as `bindButton` — for pulling the switch.
--- @string data.btn Define this field for a joystick button bind. It should be a string containing the FSUIPC joystick letter and button number: `"A5"`.
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

local function specialButtonBinding(data, onPress, onRelease)
  data.onPress = makeTable(data.onPress)
  data.onRelease = makeTable(data.onRelease)
  data.onPress[#data.onPress+1] = onPress
  data.onRelease[#data.onRelease+1] = onRelease
end

function Bind:prepareData(data)

  if data.onPress ~= nil and data.onPressRepeat ~= nil then
    error("You can't have both onPress and onPressRepeat in the same bind.", 3)
  end

  if data.bindPush then
    specialButtonBinding(data, Bind._bindPush(data.bindPush))
  end

  if data.bindPull then
    specialButtonBinding(data, Bind._bindPull(data.bindPull))
  end

  if data.bindButton then
    specialButtonBinding(data, Bind._bindButton(data.bindButton))
  end

  if data.bindToggleButton then
    specialButtonBinding(data, Bind._bindToggleButton(data.bindToggleButton))
  end
  
  if data.onPressRepeat then
    data.onPress = data.onPressRepeat
    data.Repeat = true
  end
  
  if data.onPress then
    data.onPress = self:makeSingleFunc(data.onPress)
    if data.cond then
      local onPress = data.onPress
      data.onPress = function() if data.cond() then onPress() end end
    end
  end
  data.onRelease = data.onRelease and self:makeSingleFunc(data.onRelease)
  return data
end

local bindArg = {}
function Bind.asArg(arg) return setmetatable({arg = arg}, bindArg) end

local function checkCallable(elem, nextElem)
  local _, callableType = util.isCallable(elem)
  if callableType == "function" then
    return "function"
  elseif type(elem) == "table" then
    if type(elem[nextElem]) == "function" then
      return "method"
    elseif callableType == "funcTable" then
      return "funcTable"
    elseif getmetatable(elem) == bindArg then
      return nil, elem.arg
    end
  end
end

local function checkIsValidSwitchPosition(switch, position, errLevel)
  local ok, err = switch:_getTargetLvarVal(position)
  if not ok then error(err, (errLevel or 1) + 1) end
end

local function checkFslControl(elem, callableType, args, errLevel)
  if callableType == "method" then return end
  if util.isType(elem, Switch) then
    checkIsValidSwitchPosition(elem, args[1], errLevel + 1)
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

  checkFslControl(elem, callableType, args, errLevel + 1)

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
    callableType, arg = checkCallable(elem, candidates[i+1])
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

function Bind._bindButton(butt, pressMacro, releaseMacro)
  util.checkType(butt, Button, "button", 4)
  local onPress, onRelease
  pressMacro = pressMacro or "leftPress"
  releaseMacro = releaseMacro or "leftRelease"
  if not butt.guard then
    if util.isType(butt, ToggleButton) then
      onPress = function() butt() end
      onRelease = function() end
    else
      onPress = function() butt:macro(pressMacro) end
      onRelease = function() butt:macro(releaseMacro) end
    end
  elseif util.isType(butt, ToggleButton) then
    onPress = function() butt.guard:open() butt() end
    onRelease = function() butt.guard:close() end
  else
    onPress = function()
      butt.guard:open()
      butt:macro(pressMacro)
    end
    onRelease = function()
      butt:macro(releaseMacro)
      butt.guard:close()
    end
  end
  return onPress, onRelease
end

function Bind._bindPush(switch)
  util.checkType(switch, PushPullSwitch, "FCU switch", 4)
  return Bind._bindButton(switch._button)
end

function Bind._bindPull(switch)
  util.checkType(switch, PushPullSwitch, "FCU switch", 4)
  return Bind._bindButton(switch._button, "rightPress", "rightRelease")
end

local function checkIsToggleButton(butt, errLevel)
  util.checkType(butt, ToggleButton, "toggle button", errLevel + 1)
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

local INCREASE = true
local DECREASE = false

local function initSwitchCycling(switch, ...)

  local positions = {...}

  util.assert(#positions == 0 or #positions > 1, "You need at lest two positions to cycle between", 5)

  if #positions == 0 then
    positions = {}
    for pos in pairs(switch.posn) do
      positions[#positions+1] = pos
    end
  end

  for i, position in ipairs(positions) do
    positions[i] = position:upper()
    checkIsValidSwitchPosition(switch, position)
  end
  
  table.sort(positions, function(pos1, pos2)
    return switch.posn[pos1] < switch.posn[pos2]
  end)

  local currPos = switch:getPosn()
  for i, position in ipairs(positions) do
    if position == currPos then return positions, i end
  end
  return positions, 1
end

local function cycle(currIdx, direction, switch, positions)

  local lastPos = positions[currIdx]
  local currPos = switch:getPosn()

  if currPos ~= lastPos then
  
    local currPosIdx

    for i, pos in ipairs(positions) do
      if pos == currPos then
        currPosIdx = i
        break
      end
    end

    if currPosIdx then
      if currPosIdx == #positions then direction = INCREASE
      elseif currPosIdx == 1 then  direction = DECREASE
      else direction = currPosIdx > currIdx end
      currIdx = currPosIdx
    else
      local diff = switch.maxLVarVal
      local currPosLvar = switch.posn[currPos]
      local inside
      local closestPosIdx, closestPosLvar
      for i, pos in ipairs(positions) do
        local oldDiff = diff
        local lvar = switch.posn[pos]
        diff = math.min(diff, math.abs(lvar - currPosLvar))
        if diff < oldDiff then
          closestPosLvar = lvar
          closestPosIdx = i
        end
      end
      if not inside  then
        if closestPosLvar == switch.posn[positions[1]] then
          currIdx = #positions  - 1
        elseif closestPosLvar == switch.posn[positions[#positions]] then
          currIdx = 2
        end
      end
      direction = closestPosIdx > currIdx 
    end
  end

  if direction == INCREASE then currIdx = currIdx + 1
  else currIdx = currIdx - 1 end
  
  if currIdx > #positions then 
    direction = DECREASE
    currIdx = #positions - 1
  elseif currIdx < 1 then 
    direction = INCREASE
    currIdx = 2 
  end

  switch(positions[currIdx])

  return currIdx, direction
end

--- Returns a function that will cycle the switch.
---@function Bind.cycleSwitch
---@param switch <a href="#Class_Switch">Switch</a> 
---@param[opt] ... At least two positions to cycle across. If none are specified, the switch will be cycled across all positions.
---@treturn function Function that will cycle the switch.
---@usage Bind {key = "A", onPress = Bind.cycleSwitch(FSL.OVHD_EXTLT_Strobe_Switch, "OFF", "ON")}
--
---myJoystick:onPress(1, Bind.cycleSwitch(FSL.OVHD_EXTLT_Strobe_Switch))
function Bind.cycleSwitch(switch, ...)

  util.checkType(switch, Switch, "switch", 4)

  local positions, currIdx = initSwitchCycling(switch, ...)
  local direction = DECREASE

  return function()
    currIdx, direction = cycle(currIdx, direction, switch, positions)
  end
end

--- Returns a function that will cycle the landing light switches and keep them in sync.
---@function Bind.cycleLandingLights
---@param[opt] ... At least two positions to cycle across. If none are specified, the switches will be cycled across all positions.
---@treturn function Function that will cycle the switches.
function Bind.cycleLandingLights(...)

  local left = FSL.OVHD_EXTLT_Land_L_Switch
  local right = FSL.OVHD_EXTLT_Land_R_Switch

  local direction = false
  local positions, currIdx = initSwitchCycling(right, ...)

  return function()
    left(right:getPosn())
    cycle(currIdx, direction, left, positions)
    currIdx, direction = cycle(currIdx, direction, right, positions)
  end
end

--- Divides the knob in n steps and returns a function that will cycle the knob across those steps.
---@function Bind.cycleRotaryKnob
---@param knob <a href="#Class_RotaryKnob">RotaryKnob</a> 
---@int steps In how many steps to divide the knob.
---@treturn function Function that will cycle the knob.
function Bind.cycleRotaryKnob(knob, steps)

  util.checkType(knob, RotaryKnob, "rotary knob", 4)

  steps = math.floor(steps)
  local cycleVal = 0
  local prev = 0
  local cycleDir = DECREASE

  return function()
    local step = 100 / steps
    local curr = knob:getPosn()
    if curr ~= prev then cycleVal = curr end
    if cycleVal == 100 then cycleDir = DECREASE
    elseif cycleVal == 0 then cycleDir = INCREASE  end
    if cycleDir == INCREASE then cycleVal = math.min(cycleVal + step, 100)
    else cycleVal = math.max(cycleVal - step, 0) end
    cycleVal = cycleVal - cycleVal % step
    prev = knob(cycleVal)
  end
end

--- Returns a function that will cycle multiple toggle buttons at once and keep their toggle states in sync.
---@function Bind.toggleButtons
---@param ... One or more <a href="#Class_ToggleButton">ToggleButton</a>'s
---@treturn function Function that will toggle the buttons.
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
  if util.isFuncTable(args) then args = {args} end
  local funcs = parseCallableArgs(1, args)
  if #funcs == 0 then
    error("There needs to be at least one callable object", 4)
  end
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
    if util.isFuncTable(func) then
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