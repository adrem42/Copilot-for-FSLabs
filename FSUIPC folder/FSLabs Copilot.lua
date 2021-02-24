
if false then module("copilot") end

local function addPackagePath(dir)
  package.path = dir .. "\\?.lua;" .. package.path
end

APPDIR = debug.getinfo(1, "S").source:gsub(".(.*\\).*", "%1FSLabs Copilot\\")
addPackagePath(APPDIR)

copilot = package.loadlib("FSLCopilot", "luaopen_FSLCopilot")()
require "copilot.util"
require "copilot.LoadUserOptions"

do
  local err = copilot.init()
  if err then copilot.exit(err) end
end

FSL = require "FSL2Lua"
FSL:setPilot(copilot.UserOptions.general.PM_seat)
FSL:setHttpPort(copilot.UserOptions.general.http_port)
FSL:enableSequences()

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

local callbacks = {}
local callbackNames = {}
local activeThreads = {}

--- Adds a callback to the main callback loop.
--- Dead coroutines are removed automatically.
--- @param callback A function, callable table or thread. It will be called with a timestamp (milliseconds).
--- @string[opt] name Can be used later to remove the callback with @{removeCallback}
--- @int[opt] interval Interval in milliseconds
--- @int[opt] delay Initial delay in milliseconds
--- @return The callback that was passed in
--- @treturn int current timestamp
function copilot.addCallback(callback, name, interval, delay)
  if callbacks[callback] or callbackNames[name] then 
    return callback
  end
  local now = ipc.elapsedtime()
  callbacks[callback] = {
    name = name,
    interval = interval,
    nextTime = 0,
    initTime = delay and now + delay
  }
  if name then callbackNames[name] = callback end
  return callback, now
end

function copilot.isThreadActive(thread) 
  return activeThreads[thread] == true
end

local coroutine = coroutine

--- Adds callback to the main callback loop. The callback will be removed after being called once.
--- For coroutines, it doesn't matter whether you use `addCallback` or callOnce as `addCallback` removes dead
--- coroutines anyway.
--- @param callback A function, callable table or thread. It will be called with a timestamp (milliseconds).
--- @int[opt] delay Initial delay in milliseconds
--- @return The callback that was passed in
--- @treturn int current timestamp
function copilot.callOnce(callback, delay)
  local deletthis
  if util.isCallable(callback) then
    deletthis = function(...)
      callback(...)
      copilot.removeCallback(deletthis)
    end
  elseif type(callback) == "thread" then
    deletthis = callback
  else 
    error("Bad callback parameter", 2) 
  end
  return copilot.addCallback(deletthis, nil, nil, delay)
end

--- Removes a previously added callback.
--- @param key Either the callable itself or the name passed to @{addCallback}
function copilot.removeCallback(key)
  if callbackNames[key] then
    callbackNames[key] = nil
    callbacks[callbackNames[key]] = nil
  elseif callbacks[key] then
    local name = callbacks[key].name
    if name then callbackNames[name] = nil end
    callbacks[key] = nil
  end
end

local function runFuncCallback(callback, _, timestamp)
  callback(timestamp)
end

local function runThreadCallback(thread, _, timestamp)

  activeThreads[thread] = true

  local ok, err = coroutine.resume(thread, timestamp)
  if not ok then
    event.cancel("copilot.update")
    error(err)
  end

  if coroutine.status(thread) == "dead" then
    activeThreads[thread] = nil
    copilot.removeCallback(thread)
  end
end

local function checkCallbackTiming(timestamp, props)

  if props.initTime then
    if timestamp < props.initTime then return false end
    props.initTime = nil
  end

  if props.interval then
    if timestamp < props.nextTime then return false end
    props.nextTime = timestamp + props.interval
  end

  return true
end

local function runCallback(callback, props, timestamp)
  local shouldRun = checkCallbackTiming(timestamp, props)
  if shouldRun then
    if util.isCallable(callback) then
      runFuncCallback(callback, props, timestamp)
    elseif type(callback) == "thread" then
      runThreadCallback(callback, props, timestamp)
    end
  end
end

function copilot.update()
  local timestamp = ipc.elapsedtime()
  for callback, props in pairs(callbacks) do
    runCallback(callback, props, timestamp)
  end
end

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

  copilot.addCallback(coroutine.create(function() FlightPhaseProcessor:update() end), "FlightPhaseProcessor")
  copilot.addCallback(Event.resumeThreads)
  if copilot.isVoiceControlEnabled then
    event.flag(0, "Event.fetchRecoResults")
  end

  if options.callouts.enable == options.TRUE then
    require "copilot.callouts"
    copilot.callouts:setup()
    copilot.callouts:start()
  end

  if options.actions.enable == options.TRUE then
    require "copilot.actions"
  end

  require "copilot.ScratchpadClearer"

  local customDir = APPDIR .. "custom\\"
  local userFiles = false
  for _file in lfs.dir(customDir) do
    if _file:find("%.lua$") then
      if not userFiles then
        userFiles = true
        copilot.logger:info "Loading user lua files:"
      end
      copilot.logger:info(_file)
      dofile(customDir .. _file)
    end
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

  if options.failures.enable == options.TRUE and not debugger.enable then 
    require "copilot.failures"
  end
  
end

setup()
event.timer(30, "copilot.update")
copilot.logger:info ">>>>>> Setup finished <<<<<<"