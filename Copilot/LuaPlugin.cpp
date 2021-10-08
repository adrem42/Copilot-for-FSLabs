
#include "LuaPlugin.h"
#include <filesystem>
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
#include "bass/bass.h"
#include "FSL2LuaControls/FSL2LuaControls.h"

const char* REG_KEY_JMP_BUFF = "JMPBUFF";
const char* REG_KEY_IS_RUNNING = "IS_RUNNING";

static std::atomic<size_t> currscriptID = 0;

std::vector<LuaPlugin::ScriptInst> LuaPlugin::scripts;
std::recursive_mutex LuaPlugin::globalMutex;

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

int KEYPRESS_TYPE_PRESS = 0;
int KEYPRESS_TYPE_RELEASE = 1;
int KEYPRESS_TYPE_PRESSRELEASE = 2;

void keypress(SHORT keyCode, std::vector<SHORT>&& modifiers, int type, bool extended)
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
	if (extended) {
		i.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
	}
	i.type = INPUT_KEYBOARD;

	if (type == KEYPRESS_TYPE_PRESS || type == KEYPRESS_TYPE_PRESSRELEASE) 
		SendInput(numInputs, inputs, sizeof(INPUT));
	
	if (type == KEYPRESS_TYPE_RELEASE || type == KEYPRESS_TYPE_PRESSRELEASE) {
		for (size_t i = 0; i < numInputs; ++i) 
			inputs[i].ki.dwFlags |= KEYEVENTF_KEYUP;
		SendInput(1, inputs + numInputs - 1, sizeof(INPUT));
		SendInput(numInputs - 1, inputs, sizeof(INPUT));
	}
}

LuaPlugin::LuaPlugin(const std::string& path, std::shared_ptr<std::recursive_mutex> mutex, std::shared_ptr<spdlog::logger>& logger, size_t launchCount)
	: path(path), scriptMutex(mutex), scriptID(currscriptID++), logger(logger), launchCount(launchCount)
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

bool LuaPlugin::arePathsEqual(const std::filesystem::path& lhs, const std::filesystem::path& rhs)
{
	std::error_code ec;
	return std::filesystem::equivalent(lhs, rhs, ec);
}

void LuaPlugin::onLuaStateInitialized()
{
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

	auto scriptDir = std::filesystem::path(path).parent_path().string() + "\\";

	lua["SCRIPT_PATH"] = path;
	lua["SCRIPT_DIR"] = scriptDir;
	lua["copilot"].get_or_create<sol::table>();
	lua["copilot"]["keypress"] = [&](sol::this_state ts, const std::string& s, sol::optional<int> type) {
		sol::state_view lua(ts);
		sol::unsafe_function f = lua["Bind"]["parseKeys"];
		sol::unsafe_function_result ufr = f(s);
		keypress(ufr.get<SHORT>(0), ufr.get<std::vector<SHORT>>(1), type.value_or(KEYPRESS_TYPE_PRESSRELEASE), ufr.get<bool>(2));
	};
	lua["copilot"]["sendKeyToFsWindow"] = [&](sol::this_state ts, const std::string& s, sol::optional<SimInterface::KeyEvent> event, sol::optional<int> flags) {
		sol::state_view lua(ts);
		sol::unsafe_function f = lua["Bind"]["parseKeys"];
		sol::unsafe_function_result ufr = f(s);
		if (!ufr.get<std::vector<SHORT>>(1).empty())
			throw "No modifiers allowed";
		SimInterface::sendKeyToSimWindow(ufr.get<SHORT>(0), event.value_or(SimInterface::KeyEvent::Press), flags.value_or(0));
	};
	lua["copilot"]["isSimRunning"] = &copilot::simRunning;

	lua["copilot"]["flags"] = [](sol::variadic_args va) {
		size_t flags = 0;
		for (size_t i = 0; i < va.leftover_count(); ++i) {
			flags != va.get<size_t>(i);
		}
		return flags;
	};

	auto devInfoType = lua.new_usertype<BASS_DEVICEINFO>("BASS_DEVICEINFO");
	devInfoType["name"] = &BASS_DEVICEINFO::name;
	devInfoType["flags"] = &BASS_DEVICEINFO::flags;
	devInfoType["driver"] = &BASS_DEVICEINFO::driver;
	
	lua["copilot"]["getSoundDevices"] = [] {
		BASS_DEVICEINFO info;
		std::vector<BASS_DEVICEINFO> devices;
		for (int i = 1; BASS_GetDeviceInfo(i, &info); i++) {
			devices.push_back(info);
		}
		return sol::as_table(devices);
	};

	auto Win32 = lua.create_table();
	lua["package"]["loaded"]["Win32"] = Win32;

	Win32["messageBox"] = [](std::string_view text, std::string_view caption, size_t type) {
		return MessageBoxA(NULL, text.data(), caption.data(), type);
	};

	Win32["IDABORT"] = IDABORT;
	Win32["IDABORT"] = IDCANCEL;
	Win32["IDABORT"] = IDCONTINUE;
	Win32["IDABORT"] = IDIGNORE;
	Win32["IDABORT"] = IDNO;
	Win32["IDABORT"] = IDOK;
	Win32["IDABORT"] = IDRETRY;
	Win32["IDABORT"] = IDTRYAGAIN;
	Win32["IDABORT"] = IDYES;

	Win32["MB_ABORTRETRYIGNORE"] = MB_ABORTRETRYIGNORE;
	Win32["MB_CANCELTRYCONTINUE"] = MB_CANCELTRYCONTINUE;
	Win32["MB_HELP"] = MB_HELP;
	Win32["MB_OK"] = MB_OK;
	Win32["MB_OKCANCEL"] = MB_OKCANCEL;
	Win32["MB_RETRYCANCEL"] = MB_RETRYCANCEL;
	Win32["MB_YESNO"] = MB_YESNO;
	Win32["MB_YESNOCANCEL"] = MB_YESNOCANCEL;
	Win32["MB_ICONEXCLAMATION"] = MB_ICONEXCLAMATION;
	Win32["MB_ICONWARNING"] = MB_ICONWARNING;
	Win32["MB_ICONINFORMATION"] = MB_ICONINFORMATION;
	Win32["MB_ICONASTERISK"] = MB_ICONASTERISK;
	Win32["MB_ICONQUESTION"] = MB_ICONQUESTION;
	Win32["MB_ICONSTOP"] = MB_ICONSTOP;
	Win32["MB_ICONERROR"] = MB_ICONERROR;
	Win32["MB_ICONHAND"] = MB_ICONHAND;
	Win32["MB_DEFBUTTON1"] = MB_DEFBUTTON1;
	Win32["MB_DEFBUTTON2"] = MB_DEFBUTTON2;
	Win32["MB_DEFBUTTON3"] = MB_DEFBUTTON3;
	Win32["MB_DEFBUTTON4"] = MB_DEFBUTTON4;
	Win32["MB_APPLMODAL"] = MB_APPLMODAL;
	Win32["MB_SYSTEMMODAL"] = MB_SYSTEMMODAL;
	Win32["MB_TASKMODAL"] = MB_TASKMODAL;
	Win32["MB_DEFAULT_DESKTOP_ONLY"] = MB_DEFAULT_DESKTOP_ONLY;
	Win32["MB_RIGHT"] = MB_RIGHT;
	Win32["MB_RTLREADING"] = MB_RTLREADING;
	Win32["MB_SETFOREGROUND"] = MB_SETFOREGROUND;
	Win32["MB_TOPMOST"] = MB_TOPMOST;
	Win32["MB_SERVICE_NOTIFICATION"] = MB_SERVICE_NOTIFICATION;

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
		logger->info(str);
	};

	lua["suppressCursor"] = SimInterface::suppressCursor;
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

	lua["Logic"] = lua.create_table();

	lua["Logic"]["And"] = [](uint32_t y, uint32_t z) {
		return y & z;
	};

	lua["Logic"]["Nand"] = [](uint32_t y, uint32_t z) {
		return (~y) | (~z);
	};

	lua["Logic"]["Nor"] = [](uint32_t y, uint32_t z) {
		return (~y) & (~z);
	};

	lua["Logic"]["Not"] = [](uint32_t y) {
		return ~y;
	};

	lua["Logic"]["Or"] = [](uint32_t y, uint32_t z) {
		return y | z;
	};
	
	lua["Logic"]["Shl"] = [](uint32_t y, uint32_t n) {
		return y << n;
	};

	lua["Logic"]["Shr"] = [](uint32_t y, uint32_t n) {
		return y >> n;
	};

	lua["Logic"]["Xor"] = [](uint32_t y, uint32_t z) {
		return y xor z;
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
	lua["package"]["path"] = 
		copilot::appDir + "?.lua;" + 
		copilot::appDir + "\\lua\\?.lua;" + 
		copilot::appDir + "\\Copilot\\?.lua;" +
		scriptDir + "?.lua";
	lua["package"]["cpath"] = copilot::appDir + "?.dll;" + copilot::appDir + "\\lua\\?.dll";

	lua["APPDIR"] = copilot::appDir;

	lua["_COPILOT"] = true;

	luaopen_lfs(lua.lua_state());

	lua["socket"] = lua.create_table();
	lua["mime"] = lua.create_table();

	auto HttpSessionType = lua.new_usertype<HttpSession>("HttpSession",
														 sol::constructors<HttpSession(const std::wstring&, unsigned int)>());
	HttpSessionType["get"] = &HttpSession::makeRequest;
	HttpSessionType["lastError"] = &HttpSession::lastError;
	HttpSessionType["setPath"] = &HttpSession::setPath;

	auto McduSessionType = lua.new_usertype<MCDU>("MCDUsession",
										   sol::constructors<MCDU(unsigned int, unsigned int, unsigned int)>());

	McduSessionType["getString"] = &MCDU::getString;
	McduSessionType["getRaw"] = &MCDU::getRaw;
	McduSessionType["lastError"] = &MCDU::lastError;

	lua["package"]["preload"]["FSL2Lua.FSL2Lua.invokeControl"] = [] {return FSL2LuaControls::invokeControl; };

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
		logger->error(err.what());
}

void LuaPlugin::onError(const ScriptStartupError& err)
{
	logger->error(err.what());
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
	onLuaStateInitialized();
}

void LuaPlugin::stopScript(const std::string& path)
{
	std::unique_lock<std::recursive_mutex> globalLock(globalMutex);

	std::filesystem::path fsp(path);
	if (fsp.is_relative()) {
		fsp = (copilot::appDir + "scripts\\") / fsp;
	}

	if (!fsp.has_extension()) {
		fsp /= "init.lua";
	}

	auto it = std::find_if(scripts.begin(), scripts.end(), [&](ScriptInst& s) {
		return arePathsEqual(s.path, fsp);
	});
	if (it == scripts.end()) return;

	auto& inst = *it;
	globalLock.unlock();
	std::lock_guard<std::recursive_mutex> lock(*inst.mutex);
	delete inst.script;
	inst.script = nullptr;
}

void LuaPlugin::stopAllScripts()
{
	std::unique_lock<std::recursive_mutex> globalLock(globalMutex);
	for (auto& s : scripts) {
		std::lock_guard<std::recursive_mutex> lock(*s.mutex);
		delete s.script;
		s.script = nullptr;
	}
}

void LuaPlugin::sendShutDownEvents()
{
	std::unique_lock<std::recursive_mutex> globalLock(globalMutex);
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
		if (loggingEnabled)
			logger->info("### {} ({}) Launching new thread!", logName, launchCount );
		try {
			running = true;
			if (!setjmp(jumpBuff)) run();
		}
		catch (ScriptStartupError& ex) {
			onError(ex);
		}
		catch (std::exception& ex) {
			logger->error("Exception: '{}'", ex.what());
		}
		catch (...) {
			logger->error("Caught (...) exception");
		};
		if (loggingEnabled)
			logger->info("### {} ({}) Thread finished!", logName, launchCount);
	});
}

void LuaPlugin::disableLogging()
{
	loggingEnabled = false;
}

size_t LuaPlugin::elapsedTime() const
{
	return std::chrono::duration_cast<std::chrono::milliseconds>(
		std::chrono::high_resolution_clock::now() - startTime
	).count();
}

LuaPlugin::~LuaPlugin()
{
	stopThread();
}

