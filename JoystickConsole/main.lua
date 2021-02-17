joy = Joystick.new(0x06a3, 0x0c2d)

local function test(_, _, t) 
  print(t)
end

joy:onPress(1, test, Joystick.sendEventDetails)
joy:onRelease(3, test, Joystick.sendEventDetails)

Joystick.read()