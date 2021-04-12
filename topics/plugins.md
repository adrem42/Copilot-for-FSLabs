# Making a plugin

To make Copilot load your lua code, simply create a lua file with the name of your choice inside *Copilot for FSLabs\copilot\custom*. Copilot will load all lua files in that folder at startup.

If you have multiple files that you want to be loaded in a particular order, use the standard library *require* function. Since the *custom* folder isn't scanned recursively, you can have one main lua file at the top level and have the rest in subfolders. For example, given the following structure:

	@plain
	Copilot for FSLabs\copilot\custom\
		init.lua
		myplugin\
			file1.lua
			file2.lua

you can load file1.lua and file2.lua from init.lua (which will be loaded by Copilot) like this:

	require "copilot.custom.myplugin.file1"
	require "copilot.custom.myplugin.file2"

If you want to use Copilot with other aircraft, use the *custom\_non\_fsl* folder instead of *custom* (you'll need to create it yourself). If you have multiple add-ons, you'll need to write code that tells which aircraft was loaded. One way to do that is matching a substring in *copilot.aircraftTitle*.

## Examples

See the examples in the sidebar that are prefixed with *copilot\_*.

## Monitoring the MCDUs

Copilot constantly monitors the PF's MCDU for certain variables (for example, the takeoff speeds). This is done on a background thread because the main thread may be blocked at any time by other code. 

You can have the background thread additionally run your own code. To do that, create a lua file at a location of your choice and call *copilot.addMcduCallback(filePath)* from your plugin code. The file should return a callback that will receive the MCDU display data and store variables using the *setVar* function (it can also call *getVar* and *clearVar*). These variables can be retrieved from the main thread using *copilot.mcduWatcher:getVar(varname)*.

The parameter passed to your callback is a table containing the fields *PF*, *PM*, *CPT* and *FO*. Each one is an array of tables representing MCDU display cells. A cell table contains the fields *char*, *color* and *isBold*. Each MCDU table additionaly has an *str* field which represents the display as a string.

	-- Copilot for FSLabs\copilot\custom\myplugin\mcdu.lua

	return function(data)
		local PF = data.PF.str
		if PF:sub(40, 46) == "FROM/TO" and data.PF[64].color == "cyan" then
			setVar("FROM",  PF:sub(64, 67))
			setVar("TO",    PF:sub(69, 72))
		end
	end
<br>

	-- Copilot for FSLabs\copilot\custom\init.lua

	copilot.addMcduCallback(APPDIR .. "copilot\\custom\\myplugin\\mcdu.lua")

	copilot.addCallback(function()
		print(("FROM: %s TO: %s"):format(
			copilot.mcduWatcher:getVar "FROM" or "????", 
			copilot.mcduWatcher:getVar "TO" or "????"))
	end, nil, 1000)

	copilot.events.chocksSet:addAction(function()
		copilot.mcduWatcher:clearVar "FROM"
		copilot.mcduWatcher:clearVar "TO"
	end)

	Bind {
		key = "A",
		onPress = function()
			-- use this function to find the display cell indices:
			FSL.MCDU:printCells() -- PM MCDU
			--FSL.PF.MCDU:printCells()
			--FSL.CPT.MCDU:printCells()
		end
	}