-- Drop this file into FSLabs Copilot/custom - Copilot auto-loads
-- any lua files in that directory
-- Read more @{plugins.md|here}

copilot.events.aboveTenThousand:addAction(function()

  local function shouldConnect()
    local menuEvent = Event.fromTextMenu(
      "Would you like to connect the air conditioning upon arrival?",
      "", {"Yes", "No", "Ask me again in ten minutes"}
    )
    local _, res = Event.waitForEvent(menuEvent)
    if res == 3 then
      copilot.suspend(10 * 60000)
      return shouldConnect()
    end
    return res == 1
  end

  local function connected() return ipc.readLvar("FSLA320_GndAC") == 1 end

  local function connect()
    -- This will work even if you don't have GSX
    if connected() then return true end
    ipc.createLvar("FSDT_GSX_JETWAY_AIR", 0)
    ipc.sleep(1000)
    ipc.writeLvar("FSDT_GSX_JETWAY_AIR", 5)
    ipc.sleep(1000)
    return connected()
  end

  copilot.suspend(5 * 60000)

  if shouldConnect() then
    copilot.events.chocksSet:addOneOffAction(function()
      copilot.suspend(5000, 30000)
      print(connect() and "AC connected" or "Failed to connect AC")
    end, Action.COROUTINE)
  end

end, Action.COROUTINE)