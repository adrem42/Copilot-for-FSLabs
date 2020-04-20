--- You can use this library in any script. To import, type `local FSL = require 'FSL2Lua'`
-- Click @{listofcontrols.md | here} to see the list of cockpit controls contained in the returned FSL table.
-- @module FSL2Lua

local maf = require "FSL2Lua.libs.maf"
local file = require "FSL2Lua.FSL2Lua.file"
local ipc = ipc
local math = math

local FSL2LuaDir = debug.getinfo(1, "S").source:gsub(".(.*\\).*", "%1")
package.cpath = FSL2LuaDir .. "\\?.dll;" .. package.cpath
require "FSL2LuaDLL"

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

function prob(prob) return math.random() <= prob end

function plusminus(val, percent)
  percent = (percent or 0.2) * 100
  return val * math.random(100 - percent, 100 + percent) * 0.01
end

local function think(dist)
  local time = 0
  if dist > 200 then
    time = time + plusminus(300)
    if prob(0.5) then time = time + plusminus(300) end
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
  speed = plusminus(speed, 0.1)
  log("Speed: " .. math.floor(speed * 1000) .. " mm/s")
  return speed
end

function hand:moveTo(newpos)
  if self.timeOfLastMove and ipc.elapsedtime() - self.timeOfLastMove > 5000 then
    self.pos = self.home
  end
  local dist = (newpos - self.pos):length()
  if self.pos ~= self.home and newpos ~= self.home and dist > 50 then think(dist) end
  local time
  if self.pos ~= newpos then
    time = dist / self:getSpeed(dist)
    local startTime = ipc.elapsedtime()
    if coroutine.running() and time > 100 then
      coroutine.yield()
    end
    sleep(time - (ipc.elapsedtime() - startTime))
    self.pos = newpos
    self.timeOfLastMove = ipc.elapsedtime()
  end
  return time or 0
end

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
    request = HttpRequest:new("", 8080, "MCDU/Display/3CA" .. side),
    sideStr = side == 1 and "CPT" or side == 2 and "FO"
  }, self)
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
    local display = {}
    for unitArray in self.request:get():gmatch("%[(.-)%]") do
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
  local display = {}
  for cell in self.request:get():gmatch("%[(.-)%]") do
    local char = cell:match("(%d+),")
    char = char and string.char(char) or " "
    display[#display+1] = char
  end
  return table.concat(display, nil, startpos, endpos)
end

--- @treturn string Only the last line.

function MCDU:getScratchpad()
  return self:getString(313)
end

--- Types str on the keyboard.
---@string str

function MCDU:type(str)
  str = tostring(str)
  local FSL = FSL[self.sideStr]
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
      FSL.PED_MCDU_KEY_PLUSMINUS()
      FSL.PED_MCDU_KEY_PLUSMINUS()
    else
      FSL["PED_MCDU_KEY_" .. char]()
    end
  end
end

--- @treturn bool True if the display is blank.

function MCDU:isOn()
  return self:getString():find("%S") ~= nil
end

--- Prints information about each cell into the console.

function MCDU:printCells()
  for pos,cell in ipairs(self:getArray()) do
    local isBold = cell.isBold and "bold" or cell.isBold == false and "not bold" or ""
    print(pos, cell.char or "", cell.color or "", isBold)
  end
end

FSL.CPT.MCDU = MCDU:new(1)
FSL.FO.MCDU = MCDU:new(2)

local FCU = {
  request = HttpRequest:new("", 8080, "FCU/Display")
}
FSL.FCU = FCU

function FCU:getField(json, fieldName)
  return json:match(fieldName .. ".-([%d%s]+)"):gsub(" ","")
end

function FCU:get()
  local json = self.request:get()
  local SPD = self:getField(json, "SPD")
  local HDG = self:getField(json, "HDG")
  local ALT = self:getField(json, "ALT")
  local ret = {
    SPD = tonumber(SPD),
    HDG = tonumber(HDG),
    ALT = tonumber(ALT),
    isBirdOn = json:find("HDG_VS_SEL\":false") ~= nil
  } 
  return ret
end

function FCU:setHttpPort(port)
  self.request:setPort(tonumber(port))
end

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
  }
}

function Control:new(control)
  control = control or {}
  if control.rectangle then
    control.rectangle = tonumber(control.rectangle)
  end
  self.__index = self
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
  log(("Position of control %s : x = %s, y = %s, z = %s"):format(self.LVar:gsub("VC_", ""), math.floor(self.pos.x), math.floor(self.pos.y), math.floor(self.pos.z)), 1)
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
  if type(self.Lt) == "string" then return ipc.readLvar(self.Lt) == 1
  else return ipc.readLvar(self.Lt.Brt) == 1 or ipc.readLvar(self.Lt.Dim) == 1 end
end

--- @treturn number

function Control:getLvarValue()
  return ipc.readLvar(self.LVar)
end

function Control:waitForLVarChange(timeout)
  timeout = ipc.elapsedtime() + (5000 or timeout)
  local startPos = self:getLvarValue()
  repeat until self:getLvarValue() ~= startPos or ipc.elapsedtime() > timeout
end

function Control:hideCursor()
  local x,y = mouse.getpos()
  mouse.move(x + 1, y + 1)
  mouse.move(x, y)
  sleep(10)
  ipc.control(1139)
end

--- @type Button

local Button = Control:new()

function Button:new(control)
  control = getmetatable(self):new(control)
  if control.LVar and control.LVar:find("MCDU") then control.interactionLength = 50 end
  self.__index = self
  return setmetatable(control, self)
end

--- Presses the button.
--- @function __call
--- @usage FSL.OVHD_ELEC_BAT_1_Button()

function Button:__call(twoSwitches, pressClickType, releaseClickType)
  if FSL.areSequencesEnabled and not twoSwitches then
    self:moveHandHere()
  end
  local sleepAfterPress
  ipc.mousemacro(self.rectangle, pressClickType or 3)
  if self.toggle then
    sleepAfterPress = 0
    ipc.mousemacro(self.rectangle, releaseClickType or 13)
  else
    local FPS = frameRate()
    if FPS > 30 then
      sleepAfterPress = 50
    elseif FPS > 20 then
      sleepAfterPress = 70
    else
      sleepAfterPress = 100
    end
    if twoSwitches then
      repeat 
        coroutine.yield()
        ipc.mousemacro(self.rectangle, pressClickType or 3) 
      until self:isDown()
      local time = ipc.elapsedtime()
      repeat coroutine.yield() until ipc.elapsedtime() - time >= sleepAfterPress
    else
      local timeout = ipc.elapsedtime() + 200
      repeat 
        sleep(10) 
      until self:isDown() or ipc.elapsedtime() > timeout
      sleep(sleepAfterPress)
    end
    ipc.mousemacro(self.rectangle, releaseClickType or 13)
  end
  if FSL.areSequencesEnabled then
    local interactionLength = plusminus(self.interactionLength or 300) - sleepAfterPress
    if twoSwitches then
      local time = ipc.elapsedtime()
      while ipc.elapsedtime() - time < interactionLength do
        coroutine.yield()
      end
    else
      sleep(interactionLength)
    end
    log("Interaction with the control took " .. interactionLength + sleepAfterPress .. " ms")
  end
end

--- Simulates a click of the right mouse button on the VC button.

function Button:rightClick() self(false, 1, 11) end

--- @treturn bool True if the button is depressed.

function Button:isDown() return ipc.readLvar(self.LVar) == 10 end

--- @type Guard

local Guard = Control:new()

--- <span>

function Guard:lift()
  if FSL.areSequencesEnabled then
    self:moveHandHere()
  end
  if not self:isOpen() then
    ipc.mousemacro(self.rectangle, 1)
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

function Guard:isOpen()
  return ipc.readLvar(self.LVar) == 10
end

--- All controls that have named positions
--- @type Switch

local Switch = Control:new()

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

--- @function __call
--- @usage FSL.GSLD_EFIS_VORADF_1_Switch("VOR")
--- @string targetPos

function Switch:__call(targetPos, twoSwitches)
  local targetPos = self:getTargetLvarVal(targetPos)
  if not targetPos then return end
  if FSL.areSequencesEnabled and not twoSwitches then
    self:moveHandHere()
  end
  local currPos = self:getLvarValue()
  if currPos ~= targetPos then
    if FSL.areSequencesEnabled and not twoSwitches then
      self:interact(plusminus(300))
    end
    self:set(targetPos, twoSwitches)
  end
end

function Switch:getTargetLvarVal(targetPos)
  return self.posn[tostring(targetPos):upper()]
end

function Switch:set(targetPos, twoSwitches)
  while true do
    currPos = self:getLvarValue()
    if currPos < targetPos then
      self:increase()
    elseif currPos > targetPos then
      self:decrease()
    else
      if self.springLoaded[targetPos] then self.letGo = true end
      if self.shouldHideCursor then
        self:hideCursor()
      end
      break
    end
    if FSL.areSequencesEnabled then
      if twoSwitches then
        local time = ipc.elapsedtime()
        local interactionLength = plusminus(self.interactionLength or 100)
        while ipc.elapsedtime() - time < interactionLength do
          coroutine.yield()
        end
        log("Interaction with the control took " .. interactionLength .. " ms")
      else
        self:interact(plusminus(self.interactionLength or 100))
      end
    else repeat sleep(5) until self:getLvarValue() ~= currPos
    end
  end
end

--- @treturn string Current position of the switch in uppercase.

function Switch:getPosn()
  return self.LVarToPosn[ipc.readLvar(self.LVar)]
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
end

--- Switches that can be pushed and pulled
--- @type FcuSwitch

local FcuSwitch = Control:new()

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

local EngineMasterSwitch = Switch:new()
EngineMasterSwitch.__call = getmetatable(EngineMasterSwitch).__call

function EngineMasterSwitch:increase()
  ipc.mousemacro(self.rectangle, 1)
  self:waitForLVarChange()
  ipc.sleep(plusminus(100))
  ipc.mousemacro(self.rectangle, 3)
  self:waitForLVarChange()
  ipc.sleep(plusminus(100))
  ipc.mousemacro(self.rectangle, 11)
  ipc.mousemacro(self.rectangle, 13)
  self:hideCursor()
end

EngineMasterSwitch.decrease = EngineMasterSwitch.increase

--- Knobs with no fixed positions
--- @type KnobWithoutPositions

local KnobWithoutPositions = Switch:new()

--- @function __call
--- @number targetPos Relative position from 0-100.
--- @usage FSL.OVHD_INTLT_Integ_Lt_Knob(42)

KnobWithoutPositions.__call = getmetatable(KnobWithoutPositions).__call

--- Rotates the knob left by 1 tick.
function KnobWithoutPositions:rotateLeft()
  ipc.mousemacro(self.rectangle, 15)
end

--- Rotates the knob right by 1 tick.
function KnobWithoutPositions:rotateRight()
  ipc.mousemacro(self.rectangle, 14)
end

function KnobWithoutPositions:getTargetLvarVal(targetPos)
  if type(targetPos) == "number" then
    if targetPos > 100 then targetPos = 100
    elseif targetPos < 0 then targetPos = 0 end
    return self.range / 100 * targetPos
  else return false end
end

function KnobWithoutPositions:set(targetPos)
  local timeStarted = ipc.elapsedtime()
  local tolerance = (targetPos == 0 or targetPos == self.range) and 0 or 5
  local tick = 1
  while true do
    currPos = self:getLvarValue()
    if math.abs(currPos - targetPos) > tolerance then
      if currPos < targetPos then
        self:rotateRight()
      elseif currPos > targetPos then
        self:rotateLeft()
      end
      repeat until self:getLvarValue() ~= currPos
    else
      self:hideCursor()
      if FSL.areSequencesEnabled then log("Interaction with the control took " .. ipc.elapsedtime() - timeStarted .. " ms") end
      break
    end
    if FSL.areSequencesEnabled and tick % 2 == 0 then
      sleep(1) 
    end
    tick = tick + 1
  end
  if FSL.areSequencesEnabled and not twoSwitches then
    self:interact(plusminus(300))
  end
end

--- @treturn number Relative position from 0-100.

function KnobWithoutPositions:getPosn()
  local val = ipc.readLvar(self.LVar)
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
      self:rotateRight()
      sleep(plusminus(pause))
    end
  elseif ticks < 0 then
    for _ = 1, -ticks do
      self:rotateLeft()
      sleep(plusminus(pause))
    end
  end
  if FSL.areSequencesEnabled then
    log("Interaction with the control took " .. (ipc.elapsedtime() - startTime) .. " ms")
  end
  self:hideCursor()
end

--- Sets the knob to random position between lower and upper.
--- @number[opt=0] lower
--- @number[opt=100] upper

function KnobWithoutPositions:random(lower, upper)
  self(math.random(lower or 0, upper or 100))
end

function moveTwoSwitches(switch1,pos1,switch2,pos2,chance)
  if prob(chance or 1) then
    hand:moveTo((switch1.pos + switch2.pos) / 2)
    sleep(plusminus(500,0.1))
    local co1 = coroutine.create(function() switch1(pos1,true) end)
    local co2 = coroutine.create(function() sleep(plusminus(30)) switch2(pos2,true) end)
    repeat
      local done1 = not coroutine.resume(co1)
      sleep(5)
      local done2 = not coroutine.resume(co2)
    until done1 and done2
  else
    switch1(pos1)
    switch2(pos2)
  end
end

function pressTwoButtons(butt1,butt2,chance)
  if prob(chance or 1) then
    hand:moveTo((butt1.pos + butt1.pos) / 2)
    sleep(plusminus(500,0.1))
    local co1 = coroutine.create(function() butt1(true) end)
    local co2 = coroutine.create(function() sleep(plusminus(10)) butt2(true) end)
    repeat
      local done1 = not coroutine.resume(co1)
      sleep(5)
      local done2 = not coroutine.resume(co2)
    until done1 and done2
  else
    butt1()
    butt2()
  end
end

local rawControls = require "FSL2Lua.FSL2Lua.FSL"

function FSL:initControlPositions(varname,control)
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

function FSL:init()

  for varname, control in pairs(rawControls) do

    control.pos = self:initControlPositions(varname,control)

    if control.posn then
      local temp = control.posn
      control.posn = {}
      for k,v in pairs(temp) do
        control.posn[k:upper()] = v
      end
      local highest = 0
      for k, v in pairs(control.posn) do
        if type(v) == "table" then v = v[1] end
        v = tonumber(v)
        if v > highest then highest = v end
      end
      control.maxLVarVal = highest
    end

    do
      local name = control.LVar:lower()
      local _type = control.type:lower()
      if _type == "enginemasterswitch" then
        control = EngineMasterSwitch:new(control)
      elseif _type == "fcuswitch" then
        control = FcuSwitch:new(control)
      elseif name:find("knob") and not control.posn then
        control = KnobWithoutPositions:new(control)
      elseif control.posn then
        control = Switch:new(control)
      elseif name:find("guard") then
        control = Guard:new(control)
      elseif name:find("button") or name:find("switch") or name:find("mcdu") then
        control = Button:new(control)
      else
        control = Control:new(control)
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
          self.CPT[controlName] = control
          control.name = controlName
          control.side = "CPT"
        end
      end
      for pattern, replace in pairs(replace.FO) do
        if varname:find(pattern) then
          controlName = varname:gsub(pattern,replace)
          self.FO[controlName] = control
          control.name = controlName
          control.side = "FO"
        end
      end

      if not control.side then
        self[varname] = control
        control.name = varname
      end

    end
  end

end

--#############################################################################

function FSL:getAcType()
  return self.acType
end

function FSL:setPilot(pilot)
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

function FSL:enableLogging()
  self.logging = true
  if not ipc.get("FSL2LuaLog") then
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
  self.CPT.MCDU.request:setPort(tonumber(port))
  self.FO.MCDU.request:setPort(tonumber(port))
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
    if (pos and math.abs(pos - v) < 4) or (not pos and math.abs(ipc.readLvar("VC_PED_TL_1")  - v) < 4 and math.abs(ipc.readLvar("VC_PED_TL_2")  - v) < 4) then
      return k
    elseif pos then return pos end
  end
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
  sleep(plusminus(2000,0.3))
  self.OVHD_APU_Start_Button()
end

function FSL:getTakeoffFlapsFromMcdu(side)
  side = side or self.pilot
  local sideStr = side == 1 and "CPT" or side == 2 and "FO"
  self[sideStr].PED_MCDU_KEY_PERF()
  sleep(500)
  local timeout = ipc.elapsedtime() + 5000
  while true do
    if ipc.elapsedtime() > timeout then
      return
    else
      local disp = self.MCDU:getString()
      if disp:sub(10,17) == "TAKE OFF" then
        local setting = disp:sub(162,162)
        sleep(plusminus(1000))
        self[sideStr].PED_MCDU_KEY_FPLN()
        return tonumber(setting)
      end
    end
    sleep()
  end
end

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
  path = ipc.readSTR(0x3C00,256):gsub("FSLabs\\SimObjects.+", "FSLabs\\" .. FSL:getAcType() .. "\\Data\\ATSU\\ATSU.log")
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

local bindCount = 0

function keyBind(keycode,func,cond,shifts,downup)
  cond = cond or function() return true end
  bindCount = bindCount + 1
  local funcName = "FSL2LuaLegacyBind" .. bindCount
  _G[funcName] = function() if cond() then func() end end
  event.key(keycode,shifts,downup or 1,funcName)
end

function buttBind(joyLetter,butt,func,cond,downup)
  cond = cond or function() return true end
  bindCount = bindCount + 1
  local funcName = "FSL2LuaLegacyBind" .. bindCount
  _G[funcName] = function() if cond() then func() end end
  event.button(joyLetter,butt,downup or 1,funcName)
end

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

for i = 1,22 do
  keyList["F" .. i] = i +  111
end
for i = 0,9 do
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

function keyBind:prepareData(data)
  assert(type(data.key) == "string", "The key combination must be a string")
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
        keys.key = string.byte(key) or error("Not a valid key")
      end
    end
  end
  assert(keyCount ~= #shifts, "Can't have only modifier keys")
  assert(keyCount - #shifts == 1, "Can't have more than one non-modifier key")
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
  assert(type(data.btn) == "string", "Wrong joystick button format")
  data.joyLetter = data.btn:sub(1,1)
  data.btnNum = tostring(data.btn:sub(2, #data.btn))
  data.btn = nil
  assert(data.joyLetter:find("%A") == nil, "Wrong joystick button format")
  assert(tostring(data.btnNum):find("%D") == nil, "Wrong joystick button format")
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

Bind = {
  binds = {},
  funcCount = 0
}

setmetatable(Bind, Bind)

--- @section Bind

--- @function Bind
--- @tparam table data A table containing the following fields: 
--- @tparam function data.onPress
--- @tparam function data.onPressRepeat
--- @tparam function data.onRelease
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
---   onPressRepeat = function() FSL.OVHD_INTLT_Integ_Lt_Knob:rotateLeft() end
--- }
--- Bind {
---   btn = "C5",
---   onPress = {FSL.PED_COMM_INT_RAD_Switch, "RAD"}, 
---   onRelease = {FSL.PED_COMM_INT_RAD_Switch, "OFF"}
--- }

function Bind:__call(data)
  data = self:prepareData(data)
  local bind = data.key and keyBind:new(data) or data.btn and joyBind:new(data)
  if bind then
    self.binds[#self.binds+1] = bind
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

function Bind:makeSingleFunc(funcs)
  if type(funcs) == "table" then
    if funcs.__call or (getmetatable(funcs) and getmetatable(funcs).__call) then
      return funcs
    else
      local _funcs = funcs
      funcs = {}
      for i, func in ipairs(_funcs) do
        if type(func) ~= "string" then
          local nextElem = _funcs[i+1]
          local _func
          if type(nextElem) == "string" then
            if type(func) == "table" and func[nextElem] then
              _func = function() func[nextElem](func) end
            else
              _func = function() func(nextElem) end
            end
          else
            _func = func
          end
          funcs[#funcs+1] = _func
        end
      end
      if #funcs == 1 then
        return funcs[1]
      else
        return function()
          for _, func in ipairs(funcs) do
            func()
          end
        end
      end
    end
  elseif type(funcs) == "function" then
    return funcs
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

FSL:init()
FSL.init = nil
FSL.initControlPositions = nil
FSL.MIP_GEAR_Lever = FSL.GEAR_Lever
collectgarbage("collect")
return FSL