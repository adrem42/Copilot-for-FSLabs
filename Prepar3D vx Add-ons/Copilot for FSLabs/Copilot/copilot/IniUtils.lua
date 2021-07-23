if false then module "copilot" end

local UserOptions = {TRUE = 1, FALSE = 0, ENABLED = 1, DISABLED = 0}
copilot.UserOptions = UserOptions
local file = require "FSL2Lua.FSL2Lua.file"

local typeConverters = {}

function typeConverters.bool(val)
  local _val = tonumber(val)
  if _val ~= UserOptions.FALSE and _val ~= UserOptions.TRUE then 
    return
  end
  return _val
end

typeConverters.boolean = typeConverters.bool

function typeConverters.number(val)
  return tonumber(val)
end

function typeConverters.int(val)
  local _val = tonumber(val)
  return _val and math.floor(_val)
end

function typeConverters.string(val)
  return tostring(val)
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
  if not found and option.required then
    error(string.format(
      "Invalid value for option %s: %s. Only the following values are accepted: %s.",
      option.name, val, table.concat(option.values, ", ")
    ))
  end
  return val
end

typeConverters.double = typeConverters.number

local function checkOption(option, iniValue)
  local val
  local missingType = true
  for _type in option.type:gmatch("[^(%|)]+") do
    if typeConverters[_type] then
      missingType = false
      val = typeConverters[_type](iniValue, option)
      if val then break end
    end
  end
  if missingType then
    error(string.format("Invalid ini format: %s, %s, %s", option.name or "nil", option.type or "nil", iniValue or "nil"))
  end
  return val
end

local function load(cfg, path, optionsTable)
  local iniFile = file.read(path)
  local cfgTable = type(cfg) == "table" and cfg or {}
  if iniFile then
    for sectionTitle, iniSection in iniFile:gmatch("%[(.-)%]([^%[%]]+)") do
      local section
      if type(cfg) == "table" then
        for _, _section in ipairs(cfg) do
          if _section.title == sectionTitle then
            section = _section
          end
        end
      elseif type(cfg) == "function" then
        section = cfg(sectionTitle)
        cfgTable[#cfgTable+1] = section
      end
      if section then
        section.keys = section.keys or {}
        local pattern = "([%w _%.]+)=([^$^\n^;]+)"
        for iniKey, iniValue in iniSection:gmatch(pattern) do
          iniValue = iniValue:gsub("%s*$", "")
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
            option.value = checkOption(option, iniValue)
          end
        end
      end
    end
  end
  for _, section in ipairs(cfgTable) do
    local sectionTitle = section.title
    if not section.preserveTitleCase then
      sectionTitle = section.title:lower()
    end
    optionsTable[sectionTitle] = optionsTable[sectionTitle] or {}
    for _, option in ipairs(section.keys) do
      option.value = option.value ~= nil and option.value or option.default
      local key, value = option.name, option.value
      assert(optionsTable[sectionTitle][key] == nil, "The key has already been set")
      optionsTable[sectionTitle][key] = value
    end
  end
  return optionsTable, cfgTable
end

local function save(options, path)
  local f = {}
  for _, section in ipairs(options) do
    table.insert(f, ("[%s]"):format(section.title))
    if section.comment then
      for _, line in ipairs(section.comment) do
        table.insert(f, ";" .. line)
      end
    end
    for i, option in ipairs(section.keys) do
      local key, value = option.name, option.value
      if not (option.hidden and not value) then
        if option.format == "hex" then
          value = "0x" .. string.format("%x", value):upper()
        end
        local s = ("%s=%s"):format(key, value or "")
        if option.comment then s = s .. " ;" .. option.comment end
        table.insert(f, s)
      end
      if i == #section.keys then table.insert(f, "") end
    end
  end
  file.write(path, table.concat(f,"\n"), "w")
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
  local optionsTable, cfgTable = load(cfg, path, init or {})
  save(cfgTable, path)
  return optionsTable
end