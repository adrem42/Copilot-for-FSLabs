
if false then module "Event" end

Event = Event or require "copilot.Event"
local EventUtils = require "copilot.EventUtils"

local recognizer = copilot.recognizer

--- VoiceCommand is a subclass of <a href="#Class_Event">Event</a> and is implemented with the Windows Speech API.
--
-- A voice command can be in one of these  states:
--
-- * Active
--
-- * Inactive
--
-- * Ignore mode: the phrases are active in the recognizer but recognition events don't trigger the voice command.
--
-- If you only have a couple of phrases active in the recognizer at a given time, especially short ones, the accuracy will be low and
-- the recognizer will recognize just about anything as those phrases. On the other hand, having a lot of active phrases
-- will also degrade the quality of recognition.<br>
--
--- @type VoiceCommand
VoiceCommand = {DefaultConfidence = 0.93}
setmetatable(VoiceCommand, {__index = Event})

local PersistenceMode = {
  ignore = RulePersistenceMode.Ignore,
  [true] = RulePersistenceMode.Persistent,
  [false] = RulePersistenceMode.NonPersistent
}

local function _persistenceMode(persistence)
  if persistence == nil then
    return RulePersistenceMode.NonPersistent
  else
    return PersistenceMode[persistence] or error("Invalid persistence mode", 3)
  end
end

local function parsePhrases(input)
  input = type(input) == "table" and input or {input}
  for i, v in ipairs(input) do
    if type(v) == "string" then
      input[i] = Phrase.new():append(v)
    end
  end
  return input
end

--- Constructor
--- @param data A table containing the following fields (also the fields taken by @{Event:new|the parent constructor}):
--  @param data.phrase string or array of strings. @{addPhrase|You can modify the required confidence of each word in the phrase}
--  @param data.dummy string or array of strings. One or multiple dummy phrase variants which will activated and deactivated 
-- synchronously with the voice command's actual phrase variants to help the recognizer discriminate between them and similarly 
-- sounding phrases. For example, the default 'takeoff' voice command has a 'takeoff runway' dummy phrase which is an item on the
-- standard takeoff checklist. 
--  @number[opt=0.93] data.confidence between 0 and 1
--  @param[opt=false] data.persistent
-- * omitted or false: the voice command will be deactivated after being triggered.
-- * 'ignore': the voice command will be put into ignore mode after being triggered.
-- * true: the voice command will stay active after being triggered.
--- @usage
-- local myVoiceCommand = VoiceCommand:new {
--  phrase = "hello",
--  confidence = 0.95,
--  action = function() print "hi there" end
-- }

function VoiceCommand:new(data, confidence)
  data = type(data) == "string"
    and {phrase = data, confidence = confidence}
    or type(data) == "table" and data
    or {}
  local voiceCommand = data
  voiceCommand.confidence = data.confidence or VoiceCommand.DefaultConfidence
  local phrase = parsePhrases(data.phrase)
  data.phrase = nil
  if copilot.isVoiceControlEnabled then
    voiceCommand.ruleID = recognizer:addRule(
      phrase, voiceCommand.confidence, _persistenceMode(data.persistent)
    )
    voiceCommand.persistent = nil
    Event.voiceCommands[voiceCommand.ruleID] = voiceCommand
  end
  voiceCommand.eventRefs = {activate = {}, deactivate = {}, ignore = {}}
  self.__index = self
  voiceCommand.logMsg = voiceCommand.logMsg or phrase[1] and phrase[1].asString
  voiceCommand = setmetatable(Event:new(voiceCommand), self)
  if data.dummy then
    voiceCommand:addPhrase(parsePhrases(data.dummy), true)
    data.dummy = nil
  end
  return voiceCommand
end

--- Call this function inside a plugin lua before activating or deactivating voice commands. 
---@static
function VoiceCommand.resetGrammar()
  if not VoiceCommand.isGrammarReset then
    recognizer:resetGrammar()
    VoiceCommand.isGrammarReset = true
  end
end

--- Returns all phrase variants of a voice command.
---@bool dummy True to return dummy phrase variants, omitted or false to return actual phrase variants.
---@return Array of strings.
function VoiceCommand:getPhrases(dummy)
  --return recognizer:getPhrases(self.ruleID, dummy == true and true or false)
  return {}
end

--- Sets persistence mode of a voice command.
---@param persistenceMode
-- * omitted or false: the voice command will be deactivated after being triggered.
-- * 'ignore': the voice command will be put into ignore mode after being triggered.
-- * true: the voice command will stay active after being triggered.
---@return self
function VoiceCommand:setPersistence(persistenceMode)
  recognizer:setRulePersistence(_persistenceMode(persistenceMode), self.ruleID)
  return self
end

--- Adds phrase variants to a voice command.
--
---The SAPI recognizer has two confidence metrics - a float from 0-1 and another one that has three states: low, normal and high.
---If a word is preceded by a '+' or '-', its required confidence is set to 'high' or 'low', respectively, otherwise, it has the default required confidence 'normal'.
---@param phrase string or array of strings
---@bool dummy True to add dummy phrase variants, omitted or false to add actual phrase variants.
---@return self
function VoiceCommand:addPhrase(phrase, dummy)
  recognizer:addPhrases(parsePhrases(phrase), self.ruleID, dummy == true and true or false)
  return self
end

local function trimPhrase(phrase) return phrase:gsub("[%+%-]+(%S+)", "%1") end

--- Removes phrase variants from a voice command.
---@param phrase string or array of strings
---@bool dummy True to remove dummy phrase variants, omitted or false to remove actual phrase variants.
---@return self
function VoiceCommand:removePhrase(phrase, dummy)
  -- local phrasesToRemove = type(phrase) == "table" and phrase or {phrase}
  -- local deletthis = {}
  -- for _, phraseToRemove in ipairs(phrasesToRemove) do
  --  phraseToRemove = trimPhrase(phraseToRemove)
  --   for _, _phrase in ipairs(self:getPhrases(dummy == true and true or false)) do
  --     if phraseToRemove == _phrase then
  --       deletthis[#deletthis+1] = _phrase
  --     end
  --   end
  -- end
  -- recognizer:removePhrases(deletthis, self.ruleID, dummy == true and true or false)
  return self
end

--- Removes all phrase variants from a voice command.
---@bool dummy True to remove dummy phrase variants, omitted or false to remove actual phrase variants.
---@return self
function VoiceCommand:removeAllPhrases(dummy)
  recognizer:removeAllPhrases(self.ruleID, dummy == true and true or false)
  return self
end

--- Sets required confidence of a voice command.
--- @number confidence A number from 0-1
---@return self
function VoiceCommand:setConfidence(confidence)
  recognizer:setConfidence(confidence, self.ruleID)
  return self
end

function VoiceCommand:_checkActiveChecklistOnStateChange(state)
  if Checklist.voiceCommands[self] then return false end
  local checklist = Checklist.currChecklist()
  if not checklist then return false end
  return checklist:onVcStateChange(self, state)
end

---<span>
---@return self
function VoiceCommand:activate()
  if self:_checkActiveChecklistOnStateChange(RuleState.Active) then
    return self
  end
  if copilot.isVoiceControlEnabled then recognizer:activateRule(self.ruleID) end
  return self
end

---<span>
---@return self
function VoiceCommand:ignore()
  if self:_checkActiveChecklistOnStateChange(RuleState.Ignore) then
    return self
  end
  if copilot.isVoiceControlEnabled then recognizer:ignoreRule(self.ruleID) end
  return self
end

---<span>
---@return self
function VoiceCommand:deactivate()
  if self:_checkActiveChecklistOnStateChange(RuleState.Inactive) then
    return self
  end
  if copilot.isVoiceControlEnabled then recognizer:deactivateRule(self.ruleID) end
  return self
end

---Deactivates the voice command and makes successive calls to @{activate} and @{ignore} have no effect.
function VoiceCommand:disable()
  if self:_checkActiveChecklistOnStateChange(RuleState.Disabled) then
    return self
  end
  recognizer:disableRule(self.ruleID)
  return self
end

function VoiceCommand:getState()
  return recognizer:getRuleState(self.ruleID)
end

---If the voice command has only one action, returns that action. All default voice commands have only one action.
function VoiceCommand:getAction()
  if self:getActionCount() ~= 1 then
    error(string.format("Cannot get action of voice command %s - action count isn't 1", self.logMsg), 2)
  end
  for action in pairs(self.actions.nodes) do return action end
end

function VoiceCommand:react(plus) ipc.sleep(math.random(80, 120) * 0.01 * (500 + (plus or 0))) end

VoiceCommand.makeEventRef = EventUtils.makeEventRef

--- The voice command will become active when the events passed as parameters are triggered.
--
--- Adds an 'activate' event reference that can be removed from the event via @{removeEventRef}
--- @param ...  one or more events
function VoiceCommand:activateOn(...)
  self:makeEventRef(function() self:activate() end, "activate", ...)
  return self
end

--- The voice command will be deactivated when the events passed as parameters are triggered.
--
--- Adds a 'deactivate' event reference that can be removed from the event via @{removeEventRef}
--- @param ...  one or more events
function VoiceCommand:deactivateOn(...)
  self:makeEventRef(function() self:deactivate() end, "deactivate", ...)
  return self
end

--- The voice command will go into ignore mode when the events passed as parameters
--
--- are triggered.
--
--- Adds a 'ignore' event reference that can be removed from the event via @{removeEventRef}
--- @param ...  one or more events
function VoiceCommand:ignoreOn(...)
  self:makeEventRef(function() self:ignore() end, "ignore", ...)
  return self
end

--- Disables the effect of @{activateOn}, @{deactivateOn} or @{ignore} for the default voice commands in @{copilot.voiceCommands}
--- @function removeEventRef
--- @string refType 'activate', 'deactivate' or 'ignore'
--- @param ... one or more <a href="#Class_Event">Event</a>'s
--- @usage copilot.voiceCommands.gearUp:removeEventRef('activate',
--copilot.events.goAround, copilot.events.takeoffInitiated)
VoiceCommand.removeEventRef = EventUtils.removeEventRef

return VoiceCommand