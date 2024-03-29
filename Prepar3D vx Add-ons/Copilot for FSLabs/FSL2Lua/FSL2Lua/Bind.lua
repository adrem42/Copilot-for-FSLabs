
if false then module "FSL2Lua" end

local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"
local util = require "FSL2Lua.FSL2Lua.util"
local KeyBind = require "FSL2Lua.FSL2Lua.KeyBind"

local Positionable = require "FSL2Lua.FSL2Lua.Positionable"
local RotaryKnob = require "FSL2Lua.FSL2Lua.RotaryKnob"
local Switch = require "FSL2Lua.FSL2Lua.Switch"
local PushPullSwitch = require "FSL2Lua.FSL2Lua.PushPullSwitch"
local Button = require "FSL2Lua.FSL2Lua.Button"
local ToggleButton = require "FSL2Lua.FSL2Lua.ToggleButton"

local Bind = setmetatable(Bind or {}, {})
Bind.__index = Bind

--- Function for making key bindings. The key events for the bindings you define are trapped and not passed on to the sim.
--
--- Accepted values for onPress, onRelease, and onPressRepeat are:
--
--- * A function or callable table.
--
--- * An array in the following format: `{**callable1**, arg1, arg2, ..., argn, **callable2**, arg1, arg2, ..., argn, ...}`
--- where a callable can be either a function, callable table, or object followed by a method name: `FSL.OVHD_INTLT_Integ_Lt_Knob, "rotateLeft"`.
--- @function Bind
--- @tparam table args A table that may contain the following fields: 
--- @param args.onPress See above.
--- @param args.onPressRepeat See above.
--- @param args.onRelease See above.
--- @param args.bindButton <a href="#Class_Button">Button</a> Binds the press and release actions of a physical key or button to those of a virtual cockpit button.
--- @param args.bindToggleButton <a href="#Class_ToggleButton">ToggleButton</a> Maps the toggle states of a joystick toggle button to those of a virtual cockpit toggle button.
--- @param args.bindPush <a href="#Class_PushPullSwitch">PushPullSwitch</a> Same as `bindButton` — for pushing the switch.
--- @param args.bindPull <a href="#Class_PushPullSwitch">PushPullSwitch</a> Same as `bindButton` — for pulling the switch.
--- @bool args.extended True if the key is an extended key. For example, both the regular and the numpad Enter keys share the same keycode, but only the latter has the extended flag set.
--- @string args.key @{list_of_keys.md|See the list of keys here}
-- @usage 
-- Bind {key = "SHIFT+ALT+PageUp", extended = true, onPress = function() print "hi" end}
-- Bind {key = "A", onPress = {FSL.OVHD_EXTLT_Nose_Switch, "TAXI"}}

local bindMt = getmetatable(Bind)

function bindMt:__call(args)
  util.assert(args.key, "You need to specify a key and/or button", 2)
  local bind = self:prepareBind(args)
  bind._keyBind = KeyBind:new(args)
  if args.dispose == true then
    util.setOnGCcallback(bind, function() bind:_destroy() end)
  end
  return setmetatable(bind, Bind)
end

function Bind:_destroy() self._keyBind:destroy() end
Bind.unbind = Bind._destroy
function Bind:rebind() self._keyBind:rebind() end

local function makeTable(args)
  return type(args) == "table" and args or {args}
end

local function specialButtonBinding(args, onPress, onRelease)
  args.onPress = makeTable(args.onPress)
  args.onRelease = makeTable(args.onRelease)
  args.onPress[#args.onPress+1] = onPress
  args.onRelease[#args.onRelease+1] = onRelease
end

function Bind:prepareBind(args)

  if args.bindPush then
    specialButtonBinding(args, Bind._bindPush(args.bindPush))
  end

  if args.bindPull then
    specialButtonBinding(args, Bind._bindPull(args.bindPull))
  end

  if args.bindButton then
    specialButtonBinding(args, Bind._bindButton(args.bindButton))
  end

  if args.bindToggleButton then
    specialButtonBinding(args, Bind._bindToggleButton(args.bindToggleButton))
  end
  
  if args.onPress then
    args.onPress = Bind.makeSingleFunc(args.onPress)
    if args.cond then
      local onPress = args.onPress
      args.onPress = function() if args.cond() then onPress() end end
    end
  end

  if args.onPressRepeat then
    args.onPressRepeat = Bind.makeSingleFunc(args.onPress)
    if args.cond then
      local onPressRepeat = args.onPressRepeat
      args.onPressRepeat = function() if args.cond() then onPressRepeat() end end
    end
  end

  args.onRelease = args.onRelease and Bind.makeSingleFunc(args.onRelease)
  return args
end

local bindArg = {}
function Bind.asArg(arg) return setmetatable({arg = arg}, bindArg) end

local function checkCallable(elem, nextElem)
  local _, callableType = util.isCallable(elem)
  if callableType == "function" then
    return "function"
  elseif type(elem) == "table" or type(elem) == "userdata" then
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
  if type(args) ~= "table" and type(args) ~= "userdata" then 
    error("Invalid callback arguments", 4) 
  end
  if util.isFuncTable(args) then 
    args = {args} 
  end
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
  util.checkType(switch, PushPullSwitch, "push-pull switch", 4)
  return Bind._bindButton(switch._button)
end

function Bind._bindPull(switch)
  util.checkType(switch, PushPullSwitch, "push-pull switch", 4)
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