
if false then module "FSL2Lua" end

local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"
local util = require "FSL2Lua.FSL2Lua.util"
local KeyBind = require "FSL2Lua.FSL2Lua.KeyBind"
local JoyBind = require "FSL2Lua.FSL2Lua.JoyBind"

local Positionable = require "FSL2Lua.FSL2Lua.Positionable"
local RotaryKnob = require "FSL2Lua.FSL2Lua.RotaryKnob"
local Switch = require "FSL2Lua.FSL2Lua.Switch"
local PushPullSwitch = require "FSL2Lua.FSL2Lua.PushPullSwitch"
local Button = require "FSL2Lua.FSL2Lua.Button"
local ToggleButton = require "FSL2Lua.FSL2Lua.ToggleButton"

local Bind = setmetatable({funcCount = 0}, {})
Bind.__index = Bind

--- Function for making key bindings.
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
--- @string data.key The keyboard key. The following values for are accepted (case-insensitive):<br><br>
--
-- * Alphanumeric character keys
-- * Keycodes: `key = "\222"`. 
-- * Backspace
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
-- * NumpadIns
-- * NumpadHome 
-- * NumpadEnd
-- * NumpadPageUp 
-- * NumpadPageDown
-- * NumpadLeftArrow 
-- * NumpadRightArrow 
-- * NumpadUpArrow
-- * NumpadDownArrow
-- * Clear
-- * Numpad1
-- * Numpad2
-- * Numpad3
-- * Numpad4
-- * Numpad5
-- * Numpad6
-- * Numpad7
-- * Numpad8
-- * Numpad9
--
-- You can combine one key with one or more of the following modifier keys using + as the delimiter:<br><br>
--
-- * Tab
-- * Shift
-- * Ctrl 
-- * RightCtrl 
-- * Alt
-- * RightAlt 
-- * Windows
-- * RightWindows 
-- * Apps
-- * RightApps

local bindMt = getmetatable(Bind)

function bindMt:__call(data)

  util.assert(data.key or data.btn, "You need to specify a key and/or button", 2)
  local bind = self:prepareBind(data)
  bind._keyBind = data.key and KeyBind:new(data)
  if not _COPILOT then
    bind._joyBind = data.btn and JoyBind:new(data)
  end

  if data.dispose == true then
    util.setOnGCcallback(bind, function() bind:_destroy() end)
  end

  return setmetatable(bind, Bind)
end

function Bind:_destroy()
  if self._keyBind then self._keyBind:destroy() end
  if self._joyBind then self._joyBind:destroy() end
end

Bind.unbind = Bind._destroy

function Bind:rebind()
  if self._keyBind then self._keyBind:rebind() end
  if self._joyBind then self._joyBind:rebind() end
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

function Bind:prepareBind(data)

  if not _COPILOT and data.onPress ~= nil and data.onPressRepeat ~= nil then
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
  
  if data.onPressRepeat and not _COPILOT then
    data.onPress = data.onPressRepeat
    data.Repeat = true
  end
  
  if data.onPress then
    data.onPress = Bind.makeSingleFunc(data.onPress)
    if data.cond then
      local onPress = data.onPress
      data.onPress = function() if data.cond() then onPress() end end
    end
  end
  data.onRelease = data.onRelease and Bind.makeSingleFunc(data.onRelease)
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

local function checkIsValidPosition(control, position, errLevel)
  local lvar, err = control:_getTargetLvarVal(position)
  if not lvar then error(err, (errLevel or 1) + 1) end
  return lvar
end

local function checkFslControl(elem, callableType, args, errLevel)
  if callableType == "method" then return end
  if util.isType(elem, Positionable) then
    checkIsValidPosition(elem, args[1], errLevel + 1)
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
  local elem, callableType, arg

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
    local func = makeFuncFromCallable(i, elem, callableType, candidates, funcs, errLevel)
    funcs[#funcs+1] = func
  end

  return funcs
end

function Bind.makeSingleFunc(args)
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

  local posNames = {...}

  util.assert(#posNames == 0 or #posNames > 1, "You need to specify at least two positions", 5)

  local lvars = {lvarToIdx = {}}

  if #posNames == 0 then
    for _, lvar in pairs(switch.posn) do
      lvars[#lvars+1] = lvar
    end
  else
    for _, position in ipairs(posNames) do
      lvars[#lvars+1] = checkIsValidPosition(switch, position)
    end
  end

  table.sort(lvars)

  for i, lvar in ipairs(lvars) do 
    lvars.lvarToIdx[lvar] = i 
  end

  return lvars, 1, DECREASE
end

local function cycle(switch, lvars, currIdx, direction)

  local nextIdx

  local currLvar = switch:getLvarValue()
  local lastLvar = lvars[currIdx]

  if currLvar == lastLvar then
    if currIdx == #lvars then direction = DECREASE
    elseif currIdx == 1 then direction = INCREASE end
    nextIdx = currIdx + (direction == INCREASE and 1 or -1)
  else -- The switch has been moved by something other than the calling cycler
    local idx = lvars.lvarToIdx[currLvar]
    if idx then -- Our position set contains the current position, pretend we had set it ourselves
      return cycle(switch, lvars, idx, idx > currIdx and INCREASE or DECREASE)
    elseif currLvar > lvars[#lvars] then -- The current position is to the right of our position set
      switch:_setPositionToLvar(lvars[#lvars])
      return #lvars, DECREASE
    elseif currLvar < lvars[1] then -- The current position is to the left of our position set
      switch:_setPositionToLvar(lvars[1])
      return 1, INCREASE
    else -- The current position is between two positions in our position set
      direction = currLvar > lastLvar and INCREASE or DECREASE
      for i, lvar in ipairs(lvars) do
        if direction == INCREASE and lvar > currLvar then
          nextIdx = i
          break
        elseif direction == DECREASE and lvar < currLvar then
          nextIdx = i
          break
        end
      end
    end
  end

  switch:_setPositionToLvar(lvars[nextIdx] or error "wtf")

  return nextIdx, direction
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

  local lvars, currIdx, direction = initSwitchCycling(switch, ...)

  return function()
    currIdx, direction = cycle(switch, lvars, currIdx, direction)
  end
end

--- Returns a function that will cycle the landing light switches and keep them in sync.
---@function Bind.cycleLandingLights
---@param[opt] ... At least two positions to cycle across. If none are specified, the switches will be cycled across all positions.
---@treturn function Function that will cycle the switches.
function Bind.cycleLandingLights(...)

  local left = FSL.OVHD_EXTLT_Land_L_Switch
  local right = FSL.OVHD_EXTLT_Land_R_Switch

  local lvars, currIdx, direction = initSwitchCycling(right, ...)

  return function()
    left(right:getPosn())
    cycle(left, lvars, currIdx, direction)
    currIdx, direction = cycle(right, lvars, currIdx, direction)
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
  local direction = DECREASE
  local step = 100 / steps

  return function()
    local curr = knob:getPosn()
    if curr ~= prev then cycleVal = curr end
    if cycleVal == 100 then direction = DECREASE
    elseif cycleVal == 0 then direction = INCREASE  end
    if direction == INCREASE then cycleVal = math.min(cycleVal + step, 100)
    else cycleVal = math.max(cycleVal - step, 0) end

    cycleVal = cycleVal + step / 2
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

return Bind