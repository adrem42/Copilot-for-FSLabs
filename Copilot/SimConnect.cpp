#include "SimConnect.h"
#include <mutex>

enum MuteKeyStatus {
	Depressed = 0,
	Released
};

std::shared_ptr<spdlog::sinks::wincolor_stdout_sink_mt> consoleSink;

void attachLogToConsole()
{
	auto& sinks = copilot::logger->sinks();
	auto it = std::find(sinks.begin(), sinks.end(), consoleSink);
	if (it != sinks.end())
		sinks.erase(it);
	consoleSink = std::make_shared<spdlog::sinks::wincolor_stdout_sink_mt>();
	consoleSink->set_pattern("[%T] %^[%n]%$ %v");
	copilot::logger->sinks().push_back(consoleSink);
}

void SimConnect::dispatchCallback(SIMCONNECT_RECV* pData, DWORD cbData, void* pContext)
{
	SimConnect* pThis = reinterpret_cast<SimConnect*>(pContext);
	pThis->process(pData, cbData);
}

void SimConnect::process(SIMCONNECT_RECV* pData, DWORD cbData)
{
	switch (pData->dwID) {

		case SIMCONNECT_RECV_ID_EVENT:
		{
			SIMCONNECT_RECV_EVENT* evt = (SIMCONNECT_RECV_EVENT*)pData;
			switch (evt->uEventID) {

				case EVENT_MUTE_CONTROL:
					if (copilot::recoResultFetcher) {
						switch ((MuteKeyStatus)evt->dwData) {
							case Depressed:
								copilot::recoResultFetcher->onMuteKeyEvent(true);
								break;
							case Released:
								copilot::recoResultFetcher->onMuteKeyEvent(false);
								break;
						}
					}
					break;

				case EVENT_SIM_START:
				{
					if (fslAircraftLoaded && !simStarted) {
						simStarted = true;

						HRESULT hr;

						hr = SimConnect_MapClientEventToSimEvent(hSimConnect, EVENT_MUTE_CONTROL, "SMOKE_TOGGLE");
						hr = SimConnect_AddClientEventToNotificationGroup(hSimConnect, GROUP0, EVENT_MUTE_CONTROL);

						hr = SimConnect_MenuAddItem(hSimConnect, "Copilot for FSLabs", EVENT_MENU, 0);
						hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_MENU, "Restart", EVENT_MENU_START, 0);
						hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_MENU, "Stop", EVENT_MENU_STOP, 0);
						hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_MENU, "Output log to console", EVENT_MENU_ATTACH_CONSOLE, 0);

						hr = SimConnect_SetNotificationGroupPriority(hSimConnect, GROUP0, SIMCONNECT_GROUP_PRIORITY_HIGHEST);

						attachLogToConsole();

						std::thread(copilot::autoStartLua).detach();
					}
					break;
				}

				case EVENT_MENU_START:
					copilot::startLuaThread();
					break;

				case EVENT_MENU_STOP:
					copilot::stopLuaThread();
					break;

				case EVENT_MENU_ATTACH_CONSOLE:
					attachLogToConsole();
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
					std::string path(evt->szFileName);
					fslAircraftLoaded = path.find("FSLabs") != std::string::npos;
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

		hr += SimConnect_SubscribeToSystemEvent(hSimConnect, EVENT_AIRCRAFT_LOADED, "AircraftLoaded");
		hr += SimConnect_SubscribeToSystemEvent(hSimConnect, EVENT_SIM_START, "SimStart");

		hr += SimConnect_CallDispatch(hSimConnect, dispatchCallback, this);

		return SUCCEEDED(hr);

	}
	return false;
}

SimConnect::~SimConnect()
{
	if (hSimConnect != NULL) {
		SimConnect_Close(hSimConnect);
	}
}
