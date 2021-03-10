#pragma once
#include <Windows.h>
#include <SimConnect.h>
#include <atomic>
#include <string>
#include <vector>
#include <functional>
#include <sol/sol.hpp>

namespace SimConnect {

	class SimConnectEvent : public std::enable_shared_from_this<SimConnectEvent> {
		static size_t currEventId;
	public:
		SimConnectEvent() :eventId(currEventId++) {}
		const size_t eventId;
		virtual bool dispatch(DWORD) = 0;
		virtual ~SimConnectEvent();
	};

	class TextMenuEvent : public SimConnectEvent {

	public:
		enum class Result { OK, Removed, Replaced, Timeout };
		using MenuItem = int8_t;
		using Callback = std::function<void(Result, MenuItem, const std::string&, std::shared_ptr<TextMenuEvent>)>;

	private:

		Callback callback;
		const std::string& title;
		const std::string& prompt;
		const std::vector<std::string> items;
		size_t timeout;
		char* buff;
		size_t buffSize;

	public:
		TextMenuEvent(const std::string&, const std::string& ,std::vector<std::string>, size_t, Callback);
		virtual bool dispatch(DWORD data) override;
		void show();
		void cancel();
		void makeLuaBindings(sol::state_view& lua);
		virtual ~TextMenuEvent();
	};

	extern bool fslAircraftLoaded, simStarted;

	extern HANDLE hSimConnect;

	enum EVENT_ID {

		EVENT_MUTE_CONTROL,
		EVENT_AIRCRAFT_LOADED,
		EVENT_SIM_START,
		EVENT_SIM_STOP,

		EVENT_COPILOT_MENU,
		EVENT_COPILOT_MENU_ITEM_START,
		EVENT_COPILOT_MENU_ITEM_STOP,

		EVENT_FSL2LUA_MENU,
		EVENT_FSL2LUA_MENU_ITEM_RESTART_SCRIPT,

		EVENT_EXIT,
		EVENT_ABORT,

		EVENT_CUSTOM_EVENT_MIN = 0x1000
	};

	void setupMuteControls();
	void setupCopilotMenu();
	void setupFSL2LuaMenu();

	extern std::atomic_bool simPaused;

	bool init();
	void close();
};
