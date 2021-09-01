#include "Joystick.h"
#include "Button.h"
#include "JoystickManager.h"

void Joystick::makeLuaBindings(sol::state_view& lua, std::shared_ptr<JoystickManager> manager)
{
	
	auto JoystickType = lua.new_usertype<Joystick>(
		"Joystick",
		sol::factories(
			[manager]( int vendorId, int productId) {
				std::lock_guard<std::mutex> lock(bufferThreadMutex);
				auto joy = std::make_shared<Joystick>(vendorId, productId, manager);
				stopAndJoinBufferThread();
				manager->joysticks.push_back(joy);
				startBufferThread();
				return joy;
			}, 
			[manager]( int vendorId, int productId, int devNum) {
				std::lock_guard<std::mutex> lock(bufferThreadMutex);
				auto joy = std::make_shared<Joystick>(vendorId, productId, manager, devNum);
				stopAndJoinBufferThread();
				manager->joysticks.push_back(joy);
				startBufferThread();
				return joy;
			}
		)
	);

	JoystickType["setButtonStateUnknown"] = &Joystick::setButtonStateUnknown;
	JoystickType["setButtonStatesUnknown"] = &Joystick::setButtonStatesUnknown;

	sol::table extensions = lua["require"]("FSL2Lua.FSL2Lua.JoystickExtensions");

	for (auto& [k, v] : extensions) 
		JoystickType[k.as<std::string>()] = v.as<sol::unsafe_function>();

	JoystickType["BUTTON_EVENT_PRESS"] = sol::var(Joystick::Button::EVENT_TYPE_PRESS);
	JoystickType["BUTTON_EVENT_REPEATED_PRESS"] = sol::var(Joystick::Button::EVENT_TYPE_REPEATED_PRESS);
	JoystickType["BUTTON_EVENT_RELEASE"] = sol::var(Joystick::Button::EVENT_TYPE_RELEASE);

	JoystickType["axisProps"] = sol::overload(
		static_cast<AxisProperties & (Joystick::*)(int, int)>(&Joystick::axisProps),
		static_cast<AxisProperties& (Joystick::*)(int)>(&Joystick::axisProps),
		static_cast<AxisProperties& (Joystick::*)(std::string, int)>(&Joystick::axisProps),
		static_cast<AxisProperties& (Joystick::*)(std::string)>(&Joystick::axisProps)
	);

	auto AxisCallbackType = lua.new_usertype<AxisCallback>("AxisCallback");
	AxisCallbackType["props"] = &AxisCallback::props;

	auto AxisPropsType = lua.new_usertype<AxisProperties>("AxisProps");
	AxisPropsType["bounds"] = &AxisProperties::bounds;
	AxisPropsType["nullzone"] = &AxisProperties::nullzone;
	AxisPropsType["invert"] = &AxisProperties::invert;
	AxisPropsType["delta"] = &AxisProperties::delta;

	JoystickType["info"] = &Joystick::deviceInfo;
	JoystickType["setLogName"] = &Joystick::setLogName;
	JoystickType["getInputReport"] = &Joystick::getInputReport;

	JoystickType["enumerateDevices"] = [] { return sol::as_table(Joystick::enumerateDevices()); };
	auto DeviceInfoType = lua.new_usertype<DeviceInfo>("DeviceInfo");

	DeviceInfoType["product"] = &DeviceInfo::product;
	DeviceInfoType["manufacturer"] = &DeviceInfo::manufacturer;
	DeviceInfoType["vendorId"] = &DeviceInfo::vendorId;
	DeviceInfoType["productId"] = &DeviceInfo::productId;

	JoystickType["makeEncoder"] = [](Joystick& joy, sol::variadic_args va) -> sol::object {
		auto lua = sol::state_view(va.lua_state());
		sol::function newEncoder = lua["Encoder"]["new"];
		return newEncoder(joy, va);
	};

	struct send_event_details_t {};

	JoystickType["sendEventDetails"] = sol::readonly_property([] { return send_event_details_t(); });

	auto parseCallbackArgs = [&](sol::variadic_args va) -> ButtonCallback {
		sol::state_view lua(va.lua_state());
		if (va.leftover_count() == 2
			&& va[0].get_type() == sol::type::function
			&& va[1].is<send_event_details_t>()) {
			sol::unsafe_function f = va[0];
			return f;
		}
		if (va.leftover_count() == 1 || va[1].get_type() == sol::type::nil) {
			if (va[0].get_type() == sol::type::function) {
				sol::unsafe_function f = va[0];
				return [f](size_t, size_t, unsigned short) { f(); };
			}
			sol::table mt;
			auto checkMt = [&mt](auto obj) {
				if (obj[sol::metatable_key].get_type() == sol::type::table) 
					mt = obj[sol::metatable_key];
			};
			if (va[0].is<sol::table>()) 
				checkMt(va[0].as<sol::table>());
			 else if (va[0].is<sol::userdata>()) 
				checkMt(va[0].as<sol::userdata>());
			if (mt.valid()) {
				if (mt["__call"].get_type() == sol::type::function) {
					sol::unsafe_function __call = mt["__call"];
					sol::object obj = va[0];
					return [__call, obj](size_t, size_t, unsigned short) { return __call(obj); };
				}
			}
		}
		auto args = std::vector<sol::object>(va.begin(), va.end());
		sol::unsafe_function makeSingleFunc = lua["Bind"]["makeSingleFunc"];
		return makeSingleFunc(sol::as_table(args));
	};

	JoystickType["onPress"] = [parseCallbackArgs](Joystick& joy, int buttonNum, sol::variadic_args va) {
		joy.onPress(buttonNum, parseCallbackArgs(va));
	};

	JoystickType["onRelease"] = [parseCallbackArgs](Joystick& joy, int buttonNum, sol::variadic_args va) {
		joy.onRelease(buttonNum, parseCallbackArgs(va));
	};

	JoystickType["bind"] = [](Joystick& joy, sol::table args) {
		sol::state_view lua(args.lua_state());
		sol::unsafe_function prepareBind = lua["Bind"]["prepareBind"];
		sol::table bindData = prepareBind(lua["Bind"], args);
		int buttonNum = args.get<int>("button");
		if (bindData["onPress"].get_type() == sol::type::function)
			joy.onPress(buttonNum, bindData.get<sol::unsafe_function>("onPress"));
		if (bindData["onRelease"].get_type() == sol::type::function)
			joy.onRelease(buttonNum, bindData.get<sol::unsafe_function>("onRelease"));
		if (bindData["onPressRepeat"].get_type() == sol::type::function)
			joy.onPress(buttonNum, bindData.get<sol::unsafe_function>("onPressRepeat"));
	};

	

	JoystickType["onPressRepeat"] = sol::overload(
		[parseCallbackArgs](Joystick& joy, int buttonNum, int repeatInterval, sol::variadic_args va) {
			joy.onPressRepeat(buttonNum, repeatInterval, parseCallbackArgs(va));
		},
		[parseCallbackArgs](Joystick& joy, int buttonNum, sol::variadic_args va) {
			joy.onPressRepeat(buttonNum, parseCallbackArgs(va));
		}
	);

	auto specialButtonBinding = [](Joystick& joy, int buttonNum, sol::object o, const std::string& methodName) {
		sol::function onPress;
		sol::function onRelease;
		auto lua = sol::state_view(o.lua_state());
		sol::unsafe_function makeCallbacks = lua["Bind"][methodName];
		sol::tie(onPress, onRelease) = makeCallbacks(o);
		joy.onPress(buttonNum, onPress);
		joy.onRelease(buttonNum, onRelease);
	};

	JoystickType["bindButton"] = [specialButtonBinding](Joystick& joy, int buttonNum, sol::object butt) {
		specialButtonBinding(joy, buttonNum, butt, "_bindButton");
	};

	JoystickType["bindToggleButton"] = [specialButtonBinding](Joystick& joy, int buttonNum, sol::object butt) {
		joy.setButtonStateUnknown(buttonNum);
		specialButtonBinding(joy, buttonNum, butt, "_bindToggleButton");
	};

	JoystickType["bindPush"] = [specialButtonBinding](Joystick& joy, int buttonNum, sol::object _switch) {
		specialButtonBinding(joy, buttonNum, _switch, "_bindPush");
	};

	JoystickType["bindPull"] = [specialButtonBinding](Joystick& joy, int buttonNum, sol::object _switch) {
		specialButtonBinding(joy, buttonNum, _switch, "_bindPull");
	};

	JoystickType["useZeroIndexedButtons"] = &Joystick::useZeroIndexedButtons;

	JoystickType["onAxis"] = sol::overload(
		static_cast<AxisCallback & (Joystick::*)(std::string, int, std::function<void(double)>)>(&Joystick::onAxis),
		static_cast<AxisCallback& (Joystick::*)(std::string, std::function<void(double)>)>(&Joystick::onAxis),

		static_cast<AxisCallback& (Joystick::*)(int, int, std::function<void(double)>)>(&Joystick::onAxis),
		static_cast<AxisCallback& (Joystick::*)(int, std::function<void(double)>)>(&Joystick::onAxis)
	);


	JoystickType["startLogging"] = sol::overload(
		[](Joystick& joy, size_t delta) { joy.startLogging(delta); },
		[](Joystick& joy) { joy.startLogging(); }
	);

	auto logAll = [manager] (size_t delta = -1) {Joystick::logAllJoysticks(manager, delta); };

	JoystickType["logAllJoysticks"] = sol::overload([=](size_t delta) { logAll(delta); }, [=] { logAll(); });
}
