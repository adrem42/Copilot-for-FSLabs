#pragma once

#define SPDLOG_WCHAR_TO_UTF8_SUPPORT
#define SPDLOG_WCHAR_FILENAMES
#include "../Copilot/SimConnect.h"
#include <spdlog/spdlog.h>
#include "RecoResultFetcher.h"
#include <gauges.h>
#include <atomic>
#include <memory>
#include <chrono>
#include <string>
#include <IWindowPluginSystem.h>

namespace copilot {

	extern std::shared_ptr<spdlog::logger> logger;
	extern std::mutex FSUIPCmutex;
	extern std::string appDir;
	extern bool isFslAircraft;
	double readLvar(const std::string& name);
	void startCopilotScript();
	void stopCopilotScript();
	void onSimEvent(SimConnect::EVENT_ID event);
	void onMuteKey(bool);
	void onFlightLoaded(bool isFslAircraft, const std::string& aircraftName);

	void launchFSL2LuaScript();

	P3D::IWindowPluginSystemV440* GetWindowPluginSystem();

};