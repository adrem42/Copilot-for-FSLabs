--[[--
Main module.
]]
--- @module copilot

local function addPackagePath(dir)
  package.path = dir .. "\\?.lua;" .. package.path
end

local function addPackageCPath(dir)
  package.cpath = dir .. "\\?.dll;" .. package.cpath
end

APPDIR = debug.getinfo(1, "S").source:gsub(".(.*\\).*", "%1FSLabs Copilot\\")
addPackagePath(APPDIR)
addPackageCPath(ipc.readSTR(0x1000, 256):gsub("(Prepar3D v%d) Files.*", "%1 Add-ons\\Copilot for FSLabs"))

copilot = require "Copilot"
require "copilot.helpers"
copilot.UserOptions = require "copilot.UserOptions"
local err = copilot.init()
if err then copilot.exit(err) end

FSL = require "FSL2Lua"
FSL:setPilot(copilot.UserOptions.general.PM_seat)
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
  local soundDir = copilot.soundDir .. copilot.UserOptions.general.sound_dir .. "\\"
  local sounds = {}
  copilot.sounds = sounds
  function copilot.addSound(path, length, volume)
    local name
    if not path:find("\\") then
      name = path
      path = soundDir .. path
    end
    sounds[name or path] = Sound:new(path .. ".wav", length or 0, volume or 1)
  end
  function copilot.playSound(path, delay)
    if sounds[path] then
      sounds[path]:play(delay or 0)
    end
  end
  dofile(soundDir .. "\\sounds.lua")
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
      local _, err = coroutine.resume(callback, time)
      if err then 
        copilot.exit(err)
      end
      if coroutine.status(callback) == "dead" then
        copilot.removeCallback(key)
      end
    end
  end
end

if debugger.enable then
  local update = copilot.update
  function copilot.update()
    update()
    debugger.debuggee.poll()
  end
  Bind {
    key = debugger.bind,
    onPress = function()
      debugger.debuggee.start(debugger.json)
    end
  }
end

local function setup()

  if copilot.UserOptions.callouts.PM_announces_brake_check == 0 or
    copilot.UserOptions.callouts.PM_announces_flightcontrol_check == 0 or
    copilot.UserOptions.callouts.enable == 0 then
    copilot.UserOptions.actions.during_taxi = 0
  end

  copilot.addCallback(coroutine.create(function() FlightPhaseProcessor:update() end))
  copilot.addCallback(function() Event:runThreads() end)
  if copilot.isVoiceControlEnabled then
    copilot.addCallback(function() Event:fetchRecoResult() end)
  end

  if copilot.UserOptions.callouts.enable == 1 then
    require "copilot.callouts"
    copilot.callouts:setup()
    copilot.callouts:start()
  end
  if copilot.UserOptions.actions.enable == 1 then
    require "copilot.actions"
  end

  if copilot.UserOptions.failures.enable == 1 and not debugger.enable and not ipc.get("failuresSetup") then 
    FSL:disableSequences()
    require "copilot.failures"
    FSL:enableSequences()
  end

  if copilot.isVoiceControlEnabled then
    copilot.recognizer:resetGrammar()
  end

  pcall(function() require "custom" end)
  
end

copilot.logger:info(">>>>>> Script started <<<<<<")
setup()

event.timer(30, "copilot.update")
