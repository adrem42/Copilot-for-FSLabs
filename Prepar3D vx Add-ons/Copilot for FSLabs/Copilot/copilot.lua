
if false then module("copilot") end

require "copilot.extensions"
require "copilot.util"
require "copilot.copilot.IniUtils"

file = require "FSL2Lua.FSL2Lua.file"

if copilot.UserOptions.general.con_log_level then
  copilot.logger:setLevel(tonumber(copilot.UserOptions.general.con_log_level))
end

copilot.getTimestamp = ipc.elapsedtime
copilot.__dummy = function() end

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

require "copilot.initSounds"

--- Predefined events
copilot.events = {}
--- Predefined voice commands
copilot.voiceCommands = {}

copilot.flightPhases = {}
--- Predefined actions
copilot.actions = {}
--- Predefined sequences
copilot.sequences = {}
--- Predefined checklists
copilot.checklists = {}

Event = require "copilot.Event"
VoiceCommand = require "copilot.VoiceCommand"
if copilot.isVoiceControlEnabled then
  require "copilot.PhraseUtils"
end
require "copilot.Checklist"
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
    local function clearVars()
      copilot.mcduWatcher:clearVar "V1"
      copilot.mcduWatcher:clearVar "Vr"
      copilot.mcduWatcher:clearVar "V2"
      copilot.mcduWatcher:clearVar "Vs"
      copilot.mcduWatcher:clearVar "Vf"
      copilot.mcduWatcher:clearVar "takeoffFlaps"
      copilot.mcduWatcher:clearVar "takeoffRwy"
      copilot.mcduWatcher:clearVar "flyingCircuits"
      copilot.mcduWatcher:clearVar "isFmgcSetup"
    end
    copilot.events.landing:addAction(clearVars)
    copilot.events.aboveTenThousand:addAction(clearVars)
  end

  require "copilot.sequences"

  if copilot.IS_FSL_AIRCRAFT and options.callouts.enable == options.TRUE  then
    require "copilot.callouts"
    copilot.callouts:setup()
    copilot.callouts:start()
  end

  if copilot.IS_FSL_AIRCRAFT and options.actions.enable == options.TRUE then
    require "copilot.actions"
  end

  if copilot.IS_FSL_AIRCRAFT and options.checklists.enable == options.TRUE and copilot.isVoiceControlEnabled then
    require "copilot.initChecklists"
  end

  if copilot.IS_FSL_AIRCRAFT then
    require "copilot.ScratchpadClearer"
  end

  local realResetGrammar = VoiceCommand.resetGrammar
  local grammarWasReset = false

  function VoiceCommand.resetGrammar()
    realResetGrammar()
    grammarWasReset = true
  end

  local hasPlugins = false

  local function loadPlugins(dir)
    dir = dir .. "\\"
    local pluginDir = APPDIR .. "\\Copilot\\" .. dir
    local copilotPrefix = "copilot_"
    for _file in lfs.dir(pluginDir) do
      if _file:sub(1, #copilotPrefix) ~= copilotPrefix then
        if _file:find("%.lua$") then
          if not hasPlugins then
            hasPlugins = true
            print "Loading plugins:"
          end
          print(dir .. _file)
          dofile(pluginDir .. _file)
        end
      end
    end
  end

  loadPlugins "custom_common"
  loadPlugins(copilot.IS_FSL_AIRCRAFT and "custom" or "custom_non_fsl")

  VoiceCommand.resetGrammar = realResetGrammar

  if copilot.isVoiceControlEnabled and options.voice_control.mute_on_startup == options.TRUE then
    muteCopilot()
  end

  if copilot.isVoiceControlEnabled and not grammarWasReset then
    VoiceCommand.resetGrammar()
  end

  if not copilot.IS_FSL_AIRCRAFT and not hasPlugins then
    return false
  end

  wrapSequencesWithLogging()

  for _, event in pairs(copilot.events) do 
    if not event.areActionsSorted then
      event:sortActions()
    end
  end

  if copilot.IS_FSL_AIRCRAFT and options.failures.enable == options.TRUE and not debugging then 
    require "copilot.failures"
  end

  copilot.scratchpadClearer.setMessages {"GPS PRIMARY", "ENTER DEST DATA"}

  return true
  
end

if setup() then 
  print ">>>>>> Setup finished"
  print(">>>>>> Voice control is " .. (copilot.isVoiceControlEnabled and "enabled" or "disabled"))
  startUpdating()
end
