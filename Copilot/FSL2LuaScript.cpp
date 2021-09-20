/////////
// 
// Class for displaying a SimConnect text menu and handling the result.
// 
// SimConnect maintains a queue of menus from all of its clients.<br><br>
// When the user closes the window without selecting an item, SimConnect doesn't emit any event, so you have to set a timeout if you want to handle this possibility.<br><br>
// When you call `TextMenu:show`, the object will be kept alive until a result is received.<br><br>
// 
// @classmod TextMenu

#include "FSL2LuaScript.h"
#include "JoystickManager.h"
#include "Copilot.h"
#include "CallbackRunner.h"
#include "SimInterface.h"
#include "SystemEventLuaManager.h"

std::unordered_map< P3D::MOUSE_CLICK_TYPE, std::string> clickTypes{
	{P3D::MOUSE_CLICK_LEFT_SINGLE,		"leftPress"},
	{P3D::MOUSE_CLICK_LEFT_RELEASE,		"leftRelease"},
	{P3D::MOUSE_CLICK_RIGHT_SINGLE,		"rightPress"},
	{P3D::MOUSE_CLICK_RIGHT_RELEASE,	"rightRelease"},
	{P3D::MOUSE_CLICK_WHEEL_UP,			"wheelUp"},
	{P3D::MOUSE_CLICK_WHEEL_DOWN,		"wheelDown"},
};

void FSL2LuaScript::MouseRectListenerCallback::MouseRectListenerProc(UINT rect, P3D::MOUSE_CLICK_TYPE clickType)
{
	if (!SimInterface::firingMouseMacro()) {
		withScript<FSL2LuaScript>(scriptID, [=](FSL2LuaScript& script) {
			script.enqueueCallback([=, &script](sol::state_view& lua) {
				auto it = clickTypes.find(clickType);
				if (it != clickTypes.end()) {
					sol::protected_function trigger = lua["Event"]["trigger"];
					script.callProtectedFunction(trigger, script.mouseMacroEvent, rect, it->second);
				}
			});
		});
	}
}


using namespace SimConnect;

class LuaNamedSimConnectEvent  {

	const size_t scriptID;
	int eventID;
	static constexpr const char* REGISTRY_KEY = "SIMCONNECT_EVENTS";

	static sol::table getLuaEvent(sol::state_view& lua, LuaNamedSimConnectEvent& e)
	{
		return lua.registry().raw_get<sol::table>(e.eventID);
	}

public:

	std::shared_ptr<NamedSimConnectEvent> event;
	SimConnectEvent::Callback cb;
	size_t callbackID = -1;

	LuaNamedSimConnectEvent(size_t scriptID, const std::string& name, SimConnectEvent::Callback cb)
		:scriptID(scriptID)
	{
		event = getNamedEvent(name);
		this->cb = cb;
	}

	virtual ~LuaNamedSimConnectEvent()
	{
		event->removeCallback(callbackID);
		LuaPlugin::withScript<FSL2LuaScript>(scriptID, [=](FSL2LuaScript& s) {
			s.enqueueCallback([=, &s](sol::state_view& lua) {
				luaL_unref(lua.lua_state(), LUA_REGISTRYINDEX, eventID);
			});
		});
	}

	static void makeLuaBindings(sol::state_view& lua, size_t scriptID)
	{
		lua.registry()[REGISTRY_KEY] = lua.create_table();

		auto LuaType = lua.new_usertype<LuaNamedSimConnectEvent>("SimConnectEvent");

		LuaType["transmit"] = [](LuaNamedSimConnectEvent& e, sol::optional<DWORD> param) {
			e.event->transmit(param.value_or(0));
		};
		LuaType["subscribe"] = [](LuaNamedSimConnectEvent& e) {
			e.callbackID = e.event->addCallback(e.cb);
		};
		LuaType["unsubscribe"] = [](LuaNamedSimConnectEvent& e) {
			e.event->removeCallback(e.callbackID);
		};

		LuaType["event"] = sol::readonly_property([](LuaNamedSimConnectEvent& e, sol::this_state ts) -> sol::table {
			sol::state_view lua(ts);
			return getLuaEvent(lua, e);
		});

		lua["copilot"]["simConnectEvent"] = [scriptID](sol::this_state ts, const std::string& name) {

			sol::state_view lua(ts);
			sol::object maybeEvent = lua.registry()[REGISTRY_KEY][name];
			if (maybeEvent.is<std::shared_ptr<LuaNamedSimConnectEvent>>()) {
				return maybeEvent.as<std::shared_ptr<LuaNamedSimConnectEvent>>();
			}

			auto callback = [scriptID, name](DWORD data) {
				LuaPlugin::withScript<FSL2LuaScript>(scriptID, [=](FSL2LuaScript& s) {
					s.enqueueCallback([=, &s](sol::state_view& lua) {
						sol::table regT = lua.registry()[REGISTRY_KEY];
						auto& event = regT.get<std::shared_ptr<LuaNamedSimConnectEvent>>(name);
						auto luaEvent = getLuaEvent(lua, *event);
						sol::protected_function trigger = lua["Event"]["trigger"];
						s.callProtectedFunction(trigger, luaEvent, name, data);
					});
				});
			};

			auto event = std::make_shared<LuaNamedSimConnectEvent>(scriptID, name, callback);
			lua.registry()[REGISTRY_KEY][name] = event;

			sol::table luaEvent = lua["Event"]["new"](lua["Event"]);
			sol::stack::push(lua.lua_state(), luaEvent);
			event->eventID = luaL_ref(lua.lua_state(), LUA_REGISTRYINDEX);
			return event;
		};
	}
};

/*** @type TextMenu */
class LuaTextMenu : public SimConnect::TextMenuEvent {

	const size_t scriptID;
	int callbackID, eventID;

public:

	static void makeLuaBindings(sol::state_view& lua, size_t scriptID)
	{

		auto factory1 = [scriptID](
			sol::this_state ts,
			const std::string& title,
			const std::string& prompt,
			std::vector<std::string> items,
			size_t timeout,
			sol::function callback) {
			sol::state_view lua(ts);
			return std::make_shared<LuaTextMenu>(title, prompt, items, timeout, callback, lua, scriptID);
		};

		auto factory2 = [scriptID](
			sol::this_state ts,
			const std::string& title,
			const std::string& prompt,
			std::vector<std::string> items,
			sol::function callback) {
			sol::state_view lua(ts);
			return std::make_shared<LuaTextMenu>(title, prompt, items, 0, callback, lua, scriptID);
		};

		auto factory3 = [scriptID](sol::this_state ts, size_t timeout, sol::function callback) {
			sol::state_view lua(ts);
			return std::make_shared<LuaTextMenu>(timeout, callback, lua, scriptID);
		};

		auto factory4 = [scriptID](sol::this_state ts, sol::function callback) {
			sol::state_view lua(ts);
			return std::make_shared<LuaTextMenu>(0, callback, lua, scriptID);
		};

		auto factory5 = [scriptID](sol::this_state ts) {
			auto lua = sol::state_view(ts);
			sol::function f = lua["copilot"]["__dummy"];
			return std::make_shared<LuaTextMenu>(0, f, lua, scriptID);
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
		TextMenuType["event"] = sol::readonly_property([](LuaTextMenu& m, sol::this_state ts) {
			return m.getEvent(ts);
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
	}

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
		sol::state_view& lua,
		size_t scriptID
	) : LuaTextMenu(timeout, callback, lua, scriptID)
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
	LuaTextMenu(size_t timeout, sol::function callback, sol::state_view& lua, size_t scriptID)
		: scriptID(scriptID)
	{

		sol::stack::push<sol::unsafe_function>(lua.lua_state(), callback);
		callbackID = luaL_ref(lua.lua_state(), LUA_REGISTRYINDEX);

		sol::table event = lua["Event"]["new"](lua["Event"]);
		sol::stack::push<sol::table>(lua.lua_state(), event);
		eventID = luaL_ref(lua.lua_state(), LUA_REGISTRYINDEX);

		this->timeout = timeout;
		
		using namespace SimConnect;
		this->callback = [=](Result res, MenuItem item, const std::string& str, std::shared_ptr<TextMenuEvent> e)
		{
			LuaPlugin::withScript<::FSL2LuaScript>(scriptID, [=](::FSL2LuaScript& s) {
				s.enqueueCallback([=, &s](sol::state_view& lua) {
					auto f = lua.registry().raw_get<sol::protected_function>(callbackID);
					auto event = lua.registry().raw_get<sol::table>(eventID);
					sol::object luaItem(sol::nil);
					if (item != -1)
						luaItem = sol::make_object(lua.lua_state(), item + 1);
					lua.registry()[sol::light(this)] = sol::nil;
					s.callProtectedFunction(f, res, luaItem, str, std::static_pointer_cast<LuaTextMenu>(shared_from_this()));
					s.callProtectedFunction(
						event.get<sol::protected_function>("trigger"), 
						event, res, luaItem, str, 
						std::static_pointer_cast<LuaTextMenu>(shared_from_this())
					);
				});
			});
		};
	}

	sol::table getEvent(sol::this_state ts)
	{
		sol::state_view lua(ts);
		return lua.registry().raw_get<sol::table>(eventID);
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
		LuaPlugin::withScript<FSL2LuaScript>(scriptID, [=](FSL2LuaScript& s) {
			s.enqueueCallback([=, &s](sol::state_view& lua) {
				luaL_unref(lua.lua_state(), LUA_REGISTRYINDEX, callbackID);
				luaL_unref(lua.lua_state(), LUA_REGISTRYINDEX, eventID);
			});
		});
	}
};

void FSL2LuaScript::initLuaState(sol::state_view lua)
{

	LuaPlugin::initLuaState(lua);

	using logger = spdlog::logger;
	auto LoggerType = lua.new_usertype<logger>("Logger");

	LoggerType["trace"] = static_cast<void (logger::*)(const std::string&)>(&logger::trace);
	LoggerType["debug"] = static_cast<void (logger::*)(const std::string&)>(&logger::debug);
	LoggerType["info"] = static_cast<void (logger::*)(const std::string&)>(&logger::info);
	LoggerType["warn"] = static_cast<void (logger::*)(const std::string&)>(&logger::warn);
	LoggerType["error"] = static_cast<void (logger::*)(const std::string&)>(&logger::error);
	LoggerType["setLevel"] = [](spdlog::logger& logger, unsigned int level) {
		logger.sinks().back()->set_level(static_cast<spdlog::level::level_enum>(level));
	};
	lua["copilot"]["logger"] = this->logger;

	lua["copilot"]["newLuaThread"] = [](const std::string& path) {
		LuaPlugin::launchScript<FSL2LuaScript>(path);
	};

	lua["copilot"]["killLuaThread"] = [](const std::string& path) {
		LuaPlugin::stopScript(path);
	};


	SystemEventLuaManager<int>::createRegistryTable(lua);

	lua["copilot"]["simConnectSystemEvent"] = [scriptID = scriptID](sol::this_state ts, const std::string& evtName) {
		sol::state_view lua(ts);
		return SimConnect::subscribeToSystemEventLua(evtName, lua, scriptID);
	};

	keyBindManager = std::make_shared<KeyBindManager>();
	Keyboard::addKeyBindManager(keyBindManager);
	KeyBindManager::makeLuaBindings(lua, keyBindManager);

	joystickManager = std::make_shared<JoystickManager>();
	Joystick::addJoystickManager(joystickManager);
	Joystick::makeLuaBindings(lua, joystickManager);

	lua["Event"] = lua["require"]("copilot.Event");
	lua["muteCopilot"] = [] { copilot::onMuteKey(true); };
	lua["unmuteCopilot"] = [] { copilot::onMuteKey(false); };

	lua.registry()["dispatchKeyboardEvents"] = [this] {
		keyBindManager->dispatchEvents();
	};

	lua.registry()["dispatchJoystickEvents"] = [this] {
		joystickManager->dispatchEvents();
	};

	LuaTextMenu::makeLuaBindings(lua, scriptID);
	LuaNamedSimConnectEvent::makeLuaBindings(lua, scriptID);

	lua["copilot"]["mouseMacroEvent"] = [this](sol::this_state ts) {
		if (!mouseMacroCallback) {
			mouseMacroCallback = std::make_unique<MouseRectListenerCallback>(this->scriptID);
			copilot::GetWindowPluginSystem()->RegisterMouseRectListenerCallback(mouseMacroCallback.get());
			sol::state_view lua(ts);
			mouseMacroEvent = lua["Event"]["new"](lua["Event"]);
			mouseMacroEvent["logMsg"] = lua["Event"]["NOLOGMSG"];
		}
		return mouseMacroEvent;
	};

	callbackRunner = std::make_unique<CallbackRunner>(this);
	callbackRunner->makeLuaBindings(lua, "copilot");

	lua["require"]("copilot.common");
	lua["require"]("copilot.fsuipc_compat.event");
	
}

FSL2LuaScript::Events* FSL2LuaScript::createEvents()
{
	auto joystickEvents = joystickManager->getEvents();
	size_t numEvents = joystickEvents.size() + 3;
	HANDLE* events = new HANDLE[numEvents]();
	for (size_t i = 0; i < joystickEvents.size(); ++i)
		events[i] = joystickEvents.at(i);

	size_t EVENT_LUA_CALLBACK = numEvents - 3;
	events[EVENT_LUA_CALLBACK] = luaCallbackEvent;

	size_t KEYBOARD_EVENT = numEvents - 2;
	events[KEYBOARD_EVENT] = keyBindManager->queueEvent;

	size_t SHUTDOWN_EVENT = numEvents - 1;
	events[SHUTDOWN_EVENT] = shutdownEvent;

	auto e = new Events();

	e->events = events;
	e->numEvents = numEvents;
	e->JOYSTICK_EVENT_MIN = 0;
	e->JOYSTICK_EVENT_MAX = std::min<size_t>(joystickEvents.size() - 1, 0);
	e->KEYBOARD_EVENT = KEYBOARD_EVENT;
	e->SHUTDOWN_EVENT = SHUTDOWN_EVENT;
	e->EVENT_LUA_CALLBACK = EVENT_LUA_CALLBACK;

	return 	e;
}

void FSL2LuaScript::onEvent(Events* events, DWORD eventIdx)
{
	if (eventIdx == events->KEYBOARD_EVENT) {
		while (keyBindManager->hasEvents()) 
			callProtectedFunction(lua.registry()["dispatchKeyboardEvents"]);
	} else if (eventIdx == WAIT_OBJECT_0 + events->EVENT_LUA_CALLBACK) {
		std::unique_lock<std::mutex> lock(luaCallbackQueueMutex);
		std::queue<LuaCallback> callbacks = luaCallbacks;
		luaCallbacks = std::queue<LuaCallback>();
		lock.unlock();
		while (callbacks.size()) {
			auto& callback = callbacks.front();
			callback(lua);
			callbacks.pop();
		}
	} else {
		joystickManager->onNewDataAvailable(eventIdx);
		while (joystickManager->hasEvents()) 
			callProtectedFunction(lua.registry()["dispatchJoystickEvents"]);
	}
}

void FSL2LuaScript::run() 
{

	LuaPlugin::run();

	auto events = createEvents();

	while (true) {

		size_t timeout = 0;

		if (callbackRunner->nextUpdate == CallbackRunner::INDEFINITE) {
			timeout = INFINITE;
		} else {
			size_t elapsed = elapsedTime();
			if (callbackRunner->nextUpdate > elapsed)
				timeout = callbackRunner->nextUpdate - elapsed;
		}

		if (timeout == INFINITE && !events->numEvents)
			break;

		DWORD res = WaitForMultipleObjects(events->numEvents, events->events, false, timeout);
		if (res == events->SHUTDOWN_EVENT) {
			break;
		} else if (res == WAIT_TIMEOUT) {
			callbackRunner->update();
		} else {
			onEvent(events, res);
		}
	}

	delete[] events->events;
	delete events;
}

void FSL2LuaScript::enqueueCallback(LuaCallback callback)
{
	std::lock_guard<std::mutex> lock(luaCallbackQueueMutex);
	luaCallbacks.push(callback);
	SetEvent(luaCallbackEvent);
}

void FSL2LuaScript::stopThread()
{
	Joystick::removeJoystickManager(joystickManager);
	Keyboard::removeKeyBindManager(keyBindManager);
	LuaPlugin::stopThread();
}

FSL2LuaScript::~FSL2LuaScript()
{
	if (mouseMacroCallback)
		copilot::GetWindowPluginSystem()->UnRegisterMouseRectListenerCallback(mouseMacroCallback.get());
	Joystick::removeJoystickManager(joystickManager);
	Keyboard::removeKeyBindManager(keyBindManager);
	stopThread();
}
