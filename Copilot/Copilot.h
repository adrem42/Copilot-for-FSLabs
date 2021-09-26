#pragma once
#include "../Copilot/SimConnect.h"
#include <spdlog/spdlog.h>
#include <gauges.h>
#include <atomic>
#include <memory>
#include <chrono>
#include <string>
#include <spdlog/sinks/rotating_file_sink.h>
#include <IWindowPluginSystem.h>

namespace sol {
	template <typename T>
	struct unique_usertype_traits<CComPtr<T>> {
		typedef T type;
		typedef CComPtr<T> actual_type;
		static const bool value = true;
		static bool is_null(const actual_type& ptr) {
			return ptr == NULL;
		}
		static type* get(const actual_type& ptr) {
			return ptr.p;
		}
	};
}

namespace copilot {

	extern std::shared_ptr<spdlog::logger> logger;
	extern std::shared_ptr<spdlog::sinks::wincolor_stdout_sink_mt> consoleSink;
	extern std::shared_ptr<spdlog::sinks::rotating_file_sink_mt> fileSink;
	extern std::mutex FSUIPCmutex;
	extern std::string appDir;
	extern bool isFslAircraft;
	double readLvar(const std::string& name);
	void startCopilotScript();
	void stopCopilotScript();
	void onSimEvent(SimConnect::EVENT_ID event);
	void onMuteKey(bool);
	void onFlightLoaded(bool isFslAircraft, const std::string& aircraftName, int airfileCount);
	void onWindowClose();
	bool simRunning();
	bool isMuted();

	void launchAutorunLua();
	void loadScriptsIni(bool firstRun);

	P3D::IWindowPluginSystemV440* GetWindowPluginSystem();

};