#define _CRT_SECURE_NO_WARNINGS 1
#define _SILENCE_ALL_CXX17_DEPRECATION_WARNINGS 1
#include "../lua515/include/lua.hpp"
#include <sol/sol.hpp>
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
#include "versioninfo.h"

using namespace std::literals::chrono_literals;

Recognizer* recognizer = nullptr;
McduWatcher* mcduWatcher = nullptr;

std::unique_ptr<std::thread> copilotInitThread, luaInitThread;
std::atomic<bool> scriptStarted = false;
std::string appDir;

HANDLE simExit = CreateEventA(NULL, TRUE, FALSE, NULL);

GAUGESIMPORT ImportTable = {
{ 0x0000000F, (PPANELS)NULL },
{ 0x00000000, NULL }
};
PPANELS Panels = NULL;

class MessageLoop {

	std::unique_ptr<std::thread> thread;
	HANDLE callbackRegistered = CreateEventA(NULL, FALSE, NULL, NULL);
	bool callbackRegisteredOk;

	static VOID timerProc(HWND, UINT, UINT_PTR, DWORD)
	{
		mcduWatcher->update();
		Sound::processQueue();
	}

	void _messageLoop(bool voiceControl)
	{
		if (voiceControl) {
			callbackRegisteredOk = copilot::recoResultFetcher->registerCallback();
			SetEvent(callbackRegistered);
		}
		SetTimer(NULL, NULL, 70, timerProc);
		MSG msg;
		while (GetMessage(&msg, NULL, 0, 0)) {
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	}

public:
	
	bool start(bool voiceControl)
	{
		bool res; 
		ResetEvent(callbackRegistered);
		callbackRegisteredOk = false;
		thread = std::make_unique<std::thread>(&MessageLoop::_messageLoop, this, voiceControl);
		if (voiceControl) {
			WaitForSingleObject(callbackRegistered, 10000);
			res = callbackRegisteredOk;
		}
		return res;
	}

	void stop()
	{
		if (thread != nullptr) {
			PostThreadMessage(GetThreadId(thread->native_handle()),
							  WM_QUIT, 0, 0);
			thread->join();
			thread = nullptr;
		}
	}

} messageLoop;

bool connectToFSUIPC()
{
	DWORD dwResult;
	static BYTE* pMem = new BYTE[1024];
	bool connected = FSUIPC_Open2(SIM_ANY, &dwResult, pMem, 1024);
	FSUIPC_Process(&dwResult);
	return connected;
}

namespace copilot {

	RecoResultFetcher* recoResultFetcher = nullptr;
	std::shared_ptr<spdlog::logger> logger = nullptr;
	std::unique_ptr<SimConnect> simConnect = nullptr;
	std::mutex FSUIPCmutex;

	double readLvar(PCSTRINGZ lvname)
	{
		if (lvname == 0) return 0;
		if (strlen(lvname) == 0) return 0;
		ID i = check_named_variable(lvname);
		return get_named_variable_value(i);
	}

	void startLuaThread()
	{
		const char* request = "Lua FSLabs Copilot";
		DWORD dwResult;
		std::lock_guard<std::mutex> lock(FSUIPCmutex);
		FSUIPC_Write(0x0D70, strlen(request) + 1, (void*)request, &dwResult);
		FSUIPC_Process(&dwResult);
	}

	void shutDown()
	{
		const char* request = "LuaKill FSLabs Copilot";
		DWORD dwResult;
		std::lock_guard<std::mutex> lock(FSUIPCmutex);
		FSUIPC_Write(0x0D70, strlen(request) + 1, (void*)request, &dwResult);
		FSUIPC_Process(&dwResult);

		messageLoop.stop();
		delete copilot::recoResultFetcher;
		delete recognizer;
		delete mcduWatcher;
		copilot::recoResultFetcher = nullptr;
		recognizer = nullptr;
		mcduWatcher = nullptr;
	}

	void autoStartLua()
	{
		luaInitThread = std::make_unique<std::thread>([] {
			if (WaitForSingleObject(simExit, 30000) == WAIT_OBJECT_0) return;
			do {
				startLuaThread();
				if (WaitForSingleObject(simExit, 5000) == WAIT_OBJECT_0) return;
			} while (!scriptStarted);
													  });
	}

	void init()
	{
		while (!connectToFSUIPC()) {
			if (WaitForSingleObject(simExit, 2000) == WAIT_OBJECT_0) return;
		}

		char lpFilename[MAX_PATH];
		HMODULE hMod = GetModuleHandleA("FSUIPC5");
		if (!hMod) hMod = GetModuleHandleA("FSUIPC6");
		GetModuleFileNameA(hMod, lpFilename, MAX_PATH);
		std::string FSUIPC_DIR = std::regex_replace(lpFilename, std::regex("FSUIPC\\d.dll"), "");
		std::string appDir = FSUIPC_DIR + "\\FSLabs Copilot\\";

		if (GetFileAttributes(appDir.c_str()) != INVALID_FILE_ATTRIBUTES) {
			std::string logFileName = appDir + "\\Copilot.log";
#ifdef DEBUG
			logFileName = appDir + "\\Copilot(debug).log";
#endif
			auto fileSink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(logFileName, 1048576 * 5, 0, true);
			fileSink->set_pattern("[%T] [%l] %v");
			std::string logName = "FSLabs Copilot";
#ifdef DEBUG
			logName += "(debug)";
#endif
			copilot::logger = std::make_shared<spdlog::logger>(logName, fileSink);
			copilot::logger->flush_on(spdlog::level::trace);
			copilot::logger->info("************** Copilot for FSLabs {} **************", COPILOT_VERSION);
			copilot::logger->info("");
			sol::state lua;
			lua.open_libraries();
			lua["FSUIPC_DIR"] = FSUIPC_DIR;
			lua["APPDIR"] = appDir;
			lua.do_string(R"(package.path = FSUIPC_DIR .. '\\?.lua')");
			auto result = lua.do_file(appDir + "\\copilot\\UserOptions.lua");
			if (!result.valid()) {
				sol::error err = result;
				copilot::logger->error(err.what());
			}

			BASS_DEVICEINFO info;
			copilot::logger->info("***************** Output device info: ****************");
			copilot::logger->info("");
			for (int i = 1; BASS_GetDeviceInfo(i, &info); i++)
				copilot::logger->info("{}={} {}",
									  i, info.name,
									  info.flags & BASS_DEVICE_DEFAULT ? "(Default)" : "");
			copilot::logger->info("");
			copilot::logger->info("******************************************************");
			copilot::logger->info("");

		}

	}

	void onSimStart()
	{
		simConnect = std::make_unique<SimConnect>();
		simConnect->init();

		if (Panels != NULL) {
			ImportTable.PANELSentry.fnptr = (PPANELS)Panels;
		}

		copilotInitThread = std::make_unique<std::thread>(copilot::init);
	}

	void onSimExit()
	{
		SetEvent(simExit);
		if (copilotInitThread && copilotInitThread->joinable())
			copilotInitThread->join();
		if (luaInitThread && luaInitThread->joinable())
			luaInitThread->join();
		shutDown();
		simConnect->close();
	}

}

std::optional<std::string> initLua(sol::this_state ts)
{
	sol::state_view lua(ts);

	messageLoop.stop();

	auto options = lua["copilot"]["UserOptions"];

	int log_level = options["general"]["log_level"];
	copilot::logger->set_level((spdlog::level::level_enum)log_level);

	int devNum = options["callouts"]["device_id"];
	int pmSide = options["general"]["PM_seat"];
	Sound::init(devNum, pmSide);

	auto RecoResultFetcherType = lua.new_usertype<RecoResultFetcher>("RecoResultFetcher");
	RecoResultFetcherType["getResults"] = &RecoResultFetcher::getResults;

	auto SoundType = lua.new_usertype<Sound>("Sound",
											 sol::constructors<Sound(const std::string&, int, double),
											 Sound(const std::string&, int),
											 Sound(const std::string&)>());
	SoundType["play"] = sol::overload(static_cast<void (Sound::*)(int)>(&Sound::play),
									  static_cast<void (Sound::*)()>(&Sound::play));

	auto RecognizerType = lua.new_usertype<Recognizer>("Recognizer");
	RecognizerType["addRule"] = &Recognizer::addRule;
	RecognizerType["activateRule"] = &Recognizer::activateRule;
	RecognizerType["deactivateRule"] = &Recognizer::deactivateRule;
	RecognizerType["ignoreRule"] = &Recognizer::ignoreRule;
	RecognizerType["disableRule"] = &Recognizer::disableRule;
	RecognizerType["resetGrammar"] = &Recognizer::resetGrammar;
	RecognizerType["addPhrases"] = &Recognizer::addPhrases;
	RecognizerType["removePhrases"] = &Recognizer::removePhrases;
	RecognizerType["removeAllPhrases"] = &Recognizer::removeAllPhrases;
	RecognizerType["setConfidence"] = &Recognizer::setConfidence;
	RecognizerType["getPhrases"] = &Recognizer::getPhrases;
	RecognizerType["setRulePersistence"] = &Recognizer::setRulePersistence;
	lua.new_enum("RulePersistenceMode", 
				 "Ignore", Recognizer::RulePersistenceMode::Ignore,
				 "Persistent", Recognizer::RulePersistenceMode::Persistent,
				 "NonPersistent", Recognizer::RulePersistenceMode::NonPersistent );

	auto McduWatcherType = lua.new_usertype<McduWatcher>("McduWatcher");
	McduWatcherType["getVar"] = &McduWatcher::getVar;
	McduWatcherType["resetVars"] = &McduWatcher::resetVars;

	delete copilot::recoResultFetcher;
	delete recognizer;
	recognizer = nullptr;
	copilot::recoResultFetcher = nullptr;
	bool voiceControl = options["voice_control"]["enable"] == 1;
	if (voiceControl) {
		recognizer = new Recognizer;
		if (!recognizer->init()) return "Failed to create recognizer";
		copilot::recoResultFetcher = new RecoResultFetcher(recognizer);
	}

	std::string port = options["general"]["http_port"];
	delete mcduWatcher;
	mcduWatcher = new McduWatcher(pmSide, std::stoi(port));
	auto copilot = lua["copilot"];
	copilot["recognizer"] = recognizer;
	copilot["recoResultFetcher"] = copilot::recoResultFetcher;
	copilot["mcduWatcher"] = mcduWatcher;

	bool callbackRegisteredOk = messageLoop.start(voiceControl);
	if (voiceControl && !callbackRegisteredOk)
		return "Failed to create SAPI callback";
	return {};
}

void DLLStart()
{
	copilot::onSimStart();
}

void DLLStop()
{
	copilot::onSimExit();
}

extern "C" 
__declspec(dllexport) int luaopen_FSLCopilot(lua_State* L)
{
	sol::state_view lua(L);
	scriptStarted = true;

	using logger = spdlog::logger;
	sol::usertype<logger> LoggerType = lua.new_usertype<logger>("Logger");
	LoggerType["trace"] = static_cast<void (logger::*)(const std::string&)>(&logger::trace);
	LoggerType["debug"] = static_cast<void (logger::*)(const std::string&)>(&logger::debug);
	LoggerType["info"] = static_cast<void (logger::*)(const std::string&)>(&logger::info);
	LoggerType["warn"] = static_cast<void (logger::*)(const std::string&)>(&logger::warn);
	LoggerType["error"] = static_cast<void (logger::*)(const std::string&)>(&logger::error);
	LoggerType["setLevel"] = &logger::set_level;
	
	auto copilot = lua.create_table();
	copilot["init"] = initLua;
	copilot["logger"] = copilot::logger;
	copilot.push();
	return 1;
}
