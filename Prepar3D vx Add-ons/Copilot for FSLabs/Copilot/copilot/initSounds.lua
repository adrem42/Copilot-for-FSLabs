
local calloutDir = string.format("%s\\callouts\\%s", copilot.soundDir, copilot.UserOptions.callouts.sound_set)
local callouts = {}
copilot.sounds = {callouts = callouts}

local loadFolder

local function loadNormalConfig(dir, prefix, cfg)
  local ext = {}
  for _file in lfs.dir(dir) do
    if _file:find "[^%.]" then
      local maybeSubdir = dir .. "\\" .. _file
      if lfs.attributes(maybeSubdir, "mode") == "directory" then
        loadFolder(maybeSubdir, prefix .. _file)
      else
        local name, _ext = _file:match "(.*)%.(.*)$"
        ext[name:lower()] = _ext
      end
    end
  end
  for _, entry in ipairs(cfg) do
    if type(entry) == "string" then
      entry = {entry}
    end
    local name = entry[1] or entry.name
    if not ext[name:lower()] then
      error(("Callout file not found: %s\\%s"):format(dir, name))
    end
    callouts[prefix .. name] = Sound:new(
      string.format("%s\\%s", dir, name .. "." .. ext[name:lower()]), entry.length or 0, entry.volume or 1
    )
  end
end

local function loadTtsConfig(ttsCfg)

  local ttsPhrases = {}

  local function load(t, prefix)
    if prefix ~= "" then prefix = prefix .. "." end
    for k, v in pairs(t) do
      if type(v) == "table" then
        load(v, prefix .. k)
      else
        ttsPhrases[prefix .. k] = v
      end
    end
  end

  if ttsCfg.parent then
    local dir = copilot.soundDir .. "\\callouts\\" .. ttsCfg.parent .. "\\"
    load(loadfile(dir .. "config.lua") or load(dir .."sounds.lua"), "")
  end

  load(ttsCfg, "")

  function copilot.calloutExists(fileName)
    return ttsPhrases[fileName] ~= nil
  end

  function copilot.playCallout(fileName, delay)
    if ttsPhrases[fileName] then
      copilot.speak(ttsPhrases[fileName], delay or 0)
    else
      copilot.logger:warn("Callout " .. fileName .. " not found")
    end
  end
end

local isTTS

loadFolder = function(dir, prefix)
  if prefix ~= "" then prefix = prefix .. "." end
  local cfg = loadfile(dir .. "\\config.lua") or loadfile(dir .. "\\sounds.lua")
  if not cfg then return false end
  cfg = cfg()
  if type(cfg) == "table" then
    if isTTS ~= nil and isTTS ~= (cfg.isTTS and true or false) then
      error "You can't mix TTS and non-TTS configs"
    end
    isTTS = cfg.isTTS and true or false
    cfg.isTTS = nil
    if isTTS then
      copilot.usingTTScallouts = true
      loadTtsConfig(cfg)
    else
      function copilot.calloutExists(fileName)
        return callouts[fileName] ~= nil
      end
      function copilot.playCallout(fileName, delay)
        if callouts[fileName] then
          callouts[fileName]:play(delay or 0)
        else
          copilot.logger:warn("Callout " .. fileName .. " not found")
        end
      end
      loadNormalConfig(dir, prefix, cfg)
    end
  end
  return true
end

function copilot.addCallout(fileName, ...)
  local args = {...}
  local ext, length, volume
  if type(args[1]) == "string" then
    ext, length, volume = args[1], args[2], args[3]
  else
    ext, length, volume = "wav", args[1], args[2]
  end
  callouts[fileName] = Sound:new(string.format("%s\\%s.%s", calloutDir, fileName, ext), length or 0, volume or 1)
end

assert(loadFolder(calloutDir, ""), "No such voice set found: " .. copilot.UserOptions.callouts.sound_set)