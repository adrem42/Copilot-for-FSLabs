copilot = copilot or {}

require "copilot.copilot.IniUtils"
local options = require "copilot.copilot.CopilotOptions"

do
  local failureOptions
  for _, section in ipairs(options) do
    if section.title == "Failures" then
      failureOptions = section.keys
    end
  end
  for _, failure in ipairs(require "copilot.copilot.failurelist") do
    table.insert(
      failureOptions, 
      {
        name = failure[1],
        type = "double"
      }
    )
  end
end

local path = APPDIR .. "\\options.ini"
copilot.loadIniFile(path, options, copilot.UserOptions)

local seat = copilot.UserOptions.general.PM_seat
copilot.UserOptions.general.PM_seat = seat == "left" and 1 or seat == "right" and 2