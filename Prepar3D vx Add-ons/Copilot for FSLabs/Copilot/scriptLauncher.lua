
require "copilot.IniUtils"
local file = require "FSL2Lua.FSL2Lua.file"

local iniPath = APPDIR .. "scripts.ini"

if not file.exists(iniPath) then
  file.create(iniPath, "[autorun.lua]\nautorun=A32X")
end

local function makeScriptSection(sectionTitle)
  return {
    title = sectionTitle,
    preserveTitleCase = true,
    keys = {
      {
        name = "autorun",
        default = false,
        values = {"A32X"},
        type =  "enum|bool"
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
end

local function makeProfileSection(sectionTitle)
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

local scriptPaths = {}
local fsuipcProfiles = {}
local autorunScripts = {}

local function splitEntry(entry)
  local first, second = entry:match "([^:]*):?(.*)"
  if second == "" then return nil, first end
  return first, second
end

local function absoluteScriptPath(prefix, path)
  local scriptDir = prefix == "copilot" and "scripts_copilot\\" or "scripts\\"
  local absoluteScriptFilePath = APPDIR .. scriptDir
  if path:find "%.lua$" then
    absoluteScriptFilePath = absoluteScriptFilePath .. path
  else
    absoluteScriptFilePath = absoluteScriptFilePath .. path .. "\\init.lua"
  end
  return absoluteScriptFilePath
end

local ini = copilot.loadIniFile(iniPath, function(sectionTitle)
  if not sectionTitle then
    return {
      boolCompat = false
    }
  end
  local prefix, body = splitEntry(sectionTitle)
  if prefix then
    sectionTitle = prefix:lower() .. ":" .. body
  end
  if prefix == "profile" then
    fsuipcProfiles[sectionTitle] = body
    return makeProfileSection(sectionTitle)
  else
    scriptPaths[sectionTitle] = absoluteScriptPath(prefix, body)
    return makeScriptSection(sectionTitle)
  end
end)

local function processScriptSection(path, opt)
  if opt.autorun == true or opt.autorun == "A32X" and FSL.acType then
    autorunScripts[path] = true
  end
  if opt.launch_key then
    pcall(Bind, {key = opt.launch_key, onPress = function() copilot.newLuaThread(path) end})
  end
  if opt.kill_key then
    pcall(Bind, {key = opt.kill_key, onPress = function() copilot.killLuaThread(path) end})
  end
end

local function autorunProfileScripts(scripts)
  for _, entry in pairs(scripts) do
    autorunScripts[absoluteScriptPath(splitEntry(entry))] = true
  end
end

local currentFsuipcProfile = copilot.trimIpcString(0x9540)

for title, section in pairs(ini) do
  if fsuipcProfiles[title] == currentFsuipcProfile then
    autorunProfileScripts(section)
  else
    processScriptSection(scriptPaths[title], section)
  end
end

if SCRIPT_LAUNCHER_AIRCRAFT_RELOAD then
  for path in pairsByKeys(autorunScripts) do
    local autorunPath = absoluteScriptPath(nil, "autorun.lua"):lower()
    if path:lower() ~= autorunPath or file.exists(autorunPath) then
      copilot.newLuaThread(path)
    end
  end
end
