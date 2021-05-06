
local afterTakeoffBelow = Checklist:new(
  "afterTakeoff",
  "After Takeoff / Climb below the Line",
  VoiceCommand:new ({"after takeoff climb below the line", "below the line"}, 0.9)
)

copilot.checklists.afterTakeoff = afterTakeoffBelow

local standardSet

local function transAlt() return copilot.mcduWatcher:getVar "transAlt" end

copilot.voiceCommands.setStandard = VoiceCommand:new {
  phrase = "set standard",
  action = function()
    if not transAlt() then return end
    if math.abs(copilot.ALT() - transAlt()) > 1500 then return end
    standardSet = true 
    FSL.GSLD_EFIS_Baro_Switch:push()
    copilot.sleep(0, 2000)
    copilot.playCallout "checklists.afterTakeoffBelow.standardSet"
  end
}

copilot.events.landing:addAction(function() standardSet = false end)

copilot.events.takeoffInitiated:addAction(function()

  if not transAlt() then
    FSL.CPT.PED_MCDU_KEY_PERF()
    if not checkWithTimeout(5000, function() 
      copilot.suspend(100)
      return transAlt()
    end) then return end
  end

  repeat copilot.suspend(5000) 
  until math.abs(copilot.ALT() - transAlt()) < 1500
  copilot.voiceCommands.setStandard:activate()

  repeat copilot.suspend(5000) 
  until math.abs(copilot.ALT() - transAlt()) > 2000
  copilot.voiceCommands.setStandard:deactivate()
  
end, "runAsCoroutine")
  :stopOn(copilot.events.belowTenThousand, copilot.events.landing)
  :setLogMsg(Event.NOLOGMSG)

afterTakeoffBelow:appendItem {
  label = "baroRef",
  displayLabel = "Baro REF",
  response = VoiceCommand:new {"standard", "standard set"},
  onResponse = function(_, _, res)
    if standardSet then
      res.acknowledge = "standardSet"
    end
  end
}