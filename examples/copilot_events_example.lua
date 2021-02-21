-- Drop this file into FSLabs Copilot/custom - Copilot auto-loads
-- any lua files in that directory

local function askDestination(choices)
  local destination
  repeat 
    destination = Event.waitForEvent(
      Event.fromSimConnectMenu(
      "Where do you want to send the rocket?", 
      "Please select a destination:", choices
      )
    )
  until destination ~= Event.MENU_REPLACED
  return destination
end

local function makeCountdown(numSeconds)
  local e = Event:new()
  local co = coroutine.create(function()
    copilot.logger:warn(
      "You have " .. numSeconds .. " seconds to abort the launch!"
    )
    local countdownStart = os.time()
    for i = numSeconds, 1, - 1 do
      copilot.suspend(1000)
      copilot.logger:info(i .. "...")
    end
    e:trigger(countdownStart, os.time())
  end)
  return co, e
end

-- VoiceCommands have to be created in the top-level scope
-- because otherwise the recognizer grammar would need
-- to be reset for each VoiceCommand you create dynamically.

local abortWithVoice = VoiceCommand:new "Abort the launch"
local launchCommand = VoiceCommand:new "Launch it"

local function rocketLaunch()

  copilot.logger:info "Preparing for rocket launch..."
  copilot.suspend(5000, 10000)

  local destination = askDestination {
    "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"
  }

  copilot.logger:info "Launching the rocket on your command"
  if Event.waitForEventWithTimeout(
    30000, launchCommand:activate()
  ) == Event.TIMEOUT then
    return copilot.logger:warn "The launch routine has timed out"
  end

  local countdownCoro, countdownEnd = makeCountdown(10)
  copilot.addCallback(countdownCoro)

  local abortWithKey = Event.fromKeyPress "A"
  
  local event, getPayload = Event.waitForEvents {
    countdownEnd, abortWithKey, abortWithVoice:activate()
  }

  abortWithVoice:deactivate()
  copilot.removeCallback(countdownCoro)

  if event == countdownEnd then
    copilot.logger:info(
      "The rocket has successfully been launched to " .. destination .. "!"
    )
    local countStart, countEnd = getPayload()
    copilot.logger:info(
      os.date("Countdown start: %X, ", countStart) .. 
      os.date("countdown end: %X.", countEnd)
    )
  elseif event == abortWithKey then
    copilot.logger:info "The launch was aborted with a key press!"
  elseif event == abortWithVoice then
    copilot.logger:info "The launch was aborted with a voice command!"
  end
end

copilot.addCallback(coroutine.create(rocketLaunch))