#pragma once
#include <Windows.h>
#include <SimConnect.h>
#include <atomic>

namespace SimConnect {

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

		EVENT_HIDE_CURSOR,
		EVENT_MENU_ATTACH_CONSOLE,
		EVENT_EXIT,
		EVENT_ABORT
	};

	extern std::atomic_bool simPaused;

	bool init();
	void close();
};
