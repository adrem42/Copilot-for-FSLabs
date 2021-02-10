
local acType
if getLvar("AIRCRAFT_A319") == 1 then acType = "A320"
elseif getLvar("AIRCRAFT_A320") == 1 then acType = "A320"
elseif getLvar("AIRCRAFT_A321") == 1 then acType = "A321" end

package.path = currentDir .. "?.lua"

local LVarList = require "control_lvars"
local lightVarList = require "light_lvars"

local FSL2LuaDir = require "config".path

package.path = FSL2LuaDir .. "\\?.lua"

local serpent = require "libs.serpent"
local file = require "FSL2Lua.file"

local FSL_path = FSL2LuaDir .. "\\FSL2Lua\\FSL.lua"
local FSL_file = file.read(FSL_path)

local FSL = loadstring(FSL_file)()

for controlName in pairs(LVarList) do
  local newName = controlName:sub(4)
  local controlTable
  if not FSL[newName] then
    controlTable = {}
    FSL[newName] = controlTable
  else
    controlTable = FSL[newName]
  end
  controlTable.A319 = controlTable.A319 or {}
  controlTable.A320 = controlTable.A320 or {}
  controlTable.A321 = controlTable.A321 or {}
  for lightVarName in pairs(lightVarList) do
    local lightVarSubStr
    if lightVarName:find("Brt") or lightVarName:find("Dim") then
      lightVarSubStr = lightVarName:sub(1, #lightVarName - 7)
      if controlName:find(lightVarSubStr) then
        controlTable.Lt = controlTable.Lt or {}
        if lightVarName:find("Brt") then
          controlTable.Lt.Brt = lightVarName
        elseif lightVarName:find("Dim") then
          controlTable.Lt.Dim = lightVarName
        end
      end
    else
      if lightVarName:find("Lamp") then
        lightVarSubStr = lightVarName:sub(1, #lightVarName - 5)
      else
        lightVarSubStr = lightVarName:sub(1, #lightVarName - 3)
      end
      if controlName:find(lightVarSubStr) then
        controlTable.Lt = lightVarName
      end
    end
  end
end

local prev = {rectangle = 0, param = 0}
local ignore = {}

function onMacroDetected(rectangle, param)
  if param ~= 3 and param ~= 1 and param ~= 14 and param ~= 15 then return end
  local _prev = {}
  _prev.param = prev.param
  _prev.rectangle = prev.rectangle
  prev.rectangle = rectangle
  prev.param = param
  if rectangle == _prev.rectangle and param == _prev.param then
    return 
  end
  local timeout = getElapsedTime() + 1000
  local found = false
  warn("WAIT UNTIL READY")
  repeat
    for _, control in pairs(FSL) do
      if LVarList[control.LVar] then
        local currPos = getLvar(control.LVar)
        local prevPos = LVarList[control.LVar]
        if currPos ~= prevPos and not ignore[control] then
          ignore[control] = true
          found = true
          control[acType].rectangle = rectangle
          info "------------------------------------------------------------------------"
          local msg = "LVar: " .. control.LVar .. ",\trectangle: " .. "0x" .. string.format("%x", tostring(rectangle)):lower()
          info(msg)
        end
        LVarList[control.LVar] = currPos
      end
    end
  until found or getElapsedTime() > timeout
  info "READY"
end

function saveResults()
  info "saving"
  for _, control in pairs(FSL) do
    if control.type == nil then
      control.type = ""
    end
    if control[acType].rectangle then
      control[acType].rectangle = "0x" .. string.format("%x", tostring(control[acType].rectangle)):lower()
    end
  end

  local backup = FSL2LuaDir .. "\\FSL2Lua\\FSL.bak.0"

  while true do
    if not file.exists(backup) then break end
    backup = backup:sub(1, #backup - 1) .. backup:sub(#backup, #backup) + 1
  end

  file.write(backup, FSL_file)

  if not file.read(backup) == FSL_file then
    error "Failed to create backup"
  end

  file.write(FSL_path, "return " .. serpent.block(FSL, {comment = false, sparse = false}),"w")

  info "file saved"
end

for LVar in pairs(LVarList) do
  LVarList[LVar] = getLvar(LVar)
end
