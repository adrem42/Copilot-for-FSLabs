# Checklists

## The checklist flow

To start a checklist, speak its trigger phrase. 
When you start a checklist, all voice commands that aren't associated with it are suspended (their states are restored when the checklist completes).

In addition to the normal response to a challenge, you may say "restart checklist", "say again" or "standby checklist".
"standby checklist" resumes the suspended voice commands and awaits "resume checklist" or "continue checklist".

## [Checklists] section in options.ini

### display_info:

Display possible responses to a checklist item challenge in a message window.
### display_fail

If the copilot didn't like how you responded to a challenge (he will say "double check that"), display the reason in a message window (the same message will also be logged in the regular log regardless of this setting).

### menu_keybind

A key or key combination (for example, *A* or *SHIFT+F3*) that will trigger the checklist menu.
The menu lets you skip the current checklist item as well as cancel or skip the whole checklist.
Both cancelling and skipping stop the execution of the current checklist. 
The difference is that cancelling will also reactivate the checklist's trigger voice command.

## List of checklists 
##### Response phrase syntax explanation:
Curly brackets denote a multiple choice phrase element, with each choice inside round brackets.<br><br>
Square brackets denote an optional phrase element.<br><br>
... means 'match anything'.<br><br>
___
### Before Start to the Line
Trigger phrases: **"before start checklist"**<br><br>
When it's available: If preflight action enabled: when preflight action is finished, otherwise: when the chocks are set.<br><br>
###### Cockpit Prep
completed
<br><br>
###### Gear Pins and Covers
removed
<br><br>
###### Signs
on auto<br><br>
on and auto<br><br>
onanauto<br><br>
on anauto
<br><br>
###### ADIRS
nav
<br><br>
###### Fuel Quantity
&lt;1-100&gt; {(thousand [&lt;1-9&gt; hundred] [kilograms])+(tonnes)}
<br><br>
###### TO Data
set
<br><br>
###### Baro REF
[{(cue an h)+(q n h)}] &lt;3-4-digit spelled number&gt; [set]
<br><br>
___
### Before Start below the Line
Trigger phrases: **"before start below the line"**, **"below the line"**<br><br>
When it's available: When before start to the line is finished.<br><br>
###### Windows / Doors
closed
<br><br>
###### Beacon
off<br><br>
on
<br><br>
###### THR Levers
idle
<br><br>
###### Parking Brake
off<br><br>
released<br><br>
on<br><br>
set
<br><br>
___
### After start
Trigger phrases: **"after start checklist"**<br><br>
When it's available: If after\_start action enabled: when after\_start action is finished, otherwise: when the engines are started.<br><br>
###### Anti-Ice
off<br><br>
on<br><br>
engine anti-ice on
<br><br>
###### ECAM Status
checked
<br><br>
###### Pitch Trim
&lt;CG value&gt; [percent] [set]
<br><br>
###### Rudder Trim
zero
<br><br>
___
### Before Takeoff to the Line
Trigger phrases: **"before takeoff checklist"**<br><br>
When it's available: When after start checklist is finished.<br><br>
###### Flight Controls
checked
<br><br>
###### Flight Instruments
checked
<br><br>
###### Briefing
confirmed
<br><br>
###### Flap Setting
config {(1)+(1 plus f)+(2)+(3)}
<br><br>
###### V1, Vr, V2 / FLEX Temp
{(V one &lt;3-digit spelled number&gt; V r &lt;3-digit spelled number&gt; V two &lt;3-digit spelled number&gt;)+(&lt;3-digit spelled number&gt; &lt;3-digit spelled number&gt; &lt;3-digit spelled number&gt;)} {(TOGA)+(no flex [temp])+(FLEX [temp] &lt;FLEX temp&gt;)}
<br><br>
###### ATC
set
<br><br>
###### ECAM Memo
takeoff no blue
<br><br>
___
### Before Takeoff below the Line
Trigger phrases: **"before takeoff below the line"**, **"below the line"**<br><br>
When it's available: If lineup action enabled: when lineup action is finished and before takeoff to the line is finished, otherwise: when before takeoff to the line is finished.<br><br>
###### Takeoff RWY
[runway] &lt;runway identifier&gt; [confirmed]
<br><br>
###### Cabin Crew
advised
<br><br>
###### TCAS
t a<br><br>
t a r a
<br><br>
###### Engine Mode Selector
ignition<br><br>
normal
<br><br>
###### Packs
off<br><br>
on
<br><br>
___
### After Takeoff / Climb
Trigger phrases: **"after takeoff climb checklist"**<br><br>
When it's available: If after\_takeoff action enabled: when after\_takeoff action is finished, otherwise: when you're airborne.<br><br>
###### Landing Gear
up
<br><br>
###### Flaps
retracted
<br><br>
###### Packs
off<br><br>
on
<br><br>
___
### After Takeoff / Climb below the Line
Trigger phrases: **"after takeoff climb below the line"**, **"below the line"**<br><br>
When it's available: When the after takeoff climb checklist to the line is finished.<br><br>
###### Baro REF
standard<br><br>
standard set
<br><br>
___
### Approach
Trigger phrases: **"approach checklist"**<br><br>
When it's available: Below 10'000 feet.<br><br>
###### Briefing
confirmed
<br><br>
###### ECAM Status
checked
<br><br>
###### Seat Belts
off<br><br>
on
<br><br>
###### Baro REF
[{(cue an h)+(q n h)}] &lt;3-4-digit spelled number&gt; [set]
<br><br>
###### Minimum
... set
<br><br>
###### Engine Mode Selector
ignition<br><br>
normal
<br><br>
___
### Landing
Trigger phrases: **"landing checklist"**<br><br>
When it's available: Below 10'000 feet and IAS below 200 kts.<br><br>
###### Cabin Crew
advised
<br><br>
###### A/THR
off<br><br>
speed
<br><br>
###### Auto-brake
low<br><br>
medium
<br><br>
###### ECAM Memo
Landing no blue
<br><br>
___
### Parking
Trigger phrases: **"parking checklist"**<br><br>
When it's available: On engine shutdown<br><br>
###### APU Bleed
off<br><br>
on
<br><br>
###### Engines
off
<br><br>
###### Seat Belts
off<br><br>
on
<br><br>
###### External Lights
nav logo on<br><br>
off
<br><br>
###### Fuel Pumps
off
<br><br>
###### Park BRK / Chocks
{(on)+(off)} and {(in)+(out)}
<br><br>
___
### Securing the Aircraft
Trigger phrases: **"securing the aircraft checklist"**<br><br>
When it's available: When the parking checklist is finished<br><br>
###### ADIRS
off
<br><br>
###### Oxygen
off<br><br>
on
<br><br>
###### APU Bleed
off<br><br>
on
<br><br>
###### EMER Exit Lights
arm<br><br>
off<br><br>
on
<br><br>
###### Signs
off
<br><br>
###### APU and BAT
off
<br><br>
___

## Modifying and creating checklists

@{Checklist|Checklist class}

@{plugins.md|How to make a plugin}<br><br>

##### Modifying items in default checklists

	copilot.checklists.beforeTakeoff:replaceItem {
		label = "takeoffSpeedsFlexTemp",
		response = VoiceCommand:new "set",
	}

	copilot.checklists.landing:getItem"autoThrust".response.SPEED:setConfidence(0.8)

##### Creating checklists

Browse the lua files at *copilot\copilot\checklists* and *copilot\copilot\initChecklists.lua* for examples.

The simplest checklist with no validation looks like this:

	approachChecklist = Checklist:new(
		"approach", 
		"Approach checklist", 
		VoiceCommand:new "approach checklist"
	)
	approachChecklist:appendItem {
		label = "briefing", 
		displayLabel = "Briefing", 
		response = VoiceCommand:new "confirmed"
	}
	approachChecklist.trigger:activateOn(copilot.events.aboveTenThousand)

The above checklist will require the following callout file structure:

	@plain
	copilot\sounds\callouts\soundSetName\checklists\approach\
		config.lua
		announce.wav
		completed.wav
		briefing.wav

with config.lua that looks like this:

	return {
		"announce",
		"completed",
		"briefing"
	}

Alternatively, you can create a text-to-speech set by creating the file *copilot\sounds\callouts\soundSetName\config.lua* with the following content:

	return {
		isTTS = true,
		parent = "TTS", -- inherit all phrases from the default TTS set
		checklists = {
			approach = {
				announce = "approach checklist",
				completed = "approach checklist completed",
				briefing = "briefing"
			}
		}
	}

The default checklists can be disabled by setting enable=0 in options.ini or programmatically:

	for _, checklist in ipairs(copilot.checklists) do 
		checklist.trigger:disable() 
	end

You can still re-use checklists disabled with enable=0 by loading their files yourself:

	require "copilot.checklists.beforeStart"
	copilot.checklists.beforeStart.trigger:activate()





















