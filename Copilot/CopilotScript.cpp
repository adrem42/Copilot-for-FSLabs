/////////
// 
// Class for displaying a SimConnect text menu and handling the result.
// 
// SimConnect maintains a queue of menus from all of its clients.<br><br>
// When the user closes the window without selecting an item, SimConnect doesn't emit any event, so you have to set a timeout if you want to handle this possibility.<br><br>
// When you call `TextMenu:show`, the object will be kept alive until a result is received.<br><br>
// 
// @classmod TextMenu

#include "CopilotScript.h"
#include "Copilot.h"
#include "Sound.h"
#include "McduWatcher.h"
#include <functional>
#include <string>
#include <filesystem>
#include "SimInterface.h"

std::unordered_map< P3D::MOUSE_CLICK_TYPE, std::string> clickTypes{
	{P3D::MOUSE_CLICK_LEFT_SINGLE,		"leftPress"},
	{P3D::MOUSE_CLICK_LEFT_RELEASE,		"leftRelease"},
	{P3D::MOUSE_CLICK_RIGHT_SINGLE,		"rightPress"},
	{P3D::MOUSE_CLICK_RIGHT_RELEASE,	"rightRelease"},
	{P3D::MOUSE_CLICK_WHEEL_UP,			"wheelUp"},
	{P3D::MOUSE_CLICK_WHEEL_DOWN,		"wheelDown"},
};

void CopilotScript::MouseRectListenerCallback::MouseRectListenerProc(UINT rect, P3D::MOUSE_CLICK_TYPE clickType)
{
	if (!SimInterface::firingMouseMacro()) {
		withScript<CopilotScript>(pScript, [=](CopilotScript& script) {
			script.enqueueCallback([=, &script](sol::state_view& lua) {
				auto it = clickTypes.find(clickType);
				if (it != clickTypes.end())
					script.mouseMacroEvent["trigger"](script.mouseMacroEvent, rect, it->second);
			});
		});
	}
}

/*** @type TextMenu */
class LuaTextMenu : public SimConnect::TextMenuEvent {

	CopilotScript* pScript;
	const CopilotScript::RegisterID callbackID;
	CopilotScript::RegisterID eventID;

public:

	/***
	* Constructor
	* @static
	* @function new
	* @string title
	* @string prompt Can be an empty string
	* @tparam table items Array of strings
	* @int timeout Timeout in seconds. 0 means infinite.
	* @tparam function callback The function that's going to handle the menu events, with the following parameters:
	* 
	*> 1. The result: TextMenuResult.OK, TextMenuResult.Replaced, TextMenuResult.Timeout, TextMenuResult.Removed
	* 
	*> 2. The array index of the item
	* 
	*> 3. The item itself (string)
	* 
	*> 4. The menu
	*/
	LuaTextMenu(
		const std::string& title,
		const std::string& prompt,
		std::vector<std::string> items,
		size_t timeout,
		sol::function callback,
		CopilotScript& script
	) : LuaTextMenu(timeout, callback, script)
	{
		this->title = title;
		this->prompt = prompt;
		this->items = items;
	}

	/***
	* Constructor
	* @static
	* @function new
	* @string title
	* @string prompt Can be an empty string
	* @tparam table items Array of strings
	* @tparam function callback Same as above
	*/

	/***
	* Constructor
	* @static
	* @function new
	* @int timeout Timeout in seconds. 0 means infinite.
	* @tparam function callback Same as above
	*/
	LuaTextMenu(size_t timeout, sol::function callback, CopilotScript& script)
		: pScript(&script), callbackID(script.registerLuaObject(callback))
	{
	
		this->timeout = timeout;
		auto& lua = script.lua;
		sol::table event = lua["Event"]["new"](lua["Event"]);
		eventID = script.registerLuaObject(event);
		using namespace SimConnect;
		this->callback = [=, &script](Result res, MenuItem item, const std::string& str, std::shared_ptr<TextMenuEvent> e)
		{
			LuaPlugin::withScript<CopilotScript>(&script, [=](CopilotScript& s) {
				s.enqueueCallback([=, &s](sol::state_view& lua) {
					auto f = s.getRegisteredObject<sol::protected_function>(callbackID);
					auto event = s.getRegisteredObject<sol::table>(eventID);
					sol::object luaItem(sol::nil);
					if (item != -1)
						luaItem = sol::make_object(lua.lua_state(), item + 1);
					lua.registry()[sol::light(this)] = sol::nil;
					s.callProtectedFunction(f, res, luaItem, str, std::static_pointer_cast<LuaTextMenu>(shared_from_this()));
					event["trigger"](event, res, luaItem, str, std::static_pointer_cast<LuaTextMenu>(shared_from_this()));
				});
			});
		};
	}

	sol::table getEvent()
	{
		return pScript->getRegisteredObject<sol::table>(eventID);
	}

	/***
	* Constructor
	* @static
	* @function new
	* @tparam function callback Same as above
	*/

	/***
	* @function show
	*/
	void show(sol::this_state s)
	{
		sol::state_view lua(s);
		lua.registry()[sol::light(this)] = shared_from_this();
		TextMenuEvent::show();
	}

	/***
	* @function setTitle
	* @string title
	* @return self
	*/
	LuaTextMenu& setTitle(const std::string& title)
	{
		this->title = title;
		invalidateBuffer();
		return *this;
	}


	/***
	* @function setItems
	* @tparam table items Array of strings
	* @return self
	*/
	LuaTextMenu& setItems(std::vector<std::string> items)
	{
		this->items = items;
		invalidateBuffer();
		return *this;
	}

	LuaTextMenu& setTimeout(size_t timeout)
	{
		this->timeout = timeout;
		return *this;
	}

	/***
	* @function setPrompt
	* @string prompt
	* @return self
	*/
	LuaTextMenu& setPrompt(const std::string& prompt)
	{
		this->prompt = prompt;
		invalidateBuffer();
		return *this;
	}

	/***
	* @function setItem
	* @int index The position of the item
	* @string item
	* @return self
	*/
	LuaTextMenu& setItem(MenuItem idx, const std::string& item)
	{
		items.resize(static_cast<size_t>(idx) + 1);
		items[idx] = item;
		invalidateBuffer();
		return *this;
	}

	LuaTextMenu& setMenu(const std::string& title, const std::string& prompt, std::vector<std::string> items)
	{
		SimConnect::TextMenuEvent::setMenu(title, prompt, items);
		return *this;
	}

	/***
	* @function cancel
	*/

	~LuaTextMenu()
	{
		pScript->unregisterLuaObject(callbackID);
		pScript->unregisterLuaObject(eventID);
	}

};

void CopilotScript::initLuaState(sol::state_view lua)
{
	FSL2LuaScript::initLuaState(lua);
	stopBackgroundThread();

	std::string packagePath = lua["package"]["path"];

	lua["package"]["path"] = copilot::appDir + "\\Copilot\\?.lua;" + packagePath;
	lua["APPDIR"] = copilot::appDir;
	lua.registry()["asyncCallbacks"] = lua.create_table();

	sol::protected_function_result res = lua.script(R"(require "copilot.LoadCopilotOptions")");

	if (!res.valid())
		throw ScriptStartupError(res);

	auto options = lua["copilot"]["UserOptions"];

	int devNum = options["callouts"]["device_id"];
	int pmSide = options["general"]["PM_seat"];
	double volume = options["callouts"]["volume"];

	if (SUCCEEDED(CoInitialize(NULL))) {
		HRESULT hr = CoCreateInstance(CLSID_SpVoice, NULL, CLSCTX_ALL, IID_ISpVoice, reinterpret_cast<void**>(&voice));
	}

	Sound::init(devNum, pmSide, volume * 0.01, voice);

	auto copilot = lua["copilot"];

	copilot["onVolKnobPosChanged"] = Sound::onVolumeChanged;

	copilot["speak"] = [&](const std::wstring& phrase, std::optional<size_t> delay) {
		if (delay == -1) {
			voice->Speak(phrase.c_str(), 0, NULL);
		} else {
			std::lock_guard<std::mutex> lock(ttsQueueMutex);
			ttsQueue.push(std::make_pair(elapsedTime() + delay.value_or(0), phrase));
		}
	};

	copilot["mouseMacroEvent"] = [&](sol::this_state ts) {
		if (!mouseMacroCallback) {
			mouseMacroCallback = std::make_unique<MouseRectListenerCallback>(this);
			copilot::GetWindowPluginSystem()->RegisterMouseRectListenerCallback(mouseMacroCallback.get());
			sol::state_view lua(ts);
			mouseMacroEvent = lua["Event"]["new"](lua["Event"]);
			mouseMacroEvent["logMsg"] = lua["Event"]["NOLOGMSG"];
		}
		return mouseMacroEvent;
	};

	mcduWatcherLua.open_libraries();
	mcduWatcherLua["print"] = [this](sol::variadic_args va) {
		std::string str;
		for (size_t i = 0; i < va.size(); i++) {
			auto v = va[i];
			str += this->lua["tostring"](v.get<sol::object>());
			if (i != va.size() - 1) {
				str += " ";
			}
		}
		copilot::logger->info(str);
	};

	mcduWatcherToArray = mcduWatcherLua.script(R"(
		local colors = {
			["1"] = "cyan",
			["2"] = "grey",
			["4"] = "green",
			["5"] = "magenta",
			["6"] = "amber",
			["7"] = "white",
		}
				
		return function(response)
			local display = {}
			for unitArray in response:gmatch("%[(.-)%]") do
				local unit = {}
				if unitArray:find(",") then
					local char, color, isBold = unitArray:match('(%d+),(%d),(%d)')
					unit.char = string.char(char)
					unit.color = colors[color] or tonumber(color)
					unit.isBold = tonumber(isBold) == 0
				end
				display[#display + 1] = unit
			end
			return display
		end
	)");

	mcduWatcherLua["getVar"] = [this](const std::string& key) {
		return currMcduWatcherVarStore->getVar(key);
	};
	mcduWatcherLua["setVar"] = [this](const std::string& key, McduWatcher::LuaVar value) {
		 currMcduWatcherVarStore->setVar(key, value);
	};
	mcduWatcherLua["clearVar"] = [this](const std::string& key) {
		currMcduWatcherVarStore->clearVar(key);
	};

	copilot["addMcduCallback"] = [this](const std::string& path) {
		if (backgroundThread.joinable())
			throw "You must call addMcduCallback during the initial setup";
		sol::protected_function_result pfr = mcduWatcherLua.safe_script_file(path);
		if (!pfr.valid()) {
			throw ScriptStartupError(pfr);
		}
		if (pfr.get_type() != sol::type::function) {
			throw ScriptStartupError(path + " needs to return a function");
		}
		McduWatcherLuaCallback& callback = mcduWatcherLuaCallbacks.emplace_back(McduWatcherLuaCallback {pfr.get<sol::protected_function>()});
		auto getVar = [varStore = callback.varStore] (const std::string& key) {
			return varStore->getVar(key);
		};
		auto clearVar = [varStore = callback.varStore](const std::string& key) {
			varStore->clearVar(key);
		};
		return std::make_tuple(std::move(getVar), std::move(clearVar));
	};

	auto RecoResultFetcherType = lua.new_usertype<RecoResultFetcher>("RecoResultFetcher");
	RecoResultFetcherType["getResults"] = &RecoResultFetcher::getResults;

	auto SoundType = lua.new_usertype<Sound>("Sound",
											 sol::constructors<Sound(const std::string&, int, double),
											 Sound(const std::string&, int),
											 Sound(const std::string&)>());
	SoundType["play"] = sol::overload(static_cast<void (Sound::*)(int)>(&Sound::enqueue),
									  static_cast<void (Sound::*)()>(&Sound::enqueue));



	auto McduWatcherType = lua.new_usertype<McduWatcher>("McduWatcher");
	McduWatcherType["getVar"] = &McduWatcher::getVar;
	McduWatcherType["clearVar"] = &McduWatcher::clearVar;
	
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
	recognizer->makeLuaBindings(lua);
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

	auto factory1 = [this](
		const std::string& title,
		const std::string& prompt,
		std::vector<std::string> items,
		size_t timeout,
		sol::function callback
	) {
		return std::make_shared<LuaTextMenu>(title, prompt, items, timeout, callback, *this);
	};

	auto factory2 = [this](
		const std::string& title,
		const std::string& prompt,
		std::vector<std::string> items,
		sol::function callback
	) {
		return std::make_shared<LuaTextMenu>(title, prompt, items, 0, callback, *this);
	};

	auto factory3 = [this](size_t timeout, sol::function callback) {
		return std::make_shared<LuaTextMenu>(timeout, callback, *this);
	};

	auto factory4 = [this](sol::function callback) {
		return std::make_shared<LuaTextMenu>(0, callback, *this);
	};

	auto factory5 = [this](sol::this_state ts) {
		auto lua = sol::state_view(ts);
		sol::function f = lua["copilot"]["__dummy"];
		return std::make_shared<LuaTextMenu>(0, f, *this);
	};

	auto TextMenuType = lua.new_usertype<LuaTextMenu>("TextMenu", sol::factories(factory1, factory2, factory3, factory4, factory5));
	TextMenuType["show"] = &LuaTextMenu::show;
	TextMenuType["cancel"] = &LuaTextMenu::cancel;
	TextMenuType["setMenu"] = &LuaTextMenu::setMenu;
	TextMenuType["setItems"] = &LuaTextMenu::setItems;
	TextMenuType["setItem"] = [](LuaTextMenu& menu, LuaTextMenu::MenuItem idx, const std::string& item) -> LuaTextMenu& {
		return menu.setItem(idx - 1, item);
	};
	TextMenuType["setTitle"] = &LuaTextMenu::setTitle;
	TextMenuType["setPrompt"] = &LuaTextMenu::setPrompt;
	TextMenuType["setTimeout"] = &LuaTextMenu::setTimeout;
	TextMenuType["event"] = sol::readonly_property([](LuaTextMenu& m) {
		return m.getEvent();
	});

	lua.new_enum<LuaTextMenu::Result>(
		"TextMenuResult",
		{
			{"OK", LuaTextMenu::Result::OK},
			{"Removed", LuaTextMenu::Result::Removed},
			{"Replaced", LuaTextMenu::Result::Replaced},
			{"Timeout", LuaTextMenu::Result::Timeout}
		}
	);

	lua.registry()[KEY_OBJECT_REGISTRY] = lua.create_table();

	lua["startUpdating"] = [this] {shouldRun = true; };

	callbackRunner = std::make_unique<CallbackRunner>(
		lua,
		[this] { nextUpdate = elapsedTime(); },
		[this] { return elapsedTime(); },
		[this] (sol::error& err) { LuaPlugin::onError(err); }
	);

	callbackRunner->makeLuaBindings(lua, "copilot");

	
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
	
	startBackgroundThread();

	auto events = createEvents();

	nextUpdate = elapsedTime();

	while (true) {

		size_t timeout = 0;

		if (nextUpdate == INFINITE) {
			timeout = INFINITE;
		} else {
			size_t elapsed = elapsedTime();
			if (nextUpdate > elapsed) 
				timeout = nextUpdate - elapsed;
		}

		Sleep(14);

		auto res = WaitForMultipleObjects(events.numEvents, events.events, FALSE, timeout);

		if (res == WAIT_TIMEOUT) {

			auto _nextUpdate = callbackRunner->update();
			nextUpdate = _nextUpdate == CallbackRunner::INDEFINITE ? INFINITE : _nextUpdate;

		} else {

			if (res == WAIT_OBJECT_0 + events.EVENT_RECO_EVENT) {

				sol::protected_function trigger = lua["Event"]["trigger"];
				sol::table voiceCommands = lua["Event"]["voiceCommands"];

				for (const auto& result : recoResultFetcher->getResults()) {
					sol::table voiceCommand = voiceCommands[result.ruleID];
					callProtectedFunction(trigger, voiceCommand, std::move(result));
				}

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

				return;

			} else if (res < WAIT_OBJECT_0 + events.EVENT_RECO_EVENT) {

				FSL2LuaScript::onEvent(events, res);

			}
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

void CopilotScript::enqueueCallback(LuaCallback callback)
{
	std::lock_guard<std::mutex> lock(luaCallbackQueueMutex);
	luaCallbacks.push(callback);
	SetEvent(luaCallbackEvent);
}

void CopilotScript::onMessageLoopTimer()
{
	if (copilot::isFslAircraft) {
		if (mcduWatcherLuaCallbacks.size()) {
			mcduWatcher->update([this](const std::string& pf, const std::string& pm, int pmSide) {
				sol::table data = mcduWatcherLua.create_table();
				sol::table pfDisplay = mcduWatcherToArray(pf);
				sol::table pmDisplay = mcduWatcherToArray(pm);
				pfDisplay["str"] = MCDU::getStringFromRaw(pf);
				pmDisplay["str"] = MCDU::getStringFromRaw(pm);
				data["PM"] = pmDisplay;
				data["PF"] = pfDisplay;
				if (pmSide == 1) {
					data["pmSide"] = "CPT";
					data["CPT"] = pmDisplay;
					data["FO"] = pfDisplay;
				} else {
					data["pmSide"] = "FO";
					data["CPT"] = pfDisplay;
					data["FO"] = pmDisplay;
				}
				for (auto& callback : mcduWatcherLuaCallbacks) {
					currMcduWatcherVarStore = callback.varStore.get();
					callProtectedFunction(callback.callback, data);
				}
			});
		} else {
			mcduWatcher->update(nullptr);
		}
	}
	Sound::update(copilot::isFslAircraft);
	std::lock_guard<std::mutex> lock(ttsQueueMutex);
	if (ttsQueue.size() && elapsedTime() >= ttsQueue.front().first) {
		HRESULT hr = voice->Speak(ttsQueue.front().second.c_str(), SPF_ASYNC, NULL);
		ttsQueue.pop();
	}
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
	//CoInitialize(NULL);
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

void CopilotScript::unregisterLuaObject(RegisterID id)
{
	auto unregister = [this, id] {
		lua.registry()[KEY_OBJECT_REGISTRY][id] = sol::nil;
	};
	if (GetCurrentThreadId() == luaThreadId) {
		unregister();
	} else {
		enqueueCallback(std::bind(unregister));
	}
}

CopilotScript::~CopilotScript()
{
	if (mouseMacroCallback)
		copilot::GetWindowPluginSystem()->UnRegisterMouseRectListenerCallback(mouseMacroCallback.get());
	if (voice)
		voice->Release();
	CoUninitialize();
	stopBackgroundThread();
	stopThread();
	
}