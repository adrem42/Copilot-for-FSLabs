#pragma once
#include <Windows.h>
#include <SimConnect.h>
#include <map>

#include "RecoResultFetcher.h"

class SimConnect {
	enum GROUP_ID {
		GROUP0,
	};
	bool m_fslAircraftLoaded = false, m_simStarted = false;
	HANDLE m_hSimConnect = NULL;
	static void dispatchCallback(SIMCONNECT_RECV* pData, DWORD cbData, void* pContext);
	void process(SIMCONNECT_RECV* pData, DWORD cbData);
public:
	enum EVENT_ID {
		EVENT_MUTE_CONTROL,
		EVENT_AIRCRAFT_LOADED,
		EVENT_SIM_START,
		EVENT_SIM_STOP,
		EVENT_MENU,
		EVENT_MENU_START,
		EVENT_MENU_STOP,
		EVENT_MENU_ATTACH_CONSOLE,
	};
	std::atomic_bool simPaused;
	bool init();
	void close();
};
