
local checklists = {
  {
    name = "beforeStart",
    activationTrigger = "If preflight action enabled: when preflight action is finished, otherwise: when the chocks are set.<br><br>"
  },
  {
    name = "beforeStartBelow",
    activationTrigger = "When before start to the line is finished.<br><br>"
  },
  {
    name = "afterStart",
    activationTrigger = [[If after\_start action enabled: when after\_start action is finished, otherwise: when the engines are started.<br><br>]]
  },

  {
    name = "beforeTakeoff",
    activationTrigger = "When after start checklist is finished.<br><br>"
  },
  {
    name = "beforeTakeoffBelow",
    activationTrigger = "If lineup action enabled: when lineup action is finished and before takeoff to the line is finished, otherwise: when before takeoff to the line is finished.<br><br>"
  },
  {
    name = "afterTakeoff",
    activationTrigger = [[If after\_takeoff action enabled: when after\_takeoff action is finished, otherwise: when you're airborne.<br><br>]]
  },
  {
    name = "afterTakeoffBelow",
    activationTrigger = "When the after takeoff climb checklist to the line is finished.<br><br>"
  },
  {
    name = "approach",
    activationTrigger = "Below 10'000 feet.<br><br>"
  },
  {
    name = "landing",
    activationTrigger = "Below 10'000 feet and IAS below 200 kts.<br><br>"
  },
  {
    name = "parking",
    activationTrigger = "On engine shutdown<br><br>"
  },
  {
    name = "securingTheAircraft",
    activationTrigger = "When the parking checklist is finished<br><br>"
  }
}

return function(solutionDir)
  local output = {}
  local function add(fmt, ...) output[#output+1] = fmt:format(...) end
  add "##### Response phrase syntax explanation:"
  add "Curly brackets denote a multiple choice phrase element, with each choice inside round brackets.<br><br>"
  add "Square brackets denote an optional phrase element.<br><br>"
  add "... means 'match anything'.<br><br>"
  add "___"
  for _, entry in ipairs(checklists) do
    local checklist = copilot.checklists[entry.name]
    add("### " .. checklist.displayLabel)
    add([[Trigger phrases: **"%s"**<br><br>]], table.concat(table.map(checklist.trigger:getPhrases(), tostring), [["**, **"]]))
    add("When it's available: " .. entry.activationTrigger)
    
    for _, item in ipairs(checklist.items) do
      local responsePhrases = {}
      for _, vc in pairsByKeys(item.response) do
        for _, phrase in ipairs(vc:getPhrases()) do
          responsePhrases[#responsePhrases+1] = tostring(phrase)
        end
      end
      add ("###### " ..( item.displayLabel or item.label))
      add(table.concat(table.map(responsePhrases, function(s) return s:gsub("<", "&lt;"):gsub(">", "&gt;") end), "<br><br>\n"))
      add "<br><br>"
    end

    add "___"
    
  end
  local checklistsMd = file.read(solutionDir .. "\\checklists.md")
  local res = checklistsMd:gsub("(List of checklists)", "%1 \n" .. table.concat(output, "\n"))
  file.write(solutionDir .. "\\topics\\checklists.md", res, "w")
  os.execute(([[cd "%s" && makedoc && copytosim]]):format(solutionDir))
end