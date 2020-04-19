#pragma once

#include <spdlog/spdlog.h>
#include "RecoResultFetcher.h"
#include <gauges.h>

namespace copilot {
	extern std::shared_ptr<RecoResultFetcher> recoResultFetcher;
	extern std::shared_ptr<spdlog::logger> logger;
	double readLvar(PCSTRINGZ lvname);
	void connectToFSUIPC();
	void startLuaThread();
	void stopLuaThread();
};