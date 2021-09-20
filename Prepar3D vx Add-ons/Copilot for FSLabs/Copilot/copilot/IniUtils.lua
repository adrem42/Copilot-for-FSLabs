
if false then module "copilot" end

local UserOptions = {TRUE = 1, FALSE = 0, ENABLED = 1, DISABLED = 0}
copilot.UserOptions = UserOptions
local file = require "FSL2Lua.FSL2Lua.file"

local typeConverters = {}
local reverseTypeConverters = {}

function typeConverters.bool(val, _, cfgTable)
  local _val = tonumber(val)
  if _val ~= UserOptions.FALSE and _val ~= UserOptions.TRUE then 
    return
  end
  if cfgTable.boolCompat == false then
    return _val == UserOptions.TRUE
  end
  return _val
end

function reverseTypeConverters.bool(val, _, cfgTable)
  if cfgTable.boolCompat == false then
    return val and UserOptions.TRUE or UserOptions.FALSE
  end
  return val
end

typeConverters.boolean = typeConverters.bool
reverseTypeConverters.boolean = reverseTypeConverters.bool

function typeConverters.number(val)
  return tonumber(val)
end

function typeConverters.int(val)
  local _val = tonumber(val)
  return _val and math.floor(_val)
end

function typeConverters.string(val)
  if val == nil then return nil end
  if not val:find("%S") then
    return nil
  end
  return val
end

function typeConverters.enum(val, option)
  local found = false
  for _, enumVal in ipairs(option.values) do
    if type(enumVal) == "number" then
      val = tonumber(val)
    elseif type(enumVal) ~= "string" then 
      error "wtf" 
    end
    if val == enumVal then
      found = true
      val = val
      break
    end
  end
  if not found then val = nil end
  if not found and option.required and not option.hidden then
    error(string.format(
      "Invalid value for option %s: %s. Only the following values are accepted: %s.",
      option.name, val, table.concat(option.values, ", ")
    ))
  end
  return val
end

typeConverters.double = typeConverters.number

local function parseValue(option, cfgTable)
  local val
  local missingType = true
  local reverseTypes = {}
  for _type in option.type:gmatch("[^(%|)]+") do
    if reverseTypeConverters[_type] then
      reverseTypes[#reverseTypes+1] = _type
    end
    if typeConverters[_type] then
      missingType = false
      val = typeConverters[_type](option.iniValue, option, cfgTable)
      if val ~= nil then 
        option.value = val
        option.type = _type
        break 
      end
    end
  end
  if val == nil then
    option.value = option.default
    if option.hidden then
      option.serialize = false
    end
    option.type = nil
    for _, _type in ipairs(reverseTypes) do
      val = reverseTypeConverters[_type](option.value, option, cfgTable)
      if val then 
        option.type = _type
        break 
      end
    end
  end
  if missingType then
    error(string.format("Invalid ini format: %s, %s, %s", option.name or "nil", option.type or "nil", option.iniValue or "nil"))
  end
end

local function trimTrailingSpace(s) return s:gsub("%s*$", "") end

local function processKeyValue(iniKey, iniValue, section)
  iniValue = trimTrailingSpace(iniValue)
  local option
  for _, opt in ipairs(section.keys) do
    if opt.name == iniKey then
      option = opt
      break
    end
  end
  if not option and section.arrayKeys then
    for _, arrayKey in ipairs(section.arrayKeys) do
      if iniKey:sub(1, #arrayKey.prefix) == arrayKey.prefix then
        option = {
          name = iniKey,
          type = arrayKey.type
        }
        section.keys[#section.keys+1] = option
        break
      end
    end
  end
  if option then
    option.iniValue = iniValue
  end
end

local function saveOptionToOutputMap(outputMap, sectionTitle, option)
  local key, value = option.name, option.value
  assert(outputMap[sectionTitle][key] == nil, "The key has already been set")
  outputMap[sectionTitle][key] = value
end

local function serializeIniOption(option, optionIdx, section, serializedIniTable, outputArray)
  local key, value = option.name, option.value
  if option.serialize ~= false then
    if option.format == "hex" then
      value = "0x" .. string.format("%x", value):upper()
    end
    local converter = reverseTypeConverters[option.type] or function(val) return val end
    local s = ("%s=%s"):format(key, converter(value, option, outputArray) or "")
    if option.comment then 
      s = s .. " ;" .. option.comment 
    end
    table.insert(serializedIniTable, s)
  end
  if optionIdx == #section.keys then 
    table.insert(serializedIniTable, "") 
  end
end

local function beginOutputMapSection(outputMap, section)
  
  local sectionTitle = section.title
  if not section.preserveTitleCase then
    sectionTitle = section.title:lower()
  end
  outputMap[sectionTitle] = outputMap[sectionTitle] or {}
  return sectionTitle
end

local function beginSerializeSection(serializedIniTable, section)
  table.insert(serializedIniTable, ("[%s]"):format(section.title))
  if section.comment then
    for _, line in ipairs(section.comment) do
      table.insert(serializedIniTable, ";" .. line)
    end
  end
end

local function processIniSection(sectionTitle, sectionString, iniFormat, outputArray, serializedIniTable, outputMap)

  local section
  if type(iniFormat) == "table" then
    for _, _section in ipairs(iniFormat) do
      if _section.title == sectionTitle then
        section = _section
      end
    end
  elseif type(iniFormat) == "function" then
    section = iniFormat(sectionTitle)
    outputArray[#outputArray+1] = section
  end
  if not section then return end

  section.keys = section.keys or {}
  local pattern = "([%w _%.]+)=([^$^\n^;]+)"
  for iniKey, iniValue in sectionString:gmatch(pattern) do
    processKeyValue(iniKey, iniValue, section)
  end
end


local function processIniFile(iniFormat, path, outputMap)

  local iniFile = file.read(path)
  local outputArray = type(iniFormat) == "table" and iniFormat or iniFormat()
  local serializedIniTable = {}

  if iniFile then
    for title, section in iniFile:gmatch("%[(.-)%]([^%[%]]+)") do
      processIniSection(title, section, iniFormat, outputArray, serializedIniTable, outputMap)
    end
  end

  for _, section in ipairs(outputArray) do
    
    local outputMapSectionTitle = beginOutputMapSection(outputMap, section)   
    beginSerializeSection(serializedIniTable, section) 

    for i, option in ipairs(section.keys) do
      parseValue(option, outputArray)
      saveOptionToOutputMap(outputMap, outputMapSectionTitle, option)
      serializeIniOption(option, i, section, serializedIniTable, outputArray)
    end
  end

  file.write(path, table.concat(serializedIniTable,"\n"), "w")
  return outputMap
end

--- Loads (also creates, if it doesn't exist) an ini file into a lua table
---@string path
---@tparam table cfg The format of the ini file (see usage below)
---@tparam[opt] table init If specified, loadIniFile will not create a new table, but will populate this table instead.
---@treturn table The table with the options (see usage below). If init was specified, it will be the same table.
---@usage
---local optionsCfg = {
---  {
---    title = "Section1",
---    keys = {
---      {
---        name = "enable",
---        default = copilot.UserOptions.TRUE,
---        comment = "a comment",
---        type = "bool" -- other types: "int", "double" or "number", "enum", "string"
---      }
---    }
---  },
---  {
---    title = "SeCtiOn2",
---    keys = {
---      {
---        name = "fruit",
---        type = "enum",
---        default = "apple",
---        required = true,
---        values = {"apple", "orange", "banana"}
---      } 
---    }
---  }
---}
---
---local options = copilot.loadIniFile(APPDIR .. "my_ini_file.ini", optionsCfg)
---print(
---  ("section1.enable: %s, section2.fruit: %s")
---    :format(options.section1.enable, options.section2.fruit)
---)
function copilot.loadIniFile(path, cfg, init)
  return processIniFile(cfg, path, init or {})
end