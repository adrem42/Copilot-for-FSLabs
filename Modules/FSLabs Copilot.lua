--[[--
Main module.
]]
--- @module copilot

local function addPackagePath(dir)
  package.path = dir .. "\\?.lua;" .. package.path
end

APPDIR = debug.getinfo(1, "S").source:gsub(".(.*\\).*", "%1FSLabs Copilot\\")
addPackagePath(APPDIR)

copilot = package.loadlib("FSLCopilot", "luaopen_FSLCopilot")()
require "copilot.helpers"
copilot.UserOptions = require "copilot.UserOptions"
local err = copilot.init()
if err then copilot.exit(err) end

FSL = require "FSL2Lua"
FSL:setPilot(copilot.UserOptions.general.PM_seat)
FSL:setHttpPort(copilot.UserOptions.general.http_port)
FSL:enableSequences()

copilot.soundDir = APPDIR .. "\\Sounds\\"
copilot.isVoiceControlEnabled = copilot.UserOptions.voice_control.enable == 1

local debugger = {
  enable = copilot.UserOptions.general.debugger == 1,
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

require "copilot.Event"
local Event = Event
FlightPhaseProcessor = require "copilot.FlightPhaseProcessor"
local FlightPhaseProcessor = FlightPhaseProcessor

local callbacks = {}

--- adds function or couroutine func to the main callback loop
--- @param func a function or thread
--- @param name optional string which can be used to remove the callback with @{removeCallback}
--- @return func

function copilot.addCallback(func, name)
  callbacks[name or func] = func
  return func
end

function copilot.callOnce(func, timeOffset)
  local deletthis
  local callAt = ipc.elapsedtime() + (timeOffset or 0) 
  deletthis = function(...)
    if ipc.elapsedtime() > callAt then
      func(...)
      copilot.removeCallback(deletthis)
    end
  end
  copilot.addCallback(deletthis)
end

--- removes a previously added callback
--- @param key Either the function or thread itself or the name argument passed to @{addCallback}
function copilot.removeCallback(key)
  callbacks[key] = nil
end

function copilot.update(time)
  for key, callback in pairs(callbacks) do
    if type(callback) == "function" then
      callback(time)
    elseif type(callback) == "thread" then
      if coroutine.status(callback) == "dead" then
        copilot.removeCallback(key)
      end
      local _, err = coroutine.resume(callback, time)
      if err then error(err) end
    end
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

local function setup()

  if copilot.UserOptions.callouts.PM_announces_brake_check == 0 or
    copilot.UserOptions.callouts.PM_announces_flightcontrol_check == 0 or
    copilot.UserOptions.callouts.enable == 0 then
    copilot.UserOptions.actions.during_taxi = 0
  end

  copilot.addCallback(coroutine.create(function() FlightPhaseProcessor:update() end))
  copilot.addCallback(Event.resumeThreads)
  if copilot.isVoiceControlEnabled then
    copilot.addCallback(Event.fetchRecoResult)
  end

  if copilot.UserOptions.callouts.enable == 1 then
    require "copilot.callouts"
    copilot.callouts:setup()
    copilot.callouts:start()
  end
  if copilot.UserOptions.actions.enable == 1 then
    require "copilot.actions"
  end

  local customDir = APPDIR .. "\\custom"
  for file in lfs.dir(customDir) do
    if file:find(".lua$") then
      dofile(customDir .. "\\" .. file)
    end
  end 

  if copilot.isVoiceControlEnabled then
    copilot.recognizer:resetGrammar()
  end

  if copilot.UserOptions.failures.enable == 1 and not debugger.enable then 
    require "copilot.failures"
  end
  
end

setup()
event.timer(30, "copilot.update")

copilot.logger:info(">>>>>> Script started <<<<<<")
