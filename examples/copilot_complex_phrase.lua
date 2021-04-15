-- Drop this file into FSLabs Copilot/custom - Copilot auto-loads
-- any lua files in that directory
-- Read more @{plugins.md|here}

local MCDU_ERROR = "unexpected display state"
local getWeatherSequence, ensureAirportSelected, pressAndWait
local alphabet = {
  "Alfa",
  "Bravo",
  "Charlie",
  "Delta",
  "Echo",
  "Foxtrot",
  "Golf",
  "Hotel",
  "India",
  "Juliett",
  "Kilo",
  "Lima",
  "Mike",
  "November",
  "Oscar",
  "Papa",
  "Quebec",
  "Romeo",
  "Sierra",
  "Tango",
  "Uniform",
  "Victor",
  "Whiskey",
  "X-ray",
  "Yankee",
  "Zulu"
}

local variants = {}
for _, code in pairs(alphabet) do
  variants[#variants+1] = {propVal = code:sub(1, 1), variant = code}
end
local alphabetPhrase  = Phrase.new():append(variants, "letter")
local reportPhrase    = Phrase.new():append {
  propName = "reportType",
  variants = {"metar", "forecast", {propVal = "metar", variant = "weather"}}
}

-- Some examples of what you can say with this:
-- 'Get the weather please'
-- 'Get the destination forecast please'
-- 'Get the METAR at Echo November Golf Mike please'

local getWeather = VoiceCommand:new {

  confidence = 0.9,

  phrase = Phrase.new()
    :append "get the"
    :append {
      Phrase.new()
        :appendOptional("destination", "destination")
        :append(reportPhrase),
      Phrase.new()
        :append(reportPhrase)
        :append "at"
        :append {
          propName = "ICAO",
          asString = "ICAO code",
          variants = Phrase.new()
            :append(alphabetPhrase, "1"):append(alphabetPhrase, "2")
            :append(alphabetPhrase, "3"):append(alphabetPhrase, "4")
        }
    }
    :appendOptional("please", "isPolite"),

  action = function(vc, res)
    if not res:getProp "isPolite" then
      copilot.speak "You have to ask nicely"
    else
      local numTries = 0
      local airport
      if res:getProp "ICAO" then
        airport = 
          res:getProp("ICAO", "1", "letter") ..
          res:getProp("ICAO", "2", "letter") ..
          res:getProp("ICAO", "3", "letter") ..
          res:getProp("ICAO", "4", "letter") 
      else
        airport = res:getProp "destination" or "origin"
      end
      repeat 
        local ok, err = pcall(
          getWeatherSequence, res:getProp "reportType", airport
        )
        numTries = numTries + 1
        if not ok and err ~= MCDU_ERROR then 
          vc:activate()
          error(err) 
        end
      until ok or numTries == 5
    end
    vc:activate()
  end
}

Bind {key = "SHIFT+F", onPress = function() getWeather:activate() end}

getWeatherSequence = function(reportType, airport)
  if not FSL.MCDU:getString():find "MCDU MENU" then
    pressAndWait(FSL.PED_MCDU_KEY_MENU, "MCDU MENU")
  end
  pressAndWait(FSL.PED_MCDU_LSK_L6, "ATSU DATALINK")
  pressAndWait(FSL.PED_MCDU_LSK_R2, "AOC MENU")
  pressAndWait(FSL.PED_MCDU_LSK_R2, "ATIS/WX")
  if airport == "destination" then
    ensureAirportSelected(97, FSL.PED_MCDU_LSK_L2)
  elseif airport == "origin" then
    ensureAirportSelected(49, FSL.PED_MCDU_LSK_L1)
  else
    ensureAirportSelected(airport)
  end
  if reportType == "forecast" then
    FSL.PED_MCDU_LSK_R5()
  else
    FSL.PED_MCDU_LSK_R6()
  end
end

ensureAirportSelected = function(firstArg, selectKey)
  local disp = FSL.MCDU:getString()
  local manSelected = false
  local autoSelected, ICAO 
  if type(firstArg) == "string" then
    ICAO = firstArg
    autoSelected = false
  else
    autoSelected = FSL.MCDU:getArray()[firstArg].isBold
    ICAO = disp:sub(firstArg, firstArg + 3)
  end
  local hasManualEntry
  local freeSlot
  local manEntryIdx = 69
  for i = 1, 4 do
    if disp:sub(manEntryIdx, manEntryIdx) ~= "[" then
      hasManualEntry = true
      if disp:sub(manEntryIdx, manEntryIdx + 3) == ICAO then
        manSelected = true
      end
    else
      freeSlot = freeSlot or i
    end
    manEntryIdx = manEntryIdx + FSL.MCDU.LENGTH_LINE * 2
  end
  if not manSelected and (not autoSelected or hasManualEntry) then
    if selectKey then 
      pressAndWait(selectKey)
    else
      copilot.scratchpadClearer.clearScratchpad()
      FSL.MCDU:type(ICAO)
    end
    pressAndWait(FSL["PED_MCDU_LSK_R" .. (freeSlot or 1)])
  end
end

pressAndWait = function(keyToPress, checkFunc, waitMin, waitMax, init, timeout)
  init = init or FSL.MCDU:getString()
  if not checkFunc then
    checkFunc = function(disp) return disp ~= init end
  elseif type(checkFunc) == "string" then
    local sub = checkFunc
    local firstLine = FSL.MCDU:getLine(1, init)
    checkFunc = function(disp)
      if disp:find(sub) then return true end
      if FSL.MCDU:getLine(1, disp) ~= firstLine then
        -- Oh no, someone opened a different page in our MCDU!
        error(MCDU_ERROR, 0) 
      end
    end
  end
  if timeout ~= 0 then 
    timeout = timeout or 10000
    local timedOut = not checkWithTimeout(timeout, function()
      keyToPress() 
      -- Press again every second if nothing happens, for good measure
      return checkWithTimeout(1000, function()
        ipc.sleep(100)
        return checkFunc(FSL.MCDU:getString())
      end)
    end)
    if timedOut then error(MCDU_ERROR, 0) end
  else
    repeat ipc.sleep(100) until checkFunc(FSL.MCDU:getString())
  end
  ipc.sleep(math.random(waitMin or 300, waitMax or 1000))
  if not checkFunc(FSL.MCDU:getString()) then error(MCDU_ERROR, 0) end
end