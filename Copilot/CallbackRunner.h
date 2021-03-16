#pragma once
#include <sol/sol.hpp>
#include <optional>
#include <string>
#include <map>
#include <variant>
#include "LuaPlugin.h"
#include <unordered_set>
#include "Copilot.h"

class CallbackRunner {

public:

	using Timestamp = size_t;
	using Interval = uint16_t;

	static const Timestamp INDEFINITE = -1;

	std::function<void()> onCallbackAwake;
	std::function<Timestamp()> elapsedTime;
	std::function<void(sol::error&)> onError;
	std::function<sol::table()> makeThreadEvent;

private:

#ifdef _DEBUG
	template <typename... Args>
	static void debug(Args&&... args)
	{
		copilot::logger->trace(std::forward<Args>(args)...);
	}
#else
	static void debug(...) {}
#endif

	const Interval MIN_INTERVAL = 30;
	static constexpr const char* REGISTRY_KEY_CALLBACKS_TABLE = "__CALLBACKS";
	
	struct indefinite_t {};
	const indefinite_t lua_indefinite;
	struct thread_removed_t {};
	const thread_removed_t lua_thread_removed;

	struct Callback {
		enum class Status {
			Idle, Active, Suspended, Removed
		};
		std::optional<std::string> name;
		Interval interval;
		sol::object functionOrThread;
		std::variant<sol::main_protected_function, sol::coroutine> callable;
		Timestamp deadline;
		std::optional<sol::table> threadEvent = {};
		lua_State* threadState = nullptr;
		bool isFunction();
		Status status = Status::Idle;
		bool runOnce = false;
		sol::thread th;
	};

	Callback* currentCallback = nullptr;
	Callback* lastAdded = nullptr;
	std::unordered_map<std::string, std::shared_ptr<Callback>> callbackNames;
	std::multimap<Timestamp, std::shared_ptr<Callback>> activeCallbacks;

	using ActiveCallbackIter = std::multimap<Timestamp, std::shared_ptr<Callback>>::iterator;

	using CallbackReturn = std::tuple<sol::object, std::optional<sol::table>>;

	template <typename T, typename... Args>
	sol::protected_function_result callRunable(T& runnable, Args&&... args)
	{
		sol::protected_function_result pfr = runnable(std::forward<Args>(args)...);
		if (!pfr.valid()) {
			sol::error err = pfr;
			onError(err);
		}
		return pfr;
	}

	template <typename... Args>
	void runThreadCallback(std::shared_ptr<Callback>& callback, sol::coroutine& co, ActiveCallbackIter& it, Args&&... args)
	{
		sol::protected_function_result pfr = callRunable(co, std::forward<Args>(args)...);
		if (co.status() != sol::call_status::yielded) {
			sol::state_view lua(co.lua_state());
			actuallyRemoveCallback(lua, callback, it);
			if (pfr.valid()) {
				auto& threadEvent = *callback->threadEvent;
				std::vector<sol::object> args(pfr.begin() + 1, pfr.end());
				threadEvent["trigger"](threadEvent, sol::as_args(args));
			}
		}
	}

	template <typename... Args>
	void runFuncCallback(sol::main_protected_function& f, Args&&... args)
	{
		callRunable(f, std::forward<Args>(args)...);
	}

	std::shared_ptr<CallbackRunner::Callback> checkAlreadyAdded(sol::object& o, std::optional<std::string>& name);

	sol::unsafe_function createCoroutine;

	void actuallyRemoveCallback(sol::state_view&, std::shared_ptr<Callback>&, ActiveCallbackIter& iter);
	void actuallyRemoveCallback(sol::state_view&, std::shared_ptr<Callback>&);

	std::shared_ptr<Callback> findCallback(sol::state_view& lua, sol::object& key)
	{
		if (key.get_type() == sol::type::string) {
			auto it = callbackNames.find(key.as<std::string>());
			if (it == callbackNames.end())
				return nullptr;
			return it->second;
		}
		sol::optional<std::shared_ptr<Callback>> maybeCallback = lua.registry()[REGISTRY_KEY_CALLBACKS_TABLE][key];
		if (!maybeCallback) 
			return nullptr;
		return *maybeCallback;
	}

	std::shared_ptr<Callback> findCallback(sol::object& key)
	{
		sol::state_view lua(key.lua_state());
		return findCallback(lua, key);
	}

	template<typename Fx>
	bool setCallbackTimeout(sol::object& key, Fx&& block)
	{
		sol::state_view lua(key.lua_state());
		if (auto callback = findCallback(lua, key)) {
			if (!block(callback)) return false;
			callback->status = Callback::Status::Suspended;
			if (lua.lua_state() == callback->threadState) {
				return true;
			}
		}
		return false;
	}

	ActiveCallbackIter findActiveCallback(std::shared_ptr<Callback>&);

public:

	CallbackRunner(sol::state_view&, std::function<void()>, std::function<Timestamp()>, std::function<void(sol::error&)>);
	CallbackReturn addCallback(sol::object callable, std::optional<std::string> name, std::optional<Interval> interval, std::optional<Interval> delay);
	CallbackReturn addCoroutine(sol::object callable, std::optional<std::string> name, std::optional<Interval> delay);
	CallbackReturn callOnce(sol::object callable, std::optional<Interval> interval, std::optional<Interval> delay);
	void removeCallback(sol::object callable);
	bool setCallbackTimeout(sol::object, Timestamp);
	bool setCallbackTimeout(sol::object, indefinite_t);
	void cancelCallbackTimeout(sol::object);
	std::optional<sol::table> getThreadEvent(sol::object);
	void makeLuaBindings(sol::state_view&, const std::string&);
	Timestamp update();

};

