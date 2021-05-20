# FSUIPC Lua API compatibility

Copilot used to be a Lua plugin launched within the FSUIPC Lua environment. For backwards compatibility, the following functions from the FSUIPC Lua library have been implemented:

Logic library

ipc.writeUB<br>
ipc.writeSB<br>
ipc.writeUW<br>
ipc.writeSW<br>
ipc.writeUD<br>
ipc.writeSD<br>
ipc.writeDD<br>
ipc.writeFLT<br>
ipc.writeDBL<br>
ipc.writeSTR<br>

ipc.writeStruct

ipc.readUB<br>
ipc.readSB<br>
ipc.readUW<br>
ipc.readSW<br>
ipc.readUD<br>
ipc.readSD<br>
ipc.readDD<br>
ipc.readFLT<br>
ipc.readDBL<br>
ipc.readSTR<br>

ipc.exit<br>
ipc.sleep<br>
ipc.control (only FS controls)<br>
ipc.createLvar<br>
ipc.readLvar<br>
ipc.writeLvar<br>
ipc.elapsedtime<br>
ipc.log<br>
ipc.mousemacro<br>
ipc.get<br>
ipc.set<br>
ipc.display<br>

## Alternatives to some other functions

ipc.keypress: `copilot.keypress`<br>
ipc.setMenu: `TextMenu` and `Event.fromTextMenu`<br>
event.key: @{FSL2Lua.Bind|Bind}<br>
event.timer: `copilot.addCallback`<br>
HID library: `Joystick`