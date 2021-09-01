#pragma once
#include <sol/sol.hpp>
#include "Copilot.h"
#include <thread>
#include "KeyBindManager.h"
#include "JoystickManager.h"
#include <unordered_map>
#include <variant>
#include <setjmp.h>
#include <filesystem>
#include <atomic>

class LuaTextMenu;

class LuaPlugin {

	friend class CallbackRunner;

	LuaPlugin(const std::string&, std::shared_ptr<std::recursive_mutex>);

	static std::recursive_mutex globalMutex;
	
	struct ScriptInst {
		std::string path;
		LuaPlugin* script = nullptr;
		size_t scriptID;
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


	bool loggingEnabled = true;

	static bool arePathsEqual(const std::filesystem::path& lhs, const std::filesystem::path& rhs);

protected:
	std::shared_ptr<spdlog::logger> printLogger = copilot::logger;

	virtual void onLuaStateInitialized();

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

	std::string path;
	std::string logName;

	HANDLE shutdownEvent = CreateEvent(0, 0, 0, 0);

	virtual void initLuaState(sol::state_view lua);

	void yeetLuaThread();

	static void onError(sol::error&);
	static void onError(const ScriptStartupError&);

	virtual void run();

	virtual void stopThread();

public:

	const size_t scriptID;
	void launchThread();
	sol::state lua;

	template<typename T>
	static T* launchScript(const std::string& path, bool doLaunch = true)
	{
		std::unique_lock<std::recursive_mutex> globalLock(globalMutex);
		
		std::string _path = path;

		std::filesystem::path fsp(path);
		if (fsp.is_relative()) {
			_path = copilot::appDir + "scripts\\" + path;
		}

		auto it = std::find_if(scripts.begin(), scripts.end(), [&] (ScriptInst& s) {
			return arePathsEqual(s.path, _path);
		});

		auto launch = [&](ScriptInst& s) {
			std::lock_guard<std::recursive_mutex> lock(*s.mutex);
			auto oldScript = s.script;
			s.script = nullptr;
			globalLock.unlock();
			delete oldScript;
			auto script = new T(_path, s.mutex);
			s.script = script;
			s.scriptID = script->scriptID;
			if (doLaunch)
				s.script->launchThread();
			return script;
		};

		if (it == scripts.end()) {
			auto path = std::filesystem::path(_path).parent_path().string() + "\\";
			AddDllDirectory(std::wstring(path.begin(), path.end()).c_str());
			return launch(scripts.emplace_back(ScriptInst{_path}));
		} else {
			return launch(*it);
		}
	}

	void disableLogging();

	size_t elapsedTime() const;

	template<typename F, typename... Args>
	static void callProtectedFunction(F&& onValid, sol::protected_function func, Args&&... args)
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
	static sol::protected_function_result callProtectedFunction(sol::protected_function func, Args&&... args)
	{
		sol::protected_function_result pfr = func(std::forward<Args>(args)...);
		if (!pfr.valid()) {
			sol::error err = pfr;
			onError(err);
		}
		return pfr;
	}

	template<typename T, typename Pred>
	static bool withScript(std::function<void(T&)> block, Pred pred)
	{
		std::unique_lock<std::recursive_mutex> globalLock(globalMutex);
		auto it = std::find_if(scripts.begin(), scripts.end(), pred);
		if (it == scripts.end()) return false;
		auto& inst = *it;
		std::lock_guard<std::recursive_mutex> lock(*inst.mutex);
		globalLock.unlock();
		if (inst.script && pred(inst)) {
			if (T* script = dynamic_cast<T*>(inst.script)) {
				block(*script);
				return true;
			}
		}
		return false;
	}

	template<typename T>
	static bool withScript(const std::string& path, std::function<void(T&)> block)
	{
		return withScript<T>(block, [&](ScriptInst& s) {return arePathsEqual(path, s.path);});
	}

	template<typename T>
	static bool withScript(size_t scriptID, std::function<void(T&)> block)
	{
		return withScript<T>(block, [&](ScriptInst& s) {return s.scriptID == scriptID; });
	}

	static void stopScript(const std::string& path);

	static void stopAllScripts();
	static void sendShutDownEvents();

	virtual ~LuaPlugin() = 0;
};

