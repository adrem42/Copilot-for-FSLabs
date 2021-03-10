copilot = copilot or {}
file = require "FSL2Lua.FSL2Lua.file"

local options = require "Copilot.copilot.options"
local UserOptions = copilot.UserOptions

do
  local failureOptions
  for _, section in ipairs(options) do
    if section.title == "Failures" then
      failureOptions = section.keys
    end
  end
  for _, failure in ipairs(require "Copilot.copilot.failurelist") do
    table.insert(failureOptions, {name = failure[1]})
  end
end

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
      if iniValue == enumVal then
        val = iniValue
        break
      end
    end
    if val == nil and option.required then
      error(string.format(
        "Invalid value for option %s: %s. Only the following values are accepted: %s.",
        option.name, iniValue, table.concat(option.values, ", ")
      ))
    end
  else error "wtf" end
  return val
end

local function loadUserOptions(path)
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
    UserOptions[sectionTitle] = {}
    for _, option in ipairs(section.keys) do
      option.value = option.value ~= nil and option.value or option.default
      local key, value = option.name, option.value
      UserOptions[sectionTitle][key] = value
    end
  end
end

local function saveUserOptions(path)
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

local optionFilePath = APPDIR .. "\\options.ini"
loadUserOptions(optionFilePath)
saveUserOptions(optionFilePath)

if not ipc then return UserOptions end

local seat = UserOptions.general.PM_seat
UserOptions.general.PM_seat = seat == "left" and 1 or seat == "right" and 2