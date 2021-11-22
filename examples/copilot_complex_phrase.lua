-- Drop this file into FSLabs Copilot/custom - Copilot auto-loads
-- any lua files in that directory
-- Read more here

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

function getWeatherSequence(reportType, airport)
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
    pressAndWait(FSL.PED_MCDU_LSK_R5, "ATIS/WX", function(_disp)
      return FSL.MCDU:getLine(11, _disp):match "FORECAST $"
    end)
  else
    pressAndWait(FSL.PED_MCDU_LSK_R6, "ATIS/WX", function(_disp)
      return FSL.MCDU:getLine(13, _disp):match "METAR $"
    end)
  end
end

 function ensureAirportSelected(airport)
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
  local freeSlot, freeSlotIdx, hasManualEntry
  local manualEntryIdx = 69
  for line = 1, 4 do
    local entry = disp:match("^%u%u%u%u", manualEntryIdx)
    if entry == ICAO then return end
    if entry then
      hasManualEntry = true
    else
      freeSlot = freeSlot or line
      freeSlotIdx = freeSlotIdx  or manualEntryIdx
    end
    manualEntryIdx = manualEntryIdx + FSL.MCDU.LENGTH_LINE * 2
  end
  if autoSelected and not hasManualEntry then return end
  local action
  if selectKey then
    action = selectKey
  else
    copilot.scratchpadClearer.clearScratchpad()
    action = function() FSL.MCDU:type(ICAO) end
  end
  pressAndWait(action, "ATIS/WX", function(_disp)
    return FSL.MCDU:getScratchpad(_disp):match("^" .. ICAO)
  end)
  pressAndWait(FSL["PED_MCDU_LSK_R" .. (freeSlot or 1)], "ATIS/WX", function(_disp)
    return _disp:match("^%[" .. ICAO .. "%]", freeSlotIdx)
  end)
end

function pressAndWait(action, ...)
  local function assertDisplay(val)
    if not val then error(MCDU_ERROR, 0) end
  end
  local initIdx
  local requirePageTitle
  if type(select(1, ...)) == "string" and select(2, ...) and type(select(2, ...)) == "function" then
    requirePageTitle = select(1, ...)
    assertDisplay(FSL.MCDU:getLine(1):find(requirePageTitle))
    initIdx = 2
  else
    initIdx = 1
  end
  local predicate, waitMin, waitMax, init, timeout = select(initIdx, ...)
  init = init or FSL.MCDU:getString()
  local checkFunc
  local firstLine = FSL.MCDU:getLine(1, init)
  local function checkTitleChanged(disp)
    assertDisplay(FSL.MCDU:getLine(1, disp) == firstLine)
  end
  if type(predicate) == "string" then
    -- The caller wants to go to a different page, the predicate is the title
    function checkFunc() 
      return FSL.MCDU:getLine(1):find(predicate) 
    end
  elseif type(predicate) == "function" then
    assert(requirePageTitle, "Pass in the current page title as the second argument")
    -- The caller wants to do an action on the current page
    -- Throw if the page title has changed
    -- The predicate is a function that validates the outcome of the action
    function checkFunc()
      local disp =  FSL.MCDU:getString()
      checkTitleChanged(disp)
      return predicate(disp, assertDisplay)
    end
  else
    error "Invalid predicate type" 
  end
  action()
  assertDisplay(checkWithTimeout(timeout or 3000, 100, checkFunc))
  ipc.sleep(math.random(waitMin or 300, waitMax or 1000))
  assertDisplay(checkFunc())
end