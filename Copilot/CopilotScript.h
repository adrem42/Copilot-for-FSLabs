#pragma once
#include <Windows.h>
#include "FSL2LuaScript.h"
#include "Copilot.h"
#include "Recognizer.h"
#include "McduWatcher.h"
#include "RecoResultFetcher.h"
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

	std::thread backgroundThread;

	bool voiceControlEnabled = false;

	std::shared_ptr<Recognizer> recognizer;
	std::shared_ptr<McduWatcher> mcduWatcher;
	std::shared_ptr<RecoResultFetcher> recoResultFetcher;
	
	UINT_PTR backgroundThreadTimerId;

	struct McduWatcherLuaCallback {
		sol::protected_function callback;
		std::shared_ptr<McduWatcher::VariableStore> varStore = std::make_shared<McduWatcher::VariableStore>();
	};

	sol::state mcduWatcherLua;
	McduWatcher::VariableStore* currMcduWatcherVarStore;
	std::vector<McduWatcherLuaCallback> mcduWatcherLuaCallbacks;
	sol::protected_function mcduWatcherToArray;

	static constexpr UINT WM_STARTTIMER = WM_APP, WM_STOPTIMER = WM_APP + 1;

	void onMessageLoopTimer();
	void runMessageLoop();

	void startBackgroundThread();
	void stopBackgroundThread();

	void startBackgroundThreadTimer();
	void stopBackgroundThreadTimer();
	void actuallyStartBackgroundThreadTimer();
	void actuallyStopBackgroundThreadTimer();

	struct Events : FSL2LuaScript::Events {
		size_t EVENT_RECO_EVENT;
	};

	virtual FSL2LuaScript::Events* createEvents() override;

	std::mutex ttsQueueMutex;
	std::queue<std::pair<size_t, std::wstring>> ttsQueue;

	virtual void onEvent(FSL2LuaScript::Events* events, DWORD eventIdx) override;

public:

	using FSL2LuaScript::FSL2LuaScript;
	void onSimStart();
	void onSimExit();
	virtual ~CopilotScript();

};