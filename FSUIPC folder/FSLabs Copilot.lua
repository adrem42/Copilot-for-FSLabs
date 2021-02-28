
if false then module("copilot") end

local function addPackagePath(dir)
  package.path = dir .. "\\?.lua;" .. package.path
end

APPDIR = debug.getinfo(1, "S").source:gsub(".(.*\\).*", "%1FSLabs Copilot\\")
addPackagePath(APPDIR)

copilot = package.loadlib("FSLCopilot", "luaopen_FSLCopilot")()
require "copilot.util"
require "copilot.LoadUserOptions"

FSL = require "FSL2Lua"
FSL:setPilot(copilot.UserOptions.general.PM_seat)
FSL:setHttpPort(copilot.UserOptions.general.http_port)
FSL:enableSequences()

copilot.FSL_AIRCRAFT = FSL:getAcType() ~= nil

do
  local err = copilot.init()
  if err then copilot.exit(err) end
end

local util = require "FSL2Lua.FSL2Lua.util"

copilot.soundDir = APPDIR .. "\\Sounds\\"
copilot.isVoiceControlEnabled = copilot.UserOptions.voice_control.enable == copilot.UserOptions.TRUE

local debugger = {
  enable = copilot.UserOptions.general.debugger == copilot.UserOptions.TRUE,
  bind = copilot.UserOptions.general.debugger_bind
}
if debugger.enable then
  debugger.debuggee = require 'FSLabs Copilot.libs.vscode-debuggee'
  debugger.json = require 'FSLabs Copilot.libs.dkjson'
  debugger.debuggee.start(debugger.json)
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
require "copilot.callbacks"

if debugger.enable then
  local update = copilot.update
  function copilot.update(...)
    update(...)
    debugger.debuggee.poll()
  end
  if debugger.bind then
    Bind {
      key = debugger.bind,
      onPress = function()
        debugger.debuggee.start(debugger.json)
      end
    }
  end
end

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
        copilot.logger:info("#### Start of action sequence: " .. seqNames[name])
        _f(...)
        copilot.logger:info("#### End of action sequence: " .. seqNames[name])
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
  
  if copilot.FSL_AIRCRAFT then
    FlightPhaseProcessor.start()
  end

  if copilot.isVoiceControlEnabled then
    event.flag(0, "Event.fetchRecoResults")
  end

  if copilot.FSL_AIRCRAFT and options.callouts.enable == options.TRUE  then
    require "copilot.callouts"
    copilot.callouts:setup()
    copilot.callouts:start()
  end

  if copilot.FSL_AIRCRAFT and options.actions.enable == options.TRUE then
    require "copilot.actions"
  end

  if copilot.FSL_AIRCRAFT then
    require "copilot.ScratchpadClearer"
  end

  local userFiles = false

  local function load(dir)
    local customDir = APPDIR .. dir
    for _file in lfs.dir(customDir) do
      if _file:find("%.lua$") then
        if not userFiles then
          userFiles = true
          copilot.logger:info "Loading user lua files:"
        end
        copilot.logger:info(dir .. _file)
        dofile(customDir .. _file)
      end
    end
  end

  load "custom_common\\"
  load(copilot.FSL_AIRCRAFT and "custom\\" or "custom_non_fsl\\")

  wrapSequencesWithLogging()

  if copilot.isVoiceControlEnabled then
    VoiceCommand.resetGrammar()
  end

  for _, event in pairs(copilot.events) do 
    if not event.areActionsSorted then
      event:sortActions()
    end
  end

  if copilot.FSL_AIRCRAFT 
    and options.failures.enable == options.TRUE 
    and not debugger.enable then 
    require "copilot.failures"
  end
  
end

setup()
copilot.resume()
copilot.logger:info ">>>>>> Setup finished <<<<<<"