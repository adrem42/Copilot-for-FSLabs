
local sidestickEventFmt = "FSL.A320X.SideStick Transducer Unit " .. FSL:getPilot() .. ".%s Axis"
local sidestickLvarFmt = "VC_FLTSTICK_%s_" .. select(2, FSL:getPilot())

local sidestick = {
  evtX = copilot.simConnectEvent(sidestickEventFmt:format "Roll"),
  evtY = copilot.simConnectEvent(sidestickEventFmt:format "Pitch"),
  lvarX = sidestickLvarFmt:format("L_R"),
  lvarY = sidestickLvarFmt:format("F_B")
}

local function moveSidestick(args)
  if args.x then 
    sidestick.evtX:transmit(args.x * 0x8000) 
  end
  if args.y then 
    sidestick.evtY:transmit(args.y * 0x8000) 
  end
end

local function getAxisPos(axis)
  local lvarVal = ipc.readLvar(sidestick["lvar" .. axis:upper()])
  return (lvarVal - 500) / 500
end

local maf = require "FSL2Lua.libs.maf"

local function smoothMoveSidestick(args)
  local fromX = getAxisPos "x"
  local fromY = getAxisPos "y"
  local vec = maf.vector((args.x or fromX) - fromX, (args.y or fromY) - fromY)
  local len = vec:length()
  vec:normalize()
  local step = 0.05
  local scale = 0
  while math.abs(len - scale) >= step do
    scale = scale + step
    moveSidestick {
      x = fromX + vec.x * scale, 
      y = fromY + vec.y * scale
    }
    ipc.sleep(10)
  end 
  moveSidestick {x = args.x, y = args.y}
end

return {
  moveRaw = moveSidestick,
  move = smoothMoveSidestick
}