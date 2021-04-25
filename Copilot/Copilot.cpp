
#include "lua.hpp"
#include <sol/sol.hpp>
#include <Windows.h>
#include <thread>
#include <mutex>
#include <chrono>
#include <SimConnect.h>
#include <gauges.h>
#include <regex>
#include "Copilot.h"
#include "Sound.h"
#include "Recognizer.h"
#include "McduWatcher.h"
#include "versioninfo.h"
#include <Pdk.h>
#include <initpdk.h>
#include "FSUIPC.h"
#include "SimInterface.h"
#include "LuaPlugin.h"
#include "FSL2LuaScript.h"
#include "CopilotScript.h"
#include <filesystem>
#include <thread>

using namespace std::literals::chrono_literals;
using namespace P3D;

GAUGESIMPORT ImportTable = {
{ 0x0000000F, (PPANELS)NULL },
{ 0x00000000, NULL }
};
PPANELS Panels = NULL;

namespace copilot {

	std::string appDir;
	bool isFslAircraft = false;
	bool _simRunning = true;

	bool muteKeyDepressed = false;
	std::chrono::milliseconds delayBeforeUnmute = std::chrono::milliseconds(1000);
	std::chrono::time_point<std::chrono::system_clock> muteKeyReleasedTime = std::chrono::system_clock::now();

	bool simRunning()
	{
		return _simRunning;
	}

	bool isMuted()
	{
		if (muteKeyDepressed)
			return true;
		return std::chrono::system_clock::now() - muteKeyReleasedTime < delayBeforeUnmute;
	}

	std::string copilotScriptPath()
	{
		return appDir + "Copilot\\copilot.lua";
	}

	std::shared_ptr<spdlog::logger> logger = nullptr;
	std::shared_ptr<spdlog::sinks::wincolor_stdout_sink_mt> consoleSink = nullptr;
	std::shared_ptr<spdlog::sinks::rotating_file_sink_mt> fileSink = nullptr;

	sol::state loadUserOptions()
	{
		sol::state lua;

		lua.open_libraries();
		lua["print"] = [&](sol::variadic_args va) {
			std::string str;
			for (size_t i = 0; i < va.size(); i++) {
				auto v = va[i];
				str += lua["tostring"](v.get<sol::object>());
				if (i != va.size() - 1) {
					str += " ";
				}
			}
			copilot::logger->info(str);
		};

		lua["APPDIR"] = appDir;
		lua.do_string(R"(package.path = APPDIR .. '\\?.lua')");

		sol::protected_function_result res = lua.do_file(appDir + "copilot\\copilot\\LoadCopilotOptions.lua");

		if (!res.valid()) {
			sol::error err = res;
			copilot::logger->error(err.what());
		}

		return lua;
	}

	void launchFSL2LuaScript()
	{
		auto path = appDir + (isFslAircraft ? "scripts\\autorun.lua" : "scripts_non_fsl\\autorun.lua");
		if (std::filesystem::exists(path)) {
			std::thread([=] {
				LuaPlugin::launchScript<FSL2LuaScript>(path);
			}).detach();
		}
	}

	bool isCopilotEnabled()
	{
		auto lua = loadUserOptions();
		try {
			return lua["copilot"]["UserOptions"]["general"]["enable"] == 1;
		} catch (std::exception& ex) {
			copilot::logger->error("Failed to read options.ini");
		}
		return false;
	}

	void startCopilotScript()
	{
		std::thread([] {
			LuaPlugin::launchScript<CopilotScript>(copilotScriptPath());
		}).detach();
	}

	void stopCopilotScript()
	{
		std::thread([] {
			LuaPlugin::stopScript(appDir + "Copilot\\copilot.lua");
		}).detach();
	}

	void onMuteKey(bool isPressed)
	{
		if (!isPressed && muteKeyDepressed) {
			muteKeyReleasedTime = std::chrono::system_clock::now();
			copilot::logger->info("Unmuted");
		} else if (isPressed && !muteKeyDepressed) {
			copilot::logger->info("Muted");
		}
		muteKeyDepressed = isPressed;

	}

	double readLvar(const std::string& name)
	{
		auto val = SimInterface::readLvar(name);
		return val.has_value() ? *val : 0;
	}

	void initLogger()
	{
		logger = std::make_shared<spdlog::logger>("Copilot");
		logger->flush_on(spdlog::level::trace);
		logger->set_level(spdlog::level::trace);
		std::string logFilePath = appDir + "Copilot.log";
		fileSink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(logFilePath, 1048576 * 5, 0, true);
		fileSink->set_pattern("[%T] [%l] %v");
		fileSink->set_level(spdlog::level::debug);
		logger->sinks().push_back(fileSink);
#ifdef _DEBUG
		fileSink->set_level(spdlog::level::trace);
#endif
	}

	void initConsoleSink()
	{
		consoleSink = std::make_shared<spdlog::sinks::wincolor_stdout_sink_mt>();
		consoleSink->set_pattern("[%T] [Copilot] [%l] %v");
		logger->sinks().push_back(consoleSink);
		consoleSink->set_level(spdlog::level::info);
#ifdef _DEBUG
		consoleSink->set_level(spdlog::level::trace);
#endif
	}

	void findAppDir()
	{
		HMODULE hMod = GetModuleHandleA("Copilot.dll");
		char lpFilename[MAX_PATH];
		GetModuleFileNameA(hMod, lpFilename, MAX_PATH);
		appDir = std::string(lpFilename);
		appDir = appDir.substr(0, appDir.find("Copilot.dll"));
	}

	void init()
	{
		findAppDir();
		initLogger();

		auto lua = loadUserOptions();

		if (lua["copilot"]["UserOptions"]["general"]["enable"] == 1) {
			int lineWidth = 60;
			copilot::logger->info("{:*^{}}", fmt::format(" {} {} ", "Copilot for FSLabs", COPILOT_VERSION), lineWidth);
			copilot::logger->info("");

			BASS_SetConfig(BASS_CONFIG_UNICODE, true);

			BASS_DEVICEINFO info;
			copilot::logger->info("{:*^{}}", " Output device info: ", lineWidth);
			copilot::logger->info("");
			for (int i = 1; BASS_GetDeviceInfo(i, &info); i++)
				copilot::logger->info("{}={} {}",
									  i, info.name,
									  info.flags & BASS_DEVICE_DEFAULT ? "(Default)" : "");
			copilot::logger->info("");
			copilot::logger->info("{:*^{}}", "", lineWidth);
			copilot::logger->info("");
		}
	}

	void onSimEvent(SimConnect::EVENT_ID event)
	{
		switch (event) {

			case SimConnect::EVENT_SIM_START:
				LuaPlugin::withScript<CopilotScript>(copilotScriptPath(), [=](CopilotScript& script) {
					script.onSimStart();
				});
				break;

			case SimConnect::EVENT_EXIT:
			case SimConnect::EVENT_ABORT:
				LuaPlugin::withScript<CopilotScript>(copilotScriptPath(), [=](CopilotScript& script) {
					script.onSimExit();
				});
				break;

			default:
				break;
		}
	}

	std::thread launchThread;

	void onFlightLoaded(bool isFslAircraft, const std::string& aircraftName)
	{
		copilot::isFslAircraft = isFslAircraft;
		DWORD res = FSUIPC::connect();
		if (res != FSUIPC_ERR_OK) {
			logger->error("Failed to connect to FSUIPC: {}", FSUIPC::errorString(res));
		}
		initConsoleSink();
		SimInterface::init();
		launchThread = std::thread([] {
			Sleep(10000);
			launchFSL2LuaScript();
			SimConnect::setupFSL2LuaMenu();
			if (isCopilotEnabled()) {
				SimConnect::setupCopilotMenu();
				SimConnect::setupMuteControls();
				startCopilotScript();
			}
		});
	}

	void onWindowClose()
	{
		FSUIPC_OnSimExit();
		_simRunning = false;
		LuaPlugin::stopAllScripts();
	}

	IWindowPluginSystemV440* GetWindowPluginSystem()
	{
		return PdkServices::GetWindowPluginSystem();
	}
}

void DLLStart(P3D::IPdk* pPdk)
{
	if (Panels != NULL)
		ImportTable.PANELSentry.fnptr = (PPANELS)Panels;

	if (pPdk != nullptr)
		PdkServices::Init(pPdk);

	SimConnect::init();

	copilot::init();
}

void DLLStop()
{
	copilot::launchThread.join();
	copilot::logger->debug("Shutting down...");
	LuaPlugin::stopAllScripts();
	SimConnect::close();
	SimInterface::close();
	Joystick::stopAndJoinBufferThread();
	copilot::logger->debug("Bye!");
}