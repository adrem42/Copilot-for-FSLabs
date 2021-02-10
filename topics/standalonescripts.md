# Standalone FSL2Lua scripts

You can use FSL2Lua standalone (without Copilot) to bind FSLabs cockpit controls to your keyboard, joystick buttons and axes.

Even though you will need to write Lua code, no prior programming experience is required as the syntax is very straightforward. Making simple bindings is more akin to writing a configuration file rather than 'real programming'.

***

**See the examples:**

`cockpit_control_binds.lua`

`hid_joysticks.lua`<br><br>

All controls are listed @{listofcontrols.md|here}.

***



**These are the steps to create and run a script:**

1. Create a lua file with the name of you choice in the FSUIPC folder (the one with the FSUIPC dll), for example, *my\_script.lua*.

2. Inside your file, write your code with the help of the links above.

3. FSUIPC detects lua scripts in its folder and creates special controls for them. The control for launching *my\_script.lua* will be called *Lua my\_script*.
You can bind it to a button or key in the FSUIPC menu - it will be listed in the controls drop-down menu.

4. To tell FSUIPC to auto-run your script when the flight starts, open your FSUIPC6.ini or FSUIPC5.ini and create an entry for your script under the [Auto] section (create the section if it doesn't exist), like this:

[Auto]  
1=Lua my_script
<br><br>
<iframe style="position: relative; width: 100%; height:480px" src="https://www.youtube.com/embed/jjjrj4fHNTE" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>