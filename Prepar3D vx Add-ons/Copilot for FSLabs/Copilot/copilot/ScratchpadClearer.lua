
copilot.scratchpadClearer = {ANY = {}, NONE = {}}

local messageSets = {{thread = "global", msgs = copilot.scratchpadClearer.NONE}}
local lastMessage, nextClearTime

local startIdx, endIdx = FSL.MCDU:getLineIdx(FSL.MCDU.NUM_LINES)
endIdx = endIdx - 6
function copilot.scratchpadClearer.getScratchpad(disp)
  disp = disp or FSL.MCDU:getString()
  return disp:sub(startIdx, endIdx), disp
end

function copilot.scratchpadClearer.clearScratchpad()

  local old = copilot.scratchpadClearer.getScratchpad()
  if old:find "SELECT DESIRED SYSTEM" or not old:find "%S" then 
    return false 
  end

  copilot.logger:debug("Clearing scratchpad: " .. old)
  repeat FSL.PED_MCDU_KEY_CLR()
  until not copilot.scratchpadClearer.getScratchpad():find "%S"
  
  return true
end

local function getTop() return messageSets[#messageSets].msgs end

local function checkScratchpad(msgs)

  local disp = FSL.MCDU:getString()
  if disp:find "MCDU MENU" then return end

  local scratchpad = copilot.scratchpadClearer.getScratchpad(disp)
  if not scratchpad:find "%S" then return
  elseif msgs == copilot.scratchpadClearer.ANY then return scratchpad end

  for _, msg in ipairs(msgs) do
    if scratchpad:sub(1, #msg) == msg 
      and not scratchpad:sub(#msg + 1, #scratchpad):find "%S" then
      return msg
    end
  end
end

local function run(timestamp)

  local msg = checkScratchpad(getTop())
  if not msg then return end

  if msg == lastMessage then
    if timestamp > nextClearTime then
      copilot.scratchpadClearer.clearScratchpad()
      lastMessage = nil
    end
    return
  end

  lastMessage = msg
  nextClearTime = timestamp + math.random(1000, 5000)
end

local function refresh()
  if getTop() == copilot.scratchpadClearer.NONE then 
    copilot.removeCallback(run)
  else 
    copilot.addCallback(run, nil, 1000) 
  end
end

local function removeThread(thread)
  for i, v in ipairs(messageSets) do
    if v.thread == thread then 
      table.remove(messageSets, i)
      break
    end
  end
  refresh()
end

function copilot.scratchpadClearer.setMessages(msgs, globally)
  local thread = coroutine.running()
  globally = globally or not thread or not copilot.getCallbackStatus(thread)
  if globally then
    messageSets[1].msgs = msgs
  else
    for _, v in ipairs(messageSets) do if v.thread == thread then return end end
    messageSets[#messageSets+1] = {thread = thread, msgs = msgs}
    copilot.getThreadEvent(thread):addOneOffAction(function() removeThread(thread) end)
  end
  refresh()
end

function copilot.scratchpadClearer.restore() removeThread(coroutine.running()) end
function copilot.dontClearScratchPad() end