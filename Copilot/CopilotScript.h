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

class LuaTextMenu;

class CopilotScript : public FSL2LuaScript {

public:

	using RegisterID = uint16_t;

private:

	std::unique_ptr<CallbackRunner> callbackRunner = nullptr;

	size_t nextUpdate;

	static constexpr const char* KEY_OBJECT_REGISTRY = "OBJECT_REGISTRY";

	std::atomic<RegisterID> currRegisterID = 0;

	virtual void initLuaState(sol::state_view) override;

	friend class LuaTextMenu;

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

	Events createEvents();

public:

	using FSL2LuaScript::FSL2LuaScript;

	virtual void run() override;

	void onSimStart();

	void onSimExit();

	void onMuteKey(bool);

	template <typename T>
	RegisterID registerLuaObject(T obj)
	{
		RegisterID id = currRegisterID++;
		lua.registry()[KEY_OBJECT_REGISTRY][id] = obj;
		return id;
	}

	void unregisterLuaObject(RegisterID id);

	template <typename T>
	T getRegisteredObject(RegisterID id)
	{
		return lua.registry()[KEY_OBJECT_REGISTRY][id];
	}

	virtual ~CopilotScript();

};