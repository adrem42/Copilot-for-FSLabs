#define _CRT_SECURE_NO_WARNINGS 1
#define _SILENCE_ALL_CXX17_DEPRECATION_WARNINGS 1
#define NOMINMAX
#include "../lua/src/lua.hpp"
#include <sol/sol.hpp>
#include <Windows.h>
#include <thread>
#include <mutex>
#include <chrono>
#include <SimConnect.h>
#include <gauges.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <regex>

#include "LogReader.h"
#include "DirectoryWatcher.h"
#include "Copilot.h"
#include "Sound.h"
#include "Recognizer.h"
#include "McduWatcher.h"
#include "versioninfo.h"

using namespace std::literals::chrono_literals;

Recognizer* recognizer = nullptr;
McduWatcher* mcduWatcher = nullptr;

std::thread copilotInitThread, luaInitThread;
std::atomic_bool scriptStarted = false;
std::wstring appDir, FSUIPC_DIR;
int fsuipcVersion;
int numGreetings = 0;

std::string getGreeting()
{
	std::string greeting = "Greeting" + std::to_string(numGreetings);
	return greeting;
}

std::string makeNextGreeting()
{
	numGreetings++;
	return getGreeting();
}

HANDLE simExit = CreateEventA(NULL, TRUE, FALSE, NULL);


std::unique_ptr<LogReader> logReader;

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

	std::string fsuipcScriptHandle;

	static MessageLoop* _this;

	void checkFsuipcLogForErrors()
	{
		while (true) {
			std::string line = logReader->nextLine();
			if (line == "")
				return;
			size_t pos = line.find(fsuipcScriptHandle);
			if (pos != std::string::npos) {
				std::string err = " LUA Error";
				std::string sub = line.substr(pos + fsuipcScriptHandle.length(), err.length());
				if (sub == err)
					copilot::logger->error(line.substr(pos + fsuipcScriptHandle.length() + 1));
			}
		}
	}

	bool findScriptHandleInFsuipcLog()
	{
		if (fsuipcScriptHandle != "")
			return true;
		while (true) {
			std::string line = logReader->nextLine();
			if (line == "") 
				return false;
			if (line.find(getGreeting()) != std::string::npos) {
				static std::regex regex(R"(^\s*\d+\s*(LUA\.\d+:))");
				std::smatch sm;
				if (std::regex_search(line, sm, regex)) {
					fsuipcScriptHandle = sm[1];
					return true;
				}
			}
		}
	}

	void readFsuipcLog()
	{
		if (findScriptHandleInFsuipcLog())
			checkFsuipcLogForErrors();
	}

	static VOID timerProc(HWND, UINT, UINT_PTR, DWORD)
	{
		mcduWatcher->update();
		Sound::processQueue();
		if (_this) 
			_this->readFsuipcLog();
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
		_this = this;

		fsuipcScriptHandle = "";

		if (voiceControl) {
			callbackRegisteredOk = copilot::recoResultFetcher->registerCallback();
			SetEvent(callbackRegistered);
		}
		_startTimer();
		running = true;
		MSG msg = {};

		std::unique_ptr<DirectoryWatcher> watcher;
		HANDLE watcherEvent;

		std::wstring logFileName = std::to_wstring(fsuipcVersion) + L".log";

		auto makeLogReader = [&] {
			std::wstring path = FSUIPC_DIR + L"\\FSUIPC" + logFileName;
			logReader = std::make_unique<LogReader>(path);
		};

		try {
			watcher = std::make_unique<DirectoryWatcher>(FSUIPC_DIR, logFileName);
			watcherEvent = watcher->next();
			makeLogReader();
		} catch (InvalidHandleException & ex) {
			watcher = nullptr;
			logReader = nullptr;
			copilot::logger->error("Failed to open file {}, error code: {}", std::string(ex.path.begin(), ex.path.end()), ex.errorCode);
		}

		while (running) {

			switch (MsgWaitForMultipleObjects(1, &watcherEvent, FALSE, INFINITE, QS_ALLINPUT))
			{

				case WAIT_OBJECT_0 : 
					if (watcher->getInfo().Action == FILE_ACTION_ADDED) {
						readFsuipcLog();
						makeLogReader();
					}
					watcherEvent = watcher->next();
					break;

				case WAIT_OBJECT_0 + 1:
					while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {

						switch (msg.message) {

							case WM_STARTTIMER:
								_startTimer();
								break;

							case WM_STOPTIMER:
								_stopTimer();
								break;

							case WM_QUIT:
								running = false;
								break;

							default:
								break;
						}
						TranslateMessage(&msg);
						DispatchMessage(&msg);
					}
					break;
				default:
					break;
			}
		}

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

MessageLoop* MessageLoop::_this = nullptr;

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
		luaInitThread = std::thread([] {
			if (WaitForSingleObject(simExit, 30000) == WAIT_OBJECT_0) return;
			while (!scriptStarted) {
				startLuaThread();
				if (WaitForSingleObject(simExit, 5000) == WAIT_OBJECT_0) return;
			};
		});
	}

	void init()
	{

		std::string logName = "FSLabs Copilot";
#ifdef DEBUG
		logName += "(debug)";
#endif
		copilot::logger = std::make_shared<spdlog::logger>(logName);
		copilot::logger->flush_on(spdlog::level::trace);

		while (!connectToFSUIPC()) {
			if (WaitForSingleObject(simExit, 2000) == WAIT_OBJECT_0) return;
		}

		wchar_t lpFilename[MAX_PATH];
		HMODULE hMod = GetModuleHandle(L"FSUIPC5");
		if (!hMod) {
			hMod = GetModuleHandle(L"FSUIPC6");
			fsuipcVersion = 6;
		} else {
			fsuipcVersion = 5;
		}
		GetModuleFileName(hMod, lpFilename, MAX_PATH);
		FSUIPC_DIR = std::regex_replace(lpFilename, std::wregex(L"FSUIPC\\d.dll", std::regex_constants::icase), L"");
		appDir = FSUIPC_DIR + L"FSLabs Copilot\\";

		bool appDirExists = GetFileAttributes(appDir.c_str()) != INVALID_FILE_ATTRIBUTES;

		if (appDirExists) {
			std::wstring logFileName = appDir + L"\\Copilot.log";
#ifdef DEBUG
			logFileName = appDir + L"\\Copilot(debug).log";
#endif
			auto fileSink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(std::string(logFileName.begin(), logFileName.end()), 1048576 * 5, 0, true);
			fileSink->set_pattern("[%T] [%l] %v");

			copilot::logger->sinks().push_back(fileSink);
		}

		int lineWidth = 60;
		copilot::logger->info("{:*^{}}", fmt::format(" {} {} ", "Copilot for FSLabs", COPILOT_VERSION), lineWidth);
		copilot::logger->info("");

		if (appDirExists) {
			sol::state lua;
			lua.open_libraries();
			lua["FSUIPC_DIR"] = FSUIPC_DIR;
			lua["APPDIR"] = appDir;
			lua.do_string(R"(package.path = FSUIPC_DIR .. '\\?.lua')");
			std::string script = std::string(appDir.begin(), appDir.end());
			script += "\\copilot\\UserOptions.lua";
			auto result = lua.do_file(script);
			if (!result.valid()) {
				sol::error err = result;
				copilot::logger->error(err.what());
			}
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

		if (!appDirExists) {
			copilot::logger->error("Folder {} doesn't exist!", std::string(appDir.begin(), appDir.end()));
		}

	}

	void onSimStart()
	{
		simConnect = std::make_unique<SimConnect>();
		simConnect->init();

		if (Panels != NULL) {
			ImportTable.PANELSentry.fnptr = (PPANELS)Panels;
		}

		copilotInitThread = std::thread(copilot::init);
	}

	void onSimExit()
	{
		SetEvent(simExit);
		if (copilotInitThread.joinable())
			copilotInitThread.join();
		if (luaInitThread.joinable())
			luaInitThread.join();
		shutDown();
		simConnect->close();
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
	lua["print"](makeNextGreeting());
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
