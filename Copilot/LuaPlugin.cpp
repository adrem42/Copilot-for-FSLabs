
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

const char* REG_KEY_JMP_BUFF = "JMPBUFF";
const char* REG_KEY_IS_RUNNING = "IS_RUNNING";

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

const std::string TYPE_NONE = "";

template<typename T>
size_t writeNoProcess(size_t offset, T value)
{
	std::lock_guard<std::mutex> lock(FSUIPC::mutex);
	DWORD result;
	FSUIPC_Write(offset, sizeof(T), &value, &result);
	return sizeof(T);
}

std::unordered_set<std::string> fsuipcTypes {
	"STR", "UB", "SB", "UW", "SW", "UD", "SD", "DD", "FLT", "DBL"
};

void parseWriteStructArgs(sol::variadic_args& va, size_t offset, size_t idx, size_t numValues, const std::string& type)
{
	if (idx == va.size()) {
		std::lock_guard<std::mutex> lock(FSUIPC::mutex);
		DWORD res;
		FSUIPC_Process(&res);
		return;
	}

	if (type == TYPE_NONE) {

		if (va[idx].get_type() == sol::type::number)
			return parseWriteStructArgs(va, va.get<size_t>(idx), idx + 1, 0, TYPE_NONE);
		std::string typeOrOffset = va.get<std::string>(idx);
		if (offset) {
			std::string::iterator it = std::find_if(typeOrOffset.begin(), typeOrOffset.end(), [](char c) {return std::isalpha(c); });
			if (it != typeOrOffset.end()) {
				auto typeIdx = it - typeOrOffset.begin();
				auto size = std::stoi(typeOrOffset.substr(0, typeIdx));
				auto type = typeOrOffset.substr(typeIdx, typeOrOffset.size() - typeIdx);
				if (fsuipcTypes.find(type) != fsuipcTypes.end())
					return parseWriteStructArgs(va, offset, idx + 1, size, type);
			}
		}
		return parseWriteStructArgs(va, std::stoul(typeOrOffset, nullptr, 16), idx + 1, 0, TYPE_NONE);
	} else {
		if (type == "STR") {
			DWORD result;
			std::string str = va.get<std::string>(idx);
			{
				std::lock_guard<std::mutex> lock(FSUIPC::mutex);
				FSUIPC_Write(offset, numValues, const_cast<char*>(str.c_str()), &result);
			}
			offset += numValues;
			return parseWriteStructArgs(va, offset, idx + 1, 0, TYPE_NONE);
		} else if (type == "UB") {
			offset += writeNoProcess(offset, va.get<uint8_t>(idx));
		} else if (type == "SB") {
			offset += writeNoProcess(offset, va.get<int8_t>(idx));
		} else if (type == "UW") {
			offset += writeNoProcess(offset, va.get<uint16_t>(idx));
		} else if (type == "SW") {
			offset += writeNoProcess(offset, va.get<int16_t>(idx));
		} else if (type == "UD") {
			offset += writeNoProcess(offset, va.get<uint32_t>(idx));
		} else if (type == "SD") {
			offset += writeNoProcess(offset, va.get<int32_t>(idx));
		} else if (type == "DD") {
			offset += writeNoProcess(offset, va.get<int64_t>(idx));
		} else if (type == "FLT") {
			offset += writeNoProcess(offset, va.get<float>(idx));
		} else if (type == "DBL") {
			offset += writeNoProcess(offset, va.get<double>(idx));
		} else {
			throw "Invalid format";
		}
		numValues--;
		if (numValues == 0) {
			return parseWriteStructArgs(va, offset, idx + 1, 0, TYPE_NONE);
		}
		return parseWriteStructArgs(va, offset, idx + 1, numValues, type);
	}
}

void writeStruct(sol::variadic_args va)
{
	parseWriteStructArgs(va, 0, 0, 0, TYPE_NONE);
}

void keypress(SHORT keyCode, std::vector<SHORT>&& modifiers)
{
	SetFocus(SimInterface::p3dWnd);

	size_t numInputs = modifiers.size() + 1;
	INPUT* inputs = new INPUT[numInputs]();

	for (size_t i = 0; i < modifiers.size(); ++i) {
		auto& ip = inputs[i];
		ip.type = INPUT_KEYBOARD;
		ip.ki.wVk = modifiers[i];
	}

	auto& i = inputs[numInputs - 1];

	i.ki.wVk = keyCode;
	i.type = INPUT_KEYBOARD;

	SendInput(numInputs, inputs, sizeof(INPUT));

	for (size_t i = 0; i < numInputs; ++i) {
		inputs[i].ki.dwFlags = KEYEVENTF_KEYUP;
	}

	SendInput(1, inputs + numInputs - 1, sizeof(INPUT));
	SendInput(numInputs - 1, inputs, sizeof(INPUT));

}

LuaPlugin::LuaPlugin(const std::string& path, std::shared_ptr<std::recursive_mutex> mutex)
	: path(path), scriptMutex(mutex)
{
	if (path.find(copilot::appDir) == 0) 
		logName = path.substr(path.find("Copilot for FSLabs"));
	else 
		logName = path;
	lua = sol::state();
	lua.open_libraries();
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
	lua_pushstring(L, REG_KEY_IS_RUNNING);
	lua_gettable(L, LUA_REGISTRYINDEX);
	auto& isRunning = *reinterpret_cast<std::atomic_bool*>(lua_touserdata(L, -1));
	if (!isRunning) {
		lua_pushstring(L, REG_KEY_JMP_BUFF);
		lua_gettable(L, LUA_REGISTRYINDEX);
		jmp_buf& jumpBuff = *reinterpret_cast<jmp_buf*>(lua_touserdata(L, -1));
		longjmp(jumpBuff, true);
	}
}

void LuaPlugin::initLuaState(sol::state_view lua)
{
	AttachThreadInput(GetCurrentThreadId(), GetWindowThreadProcessId(SimInterface::p3dWnd, NULL), TRUE);
	lua_sethook(lua.lua_state(), &hookFunc, LUA_MASKCOUNT, 1337);
	lua_pushstring(lua.lua_state(), REG_KEY_IS_RUNNING);
	lua_pushlightuserdata(lua.lua_state(), &running);

	lua_settable(lua.lua_state(), LUA_REGISTRYINDEX);

	lua_pushstring(lua.lua_state(), REG_KEY_JMP_BUFF);
	lua_pushlightuserdata(lua.lua_state(), &jumpBuff);

	lua_settable(lua.lua_state(), LUA_REGISTRYINDEX);

	lua["copilot"].get_or_create<sol::table>();
	lua["copilot"]["keypress"] = [&](sol::this_state ts, const std::string& s) {
		sol::state_view lua(ts);
		sol::unsafe_function f = lua["Bind"]["parseKeys"];
		sol::unsafe_function_result ufr = f(s);
		keypress(ufr.get<SHORT>(0), ufr.get<std::vector<SHORT>>(1));
	};
	lua["copilot"]["isSimRunning"] = copilot::simRunning();

	std::unordered_map<std::string, SIMCONNECT_TEXT_TYPE>  textColors = {

		{"print_black",		SIMCONNECT_TEXT_TYPE_PRINT_BLACK },
		{"print_white",		SIMCONNECT_TEXT_TYPE_PRINT_WHITE},
		{"print_red",		SIMCONNECT_TEXT_TYPE_PRINT_RED},
		{"print_green",		SIMCONNECT_TEXT_TYPE_PRINT_GREEN},
		{"print_blue",		SIMCONNECT_TEXT_TYPE_PRINT_BLUE},
		{"print_yellow",	SIMCONNECT_TEXT_TYPE_PRINT_YELLOW},
		{"print_magenta",	SIMCONNECT_TEXT_TYPE_PRINT_MAGENTA},
		{"print_cyan",		SIMCONNECT_TEXT_TYPE_PRINT_CYAN},

		{"scroll_black",	SIMCONNECT_TEXT_TYPE_SCROLL_BLACK },
		{"scroll_white",	SIMCONNECT_TEXT_TYPE_SCROLL_WHITE},
		{"scroll_red",		SIMCONNECT_TEXT_TYPE_SCROLL_RED},
		{"scroll_green",	SIMCONNECT_TEXT_TYPE_SCROLL_GREEN},
		{"scroll_blue",		SIMCONNECT_TEXT_TYPE_SCROLL_BLUE},
		{"scroll_yellow",	SIMCONNECT_TEXT_TYPE_SCROLL_YELLOW},
		{"scroll_magenta",	SIMCONNECT_TEXT_TYPE_SCROLL_MAGENTA},
		{"scroll_cyan",		SIMCONNECT_TEXT_TYPE_SCROLL_CYAN},
	};

	lua["copilot"]["displayText"] = [textColors, EVENT_DISPLAY_TEXT = SimConnect::getUniqueEventID()](const std::string& s, std::optional<size_t> length, std::optional<std::string> type) {

		SIMCONNECT_TEXT_TYPE simconnectType;

		if (type) {
			auto it = textColors.find(*type);
			if (it == textColors.end())
				throw("Invalid text type: " + *type);
			simconnectType = it->second;
		} else {
			simconnectType = SIMCONNECT_TEXT_TYPE_PRINT_WHITE;
		}

		SimConnect_Text(
			SimConnect::hSimConnect,
			simconnectType,
			length.value_or(0),
			EVENT_DISPLAY_TEXT,
			s.length() + 1,
			const_cast<char*>(s.c_str())
		);
	};

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

	ipc["display"] = [](const std::string& s, std::optional<size_t> delay) {

		SimConnect_Text(
			SimConnect::hSimConnect,
			SIMCONNECT_TEXT_TYPE_MESSAGE_WINDOW,
			delay.value_or(0),
			-1,
			s.length() + 1,
			const_cast<char*>(s.c_str())
		);
	};

	using namespace FSUIPC;

	ipc["exit"] = [&] { yeetLuaThread(); };

	ipc["writeStruct"] = writeStruct;

	ipc["writeUB"] = write<uint8_t>;
	ipc["prepareWriteUB"] = writeNoProcess<uint8_t>;
	ipc["readUB"] = read<uint8_t>;

	ipc["writeSB"] = write<int8_t>;
	ipc["prepareWriteSB"] = writeNoProcess<int8_t>;
	ipc["readSB"] = read<int8_t>;

	ipc["writeUW"] = write<uint16_t>;
	ipc["prepareWriteUW"] = writeNoProcess<uint16_t>;
	ipc["readUW"] = read<uint16_t>;

	ipc["writeSW"] = write<int16_t>;
	ipc["prepareWriteSW"] = writeNoProcess<int16_t>;
	ipc["readSW"] = read<int16_t>;

	ipc["writeUD"] = write<uint32_t>;
	ipc["prepareWriteUD"] = writeNoProcess<uint32_t>;
	ipc["readUD"] = read<uint32_t>;

	ipc["writeSD"] = write<int32_t>;
	ipc["prepareWriteSD"] = writeNoProcess<int32_t>;
	ipc["readSD"] = read<int32_t>;

	ipc["writeDD"] = write<int64_t>;
	ipc["prepareWriteDD"] = writeNoProcess<int64_t>;
	ipc["readDD"] = read<int64_t>;

	ipc["writeFLT"] = write<float>;
	ipc["prepareWriteFLT"] = writeNoProcess<float>;
	ipc["readFLT"] = read<float>;

	ipc["writeDBL"] = write<double>;
	ipc["prepareWriteDBL"] = writeNoProcess<double>;
	ipc["readDBL"] = read<double>;

	ipc["writeSTR"] = sol::overload(
		static_cast<void(*)(DWORD, const std::string&, size_t)>(&writeSTR),
		static_cast<void(*)(DWORD, const std::string&)>(&writeSTR)
	);

	ipc["process"] = [] {
		std::lock_guard<std::mutex> lock(FSUIPC::mutex);
		DWORD result;
		FSUIPC_Process(&result);
	};

	auto prepareWriteSTR = [](DWORD offset, const std::string& str, size_t length) {
		std::lock_guard<std::mutex> lock(FSUIPC::mutex);
		DWORD result;
		FSUIPC_Write(offset, length, const_cast<char*>(str.c_str()), &result);
	};

	ipc["prepareWriteSTR"] = sol::overload(
		prepareWriteSTR,
		[=] (DWORD offset, const std::string& str){prepareWriteSTR(offset, str, str.length());}
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

	auto sleep = [&](int32_t ms) {
		ms = std::max<int32_t>(15, ms);
		if (WaitForSingleObject(shutdownEvent, ms) == WAIT_OBJECT_0)
			yeetLuaThread();
	};

	ipc["sleep"] = sol::overload([=]() {sleep(1); }, sleep);

	ipc["log"] = lua["print"];

	ipc["elapsedtime"] = [this] { return elapsedTime(); };

	ipc["control"] = sol::overload(
		[](size_t id, size_t param) { SimInterface::sendFSControl(id, param); },
		[](size_t id) { SimInterface::sendFSControl(id); }
	); 

	lua["ipc"] = ipc;
	lua["package"]["path"] = copilot::appDir + "?.lua;" + copilot::appDir + "\\lua\\?.lua";
	lua["package"]["cpath"] = copilot::appDir + "?.dll;" + copilot::appDir + "\\lua\\?.dll";

	lua["_COPILOT"] = true;

	luaopen_lfs(lua.lua_state());

	lua["socket"] = lua.create_table();
	lua["mime"] = lua.create_table();

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
	if (copilot::simRunning())
		copilot::logger->error(err.what());
}

void LuaPlugin::onError(const ScriptStartupError& err)
{
	copilot::logger->error(err.what());
}

void LuaPlugin::run()
{
	try {
		initLuaState(lua);
	}
	catch (ScriptStartupError& err) {
		throw err;
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
		s.script = nullptr;
	}
}

void LuaPlugin::sendShutDownEvents()
{
	std::unique_lock<std::mutex> globalLock(globalMutex);
	for (auto& s : scripts) {
		std::lock_guard<std::recursive_mutex> lock(*s.mutex);
		s.script->running = false;
		SetEvent(s.script->shutdownEvent);
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
			luaThreadId = GetCurrentThreadId();
			running = true;
			if (!setjmp(jumpBuff)) run();
		}
		catch (ScriptStartupError& ex) {
			onError(ex);
		}
		catch (std::exception& ex) {
			copilot::logger->error("Exception: '{}'", ex.what());
		}
		catch (...) {
			copilot::logger->error("Caught (...) exception");
		};
		luaThreadId = 0;
		copilot::logger->info("### '{}': Thread finished!", logName);
	});
}

size_t LuaPlugin::elapsedTime()
{
	return std::chrono::duration_cast<std::chrono::milliseconds>(
		std::chrono::high_resolution_clock::now() - startTime
	).count();
}

LuaPlugin::~LuaPlugin()
{
	stopThread();
}