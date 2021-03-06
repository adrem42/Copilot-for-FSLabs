#include "SimConnect.h"
#include "Copilot.h"
#include "SimInterface.h"
#include <mutex>

const unsigned short MUTE_KEY_DEPRESSED = 0;
const unsigned short MUTE_KEY_RELEASED = 1;

using namespace SimConnect;

std::string aircraftName;

namespace SimConnect {
	bool fslAircraftLoaded, simStarted;
	std::atomic_bool simPaused;
	HANDLE hSimConnect;
}

void onMuteControlEvent(DWORD param)
{
	switch (param) {

		case MUTE_KEY_DEPRESSED:
			copilot::onMuteKey(true);
			break;

		case MUTE_KEY_RELEASED:
			copilot::onMuteKey(false);
			break;
	}
}

void setupMenu()
{
	HRESULT hr;

	hr = SimConnect_MapClientEventToSimEvent(hSimConnect, EVENT_MUTE_CONTROL, "SMOKE_TOGGLE");
	hr = SimConnect_AddClientEventToNotificationGroup(hSimConnect, 0, EVENT_MUTE_CONTROL);

	hr = SimConnect_MenuAddItem(hSimConnect, "Copilot for FSLabs", EVENT_COPILOT_MENU, 0);
	hr = SimConnect_MenuAddSubItem(
		hSimConnect, EVENT_COPILOT_MENU, "Restart", EVENT_COPILOT_MENU_ITEM_START, 0);
	hr = SimConnect_MenuAddSubItem(
		hSimConnect, EVENT_COPILOT_MENU, "Stop", EVENT_COPILOT_MENU_ITEM_STOP, 0);

	hr = SimConnect_MenuAddItem(hSimConnect, "FSL2Lua", EVENT_FSL2LUA_MENU, 0);

	hr = SimConnect_MenuAddSubItem(
		hSimConnect, EVENT_FSL2LUA_MENU, "Restart script", EVENT_FSL2LUA_MENU_ITEM_RESTART_SCRIPT, 0);
}

void onFlightLoaded()
{
	setupMenu();
	bool isFslAircraft = aircraftName.find("FSLabs") != std::string::npos;
	copilot::onFlightLoaded(isFslAircraft, aircraftName);
}

void SimConnectCallback(SIMCONNECT_RECV* pData, DWORD cbData, void*)
{
	switch (pData->dwID) {

		case SIMCONNECT_RECV_ID_EVENT:
		{

			SIMCONNECT_RECV_EVENT* evt = (SIMCONNECT_RECV_EVENT*)pData;
			EVENT_ID eventID = (EVENT_ID)evt->uEventID;
			copilot::onSimEvent(eventID);

			switch (eventID) {

				case EVENT_MUTE_CONTROL:

					onMuteControlEvent(evt->dwData);
					break;

				case EVENT_SIM_START:
				{
					simPaused = false;

					if (!simStarted) {
						simStarted = true;
						onFlightLoaded();
					}

					break;
				}

				case EVENT_SIM_STOP:
					simPaused = true;
					break;

				case EVENT_COPILOT_MENU_ITEM_START:
					copilot::startCopilotScript();
					break;

				case EVENT_COPILOT_MENU_ITEM_STOP:
					copilot::stopCopilotScript();
					break;

				case EVENT_FSL2LUA_MENU_ITEM_RESTART_SCRIPT:
					copilot::launchFSL2LuaScript();
					break;

			}
			break;
		}

		case SIMCONNECT_RECV_ID_EVENT_FILENAME:
		{
			SIMCONNECT_RECV_EVENT_FILENAME* evt = (SIMCONNECT_RECV_EVENT_FILENAME*)pData;
			switch (evt->uEventID) {

				case EVENT_AIRCRAFT_LOADED:
				{
					aircraftName = std::string(evt->szFileName);
					break;
				}
				default:
					break;

			}
			break;
		}
	}
}

bool SimConnect::init()
{
	if (SUCCEEDED(SimConnect_Open(&hSimConnect, "FSLabs Copilot", NULL, 0, NULL, 0))) {

		HRESULT hr = S_OK;

		hr = SimConnect_SubscribeToSystemEvent(hSimConnect, EVENT_AIRCRAFT_LOADED, "AircraftLoaded");
		hr = SimConnect_SubscribeToSystemEvent(hSimConnect, EVENT_SIM_START, "SimStart");
		hr = SimConnect_SubscribeToSystemEvent(hSimConnect, EVENT_SIM_STOP, "SimStop");

		hr = SimConnect_MapClientEventToSimEvent(hSimConnect, EVENT_EXIT, "Exit");
		hr = SimConnect_AddClientEventToNotificationGroup(hSimConnect, 0, EVENT_EXIT);

		hr = SimConnect_MapClientEventToSimEvent(hSimConnect, EVENT_ABORT, "Abort");
		hr = SimConnect_AddClientEventToNotificationGroup(hSimConnect, 0, EVENT_ABORT);

		hr = SimConnect_SetNotificationGroupPriority(hSimConnect, 0, SIMCONNECT_GROUP_PRIORITY_HIGHEST);

		hr = SimConnect_CallDispatch(hSimConnect, SimConnectCallback, nullptr);

		return true;

	}
	return false;
}

void SimConnect::close()
{
	if (hSimConnect != NULL) {
		SimConnect_Close(hSimConnect);
		hSimConnect = NULL;
	}
}
