#pragma once
#include <Windows.h>
#include "FSL2LuaScript.h"
#include "Copilot.h"
#include "Recognizer.h"
#include "McduWatcher.h"
#include "RecognizerCallback.h"
#include <memory>
#include <functional>
#include <queue>
#include "SimConnect.h"
#include <stdint.h>
#include "CallbackRunner.h"
#include <queue>

class CopilotScript : public FSL2LuaScript {

private:

	ISpVoice* voice = nullptr;

	virtual void initLuaState(sol::state_view) override;
	virtual void onLuaStateInitialized() override;

	std::shared_ptr<McduWatcher> mcduWatcher;
	
	struct McduWatcherLuaCallback {
		sol::protected_function callback;
		std::shared_ptr<McduWatcher::VariableStore> varStore = std::make_shared<McduWatcher::VariableStore>();
	};

	sol::state mcduWatcherLua;
	McduWatcher::VariableStore* currMcduWatcherVarStore;
	std::vector<McduWatcherLuaCallback> mcduWatcherLuaCallbacks;
	sol::protected_function mcduWatcherToArray;

public:

	using FSL2LuaScript::FSL2LuaScript;
	void onSimStart();
	void onSimExit();
	void onBackgroundTimer() override;
	virtual ~CopilotScript();

};