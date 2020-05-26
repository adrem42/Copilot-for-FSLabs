#pragma once

#include "../Copilot/SimConnect.h"
#include <spdlog/spdlog.h>
#include "RecoResultFetcher.h"
#include <gauges.h>
#include <atomic>
#include <memory>
#include <chrono>
#include <string>

namespace copilot {
	extern RecoResultFetcher* recoResultFetcher;
	extern std::shared_ptr<spdlog::logger> logger;
	extern std::unique_ptr<SimConnect> simConnect;
	extern std::mutex FSUIPCmutex;
	double readLvar(PCSTRINGZ lvname);
	void startLuaThread();
	void shutDown();
	void autoStartLua();

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