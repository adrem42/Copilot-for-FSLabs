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





















