----------------------------------------
-- Library for interacting with FSLabs cockpit controls based on Lvars and mouse macros.
-- See @{standalonescripts.md|here} on how to use it outside of Copilot.
-- @module FSL2Lua

if not FSL2LUA_STANDALONE 
  and not ipc.readLvar "AIRCRAFT_A319" 
  and not ipc.readLvar "AIRCRAFT_A320"
  and not ipc.readLvar "AIRCRAFT_A321" then ipc.exit() end

--- @field CPT table containing controls on the left side
--- @field FO table containing controls on the right side
--- @field PF table containing controls on the side of the Pilot Flying
--- <br>For example, if the PF is the Captain, it will be the same as the CPT table.
--- <br>The controls on the PM side are in the root FSL table.
--- @usage FSL.GSLD_EFIS_VORADF_1_Switch("VOR")
--- @table FSL
local FSL = require "FSL2Lua.FSL2Lua.FSLinternal"

local config = require "FSL2Lua.config"

if ipc.readLvar "AIRCRAFT_A319" == 1 then FSL.acType = "A319"
elseif ipc.readLvar "AIRCRAFT_A320" == 1 then FSL.acType = "A320"
elseif ipc.readLvar "AIRCRAFT_A321" == 1 then FSL.acType = "A321" end

function FSL:getAcType() return self.acType end

local util = require "FSL2Lua.FSL2Lua.util"

package.cpath = util.FSL2LuaDir .. "\\FSL2Lua\\?.dll;" .. package.cpath
if not FSL2LUA_STANDALONE then require "FSL2LuaDLL" end

local maf = require "FSL2Lua.libs.maf"

local MCDU = require "FSL2Lua.FSL2Lua.MCDU"
local FCU = require "FSL2Lua.FSL2Lua.FCU"
local atsuLog = require "FSL2Lua.FSL2Lua.atsuLog"

local hand = require "FSL2Lua.FSL2Lua.hand"

local Control = require "FSL2Lua.FSL2Lua.Control"
local Button = require "FSL2Lua.FSL2Lua.Button"
local Guard = require "FSL2Lua.FSL2Lua.Guard"
local Switch = require "FSL2Lua.FSL2Lua.Switch"
local FcuSwitch = require "FSL2Lua.FSL2Lua.FcuSwitch"
local EngineMasterSwitch = require "FSL2Lua.FSL2Lua.EngineMasterSwitch"
local KnobWithoutPositions = require "FSL2Lua.FSL2Lua.KnobWithoutPositions"

local trimwheel = require "FSL2Lua.FSL2Lua.trimwheel"

Bind = require "FSL2Lua.FSL2Lua.Bind"
Encoder = require "FSL2Lua.FSL2Lua.Encoder"

if not FSL2LUA_STANDALONE and util.FSUIPCversion < 0x5154 then
  util.handleError("FSUIPC version 5.154 or later is required", nil, true)
end

FSL.CPT.MCDU = MCDU:new(1)
FSL.FO.MCDU = MCDU:new(2)
MCDU.new = nil

FSL.FCU = FCU
FSL.atsuLog = atsuLog
FSL.trimwheel = trimwheel

FSL.CheckMacros = require "FSL2Lua.FSL2Lua.CheckMacros"

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
  return self._pilot
end

function FSL:enableLogging(startNewLog)
  return util.enableLogging(startNewLog)
end

function FSL:disableLogging()
  return util.disableLogging()
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
  util.sleep(plusminus(3000,0.2))
  self.OVHD_APU_Start_Button()
end

function FSL:getTakeoffFlapsFromMcdu(side)
  side = side or self._pilot
  local sideStr = side == 1 and "CPT" or side == 2 and "FO"
  self[sideStr].PED_MCDU_KEY_PERF()
  util.sleep(500)
  return withTimeout(5000, function()
    local disp = self.MCDU:getString()
    if disp:sub(10,17) == "TAKE OFF" or disp:sub(5,16) == "TAKE OFF RWY" then
      local setting = disp:sub(162,162)
      util.sleep(plusminus(1000))
      self[sideStr].PED_MCDU_KEY_FPLN()
      return tonumber(setting)
    end
    util.sleep()
  end)
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

end

--------------------------------------------------------------------------------------
-- Initialization of the cockpit controls --------------------------------------------
--------------------------------------------------------------------------------------

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
    if not control._checkMacro and not FSL2LUA_IGNORE_UNCHECKED then
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
    
    for pattern, _replace in pairs(replace.CPT) do
      if varname:find(pattern) then
        if pattern == "_CP" and varname:find("_CPT") then pattern = "_CPT" end
        controlName = varname:gsub(pattern, _replace)
        FSL.CPT[controlName] = control
        control.name = "FSL.CPT." .. controlName
        control.side = "CPT"
      end
    end

    for pattern, _replace in pairs(replace.FO) do
      if varname:find(pattern) then
        controlName = varname:gsub(pattern, _replace)
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
    local acType = FSL:getAcType()
    if acType == "A319" and config.A319_IS_A320 then
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

initControls()

FSL.MIP_GEAR_Lever = FSL.GEAR_Lever

collectgarbage "collect"

return FSL