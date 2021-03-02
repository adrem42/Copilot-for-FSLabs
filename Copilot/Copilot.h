#pragma once

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

	extern RecoResultFetcher* recoResultFetcher;
	extern std::shared_ptr<spdlog::logger> logger;
	extern std::mutex FSUIPCmutex;
	extern std::string appDir;
	double readLvar(const std::string& name);
	//void startLuaThread();
	//void shutDown();
	//void autoStartLua();
	void onSimEvent(SimConnect::EVENT_ID event);
	void onFlightLoaded(bool isFslAircraft);

	void launchFSL2LuaScript();

	P3D::IWindowPluginSystemV440* GetWindowPluginSystem();

	class Timer {
	
		using TimePoint = std::chrono::time_point<std::chrono::system_clock>;
		TimePoint start = std::chrono::system_clock::now();
		std::string prefix;

	public:
		Timer(const std::string& prefix)
			:prefix(prefix)
		{
		}
		~Timer()
		{
			auto now = std::chrono::system_clock::now();
			double duration = std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();
			logger->trace("{} took {} ms", prefix, duration);
		}
	};

};