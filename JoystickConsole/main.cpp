#define OEMRESOURCE
#include <Windows.h>
#include <hidsdi.h>
#include <SetupAPI.h>
#include <vector>
#include <iostream>
#include <algorithm>
#include <map>
#include <fstream>
#include <sol\sol.hpp>
#include <regex>
#include "Joystick.h"

int main()
{
	sol::state lua;
	lua.open_libraries();
	Joystick::makeLuaBindings(lua);
	try {
		lua.safe_script_file("main.lua");
	} catch (std::exception & ex) {
		std::cerr << ex.what() << std::endl;
	}
	std::getchar();
}