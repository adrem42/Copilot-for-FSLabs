#include "CopilotScript.h"
#include "Copilot.h"
#include "Sound.h"
#include "McduWatcher.h"
#include <functional>


void CopilotScript::initLuaState(sol::state_view lua)
{
	LuaPlugin::initLuaState(lua);
	stopBackgroundThread();

	std::string packagePath = lua["package"]["path"];

	lua["package"]["path"] = copilot::appDir + "\\Copilot\\?.lua;" + packagePath;
	lua["APPDIR"] = copilot::appDir;

	lua.safe_script(R"(require "copilot.LoadUserOptions")", sol::script_throw_on_error);

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

	bool voiceControl = options["voice_control"]["enable"] == 1;
	if (voiceControl) {
		recognizer = std::make_shared<Recognizer>();
		recoResultFetcher = std::make_shared<RecoResultFetcher>(recognizer);
	}

	std::string port = options["general"]["http_port"];
	mcduWatcher = std::make_unique<McduWatcher>(pmSide, std::stoi(port));
	auto copilot = lua["copilot"];
	copilot["recognizer"] = recognizer;
	copilot["recoResultFetcher"] = recoResultFetcher;
	copilot["mcduWatcher"] = mcduWatcher;

	using logger = spdlog::logger;
	auto LoggerType = lua.new_usertype<logger>("Logger");
	LoggerType["trace"] = static_cast<void (logger::*)(const std::string&)>(&logger::trace);
	LoggerType["debug"] = static_cast<void (logger::*)(const std::string&)>(&logger::debug);
	LoggerType["info"] = static_cast<void (logger::*)(const std::string&)>(&logger::info);
	LoggerType["warn"] = static_cast<void (logger::*)(const std::string&)>(&logger::warn);
	LoggerType["error"] = static_cast<void (logger::*)(const std::string&)>(&logger::error);
	LoggerType["setLevel"] = &logger::set_level;
	copilot["logger"] = copilot::logger;

	startBackgroundThread();
}

bool CopilotScript::updateScript(MSG* pMsg, HANDLE recoResultsEvent)
{

	switch (MsgWaitForMultipleObjects(1, &recoResultsEvent, FALSE, INFINITE, QS_ALLINPUT)) {

		case WAIT_OBJECT_0:

			lua["Event"]["fetchRecoResults"]();
			break;

		case WAIT_OBJECT_0 + 1:

			if (PeekMessage(pMsg, NULL, 0, 0, PM_REMOVE)) {
				if (pMsg->message == WM_TIMER)
					lua["copilot"]["update"]();
				TranslateMessage(pMsg);
				DispatchMessage(pMsg);
			}
			break;

		default:

			copilot::logger->error("Unexpected error. Copilot will stop.");
			return false;
	}

	return true;

}

void CopilotScript::run()
{

	LuaPlugin::run();

 	mainThreadTimerId = SetTimer(NULL, mainThreadTimerId, 30, NULL);
	MSG msg = {};
	HANDLE recoResultsEvent = recoResultFetcher ? recoResultFetcher->event() : CreateEvent(0, 0, 0, 0);

	while (true) {
		
		try {
			if (!updateScript(&msg, recoResultsEvent))
				return;
		}
		catch (sol::error& err) {
			onError(err);
		}

	}
}

void CopilotScript::onSimStart()
{
	startBackgroundThreadTimer();
}

void CopilotScript::onSimExit()
{
	stopBackgroundThreadTimer();
}

void CopilotScript::onMuteKey(bool state)
{
	if (recoResultFetcher)
		recoResultFetcher->onMuteKey(state);
}

void CopilotScript::onMessageLoopTimer()
{
	if (copilot::isFslAircraft)
		mcduWatcher->update();
	Sound::processQueue();
}

void CopilotScript::actuallyStartBackgroundThreadTimer()
{
	backgroundThreadTimerId = SetTimer(NULL, backgroundThreadTimerId, 70, NULL);
}

void CopilotScript::actuallyStopBackgroundThreadTimer()
{
	KillTimer(NULL, backgroundThreadTimerId);
}

void CopilotScript::runMessageLoop()
{
	if (recoResultFetcher) {
		try {
			recoResultFetcher->registerCallback();
		}
		catch (std::exception& ex) {
			stopThread();
			copilot::logger->error("Failed to register SAPI callback. Copilot will stop execution.");
			return;
		}
	}
	actuallyStartBackgroundThreadTimer();
	MSG msg = {};
	while (GetMessage(&msg, NULL, 0, 0)) {
		switch (msg.message) {
			case (WM_STARTTIMER):
				actuallyStartBackgroundThreadTimer();
				break;
			case (WM_STOPTIMER):
				actuallyStopBackgroundThreadTimer();
				break;
			case WM_TIMER:
				onMessageLoopTimer();
				break;
		}
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}
	actuallyStopBackgroundThreadTimer();
}

void CopilotScript::startBackgroundThread()
{
	backgroundThread = std::thread(&CopilotScript::runMessageLoop, this);
}

void CopilotScript::stopBackgroundThread()
{
	if (backgroundThread.joinable()) {
		PostThreadMessage(GetThreadId(backgroundThread.native_handle()),
						  WM_QUIT, 0, 0);
		backgroundThread.join();
	}
}

void CopilotScript::startBackgroundThreadTimer()
{
	if (backgroundThread.joinable()) {
		PostThreadMessage(GetThreadId(backgroundThread.native_handle()),
						  WM_STARTTIMER, 0, 0);
	}
}

void CopilotScript::stopBackgroundThreadTimer()
{
	if (backgroundThread.joinable()) {
		PostThreadMessage(GetThreadId(backgroundThread.native_handle()),
						  WM_STOPTIMER, 0, 0);
	}
}

CopilotScript::~CopilotScript()
{
	stopBackgroundThread();
}