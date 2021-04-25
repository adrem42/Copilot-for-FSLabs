-------------------------------------
-- Collection of reusable phrase components.
--
--###### How to use:
-- 1. Append a phrase returned by `getPhrase` to your PhraseBuilder. The element needs to be bound to a named property.<br>
-- 2. Retrieve the result using `getPhraseResult`, passing to it the path to the property.<br><br>
--
--
--###### These are the available phrases:
--
-- `digit`
--
--> A single digit from 0-9
--
-- `spelledNumber`
--> Arguments: number of digits
--
-- `phoneticLetter`
--
-- `ICAOairportCode`
--
-- `runwayId`
--
--    local proposeRoute = VoiceCommand:new {
--      confidence = 0.9,
--      phrase = PhraseBuilder.new()
--        :append "let's fly from"
--        :append(PhraseUtils.getPhrase "ICAOairportCode", "from")
--        :append "to"
--        :append {
--          propName = "to",
--          choices = {
--            "amsterdam",
--            "oslo",
--            "zurich",
--            {
--              propVal = "ICAO",
--              choice = PhraseUtils.getPhrase "ICAOairportCode"
--            }
--          }
--        }
--        :build()
--    }
--    
--    copilot.addCoroutine(function()
--      proposeRoute:activate()
--      local res = Event.waitForEvent(proposeRoute)
--      local from = PhraseUtils.getPhraseResult("ICAOairportCode", res, "from")
--      local to = res:getProp "to" 
--      if to == "ICAO" then
--        to = PhraseUtils.getPhraseResult("ICAOairportCode", res, "to")
--      end
--      print("From: " .. from .. ", to: " .. to)
--    end)
-- @module PhraseUtils

PhraseUtils = {}
local phrases = {}
local resultHandlers = {}

--- Gets a component by its name.
--- @string phraseName
--- @param[opt] ... arguments
--- @return A Phrase object 
function PhraseUtils.getPhrase(phraseName, ...)
  return phrases[phraseName](...)
end

function PhraseUtils.getResultHandler(phraseName) return resultHandlers[phraseName] end

--- Retrieves the value from the phrase's properties.
--- @string phraseName
--- @param res A RecoResult object
--- @param ... path The path to the property. Same as the parameters of @{VoiceCommand.RecoResult:getProp|RecoResult:getProp}
--- @treturn string Phrase-specific result 
function PhraseUtils.getPhraseResult(phraseName, res, ...)
  local props = select(2, res:getProp(...))
  if not props then return end
  return resultHandlers[phraseName](res, props)
end

local function makePhrase(args)
  local func
  if type(args.phrase) == "function" then
    func = function(...) return args.phrase(...) end
  else
    func = function() return args.phrase end
  end
  resultHandlers[args.name] = args.handler
  phrases[args.name] = func
  return func
end

local function makeListPhrase(list, name, asString)
  return makePhrase {
    name = name,
    phrase = PhraseBuilder.new()
      :append{choices = list, propName = name, asString = asString}
      :build(),
    handler = function(res, prop) return res:getProp(prop, name) end
  }
end

local function makeCached(_makePhrase)
  local cache = setmetatable({}, {__mode = "v"})
  return function(...)
    local key = select("#", ...) == 1 and select(1, ...) or table.concat({...}, string.char(0xFF))
    cache[key] = cache[key] or _makePhrase(...)
    return cache[key]
  end 
end

do

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

  local letter = makeListPhrase(table.map(alphabet, function(code)
    return {propVal = code:sub(1, 1), choice = code}
  end), "phoneticLetter", "phonetic letter")()

  makePhrase {
    name = "ICAOairportCode",
    phrase = PhraseBuilder.new()
      :append(letter, "1")
      :append(letter, "2")
      :append(letter, "3")
      :append(letter, "4")
      :build "ICAO code",
    handler = function(res, props)
      local getLetter = PhraseUtils.getResultHandler "phoneticLetter"
      return table.concat(table.init(4, function(i) 
        return getLetter(res, select(2, res:getProp(props, tostring(i)))) 
      end))
    end
  }
end

local digitPhrase = makeListPhrase(table.init(10, function(i) return tostring(i-1) end), "digit")()

makePhrase {
  name = "spelledNumber",
  phrase = makeCached(function(numDigits)
    local builder = PhraseBuilder.new()
    for i = 1, numDigits do
      builder:append(digitPhrase, tostring(i))
    end
    return builder:build(numDigits .. "-digit spelled number")
  end),
  handler = function(res, props)
    local num = ""
    local i = 1
    local getDigit = PhraseUtils.getResultHandler "digit"
    while true do
      local digit = getDigit(res, select(2, res:getProp(props, tostring(i))))
      if not digit then return num end
      num = num .. digit
      i = i + 1
    end
  end
}

makePhrase {
  name = "runwayId",
  phrase = PhraseBuilder.new()
    :append(PhraseUtils.getPhrase("spelledNumber", 2), "digits")
    :append {
      propName = "letter",
      optional = true,
      choices = {
        {propVal = "L", choice = "left"},
        {propVal = "R", choice = "right"},
        {propVal = "C", choice = "center"}
      }
    }
    :build "runway identifier",
  handler = function(res, props)
    local digits = PhraseUtils.getPhraseResult("spelledNumber", res, props, "digits")
    local letter = res:getProp(props, "letter")
    if not letter then return digits end
    return digits .. letter
  end
}
