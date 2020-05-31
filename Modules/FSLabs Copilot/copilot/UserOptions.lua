local options = {
  {
    "General",
    {
      {"http_port", 8080, "The port of the web MCDU - leave it at default unless you changed it in the FSLabs settings"},
      {"log_level", 2},
      {"PM_seat", "right", "Where the Pilot Monitoring sits in the cockpit - left or right"},
      {"debugger", hidden = true},
      {"debugger_bind", hidden = true}
    }
  },
  {
    "Voice_control",
    {
      {"enable", 1}
    }
  },
  {
    "Callouts",
    {
      {"sound_set", "Hannes"},
      {"enable", 1},
      {"volume", 60, "This sets the maximum volume from 0-100. You can also adjust the volume with the INT volume knob in the cockpit"},
      {"device_id", -1, "-1 is the default device"},
      {"PM_announces_flightcontrol_check", 1},
      {"PM_announces_brake_check", 1}
    }
  },
  {
    "Actions",
    {
      {"enable", 1},
      {"preflight", 1},
      {"after_start", 1},
      {"during_taxi", 1},
      {"lineup", 1},
      {"takeoff_sequence", 1},
      {"after_takeoff", 1},
      {"ten_thousand_dep",1},
      {"ten_thousand_arr", 1},
      {"after_landing", 1},
      {"after_landing_trigger", 1, "explained in the manual"},
      {"FDs_off_after_landing", 1, "explained in the manual"},
      {"packs_on_takeoff", 0, "If you make an ATSU performance request, whatever you enter there will override this option"},
      {"pack2_off_after_landing", 0}
    }
  },
  {
    "Failures",
    {
      {"enable", 0},
      {"global_rate", 1 / 10000},
      {"per_airframe", 1, "track failures separately for each airframe - 1 or 0"},
    },
    {
      "If enable is set to 1, the script will set up random failures in the MCDU when the flight is loaded.",
      "By default, the rate of each failure is set to 1 / 10000 hours.",
      "You can change the global rate and the rate for each individual failure below"
    }
  }
}

file = require "FSL2Lua.FSL2Lua.file"

local optionIndex = {key = 1, value = 2, comment = 3}
local sectionIndex = {title = 1, options = 2, comments = 3}

local UserOptions = {}

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

local function loadUserOptions(path)
  local iniFile = file.read(path)
  if iniFile then
    for sectionTitle, iniSection in iniFile:gmatch("%[(.-)%]([^%[%]]+)") do
      for _, section in ipairs(options) do
        if section[sectionIndex.title] == sectionTitle then
          for iniKey, iniValue in iniSection:gmatch("([%w _]+)=([%w_%.%+]+)") do
            for _, option in ipairs(section[sectionIndex.options]) do
              if option[optionIndex.key] == iniKey then
                option[optionIndex.value] = tonumber(iniValue) or iniValue
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

local seat = UserOptions.general.PM_seat:lower()
UserOptions.general.PM_seat = seat == "left" and 1 or seat == "right" and 2 or copilot.exit("The PM_seat option value needs to be 'left' or 'right'")

return UserOptions