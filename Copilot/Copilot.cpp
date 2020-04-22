
extern "C"
{
#include "../lua515/include/lua.h"
#include "../lua515/include/lauxlib.h"
#include "../lua515/include/lualib.h"
}

#pragma warning(disable : 4996)
#include <sol/sol.hpp>
#include <iostream>
#include <Windows.h>
#include <thread>
#include <mutex>
#include <chrono>
#include <SimConnect.h>
#include <gauges.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <regex>

#include "Copilot.h"
#include "Sound.h"
#include "Recognizer.h"
#include "McduWatcher.h"
#include "SimConnect.h"

using namespace std::literals::chrono_literals;

std::shared_ptr<Recognizer> recognizer = nullptr;
std::shared_ptr<McduWatcher> mcduWatcher = nullptr;
std::shared_ptr<SimConnect> simConnect = nullptr;

std::unique_ptr<std::thread> copilotThread;
std::atomic<bool> stopThread = false;
std::string appDir;

GAUGESIMPORT ImportTable = {
{ 0x0000000F, (PPANELS)NULL },
{ 0x00000000, NULL }
};
PPANELS Panels = NULL;

namespace copilot {

	std::shared_ptr<RecoResultFetcher> recoResultFetcher = nullptr;
	std::shared_ptr<spdlog::logger> logger = nullptr;

	double readLvar(PCSTRINGZ lvname)
	{
		if (lvname == 0) return 0;
		if (strlen(lvname) == 0) return 0;
		ID i = check_named_variable(lvname);
		return get_named_variable_value(i);
	}

	void connectToFSUIPC()
	{
		DWORD dwResult;
		BYTE* pMem = new BYTE[1024];
		while (!FSUIPC_Open2(SIM_ANY, &dwResult, pMem, 1024)) {
			Sleep(2000);
		}
		FSUIPC_Process(&dwResult);
	}

	void startLuaThread()
	{
		const char* request = "Lua FSLabs Copilot";
		DWORD dwResult;
		FSUIPC_Write(0x0D70, strlen(request) + 1, (void*)request, &dwResult);
		FSUIPC_Process(&dwResult);
	}

	void stopLuaThread()
	{
		const char* request = "LuaKill FSLabs Copilot";
		DWORD dwResult;
		FSUIPC_Write(0x0D70, strlen(request) + 1, (void*)request, &dwResult);
		FSUIPC_Process(&dwResult);
	}
}

void copilotThreadProc()
{
	while (!stopThread) {
		if (copilot::recoResultFetcher) {
			copilot::recoResultFetcher->fetchResults();
		}
		mcduWatcher->update();
		Sound::processQueue();
		std::this_thread::sleep_for(50ms);
	}
}

std::optional<std::string> initLua(sol::this_state ts)
{

	sol::state_view lua(ts);

	if (copilotThread && copilotThread->joinable()) {
		stopThread = true;
		copilotThread->join();
		stopThread = false;
	}
	
	auto options = lua["copilot"]["UserOptions"];

	int log_level = options["general"]["log_level"];
	copilot::logger->set_level((spdlog::level::level_enum)log_level);

	int devNum = options["callouts"]["device_id"];
	int pmSide = options["general"]["PM_seat"];
	Sound::init(devNum, pmSide);

	sol::usertype<RecoResultFetcher> RecoResultFetcherType = lua.new_usertype<RecoResultFetcher>("RecoResultFetcher");
	RecoResultFetcherType["getResult"] = &RecoResultFetcher::getResult;

	sol::usertype<Sound> SoundType = lua.new_usertype<Sound>("Sound",
															sol::constructors<Sound(const std::string&, int, double),
															Sound(const std::string&, int),
															Sound(const std::string&)>());
	SoundType["play"] = sol::overload(static_cast<void (Sound::*)(int)>(&Sound::play),
									  static_cast<void (Sound::*)()>(&Sound::play));

	sol::usertype<Recognizer> RecognizerType = lua.new_usertype<Recognizer>("Recognizer");
	RecognizerType["addRule"] = &Recognizer::addRule;
	RecognizerType["activateRule"] = &Recognizer::activateRule;
	RecognizerType["deactivateRule"] = &Recognizer::deactivateRule;
	RecognizerType["ignoreRule"] = &Recognizer::ignoreRule;
	RecognizerType["resetGrammar"] = &Recognizer::resetGrammar;

	sol::usertype<McduWatcher> McduWatcherType = lua.new_usertype<McduWatcher>("McduWatcher");
	McduWatcherType["getVar"] = &McduWatcher::getVar;
	McduWatcherType["resetVars"] = &McduWatcher::resetVars;

	if (options["voice_control"]["enable"] == 1) {

		try { 
			recognizer = std::make_shared<Recognizer>();
			copilot::recoResultFetcher = std::make_shared<RecoResultFetcher>(recognizer);
		}
		catch(...){ 
			return "Failed to create recognizer"; 
		}
		
	}

	std::string port = options["general"]["http_port"];
	mcduWatcher = std::make_shared<McduWatcher>(pmSide, std::stoi(port));
	auto copilot = lua["copilot"];
	copilot["recognizer"] = recognizer;
	copilot["recoResultFetcher"] = copilot::recoResultFetcher;
	copilot["mcduWatcher"] = mcduWatcher;

	copilotThread = std::make_unique<std::thread>(copilotThreadProc);
	return {};
}

void init()
{
	copilot::connectToFSUIPC();

	char lpFilename[MAX_PATH];
	HMODULE hMod = GetModuleHandleA("FSUIPC5");
	if (!hMod) hMod = GetModuleHandleA("FSUIPC6");
	GetModuleFileNameA(hMod, lpFilename, MAX_PATH);
	std::string FSUIPC_DIR = std::regex_replace(lpFilename, std::regex("FSUIPC\\d.dll"), "");
	std::string appDir = FSUIPC_DIR + "\\FSLabs Copilot\\";

	std::string logFileName = appDir + "\\Copilot.log";
#ifdef DEBUG
	logFileName = appDir + "\\Copilot(debug).log";
#endif
	auto fileSink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(logFileName, 1048576 * 5, 0, true);
	fileSink->set_pattern("[%d-%m-%C %T] [%l] %v");
	std::string logName = "FSLabs Copilot";
#ifdef DEBUG
	logName += "(debug)";
#endif
	copilot::logger = std::make_shared<spdlog::logger>(logName, fileSink);
	copilot::logger->flush_on(spdlog::level::trace);

	sol::state lua;
	lua.open_libraries();
	lua["FSUIPC_DIR"] = FSUIPC_DIR;
	lua["APPDIR"] = appDir;
	lua.do_string(R"(package.path = FSUIPC_DIR .. '\\?.lua')");
	auto res = lua.do_file(appDir + "\\copilot\\UserOptions.lua");
	if (res.status() != sol::call_status::ok) {
		std::string err = "copilot - " + res.get<std::string>();
		copilot::logger->error(err);
	}

	BASS_DEVICEINFO info;
	copilot::logger->info("Output device info:");
	for (int i = 1; BASS_GetDeviceInfo(i, &info); i++)
		copilot::logger->info("{}={} {}",
							  i, info.name,
							  info.flags & BASS_DEVICE_DEFAULT ? "(Default)" : "");
	copilot::logger->info("---------------------------------------------------------------------");
}

void DLLStart(void)
{
	simConnect = std::make_unique<SimConnect>();
	simConnect->init();

	if (Panels != NULL) {
		ImportTable.PANELSentry.fnptr = (PPANELS)Panels;
	}

	std::thread(init).detach();

}

void DLLStop(void)
{

}

extern "C"
__declspec(dllexport) int luaopen_Copilot(lua_State* L)
{
	sol::state_view lua(L);

	using logger = spdlog::logger;
	sol::usertype<logger> LoggerType = lua.new_usertype<logger>("Logger");
	LoggerType["trace"] = static_cast<void (logger::*)(const std::string&)>(&logger::trace);
	LoggerType["debug"] = static_cast<void (logger::*)(const std::string&)>(&logger::debug);
	LoggerType["info"] = static_cast<void (logger::*)(const std::string&)>(&logger::info);
	LoggerType["warn"] = static_cast<void (logger::*)(const std::string&)>(&logger::warn);
	LoggerType["error"] = static_cast<void (logger::*)(const std::string&)>(&logger::error);
	
	auto copilot = lua.create_table();
	copilot["init"] = initLua;
	copilot["logger"] = copilot::logger;
	copilot.push();
	return 1;
}
