#pragma once
#include <Windows.h>
#include <SimConnect.h>
#include <map>

#include "RecoResultFetcher.h"
#include "Copilot.h"

class SimConnect {
	enum EVENT_ID {
		EVENT_MUTE_CONTROL,
		EVENT_AIRCRAFT_LOADED,
		EVENT_SIM_START,
		EVENT_MENU,
		EVENT_MENU_START,
		EVENT_MENU_STOP,
		EVENT_MENU_ATTACH_CONSOLE
	};
	enum GROUP_ID {
		GROUP0,
	};
	bool fslAircraftLoaded = false, simStarted = false;
	HANDLE hSimConnect = NULL;
	static void dispatchCallback(SIMCONNECT_RECV* pData, DWORD cbData, void* pContext);
	void process(SIMCONNECT_RECV* pData, DWORD cbData);
public:
	bool init();
	~SimConnect();
};
