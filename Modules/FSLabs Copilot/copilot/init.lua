local options = {
  {
    "General",
    {
      {"http_port", 8080, "The port of the web MCDU"},
      {"log_level", 2},
      {"PM_seat", "right", "Where the Pilot Monitoring sits in the cockpit - left or right"},
      {"sound_dir", "Hannes"},
      {"debug", hidden = true},
      {"debug_bind", hidden = true}
    }
  },
  {
    "Voice_control",
    {
      {"enable", 1},
      {"confidence_coefficient", 1, "Set above/below 1 to increase/decrease the recognition confidence threshold"}
    }
  },
  {
    "Callouts",
    {
      {"enable", 1},
      {"volume", 60, "This sets the maximum volume from 0-100. You can also adjust the volume with the INT volume knob in the cockpit"},
      {"device_id", -1, "-1 is the default device"},
      {"PM_announces_V1", 1},
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

local UserOptions = {}

do
  local failureOptions
  for _, v in ipairs(options) do
    if v[1] == "Failures" then
      failureOptions = v[2]
    end
  end
  for _, v in ipairs(require "FSLabs Copilot.copilot.failurelist") do
    table.insert(failureOptions, v)
  end
end

local function loadUserOptions(path)
  local f = file.read(path)
  if f then
    for sectionName, ini_section in f:gmatch("%[(.-)%]([^%[%]]+)") do
      for _, section in ipairs(options) do
        if section[1] == sectionName then
          for key, value in ini_section:gmatch("([%w _]+)=([%w_%.%+]+)") do
            for _, option in ipairs(section[2]) do
              if option[1] == key then
                option[2] = tonumber(value) or value
              end
            end
          end
        end
      end
    end
  end
  for _, section in ipairs(options) do
    local sectionName = section[1]:lower()
    UserOptions[sectionName] = {}
    for _, option in ipairs(section[2]) do
      local key, value = option[1], option[2]
      UserOptions[sectionName][key] = value
    end
  end
end

local function saveUserOptions(path)
  local f = {}
  for _, section in ipairs(options) do
    table.insert(f, ("[%s]"):format(section[1]))
    local comments = section[3]
    if comments then
      for _, line in ipairs(comments) do
        table.insert(f, ";" .. line)
      end
    end
    for i, option in ipairs(section[2]) do
      local key, value = option[1], option[2]
      if not (option.hidden and not value) then
        local comment = option[3]
        if option.format == "hex" then
          value = "0x" .. string.format("%x", value):upper()
        end
        local s = ("%s=%s"):format(key, value or "")
        if comment then s = s .. " ;" .. comment end
        table.insert(f, s)
      end
      if i == #section[2] then table.insert(f, "") end
    end
  end
  file.write(path, table.concat(f,"\n"), "w")
end

local optionFilePath = APPDIR .. "\\options.ini"
loadUserOptions(optionFilePath)
saveUserOptions(optionFilePath)

if not ipc then return end

do
  local seat = UserOptions.general.PM_seat
  if seat == "left" then FSL_SEAT_PM = 1
  elseif seat == "right" then FSL_SEAT_PM = 2 end
end
FSL = require "FSL2Lua"
FSL:setPilot(FSL_SEAT_PM)
FSL:enableSequences()

VOLUME = UserOptions.callouts.volume
SOUNDDIR = APPDIR .. "\\Sounds\\"
copilot.isVoiceControlEnabled = UserOptions.voice_control.enable == 1

return UserOptions