/***
* @module copilot
*/

#include "CallbackRunner.h"
#include <Windows.h>
#include "Copilot.h"

CallbackRunner::Interval CallbackRunner::validateInputInterval(std::optional<Interval>& input)
{
	return input ? std::max<Interval>(*input, MIN_INTERVAL) : MIN_INTERVAL;
}

void CallbackRunner::maybeAwaken(Timestamp deadline)
{
	if (activeCallbacks.empty()
		|| activeCallbacks.begin()->second->deadline > deadline)
		onCallbackAwake();
}

std::shared_ptr<CallbackRunner::Callback> CallbackRunner::checkAlreadyAdded(sol::object& o, std::optional<std::string>& name)
{
	sol::state_view lua(o.lua_state());
	sol::object lul = lua.registry()[REGISTRY_KEY_CALLBACKS_TABLE][o];
	auto type = lul.get_type();
	sol::optional<std::shared_ptr<Callback>> maybeCallback = lua.registry()[REGISTRY_KEY_CALLBACKS_TABLE][o];
	if (maybeCallback.has_value()) {
		if ((*maybeCallback)->name == name) {
			return *maybeCallback;
		} else {
			throw std::runtime_error("This callback was already added under a different name");
		}
	}

	if (name.has_value()) {
		auto it = callbackNames.find(*name);
		if (it != callbackNames.end()) {
			throw std::runtime_error("A different callback with this name was already added");
		}
	}

	return nullptr;
}

void CallbackRunner::actuallyRemoveCallback(sol::state_view& lua, std::shared_ptr<Callback>& callback, ActiveCallbackIter& iter)
{
	lua.registry()[REGISTRY_KEY_CALLBACKS_TABLE][callback->functionOrThread] = sol::nil;
	if (callback->name.has_value()) 
		callbackNames.erase(*callback->name);
	if (callback->deadline != INDEFINITE) {
		if (iter != activeCallbacks.end()) {
			activeCallbacks.erase(iter);
		} else {
			auto it = findActiveCallback(callback);
			if (it != activeCallbacks.end())
				activeCallbacks.erase(it);
		}
	}
	callback->status = Callback::Status::Removed;
	debug("Removed callback");
}

void CallbackRunner::actuallyRemoveCallback(sol::state_view& lua, std::shared_ptr<Callback>& callback)
{
	auto it = activeCallbacks.end();
	actuallyRemoveCallback(lua, callback, it);
}

CallbackRunner::ActiveCallbackIter CallbackRunner::findActiveCallback(std::shared_ptr<Callback>& callback)
{
	auto it = activeCallbacks.equal_range(callback->deadline);
	for (auto& itr = it.first; itr != it.second; ++itr) {
		if (itr->second == callback)
			return itr;
	}
	return activeCallbacks.end();
}

CallbackRunner::CallbackRunner(
	sol::state_view& lua,
	std::function<void()> onCallbackAwake, 
	std::function<Timestamp()> elapsedTime, 
	std::function<void(sol::error&)> onError)
	: onCallbackAwake(onCallbackAwake), elapsedTime(elapsedTime), onError(onError)
{
	lua.registry()[REGISTRY_KEY_CALLBACKS_TABLE] = lua.create_table();
}

/***
* 
* Adds a callback to the callback queue.
* @function copilot.addCallback
* @param callback A function, callable table or thread. It will be called the following arguments:
*
* 1. A timestamp (same as copilot.getTimestamp())
*
* 2. itself
* @string[opt] name Can be used later to remove the callback with `removeCallback`.
* @int[opt] interval Interval in milliseconds
* @int[opt] delay Initial delay in milliseconds
* @return The callback that was passed in.
* @return An <a href = "#Class_Event">Event</a> that will be signaled when the coroutine :
*
* 1. Finishes its execution normally.In this case, the event's payload will be the values returned by the coroutine.
*
* 2. Is removed with `removeCallback`. The payload will be copilot.THREAD_REMOVED
* 
*/
CallbackRunner::CallbackReturn CallbackRunner::addCallback(
	sol::object callable,
	std::optional<std::string> name, 
	std::optional<Interval> interval, 
	std::optional<Interval> delay)
{
	auto type = callable.get_type();

	if (type != sol::type::function && type != sol::type::thread)
		throw std::runtime_error("Bad callback parameter");

	size_t now = elapsedTime();

	if (auto alreadyAdded = checkAlreadyAdded(callable, name)) {
		if (delay.has_value() && *delay > 0) {
			size_t deadline = now;
			if (delay.has_value() && *delay > 0)
				deadline += *delay;
			alreadyAdded->deadline = deadline;
		}
		if (interval) {
			alreadyAdded->interval = validateInputInterval(interval);
		}
		maybeAwaken(alreadyAdded->deadline);
		return std::make_tuple(callable, alreadyAdded->threadEvent);
	}

	size_t deadline = now;

	if (delay && *delay > 0)
		deadline += *delay;
	
	auto _interval = validateInputInterval(interval);

	std::shared_ptr<Callback> callback;

	if (type == sol::type::function) {
		sol::main_protected_function f = callable;
		callback = std::shared_ptr<Callback>(new Callback{ name, _interval, f, f, deadline });
	} else if (type == sol::type::thread) {
		sol::thread th = callable;
		sol::coroutine co(th.thread_state());
		if (!makeThreadEvent) {
			sol::state_view lua(callable.lua_state());
			sol::object maybeSingleEvent = lua["SingleEvent"];
			if (maybeSingleEvent.get_type() == sol::type::table) {
				sol::table SingleEvent = lua["SingleEvent"];
				makeThreadEvent = [SingleEvent] {return SingleEvent["new"](SingleEvent); };
			} else {
				makeThreadEvent = [] () -> std::optional<sol::table> {return {}; };
			}
		}
		callback = std::shared_ptr<Callback>(new Callback{ name, _interval, th, co, deadline, makeThreadEvent(), th.thread_state() });
	} 

	debug("Adding new callback...");
	maybeAwaken(deadline);
	activeCallbacks.emplace(deadline, callback);
	sol::state_view lua(callable.lua_state());
	lua.registry()[REGISTRY_KEY_CALLBACKS_TABLE][callable] = callback;
	if (name.has_value()) callbackNames.emplace(*name, callback);
	lastAdded = callback.get();
	return std::make_tuple(callback->functionOrThread, callback->threadEvent);
}

CallbackRunner::CallbackReturn CallbackRunner::addCoroutine(sol::object callable, std::optional<std::string> name, std::optional<Interval> delay)
{
	if (callable.get_type() == sol::type::function) {
		sol::state_view lua(callable.lua_state());
		return addCallback(lua["coroutine"]["create"](callable), name, {}, delay);
	}
	return addCallback(callable, name, {}, delay);
}

/***
* Adds a callback to the callback queue that will be removed after running once.
* It doesn't matter whether you use `addCallback` or callOnce with coroutines as a coroutine instance cannot run twice.
* @function copilot.callOnce
* @param callback Same as `addCallback`
* @int[opt] delay Same as `addCallback`
* @return The same values as `addCallback`
*/
CallbackRunner::CallbackReturn CallbackRunner::callOnce(sol::object callable, std::optional<Interval> delay)
{
	auto callback = addCallback(callable, {}, {}, delay);
	if (callable.get_type() == sol::type::function)
		lastAdded->runOnce = true;
	return callback;
}

/***
* Removes a previously added callback.
* @function copilot.removeCallback
* @param key Either the callable itself or the name passed to @{addCallback}
*/ 
void CallbackRunner::removeCallback(sol::object key)
{
	sol::state_view lua(key.lua_state());
	if (auto callback = findCallback(lua, key)) {
		actuallyRemoveCallback(lua, callback);
		if (callback->functionOrThread.get_type() == sol::type::thread) {
			auto& threadEvent = *callback->threadEvent;
			threadEvent["trigger"](threadEvent, lua_thread_removed);
		}
	}
}

bool CallbackRunner::setCallbackTimeout(sol::object key, Timestamp timeout)
{
	return setCallbackTimeout(key, [this, timeout](std::shared_ptr<Callback>& callback) {
		auto now = elapsedTime();
		auto newDeadline = now + timeout;
		if (currentCallback != callback.get()) {
			auto it = findActiveCallback(callback);
			if (it != activeCallbacks.end()) {
				auto nh = activeCallbacks.extract(it);
				nh.key() = newDeadline;
				activeCallbacks.insert(std::move(nh));
			}
		}
		callback->deadline = newDeadline;
		return true;
	});
}

bool CallbackRunner::setCallbackTimeout(sol::object key, indefinite_t indefinite)
{
	return setCallbackTimeout(key, [this](std::shared_ptr<Callback>& callback) {
		if (callback->deadline == INDEFINITE)
			return false;
		auto it = findActiveCallback(callback);
		if (it != activeCallbacks.end())
			activeCallbacks.erase(it);
		callback->deadline = INDEFINITE;
		return true;
	});
}

void CallbackRunner::cancelCallbackTimeout(sol::object key)
{
	auto callback = findCallback(key);
	if (!callback) return;

	if (callback->status != Callback::Status::Suspended)
		return;
	auto newDeadline = elapsedTime();

	if (callback->deadline == INDEFINITE) {
		callback->deadline = newDeadline;
		activeCallbacks.emplace(newDeadline, callback);
	} else {
		auto it = findActiveCallback(callback);
		callback->deadline = newDeadline;
		auto nh = activeCallbacks.extract(it);
		nh.key() = newDeadline;
		activeCallbacks.insert(std::move(nh));
	}

	onCallbackAwake();
}

std::optional<sol::table> CallbackRunner::getThreadEvent(sol::object key)
{
	auto callback = findCallback(key);
	if (!callback) return {};
	return callback->threadEvent;
}

void CallbackRunner::makeLuaBindings(sol::state_view& lua, const std::string& tableName)
{
	auto t = lua[tableName].get_or_create<sol::table>();
	t["INFINITE"] = lua_indefinite;
	t["THREAD_REMOVED"] = lua_thread_removed;

	t["addCallback"] = [&](
		sol::object callable,
		std::optional<std::string> name,
		std::optional<CallbackRunner::Interval> interval,
		std::optional<CallbackRunner::Interval> delay) {
		return addCallback(callable, name, interval, delay);
	};
	t["removeCallback"] = [&](sol::object key) {
		return removeCallback(key);
	};
	t["callOnce"] = [&](
		sol::object callable,
		std::optional<CallbackRunner::Interval> delay) {
		return callOnce(callable, delay);
	};
	t["addCoroutine"] = [&](sol::object callable, std::optional<std::string> name, std::optional<Interval> delay) {
		return addCoroutine(callable, name, delay);
	};
	t["setCallbackTimeout"] = sol::overload(
		[&](sol::object o, indefinite_t indefinite) { return setCallbackTimeout(o, indefinite); },
		[&](sol::object o, Timestamp timestamp) { return setCallbackTimeout(o, timestamp); }
	);
	t["cancelCallbackTimeout"] = [&](sol::object callable) {
		return cancelCallbackTimeout(callable);
	};
	t["getThreadEvent"] = [&](sol::object key) {
		return getThreadEvent(key);
	};
	t["_initActionThread"] = [&](sol::thread th, sol::variadic_args va) {
		auto callback = findCallback(th);
		auto it = activeCallbacks.end();
		runThreadCallback(callback, std::get<sol::coroutine>(callback->callable), it, va);
	};
	t["getCallbackStatus"] = [&](sol::object key) -> std::optional<std::string> {
		auto callback = findCallback(key);
		if (!callback) return {};
		auto status = callback->status;
		if (status == Callback::Status::Active)
			return "active";
		if (status == Callback::Status::Idle)
			return "idle";
		if (status == Callback::Status::Suspended)
			return "suspended";
		return {};
	};
}

CallbackRunner::Timestamp CallbackRunner::update()
{

	std::unordered_set<Callback*> visited;

	debug("------------------------------------------");
	debug("Begin of update pass");

	while (true) {

		debug("Visited: {}, total: {}", visited.size(), activeCallbacks.size());

		auto it = activeCallbacks.begin();
		if (it == activeCallbacks.end())
			break;

		if (visited.size() == activeCallbacks.size())
			break;

		const size_t deadline = it->first;
		const size_t timestamp = elapsedTime();

		if (deadline > timestamp) {
			break;
		}

		std::shared_ptr<Callback> callback = it->second;

		if (visited.find(callback.get()) != visited.end()) {
			break;
		}

		auto& callable = callback->callable;

		auto maybeNewDeadline = timestamp + callback->interval;

		currentCallback = callback.get();
		callback->status = Callback::Status::Active;
		if (callback->callable.index() == 0) {
			auto& f = std::get<sol::main_protected_function>(callable);
			runFuncCallback(f, timestamp, f);
		} else {
			auto& co = std::get<sol::coroutine>(callable);
			runThreadCallback(callback, co, it, timestamp, callback->functionOrThread);
		}

		if (callback->runOnce) {
			sol::state_view lua(callback->functionOrThread.lua_state());
			actuallyRemoveCallback(lua, callback, it);
			continue;
		}

		if (callback->status == Callback::Status::Removed 
			|| callback->deadline == INDEFINITE) {
			continue;
		}

		visited.insert(callback.get());

		if (callback->deadline == deadline)
			callback->deadline = maybeNewDeadline;

		auto nh = activeCallbacks.extract(it);
		nh.key() = callback->deadline;
		activeCallbacks.insert(std::move(nh));
	}

	currentCallback = nullptr;

	auto nextUpdate = activeCallbacks.empty() ? INDEFINITE : activeCallbacks.begin()->first;

	debug(
		"End of update pass, next update: {}, wait: {}",
		nextUpdate == INDEFINITE ? "INDEFINITE" : std::to_string(nextUpdate),
		nextUpdate == INDEFINITE ? "-" : std::to_string(nextUpdate > elapsedTime() ? nextUpdate - elapsedTime() : 0)
	);
	debug("------------------------------------------");

	return nextUpdate;
}

bool CallbackRunner::Callback::isFunction()
{
	return callable.index() == 0;
}
