# Checklists

## Checklists are text-to-speech only for now

The voice sets haven't been updated with checklist callouts yet. You'll have to enable text-to-speech by setting sound_set=TTS in options.ini. 

The volume is controlled with the ACP INT knob, like the regular callouts. The maximum volume is a bit low — I had to reduce my FSLabs volume sliders to 50% for an optimal balance. 

## The checklist flow

The trigger phrases for the checklists are listed <a href="#List_of_checklists">below</a>.
When you start a checklist, all voice commands that aren't associated with it are suspended (their states are restored when the checklist completes).

In addition to the normal response to a challenge, you may say "restart checklist", "say again" or "standby checklist".
"standby checklist" resumes the suspended voice commands and awaits "resume checklist" or "continue checklist".

## [Checklists] section in options.ini

### display_info:

Display possible responses to a checklist item challenge in a message window.
A phrase may contain optional elements or elements with multiple variants, for example:

	@plain
	{Airbus}+{Boeing}+{...} is the best [aircraft manufacturer]

"..." means "match anything"

### display_fail

If the copilot didn't like how you responded to a challenge (he will say "double check that"), display the reason in a message window.

### menu_keybind

A key or key combination (for example, *A* or *SHIFT+F3*) that will trigger the checklist menu.
The menu lets you skip the current checklist item as well as cancel or skip the whole checklist.
Both cancelling and skipping stop the execution of the current checklist. 
The difference is that cancelling will also reactivate the checklist's trigger voice command.

## List of checklists

##### "trigger phrase"
When the copilot starts listening for the trigger phrase<br><br>

##### "before start to the line"
If preflight action enabled: when preflight action is finished, otherwise: when the chocks are set.<br><br>

##### "before start below the line"
When before start to the line is finished.<br><br>

##### "after start checklist"
If after\_start action enabled: when after\_start action is finished, otherwise: when the engines are started.<br><br>

##### "before takeoff to the line"
When after start checklist is finished.<br><br>

##### "before takeoff below the line"
If lineup action enabled: when lineup action is finished and before takeoff to the line is finished, otherwise: when before takeoff to the line is finished.<br><br>

##### "landing checklist"
After you descend below 10000 and IAS is below 200 kts.<br><br>

##### "parking checklist"
On engine shutdown<br><br>

##### "securing the aircraft checklist"
When the parking checklist is finished<br><br>

## Modifying and creating checklists

@{Checklist|Checklist class}

@{plugins.md|How to make a plugin}<br><br>

##### Modifying items in default checklists

	copilot.checklists.beforeStart:replaceItem {
		label = "toData",
		response = VoiceCommand:new "checked"
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
		briefing.wav

with config.lua that looks like this:

	return {
		"announce",
		"briefing"
	}

Alternatively, you can create a text-to-speech set by creating the file *copilot\sounds\callouts\soundSetName\config.lua* with the following content:

	return {
		isTTS = true,
		checklists = {
			doubleCheck = "double check that please"
			approach = {
				announce = "approach checklist",
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





















