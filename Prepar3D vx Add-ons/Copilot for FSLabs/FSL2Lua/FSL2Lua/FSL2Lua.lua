if false then module "FSL2Lua" end

if FSL2LUA_MAKE_CONTROL_LIST then
  FSL2LUA_STANDALONE = true
end

if FSL2LUA_STANDALONE then
  ipc = {readLvar = function(lvar) end}
end

function hideCursor() end

--- @field CPT table containing controls on the left side
--- @field FO table containing controls on the right side
--- @field PF table containing controls on the side of the Pilot Flying
--- <br>For example, if the PF is the Captain, it will be the same as the CPT table.
--- <br>The controls on the PM side are in the root FSL table.
--- @usage FSL.GSLD_EFIS_VORADF_1_Switch("VOR")
--- @table FSL
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

if ipc.readLvar "AIRCRAFT_A319" == 1 then FSL.acType = "A319"
elseif ipc.readLvar "AIRCRAFT_A320" == 1 then FSL.acType = "A320"
elseif ipc.readLvar "AIRCRAFT_A321" == 1 then FSL.acType = "A321" end

if FSL.acType then
  FSL.fullAcType = FSL.acType
  if ipc.readSTR(0x3C00, 256):find("--SL.air") then
    FSL.fullAcType = FSL.fullAcType .. "-SL"
  end
  FSL.FSLabsPath = ipc.readSTR(0x3C00, 256):gsub("FSLabs\\SimObjects.+", "FSLabs\\")
  FSL.FSLabsAcSpecificPath = FSL.FSLabsPath .. FSL.fullAcType .. "\\" 
end

function FSL:getAcType() return self.acType end

local util = require "FSL2Lua.FSL2Lua.util"

local maf = require "FSL2Lua.libs.maf"

local MCDU = require "FSL2Lua.FSL2Lua.MCDU"
local FCU = require "FSL2Lua.FSL2Lua.FCU"
local atsuLog = require "FSL2Lua.FSL2Lua.atsuLog"

local hand = require "FSL2Lua.FSL2Lua.hand"

local Control = require "FSL2Lua.FSL2Lua.Control"
local Button = require "FSL2Lua.FSL2Lua.Button"
local ToggleButton = require "FSL2Lua.FSL2Lua.ToggleButton"
local Guard = require "FSL2Lua.FSL2Lua.Guard"
local Switch = require "FSL2Lua.FSL2Lua.Switch"
local PushPullSwitch = require "FSL2Lua.FSL2Lua.PushPullSwitch"
local EngineMasterSwitch = require "FSL2Lua.FSL2Lua.EngineMasterSwitch"
local RotaryKnob = require "FSL2Lua.FSL2Lua.RotaryKnob"

local trimwheel = require "FSL2Lua.FSL2Lua.trimwheel"

Bind = require "FSL2Lua.FSL2Lua.Bind"
Encoder = require "FSL2Lua.FSL2Lua.Encoder"

FSL.CPT.MCDU = MCDU:new(1)
FSL.FO.MCDU = MCDU:new(2)

FSL.FCU = FCU
FCU.init()
FSL.atsuLog = atsuLog
FSL.trimwheel = trimwheel

FSL.CheckMacros = require "FSL2Lua.FSL2Lua.CheckMacros"

function FSL:skipHand() Control.skipHand() end

function FSL._uncheckedControls()
  local t = {}
  local count = 0
  local function visit(_t)
    for _, v in pairs(_t) do
      if util.isType(v, Control) and not t[v.name] and not v._checkMacro then
        t[v.name] =v
        count = count + 1
      end
    end
  end
  visit(FSL) visit(FSL.CPT) visit(FSL.FO)
  return t, count
end

---This function makes references in the root FSL table to all fields in either FSL.CPT or FSL.FO, if the 'pilot' parameter is 1 or 2, respectively. For the other side's controls, it makes
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
  if pilot == self._pilot then return end
  self._pilot = pilot
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
  if self._pilot == 1 then
    return 1, "CPT"
  else
    return 2, "FO"
  end
end

function FSL:enableLogging(startNewLog) return util.enableLogging(startNewLog) end

function FSL:disableLogging() return util.disableLogging() end

function FSL:enableSequences()
  if not self:getPilot() then
    error("Call setPilot first", 2)
  end
  self.areSequencesEnabled = true
end

function FSL:disableSequences() self.areSequencesEnabled = false end

function FSL:setHttpPort(port)
  port = tonumber(port)
  self.CPT.MCDU = MCDU:new(1, port)
  self.FO.MCDU = MCDU:new(2, port)
  FCU.init(port)
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
  util.sleep(plusminus(3000,0.2))
  self.OVHD_APU_Start_Button()
end

function FSL:setButtonSleepMult(mult) Button.sleepMult = mult end

function FSL:getTakeoffFlapsFromMcdu(side)
  side = side or self._pilot
  local sideStr = side == 1 and "CPT" or side == 2 and "FO"
  self[sideStr].PED_MCDU_KEY_PERF()
  return withTimeout(5000, function()
    local disp = self[sideStr].MCDU:getString()
    if disp:sub(10,17) == "TAKE OFF" or disp:sub(5,16) == "TAKE OFF RWY" then
      local setting = disp:sub(162,162)
      util.sleep(plusminus(1000))
      self[sideStr].PED_MCDU_KEY_FPLN()
      return tonumber(setting)
    end
    util.sleep()
  end)
end

function moveTwoSwitches(switch1, pos1, switch2, pos2, chance)
  if prob(chance or 1) then
    hand:moveTo((switch1.pos + switch2.pos) / 2)
    util.sleep(plusminus(100))
    local co1 = coroutine.create(function() 
      switch1:_setPosition(pos1, true) 
    end)
    local co2 = coroutine.create(function() 
      switch2:_setPosition(pos2, true) 
    end)
    repeat
      local done1 = not coroutine.resume(co1)
      util.sleep(1)
      local done2 = not coroutine.resume(co2)
    until done1 and done2
  else
    switch1(pos1)
    switch2(pos2)
  end
end

function pressTwoButtons(butt1, butt2, chance)
  if prob(chance or 1) then
    hand:moveTo((butt1.pos + butt1.pos) / 2)
    util.sleep(plusminus(200,0.1))
    local co1 = coroutine.create(function() 
      butt1:_pressAndRelease(true) 
    end)
    local co2 = coroutine.create(function() 
      butt2:_pressAndRelease(true) 
    end)
    repeat
      local done1 = not coroutine.resume(co1)
      util.sleep(1)
      local done2 = not coroutine.resume(co2)
    until done1 and done2
  else
    butt1()
    butt2()
  end
end

--------------------------------------------------------------------------------------
-- Initialization of the cockpit controls --------------------------------------------
--------------------------------------------------------------------------------------

local rawControls = require "FSL2Lua.FSL2Lua.FSL"

local function initControlPosition(control, varname)
  if not control.pos then return end
  local pos = control.pos
  local mirror = {
    DCDU_R = "DCDU_L",
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
  control.pos = pos
end

local function mapGuardsToButtons(guards, buttons)
  for _, button in ipairs(buttons) do
    local buttonLvar = button.LVar:lower()
    for i, guard in ipairs(guards) do
      local guardLvar = guard.LVar:lower()
      if button.guardLvar == guard.LVar or guardLvar:find(buttonLvar:gsub("(.+)_.+", "%1")) then
        button.guardLvar = nil
        button.guard = table.remove(guards, i)
        break
      end
    end
  end
end

local replace = {
  CPT = {
    WIPER_KNOB_LEFT = {"WIPER_KNOB", keep = true},
    WIPER_RPLNT_LEFT = {"WIPER_RPLNT", keep = true},
    DCDU_L = {"DCDU"},
    MCDU_L = {"MCDU"},
    COMM_1 = {"COMM"},
    RADIO_1 = {"RADIO"},
    _CP = {""}
  },
  FO = {
    WIPER_KNOB_RIGHT = {"WIPER_KNOB", keep = true},
    WIPER_RPLNT_RIGHT = {"WIPER_RPLNT", keep = true},
    DCDU_R = {"DCDU"},
    MCDU_R = {"MCDU"},
    COMM_2 = {"COMM"},
    RADIO_2 = {"RADIO"},
    _FO = {""}
  }
}

local function findControlSide(control, varname, side)
  for pattern, _replace in pairs(replace[side]) do
    if varname:find(pattern) then
      if pattern == "_CP" and varname:find("_CPT") then 
        pattern = "_CPT"
      end
      local controlName = varname:gsub(pattern, _replace[1])
      FSL[side][controlName] = control
      control.name = "FSL." .. side .. "." .. controlName
      control.side = side
      if _replace.keep then
        control.side = nil
        FSL[varname] = control
      end
      return true
    end
  end
  return false
end

local function assignClassToControl(control, buttons, guards)
  local Lvar = (control.LVar or ""):lower()
  local _type = (control.type or ""):lower()
  if _type == "unknown" then
    control = Control:new(control)
  elseif _type == "enginemasterswitch" then
    control = EngineMasterSwitch:new(control)
  elseif _type == "pushpullswitch" then
    control = PushPullSwitch:new(control)
  elseif Lvar:find("knob") and not control.posn then
    control = RotaryKnob:new(control)
  elseif control.posn then
    control = Switch:new(control)
  elseif Lvar:find("guard") then
    control = Guard:new(control)
    guards[#guards+1] = control
  elseif Lvar:find("button") or Lvar:find("switch") or Lvar:find("mcdu") or Lvar:find("key") or Lvar:find("dcdu") then
    if control.toggle == true then
      control = ToggleButton:new(control)
    else
      control = Button:new(control)
    end
    buttons[#buttons+1] = control
  else
    control = Control:new(control)
  end
  if util.isType(control, Control) and control._baseCtorCalled then
    control._baseCtorCalled = nil
    return control
  end
end

local function initControl(control, varname, guards, buttons)

  local id = control.name or control.LVar
  local function epicFail() error("Failed to create control: " .. id, 2) end

  initControlPosition(control, varname)

  control = assignClassToControl(control, buttons, guards)
  if not control then epicFail() end
  if not control._checkMacro and not FSL2LUA_IGNORE_UNCHECKED then
    if control.name then epicFail() end
    setmetatable(control, nil)
    return nil
  end

  local name = control.name
  if not findControlSide(control, varname, "CPT") and not findControlSide(control, varname, "FO") then
    FSL[varname] = control
    control.name = "FSL." .. varname
  end
  if name and control.name ~= name then
    epicFail()
  end

  return control
end

local tableOfControls = {}

local function initControls()

  local guards, buttons = {}, {}

  for varname, control in pairs(rawControls) do

    if FSL:getAcType() and control.name then
      initControl(control, varname, guards, buttons)
    elseif FSL2LUA_MAKE_CONTROL_LIST and control.name then
      tableOfControls[#tableOfControls+1] = initControl(control, varname, guards, buttons)
    end
  end

  mapGuardsToButtons(guards, buttons)

  if FSL._pilot then FSL:setPilot(FSL._pilot) end
end

initControls()

FSL._init = initControls

function FSL.ignoreFaultyLvars()
  for _, v in pairs(rawControls) do
    v.getLvarValue = nil
  end
end

if FSL:getAcType() then
  local ctrTkType = "PUMP"
  if FSL:getAcType() == "A321" or FSL.fullAcType:find "SL" then
    ctrTkType = "VALVE"
  end
  for i = 1, 2 do
    FSL["OVHD_FUEL_CTR_TK_" .. i .. "_COMPAT_Button"] = FSL["OVHD_FUEL_CTR_TK_" .. i .. "_" .. ctrTkType .. " _Button"]
  end
end


FSL.MIP_GEAR_Lever = FSL.GEAR_Lever

if FSL2LUA_MAKE_CONTROL_LIST then return tableOfControls end

return FSL