To migrate from a previous version to 2.0, follow these steps:

1) Follow the new install instructions for 2.0

2) Move the following items from 'FSUIPC folder/FSLabs Copilot' to 'Prepar3D vx Add-ons/Copilot for FSLabs/copilot':
    * the custom folder
    * the failures folder (if you have one)

3) Move 'FSUIPC folder/FSLabs Copilot/options.ini' to 'Prepar3D vx Add-ons/Copilot for FSLabs'. 

4) Inside the FSUIPC folder, delete FSLabs Copilot.lua and the 'FSL2Lua' and 'Copilot for FSLabs' folders.

**IMPORTANT**: If you have written your own code, make sure that it doesn't call any functions
from the FSUIPC library except the ones that are listed below.

The following functions from the FSUIPC library are implemented:

All offset read/write functions except readStruct writeStruct and the ones that manipulate bits.
ipc.exit
ipc.sleep
ipc.control (only FS controls)
ipc.createLvar
ipc.readLvar
ipc.writeLvar
ipc.elapsedtime
ipc.log
ipc.mousemacro
ipc.get
ipc.set

LuaFileSystem is also included.