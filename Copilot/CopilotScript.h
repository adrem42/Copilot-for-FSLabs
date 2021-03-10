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

class TextMenuWrapper;

class CopilotScript : public FSL2LuaScript {

	virtual void initLuaState(sol::state_view) override;

	friend class TextMenuWrapper;

	std::thread backgroundThread;

	bool voiceControlEnabled = false;
	bool shouldRun = false;

	std::shared_ptr<Recognizer> recognizer;
	std::shared_ptr<McduWatcher> mcduWatcher;
	std::shared_ptr<RecoResultFetcher> recoResultFetcher;

	std::unordered_set<std::shared_ptr<SimConnect::TextMenuEvent>> textMenuEvents;

	using LuaCallback = std::function<void(sol::state_view&)>;

	std::mutex luaCallbackQueueMutex;
	std::queue<LuaCallback> luaCallbacks;
	HANDLE luaCallbackEvent = CreateEvent(0, 0, 0, 0);

	void enqueueCallback(LuaCallback);
	
	static std::mutex textMenuCallbackMutex;
	static std::unordered_map<SimConnect::TextMenuEvent*, sol::function> textMenuEventCallbacks;
	std::unordered_set<std::shared_ptr<SimConnect::TextMenuEvent>> pendingTextMenuEvents;
	
	UINT_PTR mainThreadTimerId;
	UINT_PTR backgroundThreadTimerId;

	static constexpr UINT WM_STARTTIMER = WM_APP, WM_STOPTIMER = WM_APP + 1;

	void onMessageLoopTimer();

	void actuallyStartBackgroundThreadTimer();

	void actuallyStopBackgroundThreadTimer();

	void runMessageLoop();

	void startBackgroundThread();

	void stopBackgroundThread();

	void startBackgroundThreadTimer();

	void stopBackgroundThreadTimer();

	struct Events : FSL2LuaScript::Events {
		size_t EVENT_RECO_EVENT;
		size_t EVENT_LUA_CALLBACK;
	};

	bool updateScript(MSG* pMsg, Events& events);

	Events createEvents();

public:

	using FSL2LuaScript::FSL2LuaScript;

	virtual void run() override;

	void onSimStart();

	void onSimExit();

	void onMuteKey(bool);

	virtual ~CopilotScript();

};

