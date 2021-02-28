# Standalone FSL2Lua scripts

You can install FSL2Lua standalone (without Copilot) to bind your keyboard keys, joystick buttons **and axes** to FSLabs cockpit controls.

The binding facilities can also be used with non-FSL aircraft.

The syntax for writing the scripts is straightforward enough that you don't need any programming experience. 

***

**See the examples:**

`cockpit_control_binds.lua`

`hid_joysticks.lua`

`set_seat.lua`<br><br>

The names for all the cockpit controls can be found @{listofcontrols.md|here}.

***



**These are the steps to create and run a script:**

1. Create a lua file with the name of you choice in the FSUIPC install directory, for example, *my\_script.lua*.

2. Inside your file, write your code with the help of the links above.

3. FSUIPC detects lua scripts in its folder and creates special controls for them. The control for launching *my\_script.lua* will be called *Lua My Script*.
You can bind it to a button or key in the FSUIPC menu - it will be listed in the controls drop-down menu.

4. To tell FSUIPC to auto-run your script when the flight starts, open your FSUIPC6.ini or FSUIPC5.ini and create an entry for your script under the [Auto.FSLabs] section (create the section if it doesn't exist), like this:

[Auto.FSLabs]  
1=Lua my_script

**Substitute FSLabs with the name of your FSLabs-specific FSUIPC profile if you have created one.**<br><br>

<iframe width="100%" height="480" src="https://www.youtube.com/embed/D-yB_FZsqGo" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>