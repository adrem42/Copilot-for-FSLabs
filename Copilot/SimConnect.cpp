#include "SimConnect.h"
#include "Copilot.h"
#include "SimInterface.h"
#include <mutex>
#include <sstream>
#include <numeric>
#include <unordered_map>
#include "SystemEventLuaManager.h"
#include <cctype>
#include <algorithm>


using namespace SimConnect;

int flightLoadedCount = 0;

std::string airfileName;

std::atomic<size_t>  currEventId = EVENT_CUSTOM_EVENT_MIN;
std::unordered_map<std::string, std::weak_ptr<NamedSimConnectEvent>> namedEvents;

size_t SimConnect::getUniqueEventID()
{
	return currEventId++;
}

std::mutex eventsMutex;
std::unordered_map<size_t, std::weak_ptr<SimConnectEvent>> events;

std::string toLower(const std::string& s)
{
	auto copy = s;
	std::transform(copy.begin(), copy.end(), copy.begin(), [](unsigned char c) { return std::tolower(c); });
	return copy;
}

std::shared_ptr<NamedSimConnectEvent> SimConnect::getNamedEvent(const std::string& name)
{
	
	std::lock_guard<std::mutex> lock(eventsMutex);
	auto it = namedEvents.find(toLower(name));
	if (it != namedEvents.end()) return it->second.lock();
	auto event = std::make_shared<NamedSimConnectEvent>(name);
	namedEvents[toLower(name)] = event;
	return event;
}

bool SimConnect::SimConnectEvent::dispatch(DWORD param)
{
	if (callback) callback(param);
	return false;
}

std::atomic<size_t> NamedSimConnectEvent::currCallbackId = 0;

SimConnectEvent::~SimConnectEvent()
{
#ifdef DEBUG
	copilot::logger->trace("SimConnectEvent destroyed");
#endif
	std::lock_guard<std::mutex> lock(eventsMutex);
	events.erase(eventId);
}

size_t SimConnect::NamedSimConnectEvent::addCallback(Callback cb)
{
	auto callbackID = currCallbackId++;
	{
		std::lock_guard<std::mutex> lock(eventsMutex);
		callbacks[callbackID] = cb;
	}
	subscribe();
	return callbackID;
}

void SimConnect::NamedSimConnectEvent::removeCallback(size_t id)
{
	{
		std::lock_guard<std::mutex> lock(eventsMutex);
		callbacks.erase(id);
	}
	if (callbacks.empty())
		unsubscribe();
}

NamedSimConnectEvent::NamedSimConnectEvent(const std::string& name)
	:name(toLower(name))
{
	HRESULT hr = SimConnect_MapClientEventToSimEvent(hSimConnect, eventId, this->name.c_str());
}

bool SimConnect::NamedSimConnectEvent::dispatch(DWORD param)
{
	std::lock_guard <std::mutex> lock(eventsMutex);
	for (auto& [_, cb] : callbacks)
		cb(param);
	return false;
}

void SimConnect::NamedSimConnectEvent::subscribe()
{
	if (subscribed) return;
	HRESULT hr = SimConnect_AddClientEventToNotificationGroup(hSimConnect, 1, eventId);
	std::lock_guard<std::mutex> lock(eventsMutex);
	events.emplace(eventId, shared_from_this());
	subscribed = true;
}

void SimConnect::NamedSimConnectEvent::unsubscribe()
{
	std::lock_guard<std::mutex> lock(eventsMutex);
	if (!callbacks.empty()) return;
	HRESULT hr = SimConnect_RemoveClientEvent(hSimConnect, 1, eventId);
	events.erase(eventId);
	subscribed = false;
}

void SimConnect::NamedSimConnectEvent::transmit(DWORD data)
{
	HRESULT hr = SimConnect_TransmitClientEvent(
		hSimConnect, 0, eventId,
		data,
		SIMCONNECT_GROUP_PRIORITY_HIGHEST,
		SIMCONNECT_EVENT_FLAG_GROUPID_IS_PRIORITY
	);
}

SimConnect::NamedSimConnectEvent::~NamedSimConnectEvent()
{
	std::lock_guard<std::mutex> lock(eventsMutex);
	HRESULT hr = SimConnect_RemoveClientEvent(hSimConnect, 1, eventId);
	namedEvents.erase(toLower(name));
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

namespace SimConnect {
	bool fslAircraftLoaded, simStarted;
	std::atomic_bool simPaused;
	HANDLE hSimConnect;

	TextMenuCreatedEvent::TextMenuCreatedEvent()
	{
		messages.reserve(12);
	}
	sol::table TextMenuCreatedEvent::get(sol::state_view& lua)
	{
		auto t = lua.create_table();
		if (isMenu) {
			t["title"] = !messages.empty() ? messages[0] : "";
			t["prompt"] = messages.size() >= 2 ? messages[1] : "";
			t["type"] = "menu";
			t["items"] = lua.create_table(messages.size() > 2 ? messages.size() - 2 : 0);
			if (messages.size() > 2) {
				t["items"] = lua.create_table(messages.size() - 2);
				for (size_t i = 2; i < messages.size(); ++i) {
					t["items"][i - 1] = messages[i];
				}
			} else {
				t["items"] = lua.create_table(0);
			}
		} else {
			t["type"] = "message";
			if (!messages.empty())
				t["message"] = messages[0];
		}
		return t;
	}
}

void onCustomEvent(size_t id, DWORD param)
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
	hr = SimConnect_MapClientEventToSimEvent(hSimConnect, EVENT_MUTE_NAMED_EVENT, "adrem42.Copilot.Mute");
	hr = SimConnect_AddClientEventToNotificationGroup(hSimConnect, 0, EVENT_MUTE_NAMED_EVENT);
	hr = SimConnect_MapClientEventToSimEvent(hSimConnect, EVENT_UNMUTE_NAMED_EVENT, "adrem42.Copilot.Unmute");
	hr = SimConnect_AddClientEventToNotificationGroup(hSimConnect, 0, EVENT_UNMUTE_NAMED_EVENT);
}

void SimConnect::setupCopilotMenu()
{
	HRESULT hr;
	hr = SimConnect_MenuDeleteItem(hSimConnect, EVENT_COPILOT_MENU);
	hr = SimConnect_MenuAddItem(hSimConnect, "Copilot for FSLabs", EVENT_COPILOT_MENU, 0);
	hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_COPILOT_MENU, "Restart", EVENT_COPILOT_MENU_ITEM_START, 0);
	hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_COPILOT_MENU, "Stop", EVENT_COPILOT_MENU_ITEM_STOP, 0);
}

void SimConnect::setupFSL2LuaMenu()
{
	HRESULT hr;
	hr = SimConnect_MenuDeleteItem(hSimConnect, EVENT_FSL2LUA_MENU);
	hr = SimConnect_MenuAddItem(hSimConnect, "FSL2Lua", EVENT_FSL2LUA_MENU, 0);
	if (fslAircraftLoaded)
		hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_FSL2LUA_MENU, "Restart autorun.lua", EVENT_FSL2LUA_MENU_ITEM_RESTART_AUTORUN_LUA, 0);
	hr = SimConnect_MenuAddSubItem(hSimConnect, EVENT_FSL2LUA_MENU, "Reload scripts.ini", EVENT_FSL2LUA_MENU_ITEM_RELOAD_SCRIPTS_INI, 0);
}

void onFlightLoaded()
{
	bool isFslAircraft = 
		airfileName.find("FSLabs") != std::string::npos &&
			(airfileName.find("A320") != std::string::npos ||
			airfileName.find("A319") != std::string::npos ||
			airfileName.find("A321") != std::string::npos);
	fslAircraftLoaded = isFslAircraft;
	flightLoadedCount++;
	copilot::onFlightLoaded(isFslAircraft, airfileName, flightLoadedCount);
}

SystemEventLuaManager<TextMenuCreatedEvent> textMenuCreatedEventMgr("TextEventCreated");

sol::table SimConnect::subscribeToSystemEventLua(const std::string& evtName, sol::state_view& lua, size_t scriptID)
{
	if (evtName == "TextEventCreated") {
		return textMenuCreatedEventMgr.registerScript(lua, scriptID);
	}
	throw "No such event: " + evtName;
}

void SimConnectCallback(SIMCONNECT_RECV* pData, DWORD cbData, void*)
{
	switch (pData->dwID) {

		case SIMCONNECT_RECV_ID_EVENT:
		{

			SIMCONNECT_RECV_EVENT* evt = (SIMCONNECT_RECV_EVENT*)pData;
			
			if (evt->uEventID >= EVENT_CUSTOM_EVENT_MIN)
				return onCustomEvent(evt->uEventID, evt->dwData);

			EVENT_ID eventID = (EVENT_ID)evt->uEventID;
			copilot::onSimEvent(eventID);

			switch (eventID) {

				case EVENT_MUTE_NAMED_EVENT:
					copilot::onMuteKey(true);
					break;
					
				case EVENT_UNMUTE_NAMED_EVENT:
					copilot::onMuteKey(false);
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

				case EVENT_FSL2LUA_MENU_ITEM_RESTART_AUTORUN_LUA:
					copilot::launchAutorunLua();
					break;

				case EVENT_FSL2LUA_MENU_ITEM_RELOAD_SCRIPTS_INI:
					copilot::loadScriptsIni(false);
					break;

			}
			break;
		}

		case SIMCONNECT_RECV_ID_EVENT_TEXT:
		{
			SIMCONNECT_RECV_EVENT_TEXT* textData = (SIMCONNECT_RECV_EVENT_TEXT*)pData;
			TextMenuCreatedEvent evt;

			evt.isMenu = textData->eTextType == SIMCONNECT_TEXT_TYPE_MENU;
				
			auto message = reinterpret_cast<char*>(textData->rgMessage);

			int remainingSize = textData->dwUnitSize;

			for (int itemPosition = 0; remainingSize > 0; ++itemPosition) {
				int itemLength = strnlen(message, remainingSize) + sizeof(char);

				if (itemLength <= sizeof(char)) {
					break;
				}

				remainingSize -= itemLength;

				evt.messages.push_back(message);

				message = message + itemLength;
			}

			textMenuCreatedEventMgr.onEvent(evt);

		}

		case SIMCONNECT_RECV_ID_EVENT_FILENAME:
		{
			SIMCONNECT_RECV_EVENT_FILENAME* evt = (SIMCONNECT_RECV_EVENT_FILENAME*)pData;
			switch (evt->uEventID) {

				case EVENT_AIRCRAFT_LOADED:
				{
					simStarted = false;
					airfileName = std::string(evt->szFileName);
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
		hr = SimConnect_SetNotificationGroupPriority(hSimConnect, 1, SIMCONNECT_GROUP_PRIORITY_LOWEST);

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
