local A319_IS_A320 = require "Modules.FSL2Lua.FSL2Lua.config".A319_IS_A320

local paths = {
  repo = "Modules\\FSL2Lua\\FSL2Lua\\FSL.lua",
  insim = "C:\\Users\\Peter\\Documents\\Prepar3D v5 Add-ons\\FSUIPC6\\FSL2Lua\\FSL2Lua\\FSL.lua"
}

local FSL = dofile(paths[arg[1]])

print "---------------------------------------------"
print "---------------------------------------------"
print "---------------------------------------------"

local numMissing = 0

for k, v in pairs(FSL) do
  if not v.ignore and not v.FSControl then
    local missing319 = not A319_IS_A320 and v.A319.available ~= false and not v.A319.rectangle
    local missing320 = v.A320.available ~= false and not v.A320.rectangle
    local missing321 = v.A321.available ~= false and not v.A321.rectangle
    if missing320 or missing321 or missing319 then
      print("Macros missing for control " .. k .. ":")
      numMissing = numMissing + 1
    end
    if missing319 then
      print "\tA319"
    end
    if missing320 then
      print "\tA320"
    end
    if missing321 then
      print "\tA321"
    end
  end
end

print("Total missing: " .. numMissing)