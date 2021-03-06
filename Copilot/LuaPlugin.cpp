
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

LuaPlugin::LuaPlugin(const std::string& path)
	: path(path) 
{
}

void LuaPlugin::initLuaState(sol::state_view lua)
{

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
	ipc["readSTR"] = readSTR;

	ipc["createLvar"] = sol::overload(
		[](const std::string& str, double init) { SimInterface::createLvar(str, init); },
		[](const std::string& str) { SimInterface::createLvar(str); }
	);

	ipc["readLvar"] = SimInterface::readLvar;
	ipc["writeLvar"] = SimInterface::writeLvar;

	ipc["sleep"] = Sleep;

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
	HttpSessionType["setPort"] = &HttpSession::setPort;
	HttpSessionType["lastError"] = &HttpSession::lastError;

	auto McduSessionType = lua.new_usertype<MCDU>("MCDUsession",
										   sol::constructors<MCDU(unsigned int, unsigned int, unsigned int)>());

	McduSessionType["getString"] = &MCDU::getString;
	McduSessionType["getRaw"] = &MCDU::getRaw;
	McduSessionType["setPort"] = &MCDU::setPort;
	McduSessionType["lastError"] = &MCDU::lastError;

	KeyBindManager::makeLuaBindings(lua, keyBindManager);

	lua.safe_script(R"(FSL = require "FSL2Lua.FSL2Lua.FSL2Lua")", sol::script_throw_on_error);
}

void LuaPlugin::onError(const sol::error& error)
{
	copilot::logger->error(error.what());
}

void LuaPlugin::run()
{
	keyBindManager = std::make_shared<KeyBindManager>();
	Keyboard::addKeyBindManager(keyBindManager);
	std::string logPath;
	if (path.find(copilot::appDir) == 0) {
		logPath = path.substr(path.find("Copilot for FSLabs"));
	} else {
		logPath = path;
	}
	copilot::logger->info(">>>>>> Launching new lua thread: '{}'", logPath);
	lua = sol::state();
	lua.open_libraries();
	initLuaState(lua);
	auto res = lua.safe_script_file(path, sol::script_throw_on_error);
}

void LuaPlugin::stopThread()
{
	Keyboard::removeKeyBindManager(keyBindManager);
	TerminateThread(thread.native_handle(), 0);
	if (thread.joinable()) {
		thread.join();
	}
}

void LuaPlugin::launchThread()
{
	if (thread.joinable())
		stopThread();
	thread = std::thread([this] {
		try {
			run();
		}
		catch (sol::error & err) {
			onError(err);
		}
	});
}

LuaPlugin::~LuaPlugin()
{
	if (thread.joinable())
		stopThread();
}