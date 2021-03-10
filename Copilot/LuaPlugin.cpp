
#include "LuaPlugin.h"
#include "SimInterface.h"
#include "Copilot.h"
#include "FSUIPC.h"
#include "HttpSession.h"
#include "Joystick.h"
#include "Button.h"
#include "MCDU.h"
#include "lfs.h"
#include "Keyboard.h"
#include "lua.hpp"
#include <optional>
#include <string_view>

const char* YEET_THIS_THREAD = "\xF0\x9F\x92\xA9";

std::unordered_map<lua_State*, std::atomic_bool> runningFlags;
std::mutex runningFlagsMutex;

std::vector<LuaPlugin::ScriptInst> LuaPlugin::scripts;
std::mutex LuaPlugin::globalMutex;

std::mutex LuaPlugin::sessionVariableMutex;
std::unordered_map<std::string, LuaPlugin::SessionVariable> LuaPlugin::sessionVariables;

LuaPlugin::ScriptStartupError::ScriptStartupError(const std::string& what)
	:_what("Script startup error: " + what) { }

LuaPlugin::ScriptStartupError::ScriptStartupError(const sol::protected_function_result& pfr)
{
	sol::error err = pfr;
	_what = std::string("Script startup error: ") + err.what();
}

const char* LuaPlugin::ScriptStartupError::what() const { return _what.c_str(); }

LuaPlugin::LuaPlugin(const std::string& path, std::shared_ptr<std::recursive_mutex> mutex)
	: path(path), scriptMutex(mutex)
{
	if (path.find(copilot::appDir) == 0) 
		logName = path.substr(path.find("Copilot for FSLabs"));
	else 
		logName = path;
}

LuaPlugin::SessionVariable LuaPlugin::getSessionVariable(const std::string& name)
{
	std::lock_guard<std::mutex> lock(sessionVariableMutex);
	auto& value = sessionVariables[name];
	if (value.index() == 3) {
		return static_cast<double>(std::get<bool>(value));
	}
	return value;
}

void LuaPlugin::setSessionVariable(const std::string& name, SessionVariable value)
{
	std::lock_guard<std::mutex> lock(sessionVariableMutex);
	sessionVariables[name] = value;
}

bool LuaPlugin::callLuaFunction(sol::protected_function func)
{
	sol::protected_function_result res = func();
	if (!res.valid()) {
		sol::error err = res;
		onError(err);
		return false;
	}
	return true;
}

int readSTR(lua_State* L)
{
	std::lock_guard<std::mutex> lock(FSUIPC::mutex);
	size_t offset = lua_tointeger(L, 1);
	size_t length = lua_tointeger(L, 2);
	char* buff = new char[length]();
	DWORD result = 0;
	FSUIPC_Read(offset, length, buff, &result);
	FSUIPC_Process(&result);
	lua_pushlstring(L, buff, length);
	delete[] buff;
	return 1;
};

void LuaPlugin::hookFunc(lua_State* L, lua_Debug*)
{
	lua_pushstring(L, "isRunning");
	lua_gettable(L, LUA_REGISTRYINDEX);
	auto& isRunning = *reinterpret_cast<std::atomic_bool*>(lua_touserdata(L, -1));
#ifdef DEBUG
	//copilot::logger->trace("hookFunc called, isRunning: {}", isRunning);
#endif
	if (!isRunning) {
		lua_pushstring(L, "jmpBuff");
		lua_gettable(L, LUA_REGISTRYINDEX);
		auto jumpBuff = reinterpret_cast<jmp_buf*>(lua_touserdata(L, -1));
		longjmp(*jumpBuff, true);
	}
}

void LuaPlugin::initLuaState(sol::state_view lua)
{
	lua_sethook(lua.lua_state(), &hookFunc, LUA_MASKCOUNT, 1337);

	lua_pushstring(lua.lua_state(), "isRunning");
	lua_pushlightuserdata(lua.lua_state(), &running);

	lua_settable(lua.lua_state(), LUA_REGISTRYINDEX);

	lua_pushstring(lua.lua_state(), "jmpBuff");
	lua_pushlightuserdata(lua.lua_state(), &jumpBuff);

	lua_settable(lua.lua_state(), LUA_REGISTRYINDEX);

	lua["print"] = [this](sol::variadic_args va) {
		std::string str;
		for (size_t i = 0; i < va.size(); i++) {
			auto v = va[i];
			str += this->lua["tostring"](v.get<sol::object>());
			if (i != va.size() - 1) {
				str += " ";
			}
		}
		copilot::logger->info(str);
	};

	lua["hideCursor"] = SimInterface::hideCursor;
	auto ipc = lua.create_table();

	ipc["mousemacro"] = SimInterface::fireMouseMacro;

	using namespace FSUIPC;

	ipc["exit"] = [&] { yeetLuaThread(); };

	ipc["writeUB"] = write<uint8_t>;
	ipc["readUB"] = read<uint8_t>;

	ipc["writeSB"] = write<int8_t>;
	ipc["readSB"] = read<int8_t>;

	ipc["writeUW"] = write<uint16_t>;
	ipc["readUW"] = read<uint16_t>;

	ipc["writeSW"] = write<int16_t>;
	ipc["readSW"] = read<int16_t>;

	ipc["writeUD"] = write<uint32_t>;
	ipc["readUD"] = read<uint32_t>;

	ipc["writeSD"] = write<int32_t>;
	ipc["readSD"] = read<int32_t>;

	ipc["writeDD"] = write<int64_t>;
	ipc["readDD"] = read<int64_t>;

	ipc["writeFLT"] = write<float>;
	ipc["readFLT"] = read<float>;

	ipc["writeDBL"] = write<double>;
	ipc["readDBL"] = read<double>;

	ipc["writeSTR"] = sol::overload(
		static_cast<void(*)(DWORD, const std::string&, size_t)>(&writeSTR),
		static_cast<void(*)(DWORD, const std::string&)>(&writeSTR)
	);
	ipc["readSTR"] = &::readSTR;

	ipc["createLvar"] = sol::overload(
		[](const std::string& str, double init) { SimInterface::createLvar(str, init); },
		[](const std::string& str) { SimInterface::createLvar(str); }
	);

	ipc["readLvar"] = SimInterface::readLvar;
	ipc["writeLvar"] = SimInterface::writeLvar;

	ipc["get"] = &getSessionVariable;
	ipc["set"] = &setSessionVariable;

	ipc["sleep"] = [&] (size_t ms) {
		if (WaitForSingleObject(shutdownEvent, ms) == WAIT_OBJECT_0)
			yeetLuaThread();
	};

	ipc["log"] = lua["print"];

	ipc["elapsedtime"] = [this] {
		return std::chrono::duration_cast<std::chrono::milliseconds>(
			std::chrono::high_resolution_clock::now() - startTime
		).count();
	};

	ipc["control"] = sol::overload(
		[](size_t id, size_t param) { SimInterface::sendFSControl(id, param); },
		[](size_t id) { SimInterface::sendFSControl(id); }
	); 

	lua["ipc"] = ipc;
	lua["package"]["path"] = copilot::appDir + "?.lua";
	lua["package"]["cpath"] = copilot::appDir + "?.dll";

	lua["_COPILOT"] = true;

	luaopen_lfs(lua.lua_state());

	auto HttpSessionType = lua.new_usertype<HttpSession>("HttpSession",
														 sol::constructors<HttpSession(const std::wstring&, unsigned int)>());
	HttpSessionType["get"] = &HttpSession::makeRequest;
	HttpSessionType["lastError"] = &HttpSession::lastError;

	auto McduSessionType = lua.new_usertype<MCDU>("MCDUsession",
										   sol::constructors<MCDU(unsigned int, unsigned int, unsigned int)>());

	McduSessionType["getString"] = &MCDU::getString;
	McduSessionType["getRaw"] = &MCDU::getRaw;
	McduSessionType["lastError"] = &MCDU::lastError;

	sol::protected_function_result res = lua.safe_script(R"(FSL = require "FSL2Lua.FSL2Lua.FSL2Lua")");
	if (!res.valid()) 
		throw ScriptStartupError(res);
}

void LuaPlugin::yeetLuaThread()
{
	longjmp(jumpBuff, true);
}

void LuaPlugin::onError(sol::error& err)
{
	copilot::logger->error(err.what());
}

void LuaPlugin::onError(const ScriptStartupError& err)
{
	copilot::logger->error(err.what());
}

void LuaPlugin::run()
{
	lua = sol::state();
	lua.open_libraries();
	try {
		initLuaState(lua);
	}
	catch (std::exception& ex) {
		throw ScriptStartupError(ex.what());
	}
	auto res = lua.do_file(path);
	if (!res.valid()) 
		throw ScriptStartupError(res);
}

void LuaPlugin::stopScript(const std::string& path)
{
	std::unique_lock<std::mutex> globalLock(globalMutex);
	auto it = std::find_if(scripts.begin(), scripts.end(), [&](ScriptInst& s) {
		return s.path == path;
	});
	auto& inst = *it;
	std::lock_guard<std::recursive_mutex> lock(*inst.mutex);
	globalLock.unlock();
	delete inst.script;
	inst.script = nullptr;
}

void LuaPlugin::stopAllScripts()
{
	std::unique_lock<std::mutex> globalLock(globalMutex);
	for (auto& s : scripts) {
		std::lock_guard<std::recursive_mutex> lock(*s.mutex);
		delete s.script;
	}
}

void LuaPlugin::stopThread()
{
	if (thread.joinable()) {
		running = false;
		SetEvent(shutdownEvent);
		thread.join();
	}
}

void LuaPlugin::launchThread()
{
	if (thread.joinable())
		stopThread();

	thread = std::thread([this] {
		copilot::logger->info("### '{}': Launching new thread!", logName);
		try {
			running = true;
			if (!setjmp(jumpBuff)) run();
		}
		catch (ScriptStartupError& ex) {
			onError(ex);
		}
		catch (std::exception& ex) {
			copilot::logger->error("Unknown exception occured: '{}'", ex.what());
		}
		catch (...) {
			copilot::logger->error("Caught (...) exception");
		};
		copilot::logger->info("### '{}': Thread finished!", logName);
	});
}

LuaPlugin::~LuaPlugin()
{
	if (thread.joinable())
		stopThread();
}