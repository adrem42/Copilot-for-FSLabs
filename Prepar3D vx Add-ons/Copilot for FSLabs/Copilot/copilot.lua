
if false then module("copilot") end

require "copilot.util"
require "copilot.copilot.IniUtils"

file = require "FSL2Lua.FSL2Lua.file"

if copilot.UserOptions.general.con_log_level then
  copilot.logger:setLevel(tonumber(copilot.UserOptions.general.con_log_level))
end

local title = ipc.readSTR(0x3D00,256)
copilot.aircraftTitle = title:sub(1, title:find("\0") - 1)

copilot.getTimestamp = ipc.elapsedtime

local setCallbackTimeout = copilot.setCallbackTimeout
function copilot.setCallbackTimeout(...)
  if setCallbackTimeout(...) then
    coroutine.yield()
  end
end

function copilot.await(thread, event) 
  return Event.waitForEvent(event or copilot.getThreadEvent(thread)) 
end

FSL:setPilot(copilot.UserOptions.general.PM_seat)
FSL:setHttpPort(copilot.UserOptions.general.http_port)
FSL:enableSequences()

if copilot.UserOptions.general.button_sleep_mult then
  FSL:setButtonSleepMult(copilot.UserOptions.general.button_sleep_mult)
end

copilot.IS_FSL_AIRCRAFT = FSL:getAcType() ~= nil

local util = require "FSL2Lua.FSL2Lua.util"

copilot.soundDir = APPDIR .. "Copilot\\Sounds\\"
copilot.isVoiceControlEnabled = copilot.UserOptions.voice_control.enable == copilot.UserOptions.TRUE

local debugging = copilot.UserOptions.general.debugger == copilot.UserOptions.ENABLED

if debugging then
  local debuggee = require 'Copilot.libs.vscode-debuggee'
  local json = require 'Copilot.libs.dkjson'
  debuggee.start(json)
  copilot.addCallback(debuggee.poll)
  local bind = copilot.UserOptions.general.debugger_bind
  if bind then Bind { key = bind, onPress = function() debuggee.start(json) end } end
end 

do
  local calloutDir = string.format("%s\\callouts\\%s", copilot.soundDir, copilot.UserOptions.callouts.sound_set)
  local callouts = {}
  copilot.sounds = {callouts = callouts}
  function copilot.addCallout(fileName, length, volume)
    callouts[fileName] = Sound:new(string.format("%s\\%s.wav", calloutDir, fileName), length or 0, volume or 1)
  end
  function copilot.playCallout(fileName, delay)
    if callouts[fileName] then
      callouts[fileName]:play(delay or 0)
    else
      copilot.logger:warn("Callout " .. fileName .. " not found")
    end
  end
  dofile(calloutDir .. "\\sounds.lua")
end

--- Predefined events
copilot.events = {}
--- Predefined voice commands
copilot.voiceCommands = {}

copilot.flightPhases = {}
--- Predefined actions
copilot.actions = {}
--- Predefined sequences
copilot.sequences = {}

Event = require "copilot.Event"
VoiceCommand = require "copilot.VoiceCommand"
FlightPhaseProcessor = require "copilot.FlightPhaseProcessor"
local FlightPhaseProcessor = FlightPhaseProcessor

local function wrapSequencesWithLogging()

  local seqNames = {
    checkFmgcData = "FMGC data check",
    setupEFIS = "EFIS setup",
    afterStart = "After start",
    taxiSequence = "During taxi",
    lineUpSequence = "Line up",
    takeoffSequence = "Takeoff",
    afterTakeoffSequence = "After takeoff",
    tenThousandDep = "Above ten thousand",
    tenThousandArr = "Below ten thousand",
    afterLanding = "After landing"
  }

  for name, seq in pairs(copilot.sequences) do
    if seqNames[name] then
      local isFuncTable = util.isFuncTable(seq)
      local _f = isFuncTable and seq.__call or seq
      local function f(...)
        print("#### Start of action sequence: " .. seqNames[name])
        _f(...)
        print("#### End of action sequence: " .. seqNames[name])
      end
      if isFuncTable then
        copilot.sequences[name].__call = f
      else
        copilot.sequences[name] = f
      end
    end
  end
end

local function setup()

  local options = copilot.UserOptions

  if options.callouts.PM_announces_brake_check == options.FALSE or
    options.callouts.PM_announces_flightcontrol_check == options.FALSE or
    options.callouts.enable == options.FALSE then
    options.actions.during_taxi = options.FALSE
  end
  
  if copilot.IS_FSL_AIRCRAFT then
    FlightPhaseProcessor.start()
  end

  if copilot.IS_FSL_AIRCRAFT and options.callouts.enable == options.TRUE  then
    require "copilot.callouts"
    copilot.callouts:setup()
    copilot.callouts:start()
  end

  if copilot.IS_FSL_AIRCRAFT and options.actions.enable == options.TRUE then
    require "copilot.actions"
  end

  if copilot.IS_FSL_AIRCRAFT then
    require "copilot.ScratchpadClearer"
  end

  local hasUserFiles = false

  local function load(dir)
    local customDir = APPDIR .. "\\Copilot\\" .. dir
    for _file in lfs.dir(customDir) do
      if _file:find("%.lua$") then
        if not hasUserFiles then
          hasUserFiles = true
          print "Loading user lua files:"
        end
        print(dir .. _file)
        dofile(customDir .. _file)
      end
    end
  end

  load "custom_common\\"
  load(copilot.IS_FSL_AIRCRAFT and "custom\\" or "custom_non_fsl\\")

  if not copilot.IS_FSL_AIRCRAFT and not hasUserFiles then
    return false
  end

  wrapSequencesWithLogging()

  if copilot.isVoiceControlEnabled then
    VoiceCommand.resetGrammar()
  end

  for _, event in pairs(copilot.events) do 
    if not event.areActionsSorted then
      event:sortActions()
    end
  end

  if copilot.IS_FSL_AIRCRAFT and options.failures.enable == options.TRUE and not debugging then 
    require "copilot.failures"
  end

  return true
  
end

if setup() then 
  print ">>>>>> Setup finished <<<<<<"
  startUpdating()
end
