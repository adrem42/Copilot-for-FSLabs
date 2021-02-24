
ScratchpadClearer = {
  instances = setmetatable({}, {__mode = "k"}),
  ANY_MESSAGE = {}
}

function ScratchpadClearer:new(messages)
  local clearer = {messages = messages, pauseThreads = {}}
  self.instances[clearer] = true
  self.__index = self
  return setmetatable(clearer, self)
end

function ScratchpadClearer:__call(timestamp)

  if self:isPaused() then return end

  local msg = self:_checkScratchpad()
  if not msg then return end

  if msg == self.lastMessage then
    if timestamp > self.nextClearTime then
      self.clearScratchpad()
      self.lastMessage = nil
    end
    return
  end

  self.lastMessage = msg
  self.nextClearTime = timestamp + math.random(1000, 5000)
end

function ScratchpadClearer:start() copilot.addCallback(self) end

function ScratchpadClearer:stop() copilot.removeCallback(self) end

function ScratchpadClearer:_checkScratchpad()

  local disp = FSL.MCDU:getString()
  if disp:find "MCDU MENU" then return end

  local scratchpad = self.getScratchpad()
  if not scratchpad:find "%S" then return
  elseif self.messages == self.ANY_MESSAGE then return scratchpad end

  for _, msg in ipairs(self.messages) do
    if scratchpad:sub(1, #msg) == msg 
      and not scratchpad:sub(#msg + 1, #scratchpad):find "%S" then
      return msg
    end
  end
end

function ScratchpadClearer:isPaused()
  for thread in pairs(self.pauseThreads) do
    local isPaused = Action.getActionFromThread(thread) or copilot.isThreadActive(thread)
    if isPaused then return true end
    self.pauseThreads[thread] = nil
  end
  return false
end

function ScratchpadClearer.clearScratchpad()

  local old = ScratchpadClearer.getScratchpad()
  if old:find "SELECT DESIRED SYSTEM" then return false end

  copilot.logger:debug("Clearing scratchpad: " .. old)

  repeat FSL.PED_MCDU_KEY_CLR()
  until not ScratchpadClearer.getScratchpad():find "%S"

  return true
end

function ScratchpadClearer.getScratchpad()
  return FSL.MCDU:getScratchpad()
end

function ScratchpadClearer:_pause(thread) self.pauseThreads[thread] = true end

function ScratchpadClearer.pause(self)

  local thread = coroutine.running()
  if not Action.getActionFromThread(thread) 
    and not copilot.isThreadActive(thread) then
    return
  end

  if self then 
    self:_pause(thread)
  else
    for clearer in pairs(ScratchpadClearer.instances) do
      clearer:_pause(thread)
    end
  end
end

function ScratchpadClearer:_unpause(thread) self.pauseThreads[thread] = nil end

function ScratchpadClearer.unpause(self)

  local thread = coroutine.running()

  if self then 
    self:_unpause(thread)
  else
    for clearer in pairs(ScratchpadClearer.instances) do
      clearer:_unpause(thread)
    end
  end
end

copilot.scratchpadClearer = ScratchpadClearer:new(ScratchpadClearer.ANY_MESSAGE)

function copilot.dontClearScratchPad() copilot.scratchpadClearer:pause() end