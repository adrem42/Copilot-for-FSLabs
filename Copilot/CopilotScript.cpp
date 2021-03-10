#include "CopilotScript.h"
#include "Copilot.h"
#include "Sound.h"
#include "McduWatcher.h"
#include <functional>
#include <string>

class TextMenuWrapper : public std::enable_shared_from_this<TextMenuWrapper> {

public:

	static std::unordered_set <std::shared_ptr<TextMenuWrapper>> pendingMenus;
	static std::mutex pendingMenusMutex;

	std::shared_ptr<SimConnect::TextMenuEvent> menu;

	static std::shared_ptr<TextMenuWrapper> create(
		const std::string& title,
		const std::string& prompt,
		std::vector<std::string> items,
		size_t timeout,
		sol::function callback,
		CopilotScript& script
	)
	{

		static size_t currID = 0;
		const size_t callbackID = currID++;
		script.lua.registry()[sol::create_if_nil]["textMenuCallbacks"][callbackID] = callback;

		using namespace SimConnect;

		auto sp = std::shared_ptr<TextMenuWrapper>(new TextMenuWrapper(), [path = script.path, callbackID, pScript = &script](TextMenuWrapper* ptr) {
			LuaPlugin::withScript<CopilotScript>(path, [=](CopilotScript& s) {
				if (pScript != &s) return;
				s.enqueueCallback([callbackID] (sol::state_view& lua) {
					lua.registry()[sol::create_if_nil]["textMenuCallbacks"][callbackID] = sol::nil;
				});
			});
			delete ptr;
		});

		auto callbackWrapper = [callbackID, wp = std::weak_ptr<TextMenuWrapper>(sp), path = script.path, pScript = &script](
			TextMenuEvent::Result res, TextMenuEvent::MenuItem item, const std::string& str,
			std::shared_ptr<TextMenuEvent> e
			)
		{
			LuaPlugin::withScript<CopilotScript>(path, [=](CopilotScript& s) {
				if (&s != pScript) return;
				if (auto sp = wp.lock()) {
					s.enqueueCallback([=] (sol::state_view& lua) {
						{
							std::lock_guard<std::mutex> lock(pendingMenusMutex);
							pendingMenus.erase(sp);
						}
						lua.registry()["textMenuCallbacks"][callbackID](res, item + 1, str, sp);
					});
				}
			});
		};
		sp->menu = std::make_shared<TextMenuEvent>(title, prompt, items, timeout, callbackWrapper);
		return sp;
	}

	void show()
	{
		menu->show();
		std::lock_guard<std::mutex> lock(pendingMenusMutex);
		pendingMenus.insert(shared_from_this());
	}

	void cancel()
	{
		menu->cancel();
	}

};

std::unordered_set < std::shared_ptr<TextMenuWrapper>> TextMenuWrapper::pendingMenus;
std::mutex TextMenuWrapper::pendingMenusMutex;

void CopilotScript::initLuaState(sol::state_view lua)
{
	FSL2LuaScript::initLuaState(lua);
	stopBackgroundThread();

	std::string packagePath = lua["package"]["path"];

	lua["package"]["path"] = copilot::appDir + "\\Copilot\\?.lua;" + packagePath;
	lua["APPDIR"] = copilot::appDir;
	lua.registry()["asyncCallbacks"] = lua.create_table();

	sol::protected_function_result res = lua.script(R"(require "copilot.LoadUserOptions")");

	if (!res.valid())
		throw ScriptStartupError(res);

	auto options = lua["copilot"]["UserOptions"];

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
		try {
			recognizer = std::make_shared<Recognizer>();
		} 		catch (std::exception& ex) {
			throw ScriptStartupError("Failed to create Recognizer.");
		}
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
	LoggerType["setLevel"] = [](spdlog::logger& _, unsigned int level) {
		copilot::consoleSink->set_level(static_cast<spdlog::level::level_enum>(level));
	};
	copilot["logger"] = copilot::logger;

	{
		using namespace SimConnect;
		auto TextMenuEventType = lua.new_usertype<TextMenuWrapper>("TextMenu", sol::factories([=](
			const std::string& title,
			const std::string& prompt,
			std::vector<std::string> items,
			size_t timeout,
			sol::function callback
			) {
			return TextMenuWrapper::create(title, prompt, items, timeout, callback, *this);
		}));
		TextMenuEventType["show"] = &TextMenuWrapper::show;
		TextMenuEventType["cancel"] = &TextMenuWrapper::cancel;
	}

	lua["startUpdating"] = [this] {shouldRun = true; };

	startBackgroundThread();
}

bool CopilotScript::updateScript(MSG* pMsg, Events& events)
{
	auto res = MsgWaitForMultipleObjects(events.numEvents, events.events, FALSE, INFINITE, QS_ALLINPUT);

	if (res == WAIT_OBJECT_0 + events.numEvents) {

		if (PeekMessage(pMsg, NULL, 0, 0, PM_REMOVE)) {
			if (pMsg->message == WM_TIMER) {
				sol::protected_function f = lua["copilot"]["update"];
				sol::protected_function_result res = f();
				if (!res.valid()) onError(res);
			}
			TranslateMessage(pMsg);
			DispatchMessage(pMsg);
		}

	} else if (res == WAIT_OBJECT_0 + events.EVENT_RECO_EVENT) {

		sol::protected_function f = lua["Event"]["fetchRecoResults"];
		sol::protected_function_result res = f();
		if (!res.valid()) onError(res);

	} else if (res == WAIT_OBJECT_0 + events.EVENT_LUA_CALLBACK) {

		std::unique_lock<std::mutex> lock(luaCallbackQueueMutex);
		std::queue<LuaCallback> callbacks = luaCallbacks;
		luaCallbacks = std::queue<LuaCallback>();
		lock.unlock();

		while (callbacks.size()) {
			auto& callback = callbacks.front();
			callback(lua);
			callbacks.pop();
		}

	} else if (res == WAIT_OBJECT_0 + events.SHUTDOWN_EVENT) {

		return false;

	} else if (res < WAIT_OBJECT_0 + events.EVENT_RECO_EVENT) {

		FSL2LuaScript::onEvent(events, res);

	} else {

		copilot::logger->error("Unexpected error. Copilot will stop.");
		return false;
	}

	return true;

}

CopilotScript::Events CopilotScript::createEvents()
{
	auto parentEvents = FSL2LuaScript::createEvents();

	size_t numEvents = parentEvents.numEvents + 2;

	HANDLE* events = new HANDLE[numEvents]();

	for (size_t i = 0; i < parentEvents.numEvents; ++i) {
		events[i] = parentEvents.events[i];
	}

	CopilotScript::Events e = { parentEvents };

	e.EVENT_RECO_EVENT = numEvents - 1;
	e.EVENT_LUA_CALLBACK = numEvents - 2;

	e.events = events;
	e.numEvents = numEvents;

	events[e.EVENT_RECO_EVENT] = recoResultFetcher ? recoResultFetcher->event() : CreateEvent(0, 0, 0, 0);
	events[e.EVENT_LUA_CALLBACK] = luaCallbackEvent;

	return e;
}

void CopilotScript::run()
{

	LuaPlugin::run();

	if (!shouldRun) return;

	mainThreadTimerId = SetTimer(NULL, mainThreadTimerId, 30, NULL);
	MSG msg = {};

	auto events = createEvents();

	while (true) {
		if (!updateScript(&msg, events))
			return;
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

void CopilotScript::enqueueCallback(LuaCallback callback)
{
	std::lock_guard<std::mutex> lock(luaCallbackQueueMutex);
	luaCallbacks.push(callback);
	SetEvent(luaCallbackEvent);
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
		} 		catch (std::exception& ex) {
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
	std::lock_guard<std::mutex> lock(TextMenuWrapper::pendingMenusMutex);
	TextMenuWrapper::pendingMenus = std::unordered_set<std::shared_ptr<TextMenuWrapper>>();
	stopBackgroundThread();
}