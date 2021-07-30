#pragma once
#include <Windows.h>
#include <SimConnect.h>
#include <atomic>
#include <string>
#include <vector>
#include <functional>
#include <sol/sol.hpp>

class FSL2LuaScript;

namespace SimConnect {

	size_t getUniqueEventID();

	class SimConnectEvent : public std::enable_shared_from_this<SimConnectEvent> {
	public:
		using Callback = std::function<void(DWORD)>;
	protected:
		const Callback callback;
	public:
		SimConnectEvent(const SimConnectEvent&) = delete;
		SimConnectEvent() = default;
		SimConnectEvent(Callback callback) :callback(callback) {};
		const size_t eventId = getUniqueEventID();
		virtual bool dispatch(DWORD);
		virtual ~SimConnectEvent();
	};

	class NamedSimConnectEvent : public SimConnectEvent {
		std::unordered_map<size_t, Callback> callbacks;
		static std::atomic<size_t> currCallbackId;
		void subscribe();
		void unsubscribe();
		bool subscribed = false;
	public:
		const std::string name;
		size_t addCallback(Callback);
		void removeCallback(size_t);
		NamedSimConnectEvent(const std::string& name);
		virtual bool dispatch(DWORD);
		void transmit(DWORD);
		virtual ~NamedSimConnectEvent();
	};

	std::shared_ptr<NamedSimConnectEvent> getNamedEvent(const std::string& name);

	class TextMenuEvent : public SimConnectEvent {

	public:

		enum class Result { OK, Removed, Replaced, Timeout };
		using MenuItem = int8_t;
		using Callback = std::function<void(Result, MenuItem, const std::string&, std::shared_ptr<TextMenuEvent>)>;

		char* buff = nullptr;
		size_t buffSize = 0;

	protected:

		Callback callback;
		void buildBuffer();
		TextMenuEvent() = default;

		std::string title;
		std::string prompt{" "};
		std::vector<std::string> items;
		size_t timeout;

		void invalidateBuffer();

	public:

		TextMenuEvent(const std::string&, const std::string& ,std::vector<std::string>, size_t, Callback);
		TextMenuEvent(size_t, Callback);
		virtual bool dispatch(DWORD data) override;

		TextMenuEvent& setMenu(const std::string&, const std::string&, std::vector<std::string>);
		TextMenuEvent& setTimeout(size_t);
		void show();
		void cancel();
		virtual ~TextMenuEvent();
	};

	extern bool fslAircraftLoaded, simStarted;

	extern HANDLE hSimConnect;

	enum EVENT_ID {

		EVENT_MUTE_NAMED_EVENT,
		EVENT_UNMUTE_NAMED_EVENT,

		EVENT_AIRCRAFT_LOADED,
		EVENT_SIM_START,
		EVENT_SIM_STOP,

		EVENT_COPILOT_MENU,
		EVENT_COPILOT_MENU_ITEM_START,
		EVENT_COPILOT_MENU_ITEM_STOP,

		EVENT_FSL2LUA_MENU,
		EVENT_FSL2LUA_MENU_ITEM_RESTART_AUTORUN_LUA,
		EVENT_FSL2LUA_MENU_ITEM_RELOAD_SCRIPTS_INI,

		EVENT_EXIT,
		EVENT_ABORT,

		EVENT_CUSTOM_EVENT_MIN = 0x1000
	};

	void setupMuteControls();
	void setupCopilotMenu();
	void setupFSL2LuaMenu();

	struct TextMenuCreatedEvent {
		std::vector<std::string> messages;
		bool isMenu = false;
		static void makeLuaBindings(sol::state_view& lua);
		TextMenuCreatedEvent();
		sol::table get(sol::state_view& lua);
	};

	sol::table subscribeToSystemEventLua(const std::string& evtName, sol::state_view& lua, FSL2LuaScript* script);

	extern std::atomic_bool simPaused;

	bool init();
	void close();
};
