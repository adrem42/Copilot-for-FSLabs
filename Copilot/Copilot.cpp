#define _CRT_SECURE_NO_WARNINGS 1
#define _SILENCE_ALL_CXX17_DEPRECATION_WARNINGS 1
#include "lua.hpp"
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
#include <Pdk.h>
#include <initpdk.h>
#include "FSUIPC.h"
#include "SimInterface.h"
#include "LuaPlugin.h"
#include "FSL2LuaScript.h"

using namespace std::literals::chrono_literals;

Recognizer* recognizer = nullptr;
McduWatcher* mcduWatcher = nullptr;

std::thread copilotInitThread, luaInitThread;
std::atomic_bool scriptStarted = false;

bool FSL_AIRCRAFT = false;

using namespace P3D;

HANDLE simExit = CreateEventA(NULL, TRUE, FALSE, NULL);

GAUGESIMPORT ImportTable = {
{ 0x0000000F, (PPANELS)NULL },
{ 0x00000000, NULL }
};
PPANELS Panels = NULL;

class MessageLoop {

	std::thread thread;
	HANDLE callbackRegistered = CreateEventA(NULL, FALSE, NULL, NULL);
	bool callbackRegisteredOk;
	UINT_PTR timerID;
	std::atomic_bool running;
	static constexpr UINT WM_STARTTIMER = WM_APP, WM_STOPTIMER = WM_APP + 1;

	static VOID timerProc(HWND, UINT, UINT_PTR, DWORD)
	{
		if (FSL_AIRCRAFT)
			mcduWatcher->update();
		Sound::processQueue();
	}

	void _startTimer()
	{
		timerID = SetTimer(NULL, timerID, 70, timerProc);
	}

	void _stopTimer()
	{
		KillTimer(NULL, timerID);
	}

	void _messageLoop(bool voiceControl)
	{
		if (voiceControl) {
			callbackRegisteredOk = copilot::recoResultFetcher->registerCallback();
			SetEvent(callbackRegistered);
		}
		_startTimer();
		running = true;
		MSG msg;
		while (GetMessage(&msg, NULL, 0, 0)) {
			switch (msg.message) {
				case (WM_STARTTIMER):
					_startTimer();
					break;
				case (WM_STOPTIMER):
					_stopTimer();
					break;
				default:
					break;
			}
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
		running = false;
		_stopTimer();
	}

public:

	bool start(bool voiceControl)
	{
		bool res;
		ResetEvent(callbackRegistered);
		callbackRegisteredOk = false;
		thread = std::thread(&MessageLoop::_messageLoop, this, voiceControl);
		if (voiceControl) {
			WaitForSingleObject(callbackRegistered, 10000);
			res = callbackRegisteredOk;
		}
		return res;
	}

	void stop()
	{
		if (thread.joinable()) {
			PostThreadMessage(GetThreadId(thread.native_handle()),
							  WM_QUIT, 0, 0);
			thread.join();
		}
	}

	void startTimer()
	{
		if (running) {
			PostThreadMessage(GetThreadId(thread.native_handle()),
							  WM_STARTTIMER, 0, 0);
		}
	}

	void stopTimer()
	{
		if (running) {
			PostThreadMessage(GetThreadId(thread.native_handle()),
							  WM_STOPTIMER, 0, 0);
		}
	}

} messageLoop;




namespace copilot {

	std::string appDir;

	RecoResultFetcher* recoResultFetcher = nullptr;
	std::shared_ptr<spdlog::logger> logger = nullptr;
	std::mutex FSUIPCmutex;

	double readLvar(const std::string& name)
	{
		auto val = SimInterface::readLvar(name);
		return val.has_value() ? *val : 0;
	}

	/*void shutDown()
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
	}*/

	void initLogger()
	{
		logger = std::make_shared<spdlog::logger>("Copilot");
		logger->flush_on(spdlog::level::trace);

		std::string logFilePath = appDir + "Copilot.log";
		auto fileSink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(logFilePath, 1048576 * 5, 0, true);
		fileSink->set_pattern("[%T] [%l] %v");
		logger->sinks().push_back(fileSink);
	}

	void initConsoleSink()
	{
		auto consoleSink = std::make_shared<spdlog::sinks::wincolor_stdout_sink_mt>();
		consoleSink->set_pattern("[%T] %^[Copilot]%$ %v");
		logger->sinks().push_back(consoleSink);
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

		int lineWidth = 60;
		copilot::logger->info("{:*^{}}", fmt::format(" {} {} ", "Copilot for FSLabs", COPILOT_VERSION), lineWidth);
		copilot::logger->info("");

		sol::state lua;
		lua.open_libraries();
		lua["APPDIR"] = appDir;
		lua.do_string(R"(package.path = APPDIR .. '\\?.lua')");
		auto result = lua.do_file(appDir + "copilot\\copilot\\LoadUserOptions.lua");

		if (!result.valid()) {
			sol::error err = result;
			copilot::logger->error(err.what());
		}

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

		initConsoleSink();

	}

	void onSimEvent(SimConnect::EVENT_ID event)
	{
		switch (event) {

			case SimConnect::EVENT_SIM_START:
				messageLoop.startTimer();
				break;

			case SimConnect::EVENT_EXIT:

			case SimConnect::EVENT_ABORT:
				messageLoop.stopTimer();
				break;

			default:
				break;
		}
	}

	void onFlightLoaded(bool isFslAircraft)
	{
		DWORD res = FSUIPC::connect();
		if (res == FSUIPC_ERR_OK) {
			logger->info("Connected to FSUIPC");
		} else {
			logger->error("Failed to connect to FSUIPC: {}", FSUIPC::errorString(res));
		}
		launchFSL2LuaScript();
	}

	std::unique_ptr<FSL2LuaScript> FSL2LuaScriptInstance;

	void launchFSL2LuaScript()
	{
		if (!FSL2LuaScriptInstance)
			FSL2LuaScriptInstance = std::make_unique<FSL2LuaScript>(appDir + "scripts\\autorun.lua");
		FSL2LuaScriptInstance->launchThread();

	}

	IWindowPluginSystemV440* GetWindowPluginSystem()
	{
		return PdkServices::GetWindowPluginSystem();
	}
}

std::optional<std::string> initLua(sol::this_state ts)
{
	sol::state_view lua(ts);

	messageLoop.stop();

	FSL_AIRCRAFT = lua["copilot"]["FSL_AIRCRAFT"];

	auto options = lua["copilot"]["UserOptions"];

	int log_level = options["general"]["log_level"];
	copilot::logger->set_level((spdlog::level::level_enum)log_level);

	int devNum = options["callouts"]["device_id"];
	int pmSide = options["general"]["PM_seat"];
	double volume = options["callouts"]["volume"];
	Sound::init(devNum, pmSide, volume * 0.01);

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
				 "NonPersistent", Recognizer::RulePersistenceMode::NonPersistent);

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

void DLLStart(P3D::IPdk* pPdk)
{

	SimConnect::init();

	if (Panels != NULL) 
		ImportTable.PANELSentry.fnptr = (PPANELS)Panels;
	
	if (pPdk != nullptr)
	    PdkServices::Init(pPdk);

	copilot::init();
}

void DLLStop()
{
	SetEvent(simExit);
	//shutDown();
	SimConnect::close();
	SimInterface::onSimShutdown();
}

//extern "C"
//__declspec(dllexport) int luaopen_FSLCopilot(lua_State * L)
//{
//	sol::state_view lua(L);
//	scriptStarted = true;
//
//	using logger = spdlog::logger;
//	sol::usertype<logger> LoggerType = lua.new_usertype<logger>("Logger");
//	LoggerType["trace"] = static_cast<void (logger::*)(const std::string&)>(&logger::trace);
//	LoggerType["debug"] = static_cast<void (logger::*)(const std::string&)>(&logger::debug);
//	LoggerType["info"] = static_cast<void (logger::*)(const std::string&)>(&logger::info);
//	LoggerType["warn"] = static_cast<void (logger::*)(const std::string&)>(&logger::warn);
//	LoggerType["error"] = static_cast<void (logger::*)(const std::string&)>(&logger::error);
//	LoggerType["setLevel"] = &logger::set_level;
//
//	auto copilot = lua.create_table();
//	copilot["init"] = initLua;
//	copilot["logger"] = copilot::logger;
//	copilot.push();
//	return 1;
//}