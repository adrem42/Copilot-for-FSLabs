-- Drop this file into FSLabs Copilot/custom - Copilot auto-loads
-- any lua files in that directory

local function askDestination(choices)
  return Event.waitForEvent(
    Event.fromSimConnectMenu(
    "Where do you want to send the rocket?", 
    "Please select a destination:", choices
    )
  )
end

local function makeCountdown(numSeconds)
  return coroutine.create(function()
    copilot.logger:warn(
      "You have " .. numSeconds .. " seconds to abort the launch!"
    )
    local countdownStart = os.time()
    for i = numSeconds, 1, - 1 do
      copilot.suspend(1000)
      copilot.logger:info(i .. "...")
    end
    return countdownStart, os.time()
  end)
end

-- VoiceCommands have to be created statically
-- because otherwise the recognizer grammar would need
-- to be recompiled after each new VoiceCommand

local abortWithVoice = VoiceCommand:new "Abort the launch"
local launchCommand = VoiceCommand:new "Launch it"

local function rocketLaunch()

  copilot.logger:info "Preparing for rocket launch..."
  copilot.suspend(5000, 10000)

  local _, destination = askDestination {
    "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"
  }

  copilot.logger:info "Launching the rocket on your command"
  if Event.waitForEventWithTimeout(
    30000, launchCommand:activate()
  ) == Event.TIMEOUT then
    return copilot.logger:warn "The launch routine has timed out"
  end

  local countdownCoro, countdownEvent = copilot.addCallback(makeCountdown(10))
  local abortWithKey = Event.fromKeyPress "A"
  
  local event, getPayload = Event.waitForEvents {
    countdownEvent, abortWithKey, abortWithVoice:activate()
  }

  copilot.removeCallback(countdownCoro)
  abortWithVoice:deactivate()

  if event == countdownEvent then
    copilot.logger:info(
      "The rocket has successfully been launched to " .. destination .. "!"
    )
    local countStart, countEnd = getPayload()
    return copilot.logger:info(
      os.date("Countdown start: %X, ", countStart) .. 
      os.date("countdown end: %X.", countEnd)
    )
  end

  copilot.logger:info(
    event == abortWithKey
    and "The launch was aborted with a key press!"
    or "The launch was aborted with a voice command!"
  )

  local choice = Event.waitForEvent(
    Event.fromSimConnectMenu("Try again?", nil, {"Yes", "No"})
  )

  if choice == 1 then copilot.addCallback(coroutine.create(rocketLaunch)) end
end

copilot.addCallback(coroutine.create(rocketLaunch))
