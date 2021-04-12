
local mt = require "Copilot.libs.mt19937ar"
local serpent = require "FSL2Lua.libs.serpent"
local file = require "FSL2Lua.FSL2Lua.file"
local minutesLoggedAtStart, scriptStartTime, coldAndDark
local debugging = copilot.UserOptions.failures.debug == copilot.UserOptions.ENABLED
local failureStates
local failures = {}
local function sleep(time) ipc.sleep(time or 100) end

local aircraftReg
if copilot.UserOptions.failures.per_airframe == 1 then
  aircraftReg = ipc.readSTR(0x313C, 12)
  aircraftReg = aircraftReg:sub(1, aircraftReg:find("\0") - 1)
else
  aircraftReg = "common"
end
local aircraftRegDir = APPDIR .. "Copilot\\failures\\" .. aircraftReg
local stateFilePath = aircraftRegDir .. "\\state.lua"

for _, v in ipairs(require "Copilot.copilot.failurelist") do
  local failureName = v[1]
  failures[failureName] = {rate = copilot.UserOptions.failures[failureName], A321 = v.A321 ~= 0}
end

local function waitForDisplay(substring, disappear)
  local newDisp
  while true do
    newDisp = FSL.MCDU:getString()
    if disappear and not newDisp:find(substring) then break end
    if not disappear and newDisp:find(substring) then break end
  end 
  return newDisp
end

local function dimDisplay()
  repeatWithTimeout(7000, function()
    FSL.PED_MCDU_KEY_BRT:macro "leftPress"
    ipc.sleep(100)
  end)
  FSL.PED_MCDU_KEY_BRT:macro "leftRelease"
  ipc.sleep(1000)
  for _=1, 30 do 
    FSL.PED_MCDU_KEY_DIM() 
    repeat sleep() until not FSL.PED_MCDU_KEY_DIM:isDown() 
  end
end

local function restoreBrightness() for _ = 1, 10 do FSL.PED_MCDU_KEY_BRT() end end

local function turnOffDisplay()
  repeat
    FSL.PED_MCDU_KEY_DIM:macro("leftPress")
    ipc.sleep(100)
  until FSL.MCDU:getString():find("RELEASE DIM KEY")
  FSL.PED_MCDU_KEY_DIM:macro("leftRelease")
end

local function debug(msg) if debugging then copilot.logger:debug(msg) end end

local function saveTime(timestamp)
  local logged = math.floor((timestamp - scriptStartTime) / 60000) + minutesLoggedAtStart
  file.write(aircraftRegDir .. "\\logged", tostring(logged), "w")
end

local function saveStates()
  failureStates.lastSave = minutesLoggedAtStart
  file.write(stateFilePath, serpent.dump(failureStates), "w")
end

local function setupFailures()

  repeat
    FSL.PED_MCDU_KEY_MENU()
    sleep()
  until FSL.MCDU:getString():find("MCDU MENU")

  repeat
    FSL.PED_MCDU_LSK_R4()
    sleep()
  until FSL.MCDU:getString():find("FAILURES")

  local prevNotFound = false
  local failureCount = 0

  local hours = math.floor(minutesLoggedAtStart / 60)
  local minutes = minutesLoggedAtStart - hours * 60
  debug("-------------------------------------------------------")
  debug(string.format("Time logged on airframe %s: %s hours and %s minutes", aircraftReg, hours, minutes))
  debug("-------------------------------------------------------")

  local index, prevIndex = 0, 0
  local clearAll
  for failureName, failure in pairsByKeys(failures) do
    index = index + 1
    local state = failureStates[failureName]

    local rng = mt.new()
    rng:setState(state.state)

    if not state.disabled then 
      if minutesLoggedAtStart > failureStates.lastSave then
        for _ = failureStates.lastSave, minutesLoggedAtStart - 1 do
          rng:genrand_real1()
        end
      end
      state.state = rng:getState()
    end

    local rate = tonumber(failure.rate) or copilot.UserOptions.failures.global_rate
    local fatalSecond
    debug("-------------------------------------------------------")
    
    if rate == 0 or (not failure.A321 and FSL:getAcType() == "A321") then
      if rate == 0 then debug("Failure " .. failureName .. " is disabled")
      else debug("Failure " .. failureName .. " is not available in the A321") end
      state.disabled = true
    else
      state.disabled = nil
      debug("Failure rate of failure " .. failureName .. ":")
      debug("1 failure in " .. 1 / rate .. " hours")
      local function prob(prob) return rng:genrand_real1() <= prob end
      
      for minute = 0,  12 * 60 do
        if prob(rate / 60) then
          fatalSecond = minute * 60 + math.random(60)
          debug("Failure " .. failureName .. " will occur in " .. minute .. " minutes")
          break
        end
      end
      if not fatalSecond and failureCount < 5 and index - prevIndex > (math.random(15)) then 
        fatalSecond = math.random(30 * 3600, 1000 * 3600) 
        prevIndex = index
      end
      if fatalSecond then
        
        if not prevNotFound then
          
          if failureCount < 2 and not clearAll then 
            local disp = waitForDisplay "FAILURES LISTING"
            FSL.PED_MCDU_LSK_L1()
            waitForDisplay(disp, true)
            if failureCount == 0 and FSL.MCDU:getString():find "CLEAR ALL" then
              FSL.PED_MCDU_LSK_R6()
              clearAll = true
            end
          end
          if failureCount > 0 or clearAll then
            waitForDisplay "ARMED FAILURES"
            FSL.PED_MCDU_LSK_R1()
          end
        end
        prevNotFound = false
        waitForDisplay "NEW CONDITION"
        FSL.PED_MCDU_LSK_L1()
        waitForDisplay "FAILURES"
        local found, line, disp, prevDisp
        while true do
          disp = disp or FSL.MCDU:getString()
          if disp:sub(49,71):find(failureName, nil, true)  then
            line = 1
          elseif disp:sub(98,120):find(failureName, nil, true)  then
            line = 2
          elseif disp:sub(146,168):find(failureName, nil, true)  then
            line = 3
          elseif disp:sub(194,216):find(failureName, nil, true)  then
            line = 4
          elseif disp:sub(242,264):find(failureName, nil, true)  then
            line = 5
          else
            prevDisp = disp
            FSL.PED_MCDU_KEY_UP()
            checkWithTimeout(5000, function()
              sleep()
              disp = FSL.MCDU:getString()
              return disp ~= prevDisp
            end)
          end
          if line then
            found = true
            break
          end
        end
        if found then
          FSL["PED_MCDU_LSK_L" .. line]()
          waitForDisplay("INSERT")
          FSL.PED_MCDU_LSK_R6()
          waitForDisplay("NEW CONDITION")
          FSL.MCDU:type(fatalSecond)
          FSL.PED_MCDU_LSK_R4()
          waitForDisplay("ACTIVATE", 1)
          FSL.PED_MCDU_LSK_R6()
          failureCount = failureCount + 1
        else
          copilot.logger:info("Couldn't find failure " .. failureName .. " in the MCDU")
          prevNotFound = true
          FSL.PED_MCDU_LSK_L6()
        end
      end
    end
  end

  FSL.PED_MCDU_KEY_MENU()

  saveStates()

end

local seed = os.time()

local function makeNewState()
  local rng = mt.new()
  rng:init_genrand(seed)
  seed = seed + 1
  return rng:getState()
end

local function initLivery()
  failureStates = {}
  for failureName in pairs(failures) do
    failureStates[failureName] = {state = makeNewState()}
  end
  saveStates()
  file.write(aircraftRegDir .. "\\logged", "0")
end

local function init()

  lfs.mkdir(APPDIR .. "Copilot\\failures")
  lfs.mkdir(aircraftRegDir)

  local path = ipc.readSTR(0x3C00, 256):gsub("SimObjects.+", "A320XGauges.ini")
  coldAndDark = file.read(path):find("%[PANEL_STATE%].-Default=1")
end

local function loadStates()
  if not file.exists(stateFilePath) then
    copilot.logger:info("Creating failure file for " .. aircraftReg)
    minutesLoggedAtStart = 0
    initLivery()
  else
    failureStates = require("Copilot.failures." .. aircraftReg .. ".state")
    minutesLoggedAtStart = tonumber(file.read(aircraftRegDir .. "\\logged") or 0)
    for failureName in pairs(failures) do
      if not failureStates[failureName] then
        failureStates[failureName] = {state = makeNewState()}
      end
    end
  end
end

--#############################################################################

init()
loadStates()

if not ipc.get("FSLC_failures") then
  FSL:disableSequences()
  local pilotBefore = FSL:getPilot()
  FSL:setPilot(coldAndDark and 1 or 2)
  copilot.logger:info("Setting up failures")
  if not debugging then 
    dimDisplay() 
    ipc.set("FSLC_failures", 1)
  end
  setupFailures()
  if not coldAndDark then restoreBrightness()
  else turnOffDisplay() end
  copilot.logger:info("Finished setting up failures")
  FSL:setPilot(pilotBefore)
  FSL:enableSequences()
else
  copilot.logger:info "Failures have already been set up during this simming session" 
end

copilot.addCallback(saveTime, nil, 60000, 60000)
scriptStartTime = copilot.getTimestamp()
