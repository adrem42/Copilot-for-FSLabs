copilot = copilot or {}

require "copilot.copilot.IniUtils"
local options = require "copilot.copilot.CopilotOptions"
local file = require "FSL2Lua.FSL2Lua.file"

local failureOptions
for _, section in ipairs(options) do
  if section.title == "Failures" then
    failureOptions = section.keys
  end
end
for _, failure in ipairs(require "copilot.copilot.failurelist") do
  table.insert(failureOptions, {name = failure[1], type = "double"})
end

local path = APPDIR .. "\\options.ini"
copilot.loadIniFile(path, options, copilot.UserOptions)
if not FSL or not FSL:getAcType() then
  copilot.UserOptions.general.PM_seat = 1
  copilot.UserOptions.general.http_port = 8080
  return
end

local function processSeatOption(key)
  local opt = copilot.UserOptions.general[key]
  if opt == "left" then
    copilot.UserOptions.general[key] = 1
  elseif opt == "right" then
    copilot.UserOptions.general[key] = 2
  end
  return opt
end

local pmSeatOpt = processSeatOption "PM_seat"
local pfSeatOpt = processSeatOption "PF_seat"

if pmSeatOpt and pfSeatOpt then
  error("Please specify either PM_seat or PF_seat")
elseif pmSeatOpt then
  copilot.UserOptions.general.PF_seat = pmSeatOpt == 1 and 2 or 1
elseif pfSeatOpt then
  copilot.UserOptions.general.PM_seat = pfSeatOpt == 1 and 2 or 1
end

if not pmSeatOpt and not pfSeatOpt then
  local gaugesIni = file.read(FSL.FSLabsPath .. "A320XGauges.ini")
  local seatUsed = tonumber(gaugesIni:match "SeatUsed=(%d)") or 1
  if seatUsed ~= 1 and seatUsed ~= 2 then
    error("Unrecognized seat selection in A320XGauges.ini, please explicitly specify PF_seat or PM_seat in the general section in options.ini")
  end
  copilot.UserOptions.general.PM_seat = seatUsed == 1 and 2 or 1
  copilot.UserOptions.general.PF_seat = seatUsed
end

if not copilot.UserOptions.general.http_port then
  local httpServerIni = file.read(FSL.FSLabsPath .. "httpServer.ini")
  copilot.UserOptions.general.http_port = tonumber(httpServerIni:match "Port=(%d+)") or 8080
end