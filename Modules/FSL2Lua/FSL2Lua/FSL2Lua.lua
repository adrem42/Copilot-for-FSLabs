--- Library for interacting with FSLabs cockpit controls based on Lvars and mouse macros.
-- To import, type `local FSL = require 'FSL2Lua'`.
-- You don't need to do that in a file loaded by Copilot in the custom directory since FSL2Lua will already be included.
--
-- Click @{listofcontrols.md | here} to see the list of cockpit controls contained in the exported table.
-- @module FSL2Lua

if not FSL2LUA_STANDALONE 
  and not ipc.readLvar("AIRCRAFT_A319")
  and not ipc.readLvar("AIRCRAFT_A320")
  and not ipc.readLvar("AIRCRAFT_A321") then ipc.exit() end

local maf = require "FSL2Lua.libs.maf"
local file = require "FSL2Lua.FSL2Lua.file"
local ipc = ipc
local math = math
local FSUIPCversion = not FSL2LUA_STANDALONE and ipc.readUW(0x3306)
local copilot = type(copilot) == "table" and copilot.logger and copilot

local A319_IS_A320 = require "FSL2Lua.FSL2Lua.config".A319_IS_A320

local function handleError(msg, level, critical)
  level = level and level + 1 or 2
  msg = "FSL2Lua: " .. msg
  if copilot then
    local logFile = string.format("FSUIPC%s.log", ("%x"):format(FSUIPCversion):sub(1, 1))
    copilot.logger[critical and "error" or "warn"](copilot.logger, "FSL2Lua: something went wrong. Check " .. logFile)
    if critical then copilot.logger:error("Copilot cannot continue") end
  end
  if critical then
    error(msg, level)
  else
    local trace = debug.getinfo(level, "Sl")
    ipc.log(string.format("%s\r\nsource: %s:%s", msg, trace.short_src, trace.currentline))
  end
end

function checkWithTimeout(timeout, condition)
  timeout = ipc.elapsedtime() + (timeout or 5000)
  repeat 
    if condition() then return true end
  until ipc.elapsedtime() > timeout
  return false
end

function withTimeout(timeout, block)
  timeout = ipc.elapsedtime() + (timeout or 5000)
  repeat
    local val = block()
    if val ~= nil then return val end
  until ipc.elapsedtime() > timeout
end

function repeatWithTimeout(timeout, block)
  timeout = ipc.elapsedtime() + (timeout or 5000)
  repeat block() until ipc.elapsedtime() > timeout
end

local function handleControlTimeout(control, level)
  handleError ("Control " .. control.LVar .. " isn't responding to mouse macro commands\r\n" ..
              "Most likely its macro is invalid\r\n" ..
              "FSL2Lua version: " .. _FSL2LUA_VERSION ..
              "\r\nCheck compatibility at https://forums.flightsimlabs.com/index.php?/topic/25298-copilot-lua-script/&tab=comments#comment-194432", level + 1)
end

if not FSL2LUA_STANDALONE and FSUIPCversion < 0x5154 then
  handleError("FSUIPC version 5.154 or later is required", nil, true)
end

local FSL2LuaDir = debug.getinfo(1, "S").source:gsub(".(.*\\).*", "%1")
package.cpath = FSL2LuaDir .. "\\?.dll;" .. package.cpath
if not FSL2LUA_STANDALONE then require "FSL2LuaDLL" end
local elapsedTime = elapsedTime

--- @field CPT table containing controls on the left side
--- @field FO table containing controls on the right side
--- @field PF table containing controls on the side of the Pilot Flying
--- <br>For example, if the PF is the Captain, it will be the same as the CPT table.
--- <br>The controls on the PM side are in the root FSL table.
--- @usage FSL.GSLD_EFIS_VORADF_1_Switch("VOR")
--- @table FSL
local FSL = {CPT = {}, FO = {}, PF = {}}

if ipc.readLvar("AIRCRAFT_A319") == 1 then FSL.acType = "A319"
elseif ipc.readLvar("AIRCRAFT_A320") == 1 then FSL.acType = "A320"
elseif ipc.readLvar("AIRCRAFT_A321") == 1 then FSL.acType = "A321" end

local logFilePath = FSL2LuaDir .. "\\FSL2Lua.log"

local function log(msg, drawline, notimestamp)
  if not FSL.logging then return end
  local str = ""
  if drawline == 1 then
    str = "-------------------------------------------------------------------------------------------\n"
  end
  if not notimestamp then
    str = str .. os.date("[%H:%M:%S] - ")
  end
  file.write(logFilePath, str .. msg .. "\n")
end

local readUW = ipc.readUW
local function frameRate() return 32768 / readUW(0x0274) end

math.randomseed(os.time())

local function sleep(time1,time2)
  local time
  if time1 and time2 then
    time = math.random(time1,time2)
  elseif time1 then
    time = time1
  else
    time = 100
  end
  ipc.sleep(time)
end

---------------------------------------------------------------------------------------
-- Hand  ------------------------------------------------------------------------------
---------------------------------------------------------------------------------------

function prob(prob) return math.random() <= prob end

function plusminus(val, percent)
  percent = (percent or 0.2) * 100
  return val * math.random(100 - percent, 100 + percent) * 0.01
end

local function think(dist)
  local time = 0
  if dist > 200 and prob(0.2) then
    time = time + plusminus(300)
  end
  if prob(0.2) then time = time + plusminus(300) end
  if prob(0.05) then time = time + plusminus(1000) end
  if time > 0 then
    log("Thinking for " .. time .. " ms. Hmmm...")
    sleep(time)
  end
end

local hand = {}

function hand:init()
  if FSL.pilot == 1 then self.home = maf.vector(-70,420,70)
  elseif FSL.pilot == 2 then self.home = maf.vector(590,420,70) end
  self.pos = self.home
  self.timeOfLastMove = ipc.elapsedtime()
end

function hand:getSpeed(dist)
  log("Distance: " .. math.floor(dist) .. " mm")
  if dist < 80 then dist = 80 end
  local speed = 5.54785 + (-218.97685 / (1 + (dist / (3.62192 * 10^-19))^0.0786721))
  speed = plusminus(speed, 0.1) * 0.8
  log("Speed: " .. math.floor(speed * 1000) .. " mm/s")
  return speed
end

function hand:moveTo(newpos)
  if self.timeOfLastMove and ipc.elapsedtime() - self.timeOfLastMove > 5000 then
    self.pos = self.home
  end
  local dist = (newpos - self.pos):length()
  if self.pos ~= self.home and newpos ~= self.home and dist > 50 then 
    think(dist) 
  end
  local time
  local startTime = ipc.elapsedtime()
  if self.pos ~= newpos then
    time = dist / self:getSpeed(dist)
    if coroutine.running() and time > 100 then
      coroutine.yield()
    end
    sleep(time - (ipc.elapsedtime() - startTime))
    self.pos = newpos
    self.timeOfLastMove = ipc.elapsedtime()
  end
  return time or 0
end

---------------------------------------------------------------------------------------
-- MCDU -------------------------------------------------------------------------------
---------------------------------------------------------------------------------------

--- @type MCDU

local MCDU = {
  colors = {
    ["1"] = "cyan",
    ["2"] = "grey",
    ["4"] = "green",
    ["5"] = "magenta",
    ["6"] = "amber",
    ["7"] = "white",
  },
}

function MCDU:new(side)
  self.__index = self
  return setmetatable ({
    request = McduHttpRequest and McduHttpRequest:new(side, 8080),
    sideStr = side == 1 and "CPT" or side == 2 and "FO"
  }, self)
end

function MCDU:_onHttpError()
  handleError(string.format("%s MCDU HTTP request error %s, retrying...",
                            self.sideStr, self.request:lastError()), 3)
end

--- @treturn table Array of tables representing display cells.
--
--- Each cell table has three fields:
--
-- * char: the character (nil if the cell is blank)
-- * color: string : 
--    * 'cyan' 
--    * 'grey' 
--    * 'green' 
--    * 'magenta' 
--    * 'amber' 
--    * 'white' 
-- * isBold: bool

function MCDU:getArray()
    local response
    while true do
      response = self.request:getRaw()
      if response ~= "" then break
      else self:_onHttpError() end
    end
    local display = {}
    for unitArray in response:gmatch("%[(.-)%]") do
      local unit = {}
      if unitArray:find(",") then
        local char, color, isBold = unitArray:match("(%d+),(%d),(%d)")
        unit.char = string.char(char)
        unit.color = self.colors[color] or tonumber(color)
        unit.isBold = tonumber(isBold) == 0
      end
      display[#display+1] = unit
    end
    return display
end

--- @treturn string
--- @number[opt] startpos
--- @number[opt] endpos

function MCDU:getString(startpos, endpos)
  local display
  while true do
    display = self.request:getString()
    if display then break
    else self:_onHttpError() end
  end
  if startpos or endpos then
    return string.sub(display, startpos, endpos)
  else
    return display
  end
end

--- @treturn string Only the last line.

function MCDU:getScratchpad()
  return self:getString(313)
end

--- Types str on the keyboard.
---@string str

function MCDU:type(str)
  str = tostring(str)
  local _FSL = FSL[self.sideStr]
  for i = 1, #str do
    local chars = {
      [" "] = "SPACE",
      ["."] = "DOT",
      ["/"] = "SLASH",
      ["-"] = "PLUSMINUS"
    }
    local char = str:sub(i,i):upper()
    char = chars[char] or char
    if char == "+" then
      _FSL.PED_MCDU_KEY_PLUSMINUS()
      _FSL.PED_MCDU_KEY_PLUSMINUS()
    else
      _FSL["PED_MCDU_KEY_" .. char]()
    end
  end
end

--- @treturn bool False if the display is blank.

function MCDU:isOn()
  return self:getString():find("%S") ~= nil
end

--- Outputs information about each display cell: its index, character (including its numerical representation) and whether it's bold.
--
--- The output will be in the console and the FSUIPC log file.

function MCDU:printCells()
  for pos,cell in ipairs(self:getArray()) do
    print(pos, 
          cell.char and string.format("%s (%s)", cell.char, string.byte(cell.char)) or "", 
          cell.color or "", 
          cell.isBold and "bold" or cell.isBold == false and "not bold" or "")
  end
end

FSL.CPT.MCDU = MCDU:new(1)
FSL.FO.MCDU = MCDU:new(2)
MCDU.new = nil

---------------------------------------------------------------------------------------
-- FCU -------------------------------------------------------------------------------
---------------------------------------------------------------------------------------

local FCU = {request = HttpRequest and HttpRequest:new("http://localhost:8080/FCU/Display")}
FSL.FCU = FCU

function FCU:getField(json, fieldName)
  return json:match(fieldName .. ".-([%d%s]+)"):gsub(" ","")
end

function FCU:get()
  local json
  while true do
    json = self.request:get()
    if json ~= "" then break
    else handleError(string.format("FCU HTTP request error %s, retrying...", self.request.lastError), 2) end
  end
  local SPD = self:getField(json, "SPD")
  local HDG = self:getField(json, "HDG")
  local ALT = self:getField(json, "ALT")
  return {
    SPD = tonumber(SPD),
    HDG = tonumber(HDG),
    ALT = tonumber(ALT),
    isBirdOn = json:find("HDG_VS_SEL\":false") ~= nil
  } 
end

---------------------------------------------------------------------------------------
-- Control ----------------------------------------------------------------------------
---------------------------------------------------------------------------------------

--- Abstract control
--- @type Control

local Control = {
  clickTypes = {
    leftPress = 3,
    leftRelease = 13,
    rightPress = 1,
    rightRelease = 11,
    wheelUp = 14,
    wheelDown = 15
  },
  FSL_VC_control = true
}

function Control:new(control)
  control = control or {}
  if control.rectangle then
    control.rectangle = tonumber(control.rectangle)
  end
  self.__index = self
  if control.manual and not FSL2LUA_IGNORE_FAULTY_LVARS then
    control.getLvarValue = self.getLvarValueErr
  end
  return setmetatable(control, self)
end

--- Invokes the mouse macro directly
--- @string clickType One of the following:
--
-- * 'leftPress'
-- * 'leftRelease'
-- * 'rightPress'
-- * 'rightRelease'
-- * 'wheelUp'
-- * 'wheelDown'

function Control:macro(clickType)
  ipc.mousemacro(self.rectangle, self.clickTypes[clickType])
end

function Control:moveHandHere()
  local reachtime = hand:moveTo(self.pos)
  log(("Position of control %s : x = %s, y = %s, z = %s"):format(self.name , math.floor(self.pos.x), math.floor(self.pos.y), math.floor(self.pos.z)), 1)
  log("Control reached in " .. math.floor(reachtime) .. " ms")
end

function Control:interact(time)
  sleep(time)
  log("Interaction with the control took " .. time .. " ms")
end

--- <span>
--- @usage if not FSL.GSLD_EFIS_CSTR_Button:isLit() then
---   FSL.GSLD_EFIS_CSTR_Button()
--- end
--- @treturn bool True if the control has a light and it's on.
--
--- The control needs to have an LVar associated with its light for this to work.
--
--- Unfortunately, overhead-style square buttons don't have such LVars.

function Control:isLit()
  if not self.Lt then return end
  if type(self.Lt) == "string" then return ipc.readLvar(self.Lt) == 1 end
  return ipc.readLvar(self.Lt.Brt) == 1 or ipc.readLvar(self.Lt.Dim) == 1
end

--- @treturn number

function Control:getLvarValue() return ipc.readLvar(self.LVar) end

function Control:getLvarValueErr()
  error("The Lvar for control " .. self.name .. " doesn't work so you can't call functions that need to read the Lvar.")
end

function Control:waitForLVarChange(timeout, startPos)
  startPos = startPos or self:getLvarValue()
  return checkWithTimeout(timeout or 5000, function() 
    return self:getLvarValue() ~= startPos 
  end)
end

local hideCursor = hideCursor

---------------------------------------------------------------------------------------
-- Button -----------------------------------------------------------------------------
---------------------------------------------------------------------------------------

--- @type Button

local Button = Control:new()
Button.__class = "Button"

function Button:new(control)
  control = getmetatable(self):new(control)
  if control.LVar and control.LVar:find("MCDU") then control.interactionLength = 50 end
  self.__index = self
  return setmetatable(control, self)
end

function Button:_pressAndReleaseInternal(twoSwitches, pressClickType, releaseClickType)
  if FSL.areSequencesEnabled and not twoSwitches then
    self:moveHandHere()
  end
  local startTime = ipc.elapsedtime()
  local sleepAfterPress
  local LVarbefore = self:getLvarValue()
  ipc.mousemacro(self.rectangle, pressClickType or 3)
  if self.toggle then
    sleepAfterPress = 0
    ipc.mousemacro(self.rectangle, releaseClickType or 13)
  else
    local FPS = frameRate()
    sleepAfterPress = FPS > 30 and 100 or FPS > 20 and 150 or 200
    local timeout = 1000
    if twoSwitches then
      checkWithTimeout(timeout, function()
        coroutine.yield()
        return self:getLvarValue() ~= LVarbefore
      end)
      repeatWithTimeout(sleepAfterPress, coroutine.yield)
    else
      checkWithTimeout(timeout, function()
        return self:getLvarValue() ~= LVarbefore
      end)
      sleep(sleepAfterPress)
    end
    ipc.mousemacro(self.rectangle, releaseClickType or 13)
  end
  if FSL.areSequencesEnabled then
    local interactionLength = plusminus(self.interactionLength or 150) - ipc.elapsedtime() + startTime
    if twoSwitches then
      repeatWithTimeout(interactionLength, coroutine.yield)
    else
      sleep(interactionLength)
    end
    log("Interaction with the control took " .. interactionLength .. " ms")
  end
end

--- Presses the button.
--- @function __call
--- @usage FSL.OVHD_ELEC_BAT_1_Button()

function Button:__call()
  return self:_pressAndReleaseInternal()
end

--- Simulates a click of the right mouse button on the VC button.

function Button:rightClick() 
  return self:_pressAndReleaseInternal(false, 1, 11) 
end

--- @treturn bool True if the button is depressed.

function Button:isDown() return self:getLvarValue() == 10 end

---------------------------------------------------------------------------------------
-- Guard ------------------------------------------------------------------------------
---------------------------------------------------------------------------------------

--- @type Guard

local Guard = Control:new()
Guard.__class = "Guard"

--- <span>

function Guard:lift()
  if FSL.areSequencesEnabled then
    self:moveHandHere()
  end
  if not self:isOpen() then
    ipc.mousemacro(self.rectangle, 1)
    checkWithTimeout(5000, function() return self:isOpen() end)
  end
  if FSL.areSequencesEnabled then
    self:interact(plusminus(1000))
  end
end

--- <span>

function Guard:close()
  if FSL.areSequencesEnabled then
    self:moveHandHere()
  end
  if self:isOpen() then
    if self.toggle then
      ipc.mousemacro(self.rectangle, 1)
    else
      ipc.mousemacro(self.rectangle, 11)
    end
  end
  if FSL.areSequencesEnabled then
    self:interact(plusminus(500))
  end
end

--- @treturn bool

function Guard:isOpen() return self:getLvarValue() == 10 end

---------------------------------------------------------------------------------------
-- Switch -----------------------------------------------------------------------------
---------------------------------------------------------------------------------------

--- All controls that have named positions
--- @type Switch

local Switch = Control:new()
Switch.__class = "Switch"

function Switch:new(control)
  control = getmetatable(self):new(control)
  if control.orientation == 2 then -- right click to decrease, left click to increase
    control.incClickType = 3
    control.decClickType = 1
  else -- left click to decrease, right click to increase (most of the switches)
    control.incClickType = 1
    control.decClickType = 3
  end
  control.toggleDir = 1
  control.springLoaded = {}
  if control.posn then
    control.LVarToPosn = {}
    for k, v in pairs(control.posn) do
      if type(v) == "table" then
        v = v[1]
        control.springLoaded[v] = true
        control.posn[k] = v
      end
      control.LVarToPosn[v] = k:upper()
    end
  end
  self.__index = self
  return setmetatable(control, self)
end

function Switch:_moveInternal(targetPos, twoSwitches)
  local _targetPos, err = self:getTargetLvarVal(targetPos)
  if not _targetPos then error(err, 2) end
  if FSL.areSequencesEnabled and not twoSwitches then
    self:moveHandHere()
  end
  local currPos = self:getLvarValue()
  if currPos ~= _targetPos then
    if FSL.areSequencesEnabled and not twoSwitches then
      self:interact(plusminus(100))
    end
    return self:set(_targetPos, twoSwitches)
  end
end

--- @function __call
--- @usage FSL.GSLD_EFIS_VORADF_1_Switch("VOR")
--- @string targetPos

function Switch:__call(targetPos)
  return self:_moveInternal(targetPos)
end

function Switch:getTargetLvarVal(targetPos)
  if type(targetPos) ~= "string" then
    return nil, "targetPos must be a string"
  end
  local _targetPos = self.posn[tostring(targetPos):upper()]
  if not _targetPos then
    return nil, "Invalid targetPos: '" .. targetPos .. "'."
  end
  return _targetPos
end

function Switch:set(targetPos, twoSwitches)
  while true do
    local currPos = self:getLvarValue()
    if currPos < targetPos then
      self:increase()
    elseif currPos > targetPos then
      self:decrease()
    else
      if self.springLoaded[targetPos] then self.letGo = true end
      hideCursor()
      break
    end
    if FSL.areSequencesEnabled then
      local interactionLength = plusminus(self.interactionLength or 100)
      if twoSwitches then
        repeatWithTimeout(interactionLength, coroutine.yield)
        log("Interaction with the control took " .. interactionLength .. " ms")
      else
        self:interact(interactionLength)
      end
    end
    if not self:waitForLVarChange(1000, currPos) then
      handleControlTimeout(self, 3)
    end
  end
  if FSL.areSequencesEnabled and not twoSwitches then
    self:interact(plusminus(100))
  end
end

--- @treturn string Current position of the switch in uppercase.

function Switch:getPosn()
  return self.LVarToPosn[self:getLvarValue()]
end

function Switch:decrease()
  if self.FSControl then
    ipc.control(self.FSControl.dec)
  elseif self.letGo then
    ipc.mousemacro(self.rectangle, 13)
    ipc.mousemacro(self.rectangle, 11)
    self.letGo = false
  else
    ipc.mousemacro(self.rectangle, self.decClickType)
  end
end

function Switch:increase()
  if self.FSControl then
    ipc.control(self.FSControl.inc)
  elseif self.letGo then
    ipc.mousemacro(self.rectangle, 13)
    ipc.mousemacro(self.rectangle, 11)
    self.letGo = false
  else
    ipc.mousemacro(self.rectangle, self.incClickType)
  end
end

--- Cycles the switch back and forth.
--- @usage FSL.OVHD_EXTLT_Land_L_Switch:toggle()

function Switch:toggle()
  if self.maxLVarVal then
    local pos = self:getLvarValue()
    if pos == self.maxLVarVal then self.toggleDir = -1
    elseif pos == 0 then self.toggleDir = 1 end
    if self.toggleDir == 1 then self:increase()
    else self:decrease() end
  end
  hideCursor()
end

---------------------------------------------------------------------------------------
-- FcuSwitch --------------------------------------------------------------------------
---------------------------------------------------------------------------------------

--- Switches that can be pushed and pulled
--- @type FcuSwitch

local FcuSwitch = Control:new()
FcuSwitch.__class = "FcuSwitch"

--- <span>
function FcuSwitch:push()
  if FSL.areSequencesEnabled then
    self:moveHandHere()
  end
  ipc.mousemacro(self.rectangle, 3)
  ipc.sleep(100)
  ipc.mousemacro(self.rectangle, 13)
  if FSL.areSequencesEnabled then
    self:interact(plusminus(200))
  end
end

--- <span>
function FcuSwitch:pull()
  if FSL.areSequencesEnabled then
    self:moveHandHere()
  end
  ipc.mousemacro(self.rectangle, 1)
  ipc.sleep(100)
  ipc.mousemacro(self.rectangle, 11)
  if FSL.areSequencesEnabled then
    self:interact(plusminus(200))
  end
end

---------------------------------------------------------------------------------------
-- EngineMasterSwitch -----------------------------------------------------------------
---------------------------------------------------------------------------------------

--- @type EngineMasterSwitch
local EngineMasterSwitch = Switch:new()
EngineMasterSwitch.__call = getmetatable(EngineMasterSwitch).__call
EngineMasterSwitch.__class = "EngineMasterSwitch"

function EngineMasterSwitch:increase()
  ipc.mousemacro(self.rectangle, 1)
  self:waitForLVarChange()
  if FSL.areSequencesEnabled then
    self:interact(100)
  end
  ipc.mousemacro(self.rectangle, 3)
  self:waitForLVarChange()
  if FSL.areSequencesEnabled then
    self:interact(100)
  end
  ipc.mousemacro(self.rectangle, 11)
  ipc.mousemacro(self.rectangle, 13)
  self:waitForLVarChange()
end

EngineMasterSwitch.decrease = EngineMasterSwitch.increase

function EngineMasterSwitch:set(targetPos)
  local lvarVal = self:getLvarValue()
  if lvarVal == 10 or lvarVal == 20 then
    ipc.mousemacro(self.rectangle, 11)
    ipc.mousemacro(self.rectangle, 13)
    self:waitForLVarChange()
  end
  Switch.set(self, targetPos)
end

---------------------------------------------------------------------------------------
-- KnobWithoutPositions ---------------------------------------------------------------
---------------------------------------------------------------------------------------

--- Knobs with no fixed positions
--- @type KnobWithoutPositions

local KnobWithoutPositions = Switch:new()
KnobWithoutPositions.__class = "KnobWithoutPositions"

--- @function __call
--- @number targetPos Relative position from 0-100.
--- @usage FSL.OVHD_INTLT_Integ_Lt_Knob(42)

KnobWithoutPositions.__call = getmetatable(KnobWithoutPositions).__call

function KnobWithoutPositions:_rotateLeft()
  ipc.mousemacro(self.rectangle, 15)
end

function KnobWithoutPositions:_rotateRight()
  ipc.mousemacro(self.rectangle, 14)
end

--- Rotates the knob left by 1 tick.
function KnobWithoutPositions:rotateLeft()
  self:_rotateLeft()
  hideCursor() 
end

--- Rotates the knob right by 1 tick.
function KnobWithoutPositions:rotateRight()
  self:_rotateRight()
  hideCursor()
end

function KnobWithoutPositions:getTargetLvarVal(targetPos)
  if type(targetPos) ~= "number" then 
    return nil, "targetPos must be a number"
  end
  if targetPos > 100 then targetPos = 100
  elseif targetPos < 0 then targetPos = 0 end
  return self.range / 100 * targetPos
end

function KnobWithoutPositions:set(targetPos)
  local timeStarted = ipc.elapsedtime()
  local tolerance = (targetPos == 0 or targetPos == self.range) and 0 or 5
  local wasLower, wasGreater
  local tick = 1
  local currPos = self:getLvarValue()
  if self.prevTargetPos then
    if targetPos >= self.prevTargetPos and self.wasLower then
      wasLower = self.wasLower
    elseif targetPos < self.prevTargetPos and self.wasGreater then
      wasGreater = self.wasGreater
    end
  end
  while true do
    if math.abs(currPos - targetPos) > tolerance then
      if currPos < targetPos then
        if wasGreater then break end
        self:_rotateRight()
        wasLower = true
      elseif currPos > targetPos then
        if wasLower then break end
        self:_rotateLeft()
        wasGreater = true
      end
      if not self:waitForLVarChange(1000, currPos) then
        handleControlTimeout(self, 3)
        return
      end
    else
      break
    end
    if FSL.areSequencesEnabled and tick % 2 == 0 then
      sleep(1)
    end
    tick = tick + 1
    currPos = self:getLvarValue()
  end
  self.prevTargetPos = targetPos
  self.wasLower = wasLower
  self.wasGreater = wasGreater
  hideCursor()
  if FSL.areSequencesEnabled then 
    log("Interaction with the control took " .. ipc.elapsedtime() - timeStarted .. " ms") 
  end
  return currPos / self.range * 100
end

function KnobWithoutPositions:cycle(steps)
  steps = math.floor(steps)
  local step = 100 / steps
  local cycleVal = self.cycleVal or 0
  local curr = self:getPosn()
  if curr ~= self.prev then
    cycleVal = curr
  end
  if cycleVal == 100 then 
    self.cycleDir = false
  elseif cycleVal == 0 then 
    self.cycleDir = true 
  end
  if self.cycleDir then
    cycleVal = math.min(cycleVal + step, 100)
  else
    cycleVal = math.max(cycleVal - step, 0)
  end
  cycleVal = cycleVal - cycleVal % step
  self.prev = self(cycleVal) or self.prev
  self.cycleVal = cycleVal
end

--- @treturn number Relative position from 0-100.

function KnobWithoutPositions:getPosn()
  local val = self:getLvarValue()
  return (val / self.range) * 100
end

--- Rotates the knob by amount of ticks.
--- @number ticks positive to rotate right, negative to rotate left
--- @number[opt=70] pause milliseconds to sleep between each tick

function KnobWithoutPositions:rotateBy(ticks, pause)
  pause = pause or 70
  if FSL.areSequencesEnabled then
    self:moveHandHere()
    self:interact(300)
  end
  local startTime = ipc.elapsedtime()
  if ticks > 0 then
    for _ = 1, ticks do
      self:_rotateRight()
      if pause > 0 then
        sleep(plusminus(pause))
      end
    end
  elseif ticks < 0 then
    for _ = 1, -ticks do
      self:_rotateLeft()
      if pause > 0 then
        sleep(plusminus(pause))
      end
    end
  end
  if FSL.areSequencesEnabled then
    log("Interaction with the control took " .. (ipc.elapsedtime() - startTime) .. " ms")
  end
  hideCursor()
end

--- Sets the knob to random position between lower and upper.
--- @number[opt=0] lower
--- @number[opt=100] upper

function KnobWithoutPositions:random(lower, upper)
  self(math.random(lower or 0, upper or 100))
end

---------------------------------------------------------------------------------------
-- Misc functions ---------------------------------------------------------------------
---------------------------------------------------------------------------------------

function moveTwoSwitches(switch1,pos1,switch2,pos2,chance)
  if prob(chance or 1) then
    hand:moveTo((switch1.pos + switch2.pos) / 2)
    sleep(plusminus(100))
    local co1 = coroutine.create(function() 
      switch1:_moveInternal(pos1, true) 
    end)
    local co2 = coroutine.create(function() 
      sleep(plusminus(30))
      switch1:_moveInternal(pos2, true) 
    end)
    repeat
      local done1 = not coroutine.resume(co1)
      sleep(1)
      local done2 = not coroutine.resume(co2)
    until done1 and done2
  else
    switch1(pos1)
    switch2(pos2)
    sleep(plusminus(100))
  end
end

function pressTwoButtons(butt1, butt2, chance)
  if prob(chance or 1) then
    hand:moveTo((butt1.pos + butt1.pos) / 2)
    sleep(plusminus(200,0.1))
    local co1 = coroutine.create(function() 
      butt1:_pressAndReleaseInternal(true) 
    end)
    local co2 = coroutine.create(function() 
      sleep(1)
      butt1:_pressAndReleaseInternal(true) 
    end)
    repeat
      local done1 = not coroutine.resume(co1)
      sleep(1)
      local done2 = not coroutine.resume(co2)
    until done1 and done2
  else
    butt1()
    butt2()
  end
end

function FSL:getAcType()
  return self.acType
end

---This makes references in the root FSL table to all fields in either FSL.CPT or FSL.FO, if the 'pilot' parameter is 1 or 2, respectively. For the other side's controls, it makes
---references in the FSL.PF table.
--
---Copilot will set it depending on the 'PM_seat' option.
---@within FSL
---@usage
-- local FSL = require "FSL2Lua"
--
-- print(FSL.MCDU) -- nil
-- print(FSL.GSLD_Chrono_Button) -- nil
--
-- FSL:setPilot(1)
--
-- print(FSL.MCDU:getString() == FSL.CPT.MCDU:getString()) -- true
-- print(FSL.GSLD_Chrono_Button == FSL.CPT.GSLD_Chrono_Button) -- true
-- print(FSL.PF.MCDU:getString() == FSL.FO.MCDU:getString()) -- true
-- print(FSL.PF.GSLD_Chrono_Button == FSL.FO.GSLD_Chrono_Button) -- true
function FSL:setPilot(pilot)
  if pilot ~= 1 and pilot ~=2 and pilot ~= "CPT" and pilot ~= "FO" then
    error("'pilot' must be either 1, 2, 'CPT' or 'FO'.", 2)
  end
  if pilot == "CPT" then pilot = 1
  elseif pilot == "FO" then pilot = 2 end
  self.pilot = pilot
  for controlName, control in pairs(self) do
    if type(control) == "table" and control.side then
      self[controlName] = nil
    end
  end
  for controlName,control in pairs(self.CPT) do
    if pilot == 1 then self[controlName] = control
    elseif pilot == 2 then self.PF[controlName] = control end
  end
  for controlName,control in pairs(self.FO) do
    if pilot == 2 then self[controlName] = control
    elseif pilot == 1 then self.PF[controlName] = control end
  end
  do
    local pos = self.trimwheel.pos
    pos.x = pilot == 1 and 90 or pilot == 2 and 300
    self.trimwheel.pos = maf.vector(pos.x, pos.y, pos.z)
  end
  hand:init()
end

function FSL:getPilot()
  return self.pilot
end

function FSL:enableLogging(startNewLog)
  self.logging = true
  if not ipc.get("FSL2LuaLog") or startNewLog then
    file.create(logFilePath)
    ipc.set("FSL2LuaLog", 1)
  end
end

function FSL:disableLogging()
  self.logging = false
end

function FSL:enableSequences()
  self.areSequencesEnabled = true
end

function FSL:disableSequences()
  self.areSequencesEnabled = false
end

function FSL:setHttpPort(port)
  port = tonumber(port)
  self.CPT.MCDU.request:setPort(port)
  self.FO.MCDU.request:setPort(port)
  self.FCU.request:setPort(port)
end

local TL_posns = {
  REV_MAX = 199,
  REV_IDLE = 129,
  IDLE = 0,
  CLB = 25,
  FLX = 35,
  TOGA = 45
}

function FSL:getThrustLeversPos(TL)
  local pos = TL == 1 and ipc.readLvar("VC_PED_TL_1") or TL == 2 and ipc.readLvar("VC_PED_TL_2")
  for k,v in pairs(TL_posns) do
    if pos and math.abs(pos - v) < 4 then
      return k
    elseif not pos and math.abs(ipc.readLvar("VC_PED_TL_1")  - v) < 4 and math.abs(ipc.readLvar("VC_PED_TL_2")  - v) < 4 then
      return k
    end
  end
  return pos or (ipc.readLvar("VC_PED_TL_1") + ipc.readLvar("VC_PED_TL_2")) / 2
end

function FSL:setTakeoffFlaps(setting)
  setting = setting or self:getTakeoffFlapsFromMcdu() or self.atsuLog:getTakeoffFlaps()
  if setting then self.PED_FLAP_LEVER(tostring(setting)) end
  return setting
end

function FSL:startTheApu()
  if not self.OVHD_APU_Master_Button:isDown() then
    self.OVHD_APU_Master_Button()
  end
  sleep(plusminus(3000,0.2))
  self.OVHD_APU_Start_Button()
end

function FSL:getTakeoffFlapsFromMcdu(side)
  side = side or self.pilot
  local sideStr = side == 1 and "CPT" or side == 2 and "FO"
  self[sideStr].PED_MCDU_KEY_PERF()
  sleep(500)
  return withTimeout(5000, function()
    local disp = self.MCDU:getString()
    if disp:sub(10,17) == "TAKE OFF" or disp:sub(5,16) == "TAKE OFF RWY" then
      local setting = disp:sub(162,162)
      sleep(plusminus(1000))
      self[sideStr].PED_MCDU_KEY_FPLN()
      return tonumber(setting)
    end
    sleep()
  end)
end

---------------------------------------------------------------------------------------
-- Trim wheel -------------------------------------------------------------------------
---------------------------------------------------------------------------------------

local trimwheel = {
  control = {inc = 65607, dec = 65615},
  pos = {y = 500, z = 70},
  LVar = "VC_PED_trim_wheel_ind",
}

FSL.trimwheel = trimwheel

function trimwheel:getInd()
  sleep(5)
  local CG_ind = ipc.readLvar(self.LVar)
  if FSL:getAcType() == "A320" then
    if CG_ind <= 1800 and CG_ind > 460 then
      CG_ind = CG_ind * 0.0482226 - 58.19543
    else
      CG_ind = CG_ind * 0.1086252 + 28.50924
    end
  elseif FSL:getAcType() == "A319" then
    if CG_ind <= 1800 and CG_ind > 460 then
      CG_ind = CG_ind * 0.04687107 - 53.76288
    else
      CG_ind = CG_ind * 0.09844237 + 30.46262
    end
  elseif FSL:getAcType() == "A321" then
    if CG_ind <= 1800 and CG_ind > 460 then
      CG_ind = CG_ind * 0.04228 - 48.11
    else
      CG_ind = CG_ind * 0.09516 + 27.97
    end
  end
  return CG_ind
end

function trimwheel:set(CG, step)
  local CG_man
  if CG then CG_man = true else CG = FSL.atsuLog:getMACTOW() or ipc.readDBL(0x2EF8) * 100 end
  if not CG then return
  else CG = tonumber(CG) end
  if not step then
    if not CG_man and prob(0.1) then sleep(plusminus(10000,0.5)) end
    log("Setting the trim. CG: " .. CG, 1)
    if areSequencesEnabled then
      local reachtime = hand:moveTo(self.pos)
      log(("Position of the trimwheel: x = %s, y = %s, z = %s"):format(math.floor(self.pos.x), math.floor(self.pos.y), math.floor(self.pos.z)))
      log("Trim wheel reached in " .. math.floor(reachtime) .. " ms")
    end
  end
  sleep(plusminus(1000))
  repeat
    local CG_ind = self:getInd()
    local dist = math.abs(CG_ind - CG)
    local speed = plusminus(0.2)
    if step then speed = plusminus(0.07) end
    local time = math.ceil(1000 / (dist / speed))
    if time < 40 then time = 40
    elseif time > 1000 then time = 1000 end
    if step and time > 70 then time = 70 end
    if CG > CG_ind then
      if dist > 3.1 then self:set(CG_ind + 3,1) sleep(plusminus(350,0.2)) end
      ipc.control(self.control.inc)
      sleep(time - 5)
    elseif CG < CG_ind then
      if dist > 3.1 then self:set(CG_ind - 3,1) sleep(plusminus(350,0.2)) end
      ipc.control(self.control.dec)
      sleep(time - 5)
    end
    local trimIsSet = math.abs(CG - CG_ind) <= (step and 0.5 or 0.2)
  until trimIsSet
  return CG
end

local atsuLog = {
  path = not FSL2LUA_STANDALONE and ipc.readSTR(0x3C00, 256):gsub("FSLabs\\SimObjects.+", "FSLabs\\" .. FSL:getAcType() .. "\\Data\\ATSU\\ATSU.log")
}

FSL.atsuLog = atsuLog

function atsuLog:get()
  return file.read(self.path)
end

function atsuLog:getMACTOW()
  return tonumber(self:get():match(".+MACTOW%s+(%d+%.%d+)"))
end

function atsuLog:getTakeoffPacks()
  local packs = self:get():match(".+PACKS%s+(%a+)")
  return packs == "OFF" and 0 or packs == "ON" and 1
end

function atsuLog:getTakeoffFlaps()
  return self:get():match(".+%(F/L%).-FLAPS.-(%d)\n")
end

function atsuLog:test()
  self.path = self.path:gsub("ATSU.log", "test.log")
end

---------------------------------------------------------------------------------------
-- Bind helper functions --------------------------------------------------------------
---------------------------------------------------------------------------------------

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

local keyBind = {}

function keyBind:new(data)
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

local function assert(val, msg, level)
  if not val then error(msg, level and level + 1) end
end

function keyBind:prepareData(data)
  assert(type(data.key) == "string", "The key combination must be a string", 4)
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
        keys.key = string.byte(key) or error("Not a valid key", 4)
      end
    end
  end
  assert(keyCount ~= #shifts, "Can't have only modifier keys", 4)
  assert(keyCount - #shifts == 1, "Can't have more than one non-modifier key", 4)
  if #shifts > 0 then
    keys.shifts = shifts
  end
  data.key = nil
  data.keys = keys
  return data
end

function keyBind:registerOnPressEvents()
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
      self.isPressed = true
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

function keyBind:registerOnReleaseEvents()
  local key = self.data.keys.key
  local shifts = self.data.keys.shifts
  if shifts then
    local onRelease = self.data.onRelease
    self.data.onRelease = function()
      if self.isPressed then
        self.isPressed = false
        onRelease()
      end
    end
    event.key(key, nil, 2, Bind:addGlobalFuncs(function()
      if self.isPressed then
        self.data.onRelease()
      end
    end))
  else
    if not self.data.onPress then
      event.key(key, 8, 1, Bind:addGlobalFuncs(function()
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

local joyBind = {}

function joyBind:new(data)
  self.__index = self
  local bind = setmetatable({}, self)
  bind.data = bind:prepareData(data)
  if bind.data.onPress then
    bind:registerOnPressEvents()
  end
  if bind.data.onRelease or bind.data.Repeat then
    bind:registerOnReleaseEvents()
  end
  return bind
end

function joyBind:prepareData(data)
  assert(type(data.btn) == "string", "Wrong joystick button format", 4)
  data.joyLetter = data.btn:sub(1,1)
  data.btnNum = tostring(data.btn:sub(2, #data.btn))
  data.btn = nil
  assert(data.joyLetter:find("%A") == nil, "Wrong joystick button format", 4)
  assert(tostring(data.btnNum):find("%D") == nil, "Wrong joystick button format", 4)
  return data
end

function joyBind:registerOnPressEvents()
  if self.data.Repeat then
    self.data.timerFuncName = Bind:addGlobalFuncs(function()
      self.data.onPress()
    end)
    event.button(self.data.joyLetter, self.data.btnNum, 1, Bind:addGlobalFuncs(function()
      event.timer(20, self.data.timerFuncName)
      self.isPressed = true
      self.data.onPress()
    end))
  else
    event.button(self.data.joyLetter, self.data.btnNum, 1, Bind:addGlobalFuncs(self.data.onPress))
  end
end

function joyBind:registerOnReleaseEvents()
  local funcName
  if self.data.Repeat and not self.data.onRelease then
    funcName = Bind:addGlobalFuncs(function()
      self.isPressed = false
      event.cancel(self.data.timerFuncName)
    end)
  elseif self.data.Repeat and self.data.onRelease then
    funcName = Bind:addGlobalFuncs(function()
      self.isPressed = false
      self.data.onRelease()
    end)
  elseif self.data.onRelease then
    funcName = Bind:addGlobalFuncs(self.data.onRelease)
  end
  event.button(self.data.joyLetter, self.data.btnNum, 2, funcName)
end

---------------------------------------------------------------------------------------
-- Main Bind function -----------------------------------------------------------------
---------------------------------------------------------------------------------------

Bind = {
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
  assert(data.key or data.btn, "You need to specify a key and/or button", 2)
  data = self:prepareData(data)
  local _keyBind = data.key and keyBind:new(data)
  local _joyBind = data.btn and joyBind:new(data)
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
  assert(type(func) == "function", "The argument must be a function.")
  return setmetatable({f = func}, bindArg)
end

function Bind:makeSingleFunc(funcs)
  local errLevel = 4

  if type(funcs) == "function" then return funcs end

  if type(funcs) ~= "table" then 
    error("Invalid callback parameter", errLevel) 
  end

  if funcs.__call or (getmetatable(funcs) and getmetatable(funcs).__call) then
    return funcs
  end
  
  local _funcs = funcs
  funcs = {}

  local function parse(i, prevArgs)
    
    local callable, elem

    while i <= #_funcs do

      elem = _funcs[i]

      if type(elem) == "function" then
        callable = "func"
      elseif type(elem) == "table" then
        local nextElem = _funcs[i+1]
        if type(elem[nextElem]) == "function" then
          callable = "method"
        else
          local mt = getmetatable(elem)
          if mt == bindArg then
            elem = elem.f
          elseif type(mt) == "table" and type(mt.__call) == "function" then
            callable = "__call"
          end
        end
      end

      if callable then
        break
      elseif i == 1 then
        error("The first element in the table must be callable", errLevel + 1)
      else 
        prevArgs[#prevArgs+1] = elem
      end

      i = i + 1
    end

    if elem == nil then return end

    if callable then

      local args = {}

      if i < #_funcs then
        if callable == "method" then
          args[1] = elem
          parse(i+2, args)
        else
          parse(i+1, args)
        end
      end

      if callable == "__call" and elem.FSL_VC_control then
        local class = getmetatable(elem)
        local arg = args[1]
        if not arg and (class == KnobWithoutPositions or class == Switch) then
          error("A position must be specified for control " .. elem.name .. ".", errLevel + 1)
        end
        if class == KnobWithoutPositions then
          assert(
            type(arg) == "number",
            "The position for control " .. elem.name .. " must be a number.", errLevel + 1
          )
        end
        if class == Switch then
          assert(
            type(arg) == "string",
            "The position for control " .. elem.name .. " must be a string.", errLevel + 1
          )
          assert(
            elem.posn[arg:upper()] ~= nil,
            arg .. " is not a valid position of control " .. elem.name .. ".",
            errLevel + 1
          )
        end
      end

      local func

      if callable == "method" then 
        elem = elem[_funcs[i+1]]
      end

      if #args == 0 then 
        func = elem
      elseif #args == 1 then 
        local arg = args[1]
        func = function() elem(arg) end
      else
        func = function() elem(unpack(args)) end
      end

      funcs[#funcs+1] = func
    end
  end

  parse(1, {})

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

if getmetatable(Joystick) then

  getmetatable(Joystick).printDeviceInfo = function()
    print "------------------------------------"
    print "-------  HID device info  ----------"
    print "------------------------------------"
    for _, device in ipairs(Joystick.enumerateDevices()) do
      print("Manufacturer: " .. device.manufacturer)
      print("Product: " .. device.product)
      print(string.format("Vendor ID: 0x%04X", device.vendorId))
      print(string.format("Product ID: 0x%04X", device.productId))
      print "------------------------------------"
    end
  end

  getmetatable(Joystick).fastRepeat = function(func, calc)
    local lastExecutionTime = 0
    local function callback(timeStamp)
      local n = calc(timeStamp - lastExecutionTime)
      lastExecutionTime = timeStamp
      for _ = 1, n do func() end
    end
    return callback, Joystick.withTimestamp
  end
end

---------------------------------------------------------------------------------------
-- Encoder ----------------------------------------------------------------------------
---------------------------------------------------------------------------------------

Encoder = {
  _onCW   = function () end,
  _onCCW  = function () end,
  DIR_CW = 0,
  DIR_CCW = 1
}

function Encoder.new(joy, data)

  if type(data[1]) ~= "number" or type(data[2]) ~= "number" then
    error("Specify two button numbers for the encoder", 2)
  end

  local DPC = data.detentsPerCycle

  if DPC == nil then
    error("Missing detentsPerCycle argument", 2)
  end

  if DPC ~= 1 and DPC ~= 2 and DPC ~= 4 then
    error("detentsPerCycle must be either 1, 2 or 4", 2)
  end

  local shift = 0

  if data.shift == true then
    if DPC == 1 then shift = 2
    elseif DPC == 2 then shift = 1 end
  end

  local e = {
    _pinA = data[1],
    _pinB = data[2],
    _prevStateA = false,
    _prevStateB = false,
    _detentRatio = 4 / DPC,
    _count = 0,
    _shift = shift,
    _direction = Encoder.DIR_CW
  }

  local function callback(button, state, timestamp)
    e:_onPinEvent(button, state, timestamp)
  end

  joy:onPress   (data[1], callback, Joystick.sendEventDetails)
  joy:onPress   (data[2], callback, Joystick.sendEventDetails)
  joy:onRelease (data[1], callback, Joystick.sendEventDetails)
  joy:onRelease (data[2], callback, Joystick.sendEventDetails)

  Encoder.__index = Encoder
  return setmetatable(e, Encoder)
end

function Encoder:setTickCalculator(tickCalculator)
  self._calculateTicks = tickCalculator
  return self
end

function Encoder:_makeCallback(...)

  local func = Bind:makeSingleFunc {...}

  if not self._calculateTicks then
    return function() func() end
  end

  local prevTimestamp = 0

  return function(timestamp)
    local diff = timestamp - prevTimestamp
    prevTimestamp = timestamp
    local numTicks = self._calculateTicks(diff)
    for _ = 1, numTicks do
      func()
    end
  end
end

function Encoder:onCW(...)
  self._onCW = self:_makeCallback(...)
  return self
end

function Encoder:onCCW(...)
  self._onCCW = self:_makeCallback(...)
  return self
end

function Encoder:_calculateDirection(this, thisPrev, other)
  if this and not thisPrev then
    return other and self.DIR_CCW or self.DIR_CW
  else
    return other and self.DIR_CW or self.DIR_CCW
  end
end

function Encoder:_onPinEvent(pin, state, timestamp)
  state = state == 1
  local direction, other
  if pin == self._pinA then
    other = self._prevStateB
    direction = self:_calculateDirection(state, self._prevStateA, other)
    self._prevStateA = state
  else
    other = self._prevStateA
    direction = self:_calculateDirection(state, self._prevStateB, not other)
    self._prevStateB = state
  end
  if not state and not other then
    self._count = 0
  else
    self._count = (self._count + 1) % 4
  end
  self._direction = direction
  if (self._count + self._shift) % self._detentRatio == 0 then
    if direction == self.DIR_CW then
      self._onCW(timestamp)
    else
      self._onCCW(timestamp)
    end
  end
end

---------------------------------------------------------------------------------------
-- Initializaion of controls ----------------------------------------------------------
---------------------------------------------------------------------------------------

local rawControls = require "FSL2Lua.FSL2Lua.FSL"

local function initControlPositions(varname,control)
  local pos = control.pos
  local mirror = {
    MCDU_R = "MCDU_L",
    COMM_2 = "COMM_1",
    RADIO_2 = "RADIO_1"
  }
  for k,v in pairs(mirror) do
    if varname:find(k) then
      pos = rawControls[varname:gsub(k,v)].pos
      if pos.x and pos.x ~= "" then
        pos.x = tonumber(pos.x) + 370
      end
    end
  end
  pos = maf.vector(tonumber(pos.x), tonumber(pos.y), tonumber(pos.z))
  local ref = {
    --0,0,0 is at the bottom left corner of the pedestal's top side
    OVHD = {maf.vector(39, 730, 1070), 2.75762}, -- bottom left corner (the one that is part of the bottom edge)
    MIP = {maf.vector(0, 792, 59), 1.32645}, -- left end of the edge that meets the pedestal
    GSLD = {maf.vector(-424, 663, 527), 1.32645} -- bottom left corner of the panel with the autoland button
  }
  for section,refpos in pairs(ref) do
    if control.LVar:find(section) then
      local r = maf.rotation.fromAngleAxis(refpos[2], 1, 0, 0)
      pos = pos:rotate(r) + refpos[1]
    end
  end
  return pos
end

local function initControl(control, varname)

  control.pos = initControlPositions(varname,control)

  if control.posn then
    local temp = control.posn
    control.posn = {}
    for k,v in pairs(temp) do
      control.posn[k:upper()] = v
    end
    local maxLVarVal = 0
    for _, v in pairs(control.posn) do
      if type(v) == "table" then v = v[1] end
      v = tonumber(v)
      if v > maxLVarVal then maxLVarVal = v end
    end
    control.maxLVarVal = maxLVarVal
  end

  do
    local name = control.LVar:lower()
    local _type = control.type:lower()
    if _type == "unknown" then
      control = Control:new(control)
    elseif _type == "enginemasterswitch" then
      control = EngineMasterSwitch:new(control)
    elseif _type == "fcuswitch" then
      control = FcuSwitch:new(control)
    elseif name:find("knob") and not control.posn then
      control = KnobWithoutPositions:new(control)
    elseif control.posn then
      control = Switch:new(control)
    elseif name:find("guard") then
      control = Guard:new(control)
    elseif name:find("button") or name:find("switch") or name:find("mcdu") or name:find("key") then
      control = Button:new(control)
    else
      control = Control:new(control)
    end
    if not control.checkMacro and not FSL2LUA_IGNORE_UNCHECKED then
      control = nil
    end
  end

  if control then
    
    local replace = {
      CPT = {
        MCDU_L = "MCDU",
        COMM_1 = "COMM",
        RADIO_1 = "RADIO",
        _CP = ""
      },
      FO = {
        MCDU_R = "MCDU",
        COMM_2 = "COMM",
        RADIO_2 = "RADIO",
        _FO = ""
      }
    }
    for pattern, replace in pairs(replace.CPT) do
      if varname:find(pattern) then
        if pattern == "_CP" and varname:find("_CPT") then pattern = "_CPT" end
        controlName = varname:gsub(pattern,replace)
        FSL.CPT[controlName] = control
        control.name = "FSL.CPT." .. controlName
        control.side = "CPT"
      end
    end
    for pattern, replace in pairs(replace.FO) do
      if varname:find(pattern) then
        controlName = varname:gsub(pattern,replace)
        FSL.FO[controlName] = control
        control.name = "FSL.FO." .. controlName
        control.side = "FO"
      end
    end

    if not control.side then
      FSL[varname] = control
      control.name = "FSL." .. varname
    end

  end
end

local function initControls()
  for varname, control in pairs(rawControls) do
    local acType = FSL.acType
    if acType == "A319" and A319_IS_A320 then
      acType = "A320"
    end
    if acType then
      control.rectangle = control[acType].rectangle
      if control.rectangle or control.FSControl then
        initControl(control, varname)
        control.manual = control[acType].manual
      end
    elseif MAKE_CONTROL_LIST then
      initControl(control, varname)
    end
  end
end

---------------------------------------------------------------------------------------
-- Macro checking ---------------------------------------------------------------------
---------------------------------------------------------------------------------------

function FSL.CheckMacros()

  local checked = {}
  local missing = {}
  local manual = {}
  local notManual = {}

  local acType = FSL.acType

  if acType == "A319" and A319_IS_A320 then
    acType = "A320"
  end

  local function checkControl(control)
    if type(control) == "table" and control.FSL_VC_control and control.checkMacro then
      if control.rectangle then
        if not control:checkMacro() then
          if control[acType].manual then
            table.insert(manual, control)
          else
            print("The macro of control " .. control.name .. " appears to be invalid")
          end
        elseif control[acType].manual then
          table.insert(notManual, control)
        end
      elseif not control.FSControl then
        table.insert(missing, control)
      end
    end
  end

  local function checkMacros(table)
    for _, control in pairs(table) do
      if type(control) == "table" and control.LVar and control.LVar:lower():find("guard") then
        checkControl(control)
        checked[control] = true
      end
    end

    for _, control in pairs(table) do
      if not checked[control] then checkControl(control) end
    end
  end

  print "------------------------------------------------------"
  print "Checking macros!"

  for _, button in ipairs {FSL.OVHD_FIRE_ENG1_PUSH_Button, FSL.OVHD_FIRE_ENG2_PUSH_Button, FSL.OVHD_FIRE_APU_PUSH_Button} do
    if not button:isDown() then
      checkControl(button)
    end
  end

  checkMacros(FSL)
  checkMacros(FSL.CPT)
  checkMacros(FSL.FO)

  print "Finished checking macros!"

  if #manual > 0 then
    print("The following controls need to be checked manually for this type (" .. acType .. "):\n")
    for _, control in ipairs(manual) do
      print(control.name)
    end
  end

  if #notManual > 0 then
    print("The following are no longer manual for this type (" .. acType .. "):\n")
    for _, control in ipairs(notManual) do
      print(control.name)
    end
  end

end

function Button:checkMacro()
  local t
  for _, _t in ipairs{FSL, FSL.CPT, FSL.FO} do
    for _, control in pairs(_t) do
      if control == self then 
        t = _t 
        break
      end
    end
  end

  local guard = self.guard and t[self.guard]
  if not guard then
    for _, control in pairs(t) do
      if type(control) == "table" and control.FSL_VC_control then
        local LVar = control.LVar:lower()
        if LVar:find("guard") and LVar:find(self.LVar:lower():gsub("(.+)_.+","%1")) then
          guard = control
          break
        end 
      end
    end
  end

  if guard and not guard:isOpen() then
    guard:lift()
    local timedOut = not checkWithTimeout(2000, function()
      return guard:isOpen()
    end)
    if timedOut then return false end
  end

  local LVarbefore = self:getLvarValue()
  ipc.mousemacro(self.rectangle, 3)
  if self.toggle then
    ipc.mousemacro(self.rectangle, 13)
  end
  local timedOut = not self:waitForLVarChange(2000, LVarbefore)
  if not timedOut then ipc.mousemacro(self.rectangle, 13) end
end

function Guard:checkMacro()
  local LVarbefore = self:getLvarValue()
  if self:isOpen() then self:close()
  else self:lift() end
  return self:waitForLVarChange(2000, LVarbefore)
end

function Switch:checkMacro()
  local LVarbefore = self:getLvarValue()
  if LVarbefore > 0 then self:decrease()
  else self:increase() end
  return self:waitForLVarChange(5000, LVarbefore)
end

function FcuSwitch:checkMacro()
  ipc.mousemacro(self.rectangle, 13)
  ipc.mousemacro(self.rectangle, 11)
  local LVarbefore = self:getLvarValue()
  ipc.mousemacro(self.rectangle, 3)
  return self:waitForLVarChange(5000, LVarbefore)
end

function EngineMasterSwitch:checkMacro()
  ipc.mousemacro(self.rectangle, 13)
  ipc.mousemacro(self.rectangle, 11)
  local LVarbefore = self:getLvarValue()
  ipc.mousemacro(self.rectangle, 1)
  return self:waitForLVarChange(1000, LVarbefore)
end

function KnobWithoutPositions:checkMacro()
  if self.LVar:lower():find("comm") then
    local t
    for _, _t in ipairs{FSL, FSL.CPT, FSL.FO} do
      for _, control in pairs(_t) do
        if control == self then t = _t end
      end
    end
    for _, control in pairs(t) do
      if type(control) == "table" and control.FSL_VC_control then
        local LVar = control.LVar:lower()
        local switch = LVar:find("switch") and LVar:find(self.LVar:lower():gsub("(.+)_.+","%1"))
        if switch and control.isDown and control:isDown() then
          control()
          local timedOut = not checkWithTimeout(2000, function()
            return not control:isDown()
          end)
          if timedOut then return false end
          break
        end
      end
    end
  end
  local LVarbefore = self:getLvarValue()
  if LVarbefore > 0 then self:_rotateLeft()
  else self:_rotateRight() end
  return self:waitForLVarChange(1000, LVarbefore)
end

---------------------------------------------------------------------------------------
-- The end ----------------------------------------------------------------------------
---------------------------------------------------------------------------------------

initControls()

FSL.MIP_GEAR_Lever = FSL.GEAR_Lever

collectgarbage "collect"

return FSL