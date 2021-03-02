
#include "LuaPlugin.h"
#include "SimInterface.h"
#include "Copilot.h"
#include "FSUIPC.h"

auto startTime = std::chrono::system_clock::now();

LuaPlugin::LuaPlugin(const std::string& path): path(path) {}

void LuaPlugin::initLuaState(sol::state_view lua)
{
	
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

	ipc["writeFLT"] = write<float>;
	ipc["readFLT"] = read<float>;

	ipc["writeDBL"] = write<double>;
	ipc["readDBL"] = read<double>;

	ipc["writeSTR"] = writeSTR;
	ipc["readSTR"] = readSTR;

	ipc["createLvar"] = SimInterface::createLvar;
	ipc["readLvar"] = SimInterface::readLvar;
	ipc["writeLvar"] = SimInterface::writeLvar;

	ipc["sleep"] = Sleep;

	ipc["elapsedtime"] = [] {
		return std::chrono::duration_cast<std::chrono::milliseconds>(
			std::chrono::system_clock::now() - startTime
		).count();
	};

	lua["ipc"] = ipc;
	lua["package"]["path"] = copilot::appDir + "?.lua";
	lua["package"]["cpath"] = copilot::appDir + "?.dll";

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
	
	auto res = lua.safe_script(R"(
		require "FSL2Lua.FSL2Lua"
		FSL = require "FSL2Lua.FSL2Lua.FSL2Lua"
	)", sol::script_pass_on_error);
	if (!res.valid())
		onError(res);
}

void LuaPlugin::onError(const sol::error& error)
{
	copilot::logger->error(error.what());
}

bool LuaPlugin::run()
{
	lua = sol::state();
	lua.open_libraries();
	initLuaState(lua);


	auto res = lua.safe_script_file(path, sol::script_pass_on_error);
	if (!res.valid()) 
		onError(res);

	return res.valid();
}

void LuaPlugin::stopThread()
{
	TerminateThread(thread.native_handle(), 0);
	if (thread.joinable()) {
		thread.join();
	}
}

void LuaPlugin::launchThread()
{
	if (thread.joinable())
		stopThread();
	thread = std::thread(&LuaPlugin::run, this);
}