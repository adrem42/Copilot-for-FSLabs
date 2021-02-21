
file = require "FSL2Lua.FSL2Lua.file"

local optionIndex = {key = 1, value = 2, comment = 3}
local sectionIndex = {title = 1, options = 2, comments = 3}

local options = require "FSLabs Copilot.copilot.options"

local UserOptions = copilot.UserOptions

do
  local failureOptions
  for _, section in ipairs(options) do
    if section[sectionIndex.title] == "Failures" then
      failureOptions = section[sectionIndex.options]
    end
  end
  for _, failure in ipairs(require "FSLabs Copilot.copilot.failurelist") do
    table.insert(failureOptions, failure)
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
      copilot.exit(string.format(
        "Invalid value for option %s: %s. Only the following values are accepted: %s.",
        option[optionIndex.key], iniValue, table.concat(option.values, ", ")
      ))
    end
  else error "wtf" end
  return val ~= nil and val or option[optionIndex.value]
end

local function loadUserOptions(path)
  local iniFile = file.read(path)
  if iniFile then
    for sectionTitle, iniSection in iniFile:gmatch("%[(.-)%]([^%[%]]+)") do
      for _, section in ipairs(options) do
        if section[sectionIndex.title] == sectionTitle then
          local pattern = "([%w _]+)=([%w_%.%+]+)"
          for iniKey, iniValue in iniSection:gmatch(pattern) do
            for _, option in ipairs(section[sectionIndex.options]) do
              if option[optionIndex.key] == iniKey then
                option[optionIndex.value] = checkOption(option, iniValue)
                break
              end
            end
          end
        end
      end
    end
  end
  for _, section in ipairs(options) do
    local sectionTitle = section[sectionIndex.title]:lower()
    UserOptions[sectionTitle] = {}
    for _, option in ipairs(section[sectionIndex.options]) do
      local key, value = option[optionIndex.key], option[optionIndex.value]
      UserOptions[sectionTitle][key] = value
    end
  end
end

local function saveUserOptions(path)
  local f = {}
  for _, section in ipairs(options) do
    table.insert(f, ("[%s]"):format(section[sectionIndex.title]))
    local comments = section[sectionIndex.comments]
    if comments then
      for _, line in ipairs(comments) do
        table.insert(f, ";" .. line)
      end
    end
    for i, option in ipairs(section[sectionIndex.options]) do
      local key, value = option[optionIndex.key], option[optionIndex.value]
      if not (option.hidden and not value) then
        local comment = option[optionIndex.comment]
        if option.format == "hex" then
          value = "0x" .. string.format("%x", value):upper()
        end
        local s = ("%s=%s"):format(key, value or "")
        if comment then s = s .. " ;" .. comment end
        table.insert(f, s)
      end
      if i == #section[sectionIndex.options] then table.insert(f, "") end
    end
  end
  file.write(path, table.concat(f,"\n"), "w")
end

local optionFilePath = APPDIR .. "\\options.ini"
loadUserOptions(optionFilePath)
saveUserOptions(optionFilePath)

if not ipc then return end

local seat = UserOptions.general.PM_seat
UserOptions.general.PM_seat = seat == "left" and 1 or seat == "right" and 2
