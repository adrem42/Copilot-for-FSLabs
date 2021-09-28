
if false then module("copilot") end

require "copilot.util"
require "copilot.copilot.IniUtils"

file = require "FSL2Lua.FSL2Lua.file"

copilot.logger:setLevel(tonumber(copilot.UserOptions.general.con_log_level))



FSL:setPilot(copilot.UserOptions.general.PM_seat)
FSL:setHttpPort(copilot.UserOptions.general.http_port)
FSL:enableSequences()

if copilot.UserOptions.general.button_sleep_mult then
  FSL:setButtonSleepMult(copilot.UserOptions.general.button_sleep_mult)
end

copilot.IS_FSL_AIRCRAFT = FSL.fullAcType ~= nil

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
--VoiceCommand = require "copilot.VoiceCommand"
if copilot.isVoiceControlEnabled then
  copilot.recognizer = copilot.Recognizer.new(copilot.UserOptions.voice_control.device, "adrem42.Copilot.MuteInternal")
  VoiceCommand = copilot.recognizer.VoiceCommand
  PhraseUtils = copilot.recognizer.PhraseUtils
  PhraseBuilder = copilot.recognizer.PhraseBuilder
else
  VoiceCommand = require "copilot.VoiceCommand"()
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
    afterLanding = "After landing",
    parking = "Parking",
    securingTheAircraft = "Securing the aircraft"
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

    print("Aircraft type: " .. FSL.fullAcType)

    require "copilot.sequences"
    require "copilot.ScratchpadClearer"

    copilot.scratchpadClearer.setMessages {"GPS PRIMARY", "ENTER DEST DATA"}

    if options.callouts.enable == options.TRUE  then
      require "copilot.callouts"
      copilot.callouts:setup()
      copilot.callouts:start()
    end
  
    if options.actions.enable == options.TRUE then
      require "copilot.actions"
    end
  
    if options.checklists.enable == options.TRUE and copilot.isVoiceControlEnabled then
      require "copilot.initChecklists"
    end

    FlightPhaseProcessor.start()

    local function clearVar(key) copilot.mcduWatcher:clearVar(key) end
    local function clearVars()
      clearVar "V1"
      clearVar "Vr"
      clearVar "V2"
      clearVar "Vs"
      clearVar "Vf"
      clearVar "takeoffFlaps"
      clearVar "takeoffRwy"
      clearVar "flyingCircuits"
      clearVar "isFmgcSetup"
      clearVar "transAlt"
    end
    copilot.events.landing:addAction(clearVars)
    copilot.events.aboveTenThousand:addAction(clearVars)

  end

  if copilot.isVoiceControlEnabled then
    local confidenceBaseline = options.voice_control.confidence_baseline
    local confidenceOverride = options.voice_control.confidence_override
    if confidenceOverride then
      for _, vc in pairs(Event.voiceCommands) do
        vc:setConfidence(confidenceOverride)
      end
    elseif confidenceBaseline ~= VoiceCommand.DefaultConfidence then
      local mult = confidenceBaseline / VoiceCommand.DefaultConfidence
      for _, vc in pairs(Event.voiceCommands) do
        vc:setConfidence(vc.confidence * mult)
      end
    end
  end

  local hasPlugins = false

  local function loadPlugins(dir)
    dir = dir .. "\\"
    local pluginDir = APPDIR .. "\\Copilot\\" .. dir
    for _file in lfs.dir(pluginDir) do
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

  loadPlugins "custom_common"
  loadPlugins(copilot.IS_FSL_AIRCRAFT and "custom" or "custom_non_fsl")

  if copilot.IS_FSL_AIRCRAFT then
    if options.failures.enable == options.TRUE and not debugging then 
      require "copilot.failures"
    end
    wrapSequencesWithLogging()
  elseif not hasPlugins then
    ipc.exit()
  end

  if copilot.isVoiceControlEnabled then
    VoiceCommand.resetGrammar()
    if options.voice_control.mute_on_startup == options.TRUE then
      muteCopilot()
    end
  end

  for _, event in pairs(copilot.events) do 
    if not event.areActionsSorted then
      event:sortActions()
    end
  end

end

setup() 
print ">>>>>> Setup finished"
print(">>>>>> Voice control is " .. (copilot.isVoiceControlEnabled and "enabled" or "disabled"))
if copilot.isVoiceControlEnabled then
  print(">>>>>> Input device: " .. copilot.recognizer:deviceName())
end
print(">>>>>> Output device: " .. copilot.getOutputDeviceName())