
/// HID joystick library.
// This library can be used to bind buttons and axes of HID Joystick devices to FSLabs cockpit controls (or other functions if you want).
//
// @{hid_joysticks.lua|Click here for usage examples}
// @module Joystick

#pragma once
#pragma warning(disable:4996)
#define NOMINMAX 
#include <array>
#include <vector>
#include <queue>
#include <functional>
#include <algorithm>
#include <windows.h>
#include <hidsdi.h>
#include <SetupAPI.h>
#include <vector>
#include <iostream>
#include <map>
#include <algorithm>
#include <unordered_set>
#include <mutex>
#include <thread>
#include <sstream>
#include <iomanip>
#include <sol\sol.hpp>
#include <io.h>
#include <Fcntl.h>
#include <chrono>
#include <memory>
#include "Exceptions.h"

class Joystick {

	class Button;

	static size_t gcd(size_t a, size_t b);

	using ButtonCallback = std::function<void(uint16_t buttonNum, uint16_t action, size_t status)>;

	int productId;
	int vendorId;
	int deviceNum;

	struct DeviceInfo {
		std::wstring product;
		std::wstring manufacturer;
		int vendorId;
		int productId;
		std::wstring devicePath;
	};

	/*** @type AxisProperties */
	struct AxisProperties {

		double _delta = 0.5;
		double prevValue = 0;
		bool _invert = false;
		double nullzoneLower = 0.5;
		double nullzoneUpper = 0.5;
		double boundLower = 0;
		double boundUpper = 100;

		static constexpr double AXIS_MAX_VALUE = 100.0;

		/***
		Sets the axis delta (how much change in position is needed to trigger the callback)
		@function delta
		@number delta Percent from 0-100.
		@return self
		*/
		AxisProperties& delta(double delta);

		/***
		Inverts the axis
		@function invert
		@return self
		*/
		AxisProperties& invert();

		/***
		Sets the axis lower and upper bounds
		@function bounds
		@number lower Percent from 0-100.
		@number upper Percent from 0-100.
		@return self
		*/
		AxisProperties& bounds(double lower, double upper);

		/***
		Sets the axis null zone
		@function nullzone
		@number lower Percent from 0-100.
		@number upper Percent from 0-100.
		@return self
		*/
		AxisProperties& nullzone(double lower, double upper);

		bool valueChanged(double value);

		bool isInNullzone(double value);

		double transformValue(double value);
	};

	/*** @type AxisCallback */
	struct AxisCallback {

		std::function<void(double)> callback;
		std::shared_ptr<AxisProperties> axisProps;

		void operator()(double value);

		/***
		Creates and returns new axis properties for this callback only.
		@function props
		@return <a href="#Class_AxisProperties">AxisProperties</a>
		*/
		std::shared_ptr<AxisProperties> props();
	};

	struct Axis {
		HIDP_VALUE_CAPS caps;
		Joystick::AxisProperties props;
		std::vector<AxisCallback> callbacks;
	};

	struct InputBuffer {
		char* buff;
		size_t timestamp = getTimestamp();
	};

	std::wstring logName;

	bool zeroIndexedButtons = false;

	HANDLE bufferAvailableEvent = CreateEvent(0, 0, 0, 0);
	HANDLE buttonRepeatTimerHandle = CreateWaitableTimer(0, 0, 0);

	static const int USAGE_ID_AXIS_X = 0x30;
	static const int USAGE_ID_AXIS_Y = 0x31;
	static const int USAGE_ID_AXIS_Z = 0x32;
	static const int USAGE_ID_AXIS_Rx = 0x33;
	static const int USAGE_ID_AXIS_Ry = 0x34;
	static const int USAGE_ID_AXIS_Rz = 0x35;
	static const int USAGE_ID_AXIS_Slider = 0x36;
	static const int USAGE_ID_AXIS_Dial = 0x37;
	static const int USAGE_ID_AXIS_Wheel = 0x38;
	static const int DEFAULT_REPEAT_INTERVAL = 80;
	
	std::unordered_set<int> axisDataIndices;

	HANDLE device = 0;

	lua_State* L;

	std::unordered_map<int, Button> buttons;

	static std::vector<DeviceInfo> enumerateDevices();

	static std::map<std::string, int> axisNamesToUsageId;

	std::vector<Axis> axes;

	std::queue<InputBuffer> bufferQueue;

	static const size_t MAX_NUM_BUFFERS = 50;
	std::mutex bufferMutex;

	HIDP_CAPS caps;
	USHORT numButtonCaps;
	HIDP_BUTTON_CAPS* buttonCaps;
	USHORT numValueCaps;
	HIDP_VALUE_CAPS* valueCaps;
	PHIDP_PREPARSED_DATA preparsedData;

	size_t buffSize;

	HIDP_DATA* dataList;
	ULONG dataListSize = 0;

	static std::vector<Joystick*> joysticks;

	static void stopAndJoinBufferThread();

	static void startBufferThread();

	void processAxisData(ULONG listSize);

	void processButtonData(ULONG listSize, size_t timestamp);

	void onButtonRepeatTimer();

	void getData();

	OVERLAPPED readOverlapped = {};
	HANDLE stopThread = CreateEvent(NULL, NULL, NULL, NULL);
	HANDLE* events;

	char* buff = 0;

	void readFile();

	void saveBuffer();

	static HANDLE eventStopReadingBuffers;

	static std::thread bufferThread;

	static void readBuffers();

	bool isButtonDataIndex(int dataIndex) const;

	bool isAxisDataIndex(int dataIndex) const;

	int findDataIndexForAxis(int usageId, int index) const;

	int findDataIndexForButtonNum(size_t buttonNum) const;

	void initDevice();

	NTSTATUS initCaps();

	NTSTATUS initButtonCaps();

	NTSTATUS initValueCaps();

	void log(const std::wstring&);

	static std::chrono::time_point<std::chrono::high_resolution_clock> startTime;

	static size_t getTimestamp();

public:

	std::shared_ptr<DeviceInfo> deviceInfo;

	HANDLE threadHandle;

	void useZeroIndexedButtons();

	/*** @type Joystick */

	/***
	Constructor
	@static
	@function new
	@int vendorId
	@int productId
	@int[opt=0] deviceNum Specify this parameter if there are multiple devices with the same vendor and product IDs
	*/
	Joystick(lua_State* L, int vendorId, int productId, int deviceNum = 0);

	void setLogName(const std::wstring& logName);

	/***
	Returns the properties of an axis by its name.
	@function axisProps
	@string axisName
	@int[opt=0] index
	@return <a href="#Class_AxisProperties">AxisProperties</a>
	*/
	AxisProperties& axisProps(std::string axisName, int index);

	AxisProperties& axisProps(std::string axisName);

	/***
	Returns the properties of an axis by its usage ID.
	@function axisProps
	@int usageID
	@int[opt=0] index
	@return <a href="#Class_AxisProperties">AxisProperties</a>
	*/
	AxisProperties& axisProps(int usageID, int index);

	AxisProperties& axisProps(int usageID);

	/***
	Binds a joystick button's press and release actions to those of a virtual cockpit button.
	@function bindButton
	@int buttonNum
	@param button <a href="FSL2Lua.html#Class_Button">Button</a>
	*/

	/***
	Maps the toggle states of a joystick toggle button to those of a virtual cockpit toggle button.
	@function bindToggleButton
	@int buttonNum
	@param button <a href="FSL2Lua.html#Class_ToggleButton">ToggleButton</a>
	*/

	/***
	Same as `bindButton` - for pushing the switch.
	@function bindPush
	@int buttonNum
	@param switch <a href="FSL2Lua.html#Class_FcuSwitch">FcuSwitch</a>
	*/

	/***
	Same as `bindButton` - for pulling the switch.
	@function bindPull
	@int buttonNum
	@param switch <a href="FSL2Lua.html#Class_FcuSwitch">FcuSwitch</a>
	*/

	/***
	Binds a callback to a button press.
	@function onPress
	@int buttonNum
	@param callback A function or object with a __call metamethod. You can also call other methods on the object (see below), in which case it doesn't need to have a __call metamethod.
	@param ... Arguments that will be passed to the callback. If the callback is an object and the first argument is a string that matches a method name, the method will be called on the object, with the arguments following the method name forwarded to the call.
	*/
	void onPress(size_t buttonNum, ButtonCallback callback);

	/***
	Same as `onPress`, but the callback will be called repeatedly while the button is depressed.
	@function onPressRepeat
	@int buttonNum
	@param callback See `onPress`
	@param ... See `onPress`
	*/
	void onPressRepeat(size_t buttonNum, ButtonCallback callback);

	/***
	Same as `onPress`, but the callback will be called repeatedly while the button is depressed.
	@function onPressRepeat
	@int buttonNum
	@int repeatInterval Interval between callback invocations in milliseconds.
	@param callback See `onPress`
	@param ... See `onPress`
	*/
	void onPressRepeat(size_t buttonNum, int repeatInterval, ButtonCallback callback);

	/***
	Binds a callback to a button release.
	@function onRelease
	@int buttonNum
	@param callback See `onPress`
	@param ... See `onPress`
	*/
	void onRelease(size_t buttonNum, ButtonCallback callback);

	/***
	Binds a callback to an axis.
	@function onAxis
	@string axisName One of these: X, Y, Z, Rx, Ry, Rz, Slider, Dial
	@tparam function callback A function to be called when the axis changes its value. The callback will receive the current value (percent from 0-100) as the argument.
	*/
	AxisCallback& onAxis(std::string axisName, std::function<void(double)> callback);

	/***
	Binds a callback to an axis.
	@function onAxis
	@string axisName One of these: X, Y, Z, Rx, Ry, Rz, Slider, Dial
	@int axisIndex Specify this parameter if there are multiple axes with the same name.
	@tparam function callback A function to be called when the axis changes its value. The callback will receive the current value (percent from 0-100) as the argument.
	*/
	AxisCallback& onAxis(std::string axisName, int axisIndex, std::function<void(double)> callback);

	/***
	Binds a callback to axis by the axis' HID usage ID. You're probably not going to need this.
	@function onAxis
	@int usageId
	@tparam function callback A function to be called when the axis changes its value. The callback will receive the current value (percent from 0-100) as the argument.
	*/
	AxisCallback& onAxis(int usageId, std::function<void(double)> callback);

	/***
	Binds a callback to axis by the axis' HID usage ID. You're probably not going to need this.
	@function onAxis
	@int usageId
	@int axisIndex Specify this parameter if there are multiple axes with a given usage ID.
	@tparam function callback A function to be called when the axis changes its value. The callback will receive the current value (percent from 0-100) as the argument.
	*/
	AxisCallback& onAxis(int usageId, int axisIndex, std::function<void(double)> callback);

	/***
	Continuously reads the data for all joysticks and never returns.
	@function read
	@static
	*/
	static void read(sol::this_state s);

	/***
	Reads the latest data for all joysticks and returns.
	@function peek
	@static
	*/
	static void peek(sol::this_state s);

	/***
	Start printing into the console whenever a button is pressed or an axis is moved.
	@function startLogging
	*/
	void startLogging();

	/***
	Calls `startLogging` for all registered Joysticks.
	@function logAllJoysticks
	@static
	*/
	static void logAllJoysticks(sol::this_state s);

	static void makeLuaBindings(sol::state_view& lua);

	~Joystick();
};