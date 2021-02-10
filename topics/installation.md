# Installation

<a href="https://forums.flightsimlabs.com/index.php?/topic/25298-copilot-lua-script/&tab=comments#comment-194432">Copilot and FSLabs version compatibility</a>

## Installing only FSL2Lua

You can use FSL2Lua standalone (without Copilot) to bind FSLabs cockpit controls to your keyboard, joystick buttons and axes.

To install only FSL2Lua, unzip Modules\FSL2Lua into your FSUIPC folder (the one with the FSUIPC dll).

@{standalonescripts.md | Click here} to read on how to create a script and tell FSUIPC to run it.

## Installing Copilot

1. Unzip the content of the Modules folder into the the FSUIPC installation directory.

2. Unzip the content of the Prepar3D vx Add-ons folder into your Add-ons folder (eg *C:\Users\Username\Documents\Prepar3D v4 Add-ons*).

3. Run the simulator and respond to the prompt asking you to enable the addon.

4. After P3D has loaded into the main menu, you'll find the configuration file at *FSUIPC directory/FSLabs Copilot/options.ini*. Open it and adjust the settings.

The script will auto-run after you load a flight with FSLabs.

You can restart or stop the script (no need to do either during normal operation :) and output its log to the console (which needs to be enabled in the FSUIPC settings first) from its Add-ons submenu.

**If anything goes wrong during the script's operation**, look for any lua errors in FSUIPC6.log/FSUIPC5.log or anything unusual in Copilot.log (you can make it more verbose by setting log_level to 1).

If you want to extend the functionality of the script, see @{custom.lua | some examples here.}

@{cockpit_control_binds.lua | A few examples of binding cockpit controls to keyboard keys and joystick buttons}

## Setting up speech recognition

You need to have English as the Windows language in order for speech recognition to work  

1. Go to Control Panel -> Speech Recognition -> Advanced speech options <p><img src="../img/recosetup1.jpg" width="500px"></p>

2. Select *English - UK* or *English - US* as the language

3. Select Configure Microphone in the Microphone section

4. Train the profile with the Train Profile wizard <p><img src="../img/recosetup2.jpg" width="400px"></p>

5. If you fly online, you'll want to bind your PTT key or button to mute Copilot: <p><img src="../img/mutekey.png" width="500px"></p> <p><img src="../img/mutebutton.png" width="500px"></p>

