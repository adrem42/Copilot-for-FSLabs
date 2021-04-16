
PhraseUtils = {}
PhraseUtils.phrases = {}

local phrases = {}

local function simplePhrase(variants, propName, asString)
  phrases[propName] = {
    phrase = PhraseBuilder.new()
      :append{variants = variants, propName = propName, asString = asString}
      :build(),
    getPhraseResult = function(res, prop) return res:getProp(prop, propName) end
  }
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

  local variants = {}
  for _, code in pairs(alphabet) do
    variants[#variants+1] = {propVal = code:sub(1, 1), variant = code}
  end

  simplePhrase(variants, "phoneticLetter", "phonetic letter")

  phrases.ICAOairportCode = {

    phrase = PhraseBuilder.new()
      :append(phrases.phoneticLetter.phrase, "1")
      :append(phrases.phoneticLetter.phrase, "2")
      :append(phrases.phoneticLetter.phrase, "3")
      :append(phrases.phoneticLetter.phrase, "4")
      :build "ICAO code",

    getPhraseResult = function(res, props)
      return 
        res:getProp(props, "1", "phoneticLetter") ..
        res:getProp(props, "2", "phoneticLetter") ..
        res:getProp(props, "3", "phoneticLetter") ..
        res:getProp(props, "4", "phoneticLetter")
    end
  }
end

do
  local digits = {}
  for i = 0, 9 do digits[#digits+1] = tostring(i) end
  simplePhrase(digits, "digit")
end

do

  local cache = setmetatable({}, {__mode = "v"})

  phrases.numberByDigits = {

    phrase = function(numDigits)
      if cache[numDigits] then return cache[numDigits] end
      local builder = PhraseBuilder.new()
      for i = 1, numDigits do
        builder:append(PhraseUtils.phrases.digit(), tostring(i))
      end
      cache[numDigits] = builder:build()
      return cache[numDigits]
    end,

    getPhraseResult = function(res, props, numDigits)
      local num = ""
      for i = 1, numDigits do
        num = num .. res:getPhraseResult(props, tostring(i))
      end
      return num
    end
  }
end

for phraseName, phrase in pairs(phrases) do
  local func
  if type(phrase.phrase) == "function" then
    func = function(...) return phrase.phrase(...), phraseName end
  else
    func = function() return phrase.phrase, phraseName end
  end
  PhraseUtils.phrases[phraseName] = func
end

function PhraseUtils.getPhraseResult(res, phraseName, path, ...)
  local props
  path = path or phraseName or error "You have to provide a path"
  if type(path) == "string" then
    props = select(2, res:getProp(path))
  elseif type(path) == "table" then
    props = select(2, res:getProp(unpack(path)))
  else
    error "Invalid 'path' argument"
  end
  if not props then return end
  return phrases[phraseName].getPhraseResult(res, props, ...)
end
