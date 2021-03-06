#pragma once
#include <Windows.h>
#include "LuaPlugin.h"
#include "Copilot.h"
#include "Recognizer.h"
#include "McduWatcher.h"
#include "RecoResultFetcher.h"
#include <memory>
#include <functional>

class CopilotScript : public LuaPlugin {

	virtual void initLuaState(sol::state_view) override;

	std::thread backgroundThread;

	bool voiceControlEnabled = false;

	std::shared_ptr<Recognizer> recognizer;
	std::shared_ptr<McduWatcher> mcduWatcher;
	std::shared_ptr<RecoResultFetcher> recoResultFetcher;
	
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

	bool updateScript(MSG* pMsg, HANDLE recoResultsEvent);

public:

	using LuaPlugin::LuaPlugin;

	virtual void run() override;

	void onSimStart();

	void onSimExit();

	void onMuteKey(bool);

	~CopilotScript();

};

