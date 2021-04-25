-- Drop this file into FSLabs Copilot/custom - Copilot auto-loads
-- any lua files in that directory
-- Read more @{plugins.md|here}

local MCDU_ERROR = "unexpected display state"
local getWeatherSequence, ensureAirportSelected, pressAndWait

local reportTypePhrase = PhraseBuilder.new():append {
  propName = "reportType",
  choices = {"metar", "forecast", {propVal = "metar", choice = "weather"}}
}:build "report type"

-- Some examples of what you can say with this:
-- 'Get the weather please'
-- 'Get the destination forecast please'
-- 'Get the METAR at Echo November Golf Mike please'

local getWeather = VoiceCommand:new {

  confidence = 0.9,

  phrase = PhraseBuilder.new()
    :append "get the"
    :append {
      PhraseBuilder.new()
        :appendOptional({"destination", "arrival"}, "destination")
        :append(reportTypePhrase)
        :build(),
      PhraseBuilder.new()
        :append(reportTypePhrase)
        :append "at"
        :append(PhraseUtils.getPhrase "ICAOairportCode", "ICAO")
        :build()
    }
    :appendOptional("please", "isPolite")
    :build(),

  action = function(vc, res)

    if not res:getProp "isPolite" then
      copilot.speak "You have to ask nicely"
      vc:activate()
      return
    end

    local reportType = res:getProp "reportType"
    local airport = 
      PhraseUtils.getPhraseResult("ICAOairportCode", res, "ICAO") or 
      res:getProp "destination" and "destination" or 
      "origin"

    local numTries, maxTries = 0, 5
    repeat 
      local ok, err = pcall(getWeatherSequence, reportType, airport)
      if not ok and err ~= MCDU_ERROR then 
        vc:activate()
        error(err) 
      end
      numTries = numTries + 1
    until ok or numTries == maxTries

    vc:activate()
  end
}

Bind {key = "SHIFT+F", onPress = function() getWeather:activate() end}

getWeatherSequence = function(reportType, airport)
  local disp = FSL.MCDU:getString()
  if not disp:find "ATIS/WX" then
    if not disp:find "MCDU MENU" then
      pressAndWait(FSL.PED_MCDU_KEY_MENU, "MCDU MENU", nil, nil, disp)
    end
    pressAndWait(FSL.PED_MCDU_LSK_L6, "ATSU DATALINK")
    pressAndWait(FSL.PED_MCDU_LSK_R2, "AOC MENU")
    pressAndWait(FSL.PED_MCDU_LSK_R2, "ATIS/WX")
  end
  ensureAirportSelected(airport)
  if reportType == "forecast" then
    FSL.PED_MCDU_LSK_R5()
  else
    FSL.PED_MCDU_LSK_R6()
  end
end

ensureAirportSelected = function(airport)
  local disp = FSL.MCDU:getString()
  local autoSelected, ICAO, selectKey
  if airport == "origin" or airport == "destination" then
    local autoEntryIdx
    if airport == "origin" then
      autoEntryIdx = 49
      selectKey = FSL.PED_MCDU_LSK_L1
    else
      autoEntryIdx = 97
      selectKey = FSL.PED_MCDU_LSK_L2
    end
    ICAO = disp:match("^%u%u%u%u", autoEntryIdx) or error "huh?"
    autoSelected = FSL.MCDU:getArray()[autoEntryIdx].isBold
  else
    ICAO = airport
    autoSelected = false
  end
  local freeSlot, hasManualEntry
  local manualEntryIdx = 69
  for line = 1, 4 do
    local entry = disp:match("^%u%u%u%u", manualEntryIdx)
    if entry == ICAO then return end
    if entry then 
      hasManualEntry = true
    else 
      freeSlot = freeSlot or line 
    end
    manualEntryIdx = manualEntryIdx + FSL.MCDU.LENGTH_LINE * 2
  end
  if autoSelected and not hasManualEntry then return end
  if selectKey then 
    pressAndWait(selectKey)
  else
    copilot.scratchpadClearer.clearScratchpad()
    FSL.MCDU:type(ICAO)
  end
  pressAndWait(FSL["PED_MCDU_LSK_R" .. (freeSlot or 1)])
end

pressAndWait = function(keyToPress, checkFunc, waitMin, waitMax, init, timeout)
  init = init or FSL.MCDU:getString()
  if not checkFunc then
    checkFunc = function(disp) return disp ~= init end
  elseif type(checkFunc) == "string" then
    local stringToMatch = checkFunc
    checkFunc = function(disp) return disp:find(stringToMatch) end
  end
  local firstLine = FSL.MCDU:getLine(1, init)
  local function _checkFunc()
    local disp = FSL.MCDU:getString()
    if checkFunc(disp) then return true end
    if FSL.MCDU:getLine(1, disp) ~= firstLine then
      -- Oh no, someone opened a different page on our MCDU!
      error(MCDU_ERROR, 0) 
    end
  end
  if timeout ~= 0 then 
    timeout = timeout or 10000
    if not checkWithTimeout(timeout, function()
      keyToPress() 
      return checkWithTimeout(1000, 100, _checkFunc)
    end) then error(MCDU_ERROR, 0) end
  else
    repeat ipc.sleep(100) until _checkFunc()
  end
  ipc.sleep(math.random(waitMin or 300, waitMax or 1000))
  if not _checkFunc() then error(MCDU_ERROR, 0) end
end