#include "SimConnect.h"
#include "Copilot.h"
#include "SimInterface.h"
#include <mutex>
#include <sstream>
#include <numeric>
#include <unordered_map>

using namespace SimConnect;

bool firstAircraft = true;

std::string aircraftName;

size_t  currEventId = EVENT_CUSTOM_EVENT_MIN;

size_t SimConnect::getUniqueEventID()
{
	return currEventId++;
}

std::mutex eventsMutex;
std::unordered_map<size_t, std::weak_ptr<SimConnectEvent>> events;

SimConnectEvent::~SimConnectEvent()
{
#ifdef DEBUG
	copilot::logger->trace("SimConnectEvent destroyed");
#endif
}

TextMenuEvent::TextMenuEvent(
	const std::string& title,
	const std::string& prompt,
	std::vector<std::string> items,
	size_t timeout,
	TextMenuEvent::Callback callback
) : callback(callback), title(title), prompt(prompt), items(items), timeout(timeout)
{}

void SimConnect::TextMenuEvent::invalidateBuffer()
{
	buff = nullptr;
	buffSize = 0;
}

TextMenuEvent::TextMenuEvent(size_t timeout, Callback callback)
	:timeout(timeout), callback(callback)
{
}

void SimConnect::TextMenuEvent::buildBuffer()
{

	if (title.empty())
		throw std::runtime_error("The title must not be empty");

	if (items.empty())
		throw std::runtime_error("The menu must have items");

	if (items.size() > 10)
		throw std::runtime_error("A menu can only display 10 items");

	if (prompt.empty())
		prompt = " ";

	buffSize = std::accumulate(
		items.begin(), items.end(), 0, 
		[](size_t acc, std::string s) { return acc + s.length() + 1; });

	buffSize += prompt.length() + title.length() + 2;
	buff = new char[buffSize]();
	char* currPos = buff;

	auto insert = [&] (const std::string& s) {
		memcpy(currPos, s.c_str(), s.length());
		currPos += s.length() + 1;
	};

	insert(title);
	insert(prompt);

	std::for_each(items.begin(), items.end(), [&](const std::string& s) {
		if (s.empty()) 
			throw std::runtime_error("The menu must not contain empty items");
		insert(s);
	});
		
}

bool TextMenuEvent::dispatch(DWORD data)
{
	MenuItem selectedItem = -1;
	Result outResult = Result::OK;

	switch (data) {

		case SIMCONNECT_TEXT_RESULT_DISPLAYED:
		case SIMCONNECT_TEXT_RESULT_QUEUED:
			return false;

		default:
			selectedItem = data;
			break;

		case SIMCONNECT_TEXT_RESULT_REMOVED:
			outResult = Result::Removed;
			break;

		case SIMCONNECT_TEXT_RESULT_TIMEOUT:
			outResult = Result::Timeout;
			break;

		case SIMCONNECT_TEXT_RESULT_REPLACED:
			outResult = Result::Replaced;
			break;

	}


	std::string str;

	if (selectedItem != -1)
		str = items[selectedItem];

	callback(
		outResult, selectedItem, str,
		std::static_pointer_cast<TextMenuEvent>(shared_from_this())
	);
	return true;
}

TextMenuEvent& TextMenuEvent::setMenu(const std::string& title, const std::string& prompt, std::vector<std::string> items)
{
	this->title = title;
	this->prompt = prompt;
	this->items = items;
	invalidateBuffer();
	return *this;
}

void TextMenuEvent::show()
{
	if (!buff)
		buildBuffer();

	HRESULT hr = SimConnect_Text(
		hSimConnect, SIMCONNECT_TEXT_TYPE_MENU, timeout, eventId, buffSize, buff
	);
	
	std::lock_guard<std::mutex> lock(eventsMutex);
	events.emplace(eventId, shared_from_this());
}

TextMenuEvent& TextMenuEvent::setTimeout(size_t timeout)
{
	this->timeout = timeout;
	return *this;
}

void TextMenuEvent::cancel()
{
	char empty[1] = {};
	HRESULT hr = SimConnect_Text(
		hSimConnect, SIMCONNECT_TEXT_TYPE_MENU, timeout, eventId, 1, empty
	);
}

TextMenuEvent::~TextMenuEvent()
{
	cancel();
}

const unsigned short MUTE_KEY_DEPRESSED = 0;
const unsigned short MUTE_KEY_RELEASED = 1;

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

void onCustomEvent(EVENT_ID id, DWORD param)
{
	std::unique_lock<std::mutex> lock(eventsMutex);
	if (auto event = events[id].lock()) {
		lock.unlock();
		if (event->dispatch(param))
			events.erase(id);
	}
}

void SimConnect::setupMuteControls()
{
	HRESULT hr;

	hr = SimConnect_MapClientEventToSimEvent(hSimConnect, EVENT_MUTE_CONTROL, "SMOKE_TOGGLE");
	hr = SimConnect_AddClientEventToNotificationGroup(hSimConnect, 0, EVENT_MUTE_CONTROL);
}

void SimConnect::setupCopilotMenu()
{
	HRESULT hr;

	hr = SimConnect_MenuAddItem(hSimConnect, "Copilot for FSLabs", EVENT_COPILOT_MENU, 0);
	hr = SimConnect_MenuAddSubItem(
		hSimConnect, EVENT_COPILOT_MENU, "Restart", EVENT_COPILOT_MENU_ITEM_START, 0);
	hr = SimConnect_MenuAddSubItem(
		hSimConnect, EVENT_COPILOT_MENU, "Stop", EVENT_COPILOT_MENU_ITEM_STOP, 0);
}

void SimConnect::setupFSL2LuaMenu()
{
	HRESULT hr;

	hr = SimConnect_MenuAddItem(hSimConnect, "FSL2Lua", EVENT_FSL2LUA_MENU, 0);

	hr = SimConnect_MenuAddSubItem(
		hSimConnect, EVENT_FSL2LUA_MENU, "Restart script", EVENT_FSL2LUA_MENU_ITEM_RESTART_SCRIPT, 0);
}

void onFlightLoaded()
{
	bool isFslAircraft = aircraftName.find("FSLabs") != std::string::npos;
	copilot::onFlightLoaded(isFslAircraft, aircraftName, firstAircraft);
	firstAircraft = false;
}

void SimConnectCallback(SIMCONNECT_RECV* pData, DWORD cbData, void*)
{
	switch (pData->dwID) {

		case SIMCONNECT_RECV_ID_EVENT:
		{

			SIMCONNECT_RECV_EVENT* evt = (SIMCONNECT_RECV_EVENT*)pData;
			EVENT_ID eventID = (EVENT_ID)evt->uEventID;
			copilot::onSimEvent(eventID);

			if (eventID >= EVENT_CUSTOM_EVENT_MIN)
				return onCustomEvent(eventID, evt->dwData);

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
					simStarted = false;
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
