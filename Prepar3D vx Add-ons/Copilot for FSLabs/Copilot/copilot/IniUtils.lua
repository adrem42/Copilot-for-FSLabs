if false then module "copilot" end

copilot = copilot or {}
local UserOptions = {TRUE = 1, FALSE = 0, ENABLED = 1, DISABLED = 0}
copilot.UserOptions = UserOptions
local file = require "FSL2Lua.FSL2Lua.file"

local function checkOption(option, iniValue)
  local val
  if option.type == "bool" or option.type == "boolean" then
    val = tonumber(iniValue) == UserOptions.FALSE 
      and UserOptions.FALSE 
      or UserOptions.TRUE
  elseif option.type == "number" or option.type == "double" then
    val = tonumber(iniValue)
  elseif option.type == "int" then
    val = tonumber(iniValue) and math.floor(tonumber(iniValue))
  elseif option.type == "string" then
    val = tostring(iniValue)
  elseif option.type == "enum" then
    for _, enumVal in ipairs(option.values) do
      if type(enumVal) == "number" then
        iniValue = tonumber(enumVal)
      elseif type(enumVal) ~= "string" then error "wtf" end
      if iniValue == enumVal then
        val = enumVal
        break
      end
    end
    if val == nil and option.required then
      error(string.format(
        "Invalid value for option %s: %s. Only the following values are accepted: %s.",
        option.name, iniValue, table.concat(option.values, ", ")
      ))
    end
  else 
    error(string.format("wtf: %s, %s, %s", option.name or "nil", option.type or "nil", iniValue or "nil"))
  end
  return val
end

local function load(options, path, optionsTable)
  local iniFile = file.read(path)
  if iniFile then
    for sectionTitle, iniSection in iniFile:gmatch("%[(.-)%]([^%[%]]+)") do
      for _, section in ipairs(options) do
        if section.title == sectionTitle then
          local pattern = "([%w _]+)=([%w_%.%+]+)"
          for iniKey, iniValue in iniSection:gmatch(pattern) do
            for _, option in ipairs(section.keys) do
              if option.name == iniKey then
                option.value = checkOption(option, iniValue)
                break
              end
            end
          end
        end
      end
    end
  end
  for _, section in ipairs(options) do
    local sectionTitle = section.title:lower()
    optionsTable[sectionTitle] = optionsTable[sectionTitle] or {}
    for _, option in ipairs(section.keys) do
      option.value = option.value ~= nil and option.value or option.default
      local key, value = option.name, option.value
      assert(optionsTable[sectionTitle][key] == nil, "The key has already been set")
      optionsTable[sectionTitle][key] = value
    end
  end
  return optionsTable
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
  local optionsTable = load(cfg, path, init or {})
  save(cfg, path)
  return optionsTable
end