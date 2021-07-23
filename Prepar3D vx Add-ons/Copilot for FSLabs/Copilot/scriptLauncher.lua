
require "copilot.IniUtils"
local file = require "FSL2Lua.FSL2Lua.file"

local iniPath = APPDIR .. "scripts.ini"

if not file.exists(iniPath) then
  file.create(iniPath, "[autorun.lua]\nautorun=A32X")
end

local function isScriptSection(sectionTitle)
  return sectionTitle:find "%.lua$"
end

local function isProfileSection(sectionTitle)
  return sectionTitle:find "^Profile%."
end

local ini = copilot.loadIniFile(iniPath, function(sectionTitle)
  if isScriptSection(sectionTitle) then
    return {
      title = sectionTitle,
      keys = {
        {
          name = "autorun",
          default = copilot.UserOptions.FALSE,
          values = {"A32X", copilot.UserOptions.TRUE, copilot.UserOptions.FALSE},
          type =  "enum"
        },
        {
          name = "launch_key",
          default = nil,
          type = "string"
        },
        {
          name = "kill_key",
          default = nil,
          type = "string"
        }
      }
    }
  elseif isProfileSection(sectionTitle) then
    return {
      title = sectionTitle,
      preserveTitleCase = true,
      arrayKeys = {
        {
          prefix = "",
          type = "string"
        }
      },
    }
  end
end)

local autorunScripts = {}

local function scriptPath(path)
  return path:lower():find "%.lua$" and path or (path .. ".lua")
end

local function processScriptSection(path, script)
  if not firstRun and (script.autorun == copilot.UserOptions.TRUE or (script.autorun == "A32X" and FSL.acType)) then
    autorunScripts[path] = true
  end
  if script.launch_key then
    pcall(Bind, {key = script.launch_key, onPress = function() copilot.newLuaThread(scriptPath(path)) end})
  end
  if script.kill_key then
    pcall(Bind, {key = script.kill_key, onPress = function() copilot.killLuaThread(scriptPath(path)) end})
  end
end

local function autorunProfileScripts(scripts)
  for _, path in pairsByKeys(scripts) do
    autorunScripts[path] = true
  end
end

local fsuipcProfileName = copilot.trimIpcString(0x9540)

for title, section in pairs(ini) do
  if isProfileSection(title) and title:match "Profile.(.+)" == fsuipcProfileName then
    autorunProfileScripts(section)
  else
    processScriptSection(title, section)
  end
end

if SCRIPT_LAUNCHER_AIRCRAFT_RELOAD then
  for path in pairsByKeys(autorunScripts) do
    copilot.newLuaThread(scriptPath(path))
  end
end
