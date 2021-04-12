#pragma once
#include <sol/sol.hpp>
#include <thread>
#include "KeyBindManager.h"
#include "JoystickManager.h"
#include <unordered_map>
#include <variant>
#include <setjmp.h>
#include <atomic>

class LuaPlugin {

	LuaPlugin(const std::string&, std::shared_ptr<std::recursive_mutex>);

	static std::mutex globalMutex;

	struct ScriptInst {
		std::string path;
		LuaPlugin* script = nullptr;
		std::shared_ptr<std::recursive_mutex> mutex = std::make_shared<std::recursive_mutex>();
	};

	jmp_buf jumpBuff;

	std::atomic_bool running = true;

	static void hookFunc(lua_State* L, lua_Debug*);

	static std::vector<ScriptInst> scripts;

	using SessionVariable = std::variant<sol::nil_t, double, std::string, bool>;

	static std::mutex sessionVariableMutex;

	static SessionVariable getSessionVariable(const std::string&);

	static void setSessionVariable(const std::string&, SessionVariable);

	static std::unordered_map<std::string, SessionVariable> sessionVariables;


protected:

	std::atomic<DWORD> luaThreadId = 0;

	const std::shared_ptr<std::recursive_mutex> scriptMutex;

	struct ScriptStartupError : public std::exception {
		std::string _what;
	public:
		ScriptStartupError(const std::string&);
		ScriptStartupError(const sol::protected_function_result& pfr);
		const char* what() const override;
	};

	const size_t SHUTDOWN_TIMEOUT = 10000;

	

	std::chrono::time_point<std::chrono::high_resolution_clock> startTime = std::chrono::high_resolution_clock::now();

	std::thread thread;
	sol::state lua;

	std::string path;
	std::string logName;

	HANDLE shutdownEvent = CreateEvent(0, 0, 0, 0);

	virtual void initLuaState(sol::state_view lua);

	void yeetLuaThread();

	void onError(sol::error&);
	void onError(const ScriptStartupError&);

	virtual void run();

	virtual void stopThread();

	void launchThread();

public:

	template<typename T>
	static void launchScript(const std::string& path)
	{
		std::unique_lock<std::mutex> globalLock(globalMutex);
		auto it = std::find_if(scripts.begin(), scripts.end(), [&] (ScriptInst& s) {
			return s.path == path;
		});

		auto launch = [&](ScriptInst& s) {
			std::lock_guard<std::recursive_mutex> lock(*s.mutex);
			globalLock.unlock();
			try {
				delete s.script;
			} catch (...) {}
			s.script = new T(path, s.mutex);
			s.script->launchThread();
		};

		if (it == scripts.end()) {
			launch(scripts.emplace_back(ScriptInst{ path }));
		} else {
			launch(*it);
		}
	}

	size_t elapsedTime();

	template<typename F, typename... Args>
	void callProtectedFunction(F&& onValid, sol::protected_function func, Args&&... args)
	{
		sol::protected_function_result pfr = func(std::forward<Args>(args)...);
		if (!pfr.valid()) {
			sol::error err = pfr;
			onError(err);
		} else {
			onValid(pfr);
		}
	}

	template<typename... Args>
	sol::protected_function_result callProtectedFunction(sol::protected_function func, Args&&... args)
	{
		sol::protected_function_result pfr = func(std::forward<Args>(args)...);
		if (!pfr.valid()) {
			sol::error err = pfr;
			onError(err);
		}
		return pfr;
	}

	template<typename T, typename Pred>
	static void withScript(std::function<void(T&)> block, Pred pred)
	{
		std::unique_lock<std::mutex> globalLock(globalMutex);
		auto it = std::find_if(scripts.begin(), scripts.end(), pred);
		if (it == scripts.end()) return;
		auto& inst = *it;
		std::lock_guard<std::recursive_mutex> lock(*inst.mutex);
		globalLock.unlock();
		if (inst.script) {
			if (T* script = dynamic_cast<T*>(inst.script)) {
				block(*script);
			}
		}
	}

	template<typename T>
	static void withScript(const std::string& path, std::function<void(T&)> block)
	{
		withScript<T>(block, [&](ScriptInst& s) {return s.path == path;});
	}

	template<typename T>
	static void withScript(T* pScript, std::function<void(T&)> block)
	{
		withScript<T>(block, [&](ScriptInst& s) {return s.script == pScript; });
	}

	static void stopScript(const std::string& path);

	static void stopAllScripts();
	static void sendShutDownEvents();

	virtual ~LuaPlugin() = 0;
};

