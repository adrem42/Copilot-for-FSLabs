
require "copilot.IniUtils"
local debug, options
local startTime = ipc.elapsedtime()
local selectMenuItem

local function selectOperator(menu)
  local items = menu.items
  local operatorIdx = 0
  for i = 1, 7 do
    if items[i]:find "default" then
      operatorIdx = i 
      break
    end
  end
  if operatorIdx < 10 and operatorIdx > 0 then
    selectMenuItem(operatorIdx)
  else
    selectMenuItem(math.random(1, 7))
  end
end

local function selectJetways(menu)
  local items = menu.items
  -- The following is necessary due to a GSX bug where, if you're at a double jetway stand,
  -- it will want to switch the jetways for boarding (disconnect the already connected jetway
  -- and connect the other one instead)
  if items[1]:find "Undock" then
    if not items[1]:find "<" then
      selectMenuItem(1)
    elseif not items[2]:find ">" then
      selectMenuItem(2)
    else
      selectMenuItem(#items)
    end
  elseif items[2]:find "Undock" then
    if not items[1]:find ">" then
      selectMenuItem(1)
    elseif not items[2]:find "<" then
      selectMenuItem(2)
    else
      selectMenuItem(#items)
    end
  elseif items[#items]:find "Confirm" then
    selectMenuItem(#items)
  else
    selectMenuItem(1)
  end
end

local function handleMenu(menu)

  local items = menu.items

  if options.auto_select_operators and menu.title:find "Select operator" then
    return selectOperator(menu)
  end

  if options.auto_select_jetways and menu.prompt:find "Select jetways" then
    return selectJetways(menu)
  end

  if options.no_followme and ipc.readLvar "FSDT_VAR_EnginesStopped" == 0 and items[1] and items[1]:find "FollowMe" then
    return selectMenuItem(2)
  end

  if options.no_engines_before_pushback and items[2] and items[2]:find "Do you want to start" then
    return selectMenuItem(2)
  end

end

local currMenu

function selectMenuItem(item)
  -- ipc.sleep(100)
  debug("Selecting menu item: " .. item .. " - " .. currMenu.items[item])
  ipc.control(67135 + item)
end

local function logMenu(menu)
  local items = menu.items
  local t = {
    "Menu event:",
    "",
    menu.title,
    menu.prompt,
    ""
  }
  for i = 1, #items do
    t[#t+1] = i .. " - " .. items[i]
  end
  t[#t+1] = ""
  debug(table.concat(t, "\n\t"))
end

copilot.simConnectSystemEvent "TextEventCreated":addAction(function(_, menu)
  if menu.type == "menu" and #menu.items > 0 then
    logMenu(menu) 
    currMenu = menu
    handleMenu(menu)
  end
end)

local iniFormat = {
  boolCompat = false,
  {
    title = "gsx_autopilot",
    keys = {
      {
        name = "auto_select_operators",
        type = "bool",
        default = true
      },
      {
        name = "auto_select_jetways",
        type = "bool",
        default = true
      },
      {
        name = "auto_dock_default_jetways",
        type = "bool",
        default = true
      },
      {
        name = "no_followme",
        type = "bool",
        default = true
      },
      {
        name = "no_engines_before_pushback",
        type = "bool",
        default = true
      }
    }
  }
}

options = copilot.loadIniFile(SCRIPT_DIR .. "gsx_autopilot.ini", iniFormat).gsx_autopilot

function debug(msg)
  copilot.logger:debug("GSX autopilot - " .. msg)
end

local function lvarMonitor(_, lvar, value)
  debug(
    "Lvar event:" .. 
    "\n\n\tName: " .. lvar ..
    "\n\tValue: " .. value .. "\n"
  )
end

local gsxVars = {
  "JETWAY",
  "DEPARTURE_STATE",
  "BOARDING_STATE",
  "DEBOARDING_STATE",
  "CATERING_STATE",
  "DEICING_STATE",
  "REFUELING_STATE",
  "JETWAY_POWER",
  "JETWAY_AIR",
}

for _, lvar in ipairs(gsxVars) do
  Event.fromLvar(lvar):addAction(lvarMonitor)
end

for i = 0, 9 do
  local evtName = "SIMCONNECT_MENU_" .. i
  local evt = copilot.simConnectEvent(evtName)
  evt:subscribe()
  evt.event:addAction(function()
    debug("SimConnect event: " .. evtName)
  end)
end

if options.auto_dock_default_jetways then
  
  local initializedVars = {}
  local vars = {
    fslChocks = "FSLA320_Wheel_Chocks",
    gsxDeicing = "FSDT_GSX_DEICING_STATE",
    gsxDeparture = "FSDT_GSX_DEPARTURE_STATE"
  }

  local jetwayConnected = false
  local function toggleJetway() ipc.control(66695) end

  local GSX_REQUESTED = 4
  local GSX_IN_PROGRESS = 5

  local function onLvarChanged(_, varName, value)

    -- the handler is called with the current value upon subscribing, we don't want that
    if not initializedVars[varName] then 
      initializedVars[varName] = true
      return 
    end

    if jetwayConnected and 
      varName == vars.gsxDeparture and value >= GSX_IN_PROGRESS or 
      varName == vars.gsxDeicing and value == GSX_REQUESTED then
      if varName == vars.gsxDeparture then
        debug "GSX: departure in progress - undocking default jetway" 
      else
        debug "GSX: deicing requested - undocking default jetway" 
      end
      toggleJetway()
      jetwayConnected = false
    elseif varName == vars.fslChocks and val == 1 and ipc.elapsedtime() - startTime > 60000 then
      debug "Chocks set - docking default jetway" 
      toggleJetway()
      jetwayConnected = true
    end
  end

  for _, lvar in ipairs(vars) do
    Event.fromLvar(lvar, 1000):addAction(onLvarChanged)
  end
end