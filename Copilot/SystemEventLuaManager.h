#pragma once
#include "SimConnect.h"
#include "FSL2LuaScript.h"

template<typename Payload>
class SystemEventLuaManager {
	std::mutex mutex;
	std::unordered_set<size_t> scripts;
	const std::string eventName;
	size_t eventID = getUniqueEventID();
	static constexpr const char* REGISTRY_KEY = "SIMCONNECT_SYSTEM_EVENTS";
public:
	SystemEventLuaManager(const std::string& eventName) :eventName(eventName) {}
	sol::table registerScript(sol::state_view& lua, size_t scriptID)
	{
		sol::table regT = lua.registry()[REGISTRY_KEY];
		if (regT[eventName].get_type() != sol::type::table){
			sol::table evt = lua["Event"]["new"](lua["Event"]);
			evt["logMsg"] = lua["Event"]["NOLOGMSG"];
			regT[eventName] = evt;
			std::lock_guard<std::mutex> lock(mutex);
			if (scripts.empty())
				SimConnect_SubscribeToSystemEvent(SimConnect::hSimConnect, eventID, eventName.c_str());
			scripts.insert(scriptID);
		}
		return regT[eventName];
	}
	void unregisterScript(size_t scriptID)
	{
		std::lock_guard<std::mutex> lock(mutex);
		scripts.erase(scriptID);
		if (scripts.empty())
			SimConnect_UnsubscribeFromSystemEvent(SimConnect::hSimConnect, eventID);
	}
	static void createRegistryTable(sol::state_view& lua)
	{
		auto regT = lua.create_table();
		lua.registry()[REGISTRY_KEY] = regT;
	}
	void onEvent(Payload& payload)
	{
		std::lock_guard<std::mutex> lock(mutex);
		auto it = scripts.begin();

		while (it != scripts.end()) {
			auto scriptID = *it;
			bool sciptStillAlive = LuaPlugin::withScript<FSL2LuaScript>(scriptID, [=](FSL2LuaScript& script) {
				script.enqueueCallback([=, payload = std::move(payload)](sol::state_view& lua) mutable {
					sol::object maybeEvent = lua.registry()[REGISTRY_KEY][eventName];
					if (maybeEvent.get_type() != sol::type::table)
						return unregisterScript(scriptID);
					auto event = maybeEvent.as<sol::table>();
					event["trigger"](event, payload.get(lua));
				});
			});
			if (sciptStillAlive)
				it++;
			else
				it = scripts.erase(it);
		}
	}
};