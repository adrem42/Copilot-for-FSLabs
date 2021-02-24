copilot.events.aboveTenThousand:addAction(function()

  copilot.suspend(5 * 60000)

  local function shouldConnect()
    local menu = Event.fromSimConnectMenu(
      "Hey boss, would you like to connect the air conditioning upon arrival?",
      nil, {"Yes", "No", "Ask me again in ten minutes"}
    )
    local res = Event.waitForEvent(menu)
    if res == 3 then
      copilot.suspend(10 * 60000)
      return shouldConnect()
    end
    return res == 1
  end

  local function connected() return ipc.readLvar("FSLA320_GndAC") == 1 end

  local function tryConnect()
    -- It doesn't matter if you have GSX installed,
    -- all FSLabs does is monitor this Lvar.
    if connected() then return true end
    ipc.createLvar("FSDT_GSX_JETWAY_AIR", 0)
    ipc.sleep(1000)
    ipc.writeLvar("FSDT_GSX_JETWAY_AIR", 5)
    ipc.sleep(1000)
    return connected()
  end

  if shouldConnect() then
    copilot.events.chocksSet:addOneOffAction(function()
      copilot.suspend(5000, 30000)
      copilot.logger:info(
        tryConnect() and "AC connected" or "Failed to connect AC"
      )
    end, Action.COROUTINE)
  end

end, Action.COROUTINE)