-- Drop this file into FSLabs Copilot/custom - Copilot auto-loads
-- any lua files in that directory

local function makeCountdown(numSeconds)
  return coroutine.create(function()
    copilot.logger:warn(
      "You have " .. numSeconds .. " seconds to abort the launch!")
    local countdownStart = os.time()
    for i = numSeconds, 1, - 1 do
      copilot.suspend(1000)
      print(i .. "...")
    end
    return countdownStart, os.time()
  end)
end

-- VoiceCommands need to be created at the start of the script
-- because otherwise the recognizer grammar would need
-- to be recompiled after each dynamically added VoiceCommand

local launchCommand = VoiceCommand:new "Launch it"
local abortWithVoice = VoiceCommand:new "Abort the launch"
local abortWithKey = Event.fromKeyPress "A"

local function rocketLaunch()

  print "Preparing for rocket launch..."
  copilot.suspend(5000, 10000)

  local _, _, destination = Event.waitForEvent(
    Event.fromTextMenu(
      "Where do you want to send the rocket?", 
      "Please select a destination:", {
        "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"
      }
    )
  )

  print "Launching the rocket on your command"
  if Event.waitForEventWithTimeout(
    30000, launchCommand:activate()
  ) == Event.TIMEOUT then
    print "The launch procedure has timed out"
    return
  end

  local countdownCoro, countdownEvent = copilot.addCallback(makeCountdown(10))
  abortWithVoice:activate()
  
  local event, payload = Event.waitForEvents {
    countdownEvent, abortWithKey, abortWithVoice
  }

  copilot.removeCallback(countdownCoro)
  abortWithVoice:deactivate()

  if event == countdownEvent then
    print("The rocket has successfully been launched to " .. destination .. "!")
    local countStart, countEnd = payload()
    print(
      os.date("Countdown start: %X, ", countStart) .. 
      os.date("countdown end: %X.", countEnd)
    )
    return
  end

  print(
    event == abortWithKey
    and "The launch was aborted with a key press!"
    or "The launch was aborted with a voice command!"
  )

  local _, choice = Event.waitForEvent(
    Event.fromTextMenu("Try again?", "", {"Yes", "No"})
  )

  if choice == 1 then copilot.addCoroutine(rocketLaunch) end
end

copilot.addCoroutine(rocketLaunch)
