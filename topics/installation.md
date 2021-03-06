# Installation

<a href="https://forums.flightsimlabs.com/index.php?/topic/25298-copilot-lua-script/&tab=comments#comment-194432">Copilot and FSLabs version compatibility</a>

## Using the keyboard and joystick binding facilities

1. Install Copilot using the instructions below.

2. If you don't want the main Copilot functionality, disable Copilot by setting enable=0 in the [General] section in options.ini

3. Read more @{standalonescripts.md|here}

## Installing Copilot

1. Unzip the content of *Prepar3D vx Add-ons* into your Add-ons folder (eg *C:\Users\Username\Documents\Prepar3D v4 Add-ons*).

2. Run the simulator and respond to the prompt asking you to enable the addon.

3. After P3D has loaded into the main menu, you'll find the configuration file at *Prepar3D vx Add-ons\Copilot for FSLabs\options.ini*. Open it and adjust the settings.

The script will auto-run after you load a flight with FSLabs.

You can restart or stop the script from its Add-ons submenu.

**If anything goes wrong during the script's operation**, examine Copilot.log for errors or anything else that's unusual.

Read @{plugins.md|here} if you want to extend the functionality of the script.

## Setting up speech recognition

You need to have English as the Windows language in order for the speech recognition to work . 

1. Go to Control Panel -> Speech Recognition -> Advanced speech options <p><img src="../img/recosetup1.jpg" width="500px"></p>

2. Select *English - UK* or *English - US* as the language

3. Select Configure Microphone in the Microphone section. **Warning**: during this process, the recognition engine finds the optimal microphone level for its purposes. When an application such as Copilot instantiates a recognition engine, the microphone level will adjusted by the engine if it's not at that optimal setting.

4. Train the profile with the Train Profile wizard <p><img src="../img/recosetup2.jpg" width="400px"></p>

5. If you fly online, you'll want to bind your PTT key or button to mute Copilot. There are two ways of doing it:<br><br>

> 1. Copy *Copilot.evt* from *Copilot for FSLabs\FSUIPC* into your FSUIPC install folder. This will add Copilot's mute and unmute controls to FSUIPC's list of controls. <p><img src="../img/FSUIPC.jpg"></p>

> 2. Create a separate script as described @{standalonescripts.md|here} and bind a key or button to the muteCopilot and unmuteCopilot functions, for example:
	Bind { key = "A", onPress = muteCopilot, onRelease = unmuteCopilot }