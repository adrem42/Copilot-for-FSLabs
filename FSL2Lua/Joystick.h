
/// HID joystick library.
// This library can be used to bind buttons and axes
// of HID Joystick devices. Unlike `FSL2Lua.Bind`, this library isn't
// limited to 32 buttons and isn't implented on top of the FSUIPC lua facilities.
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

void logMessage(const char* msg)
{
	static HANDLE hConsole = NULL;
	if (!hConsole)
		hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
	WriteConsoleA(hConsole, msg, strlen(msg), NULL, NULL);
}

void logMessage(const wchar_t* msg)
{
	static HANDLE hConsole = NULL;
	if (!hConsole)
		hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
	WriteConsoleW(hConsole, msg, lstrlenW(msg), NULL, NULL);
}

class Joystick {

private:

	int productId;
	int vendorId;
	int deviceNum;

	std::wstring logName;

	bool _zeroIndexedButtons = false;

	HANDLE bufferAvailableEvent = CreateEvent(0, 0, 0, 0);
	HANDLE timerHandle = CreateWaitableTimer(0, 0, 0);

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
	static constexpr double AXIS_MAX_VALUE = 100.0;

	std::unordered_set<int> axisDataIndices;

	HANDLE device = 0;

	lua_State* L;

	struct ButtonCallback {

	};

	using ButtonCallback = std::function<void(size_t timestamp, size_t button, unsigned short status)>;

	std::unordered_map<size_t, size_t> buttonDataIndexToNumber;

	struct OnPressRepeatCallback {
		ButtonCallback callback;
		const int repeatInterval = DEFAULT_REPEAT_INTERVAL;
		ULONGLONG lastInvokationTime = GetTickCount64();
	};

	std::vector<std::vector<ButtonCallback>> onPressCallbacks;
	std::vector<std::vector<OnPressRepeatCallback>> onPressRepeatCallbacks;
	std::vector<std::vector<ButtonCallback>> onReleaseCallbacks;

	struct DeviceInfo {
		std::wstring product;
		std::wstring manufacturer;
		int vendorId;
		int productId;
		std::wstring devicePath;
		std::wstring toString()
		{
			std::wstringstream ss;

			ss << "Manufacturer: " << manufacturer << std::endl;
			ss << "Product: " << product << std::endl;
			ss << "Vendor ID: " << "0x" << std::hex << std::setfill(L'0') << std::setw(4) << std::uppercase << vendorId << std::endl;
			ss << "Product ID: " << "0x" << std::hex << std::setfill(L'0') << std::setw(4) << std::uppercase << productId;

			return ss.str();
		}
	};

	static std::vector<DeviceInfo> enumerateDevices()
	{
		GUID hidGuid;
		HidD_GetHidGuid(&hidGuid);
		auto devInfo = SetupDiGetClassDevs(&hidGuid, NULL, NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);

		int memberIndex = 0;
		int currentDeviceNum = 0;

		std::vector<DeviceInfo> devices;
		while (true) {

			SP_DEVICE_INTERFACE_DATA deviceInterFaceData = {};
			deviceInterFaceData.cbSize = sizeof(SP_DEVICE_INTERFACE_DATA);
			bool res = SetupDiEnumDeviceInterfaces(
				devInfo,
				NULL,
				&hidGuid,
				memberIndex,
				&deviceInterFaceData
			);
			if (!res && GetLastError() == ERROR_NO_MORE_ITEMS)
				break;
			SP_DEVINFO_DATA devInfoData = {};
			devInfoData.cbSize = sizeof(SP_DEVINFO_DATA);

			DWORD requiredSize;
			auto result = SetupDiGetDeviceInterfaceDetail(
				devInfo,
				&deviceInterFaceData,
				NULL,
				NULL,
				&requiredSize,
				&devInfoData
			);

			auto detailData = reinterpret_cast<PSP_DEVICE_INTERFACE_DETAIL_DATA>(calloc(1, requiredSize));
			detailData->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA);

			result = SetupDiGetDeviceInterfaceDetail(
				devInfo,
				&deviceInterFaceData,
				detailData,
				requiredSize,
				NULL,
				&devInfoData
			);

			auto deviceHandle = CreateFile(
				detailData->DevicePath,
				FILE_GENERIC_READ,
				FILE_SHARE_WRITE | FILE_SHARE_READ,
				NULL,
				OPEN_EXISTING,
				FILE_FLAG_OVERLAPPED,
				NULL
			);

			if (deviceHandle != INVALID_HANDLE_VALUE) {
				HIDD_ATTRIBUTES attr = {};
				if (HidD_GetAttributes(deviceHandle, &attr)) {
					WCHAR productString[127] = {};
					HidD_GetProductString(deviceHandle, productString, sizeof(productString));
					WCHAR manufacturerString[127] = {};
					HidD_GetManufacturerString(deviceHandle, manufacturerString, sizeof(productString));
					devices.push_back(DeviceInfo{ std::wstring(productString), std::wstring(manufacturerString), attr.VendorID, attr.ProductID, std::wstring(detailData->DevicePath) });
				}
			}

			free(detailData);

			memberIndex++;
		}
		return devices;
	}

	/*** @type AxisProperties */
	struct AxisProperties {
		double _delta = 0.5;
		double prevValue = 0;
		bool _invert = false;
		double nullzoneLower = 0.5;
		double nullzoneUpper = 0.5;
		double boundLower = 0;
		double boundUpper = 100;

		/***
		Sets the axis delta (how much change in position is needed to trigger the callback)
		@function delta
		@number delta Percent from 0-100.
		@return self
		*/
		AxisProperties& delta(double delta)
		{
			_delta = delta;
			return *this;
		}

		/***
		Inverts the axis
		@function invert
		@return self
		*/
		AxisProperties& invert()
		{
			_invert = true;
			return *this;
		}

		/***
		Sets the axis lower and upper bounds
		@function bounds
		@number lower Percent from 0-100.
		@number upper Percent from 0-100.
		@return self
		*/
		AxisProperties& bounds(double lower, double upper)
		{
			if (lower > upper)
				throw std::runtime_error("The value for the upper  bound must be greater than for the lower bound.");
			boundLower = lower;
			boundUpper = upper;
			return *this;
		}

		/***
		Sets the axis null zone
		@function nullzone
		@number lower Percent from 0-100.
		@number upper Percent from 0-100.
		@return self
		*/
		AxisProperties& nullZone(double lower, double upper)
		{
			if (lower > upper)
				throw std::runtime_error("The value for the upper null zone bound must be greater than for the lower bound.");
			nullzoneLower = lower;
			nullzoneUpper = upper;
			return *this;
		}

		bool valueChanged(double value)
		{
			return fabs(value - prevValue) >= _delta;
		}

		bool isInNullzone(double value)
		{
			return value > nullzoneLower&& value < nullzoneUpper;
		}

		double transformValue(double value)
		{
			value = std::max<double>(value, boundLower);
			value = std::min<double>(value, boundUpper);
			value = (value - boundLower - (std::min<double>(value, nullzoneUpper) - std::min<double>(value, nullzoneLower))) / (boundUpper - boundLower - (nullzoneUpper - nullzoneLower));
			value *= AXIS_MAX_VALUE;
			if (_invert)
				value = -value + AXIS_MAX_VALUE;
			return value;
		}

	};

	/*** @type AxisCallback */
	struct AxisCallback {

		std::function<void(double)> callback;
		std::shared_ptr<AxisProperties> axisProps;

		void operator()(double value)
		{
			callback(value);
		}

		/***
		Creates and returns new axis properties for this callback only.
		@function props
		@return <a href="#Class_AxisProperties">AxisProperties</a>
		*/
		AxisProperties& props()
		{
			axisProps = std::make_shared<AxisProperties>();
			return *axisProps;
		}

	};

	static std::map<std::string, int>& axisNames()
	{
		static std::map<std::string, int> axisNames{
			{"X",		USAGE_ID_AXIS_X},
			{"Y",		USAGE_ID_AXIS_Y},
			{"Z",		USAGE_ID_AXIS_Z},
			{"Rx",		USAGE_ID_AXIS_Rx},
			{"Ry",		USAGE_ID_AXIS_Ry},
			{"Rz",		USAGE_ID_AXIS_Rz},
			{"Slider",	USAGE_ID_AXIS_Slider},
			{"Dial",	USAGE_ID_AXIS_Dial}
		};
		return axisNames;
	}

	struct Axis {
		HIDP_VALUE_CAPS caps;
		AxisProperties props;
		std::vector<AxisCallback> callbacks;
	};

	std::vector<Axis> axes;

	struct InputBuffer {
		char* buff;
		size_t timeStamp;
	};

	std::unordered_set<int> prevPressedButtons;
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

	int getUsageIdForAxisName(std::string name)
	{
		return axisNames()[name];
	}

	static std::vector<Joystick*>& joysticks()
	{
		static std::vector<Joystick*> joys;
		return joys;
	}

	static void stopAndJoinBufferThread()
	{
		SetEvent(eventStopReadingBuffers());
		if (bufferThread().joinable())
			bufferThread().join();
		ResetEvent(eventStopReadingBuffers());
	}

	static void startBufferThread()
	{
		auto& thread = bufferThread();
		thread = std::thread(readBuffers);
	}

	void getData()
	{

		for (int dataIndex : prevPressedButtons) {
			auto& callbacks = onPressRepeatCallbacks.at(dataIndex);
			for (auto& callback : callbacks) {
				auto now = GetTickCount64();
				if (now - callback.lastInvokationTime > callback.repeatInterval) {
					callback.lastInvokationTime = now;
					callback.callback(buttonDataIndexToNumber[dataIndex], 2, now);
				}
			}
		}

		if (bufferQueue.empty()) return;
		ULONG listSize = 0;

		NTSTATUS status;
		std::queue<InputBuffer> bufferQueue;

		{
			std::lock_guard<std::mutex> lock(bufferMutex);
			bufferQueue = this->bufferQueue;
			this->bufferQueue = std::queue<InputBuffer>();
		}

		while (!bufferQueue.empty()) {

			std::unordered_set<int> pressedButtons;
			InputBuffer buff = bufferQueue.front();
			bufferQueue.pop();
			
			listSize = dataListSize;

			status = HidP_GetData(
				HidP_Input, dataList, &listSize,
				preparsedData, buff.buff, caps.InputReportByteLength
			);

			delete[] buff.buff;

			for (int i = 0; i < listSize; ++i) {
				auto& data = dataList[i];
				auto dataIndex = data.DataIndex;
				auto buttonNum = buttonDataIndexToNumber[dataIndex];
				if (isButtonDataIndex(dataIndex)) {
					bool isPressed = data.On;
					bool wasPressed = prevPressedButtons.find(dataIndex) != prevPressedButtons.end();
					if (isPressed) {
						pressedButtons.insert(dataIndex);
						if (!wasPressed) {
							for (auto& callback : onPressCallbacks.at(dataIndex))
								callback(buttonNum, 1, buff.timeStamp);
							if (!onPressRepeatCallbacks.empty()) {
								LARGE_INTEGER dueTime = {};
								SetWaitableTimer(timerHandle, &dueTime, 10, 0, 0, true);
							}
							for (auto& callback : onPressRepeatCallbacks.at(dataIndex)) {
								callback.lastInvokationTime = GetTickCount64();
								callback.callback(buttonNum, 1, buff.timeStamp);
							}
						}
					}
				}
			}

			for (int dataIndex : prevPressedButtons) {
				bool isPressed = pressedButtons.find(dataIndex) != pressedButtons.end();
				auto buttonNum = buttonDataIndexToNumber[dataIndex];
				if (!isPressed)
					for (auto& callback : onReleaseCallbacks.at(dataIndex))
						callback(buttonNum, 0, buff.timeStamp);
			}
			prevPressedButtons = pressedButtons;

			if (pressedButtons.empty())
				CancelWaitableTimer(timerHandle);

		}

		for (int i = 0; i < listSize; ++i) {
			auto& data = dataList[i];
			auto dataIndex = data.DataIndex;
			if (!isButtonDataIndex(dataIndex)) {
				auto& axis = axes.at(dataIndex);
				auto& info = axis.caps;
				double value = static_cast<double>(data.RawValue - static_cast<int64_t>(info.LogicalMin)) / (info.LogicalMax - static_cast<int64_t>(info.LogicalMin)) * AXIS_MAX_VALUE;
				auto& callbacks = axis.callbacks;
				const bool isInNullzone = axis.props.isInNullzone(value);
				const double transformedValue = isInNullzone ? 0.0 : axis.props.transformValue(value);
				const bool valueChanged = axis.props.valueChanged(transformedValue);
				for (auto& callback : callbacks) {
					if (callback.axisProps == nullptr) {
						if (valueChanged && !isInNullzone) callback(transformedValue);
					} else {
						const bool isInNullzone = callback.axisProps->isInNullzone(value);
						const double transformedValue = isInNullzone ? 0.0 : callback.axisProps->transformValue(value);
						const bool valueChanged = callback.axisProps->valueChanged(transformedValue);
						if (valueChanged && !isInNullzone)
							callback(transformedValue);
						if (valueChanged)
							callback.axisProps->prevValue = transformedValue;
					}
				}
				if (valueChanged)
					axis.props.prevValue = transformedValue;
			}
		}

		memset(dataList, 0, sizeof(*dataList) * dataListSize);
	}

	OVERLAPPED readOverlapped = {};
	HANDLE stopThread = CreateEvent(NULL, NULL, NULL, NULL);
	HANDLE* events;

	char* buff = 0;

	void readFile()
	{
		buff = new char[buffSize]();
		bool readResult = ReadFile(device, buff, buffSize, NULL, &readOverlapped);
	}

	void saveBuffer()
	{
		std::lock_guard<std::mutex> lock(bufferMutex);
		if (bufferQueue.size() + 1 > MAX_NUM_BUFFERS) {
			delete[] bufferQueue.front().buff;
			bufferQueue.pop();
		}
		bufferQueue.emplace(InputBuffer{buff, GetTickCount64()});
		SetEvent(bufferAvailableEvent);
	}

	static HANDLE& eventStopReadingBuffers()
	{
		static HANDLE event = CreateEvent(NULL, NULL, NULL, NULL);
		return event;
	}

	static std::thread& bufferThread()
	{
		static std::thread bufferThread;
		return bufferThread;
	}

	static void readBuffers()
	{

		if (joysticks().empty())
			return;

		HANDLE* events = 0;
		size_t numEvents, numJoysticks, IDX_EVENT_STOP;

		auto setup = [&]() {

			numJoysticks = joysticks().size();
			numEvents = numJoysticks * 2 + 1;
			delete[] events;
			events = new HANDLE[numEvents]();
			IDX_EVENT_STOP = numEvents - 1;

			for (size_t i = 0; i < numJoysticks; ++i) {
				Joystick* joystick = joysticks().at(i);
				HANDLE* pEvent = &joystick->readOverlapped.hEvent;
				if (!*pEvent) *pEvent = CreateEvent(NULL, NULL, NULL, NULL);
				joystick->readFile();
				events[i] = *pEvent;
				events[numJoysticks + i] = joystick->threadHandle;
			}

			events[IDX_EVENT_STOP] = eventStopReadingBuffers();
		};

		setup();

		while (true) {
			DWORD eventIdx = WaitForMultipleObjects(numEvents, events, false, INFINITE);
			if (eventIdx == IDX_EVENT_STOP)
				break;
			if (eventIdx < numJoysticks) {
				Joystick* joystick = joysticks().at(eventIdx);
				joystick->saveBuffer();
				joystick->readFile();
			} else {
				auto threadHandle = events[eventIdx];
				joysticks().erase(std::remove_if(joysticks().begin(), joysticks().end(), [&](Joystick* joy) {
					return joy->threadHandle == threadHandle;
				}), joysticks().end());
				setup();
			}
		}
		delete[] events;
	}

	bool isButtonDataIndex(int dataIndex) const
	{
		return !isAxisDataIndex(dataIndex);
	}

	bool isAxisDataIndex(int dataIndex) const
	{
		return axisDataIndices.find(dataIndex) != axisDataIndices.end();
	}

	class InvalidUsageId : public std::exception {
		std::string _what = "Invalid usage id: ";
	public:
		InvalidUsageId(int usageId)
		{
			char buff[50];
			sprintf(buff, "0x%2X", usageId);
			_what += buff;
		}
		const char* what() const override { return _what.c_str(); }
	};

	class InvalidIndex : public std::exception {
		std::string _what = "Invalid axis index: ";
	public:
		InvalidIndex(int index) { _what += std::to_string(index); }
		const char* what() const override { return _what.c_str(); }
	};

	int findDataIndexForAxis(int usageId, int index) const
	{
		int currIndex = 0;
		for (int i = 0; i < numValueCaps; ++i) {
			auto cap = valueCaps[i];
			if (cap.NotRange.Usage == usageId) {
				if (currIndex == index)
					return cap.NotRange.DataIndex;
				currIndex++;
			}
		}
		if (currIndex == 0) throw InvalidUsageId(usageId);
		throw InvalidIndex(index);
	}

	int findDataIndexForButtonNum(size_t buttonNum) const
	{
		if (_zeroIndexedButtons)
			buttonNum++;
		for (int i = 0; i < numButtonCaps; ++i) {
			auto cap = buttonCaps[i];
			auto range = cap.Range;
			if (buttonNum >= range.UsageMin && buttonNum <= range.UsageMax) {
				int dataIndex = range.DataIndexMin + buttonNum - range.UsageMin;
				return dataIndex;
			}
		}
		std::string error = "Invalid button number: ";
		error += std::to_string(buttonNum);
		throw std::runtime_error(error);
	}

	void initDevice()
	{
		HidD_GetPreparsedData(device, &preparsedData);
		initCaps();
		initButtonCaps();
		initValueCaps();

		buffSize = caps.InputReportByteLength;

		dataListSize = HidP_MaxDataListLength(HidP_Input, preparsedData);
		dataList = new HIDP_DATA[dataListSize]();
	}

	NTSTATUS initCaps()
	{
		return HidP_GetCaps(preparsedData, &caps);
	}

	NTSTATUS initButtonCaps()
	{
		numButtonCaps = caps.NumberInputButtonCaps;
		buttonCaps = new HIDP_BUTTON_CAPS[numButtonCaps];
		auto status = HidP_GetButtonCaps(HidP_Input, buttonCaps, &numButtonCaps, preparsedData);
		int largestDataIndex = 0;
		if (status == HIDP_STATUS_SUCCESS) {
			for (int i = 0; i < numButtonCaps; ++i) {
				auto cap = buttonCaps[i];
				auto range = cap.Range;
				largestDataIndex = std::max<size_t>(largestDataIndex, range.DataIndexMax + 1);
				for (size_t buttonNum = cap.Range.UsageMin, dataIndex = cap.Range.DataIndexMin;
					 buttonNum <= cap.Range.UsageMax;
					 ++buttonNum, ++dataIndex) {
					buttonDataIndexToNumber[dataIndex] = buttonNum;
				}
			}
		}
		onPressCallbacks.resize(largestDataIndex);
		onPressRepeatCallbacks.resize(largestDataIndex);
		onReleaseCallbacks.resize(largestDataIndex);
		return status;
	}

	NTSTATUS initValueCaps()
	{
		numValueCaps = caps.NumberInputValueCaps;
		valueCaps = new HIDP_VALUE_CAPS[numValueCaps];

		auto status = HidP_GetValueCaps(HidP_Input, valueCaps, &numValueCaps, preparsedData);
		int largestDataIndex = 0;
		if (status == HIDP_STATUS_SUCCESS) {
			for (int i = 0; i < numValueCaps; ++i) {
				auto& cap = valueCaps[i];
				axes.resize(std::max<size_t>(axes.size(), cap.NotRange.DataIndex + 1));
				axes.at(cap.NotRange.DataIndex).caps = cap;
				axisDataIndices.insert(cap.NotRange.DataIndex);
			}
		}
		return status;
	}

	using logger_t = std::function<void(const std::wstring&)>;

	static logger_t* logger()
	{
		static logger_t _logger = [](const std::wstring& msg) {
			logMessage(msg.c_str());
			logMessage(L"\n");
		};
		return &_logger;
	}

	static void log(const std::wstring& msg)
	{
		(*logger())(msg.c_str());
	}

public:

	DeviceInfo deviceInfo = {};

	HANDLE threadHandle;

	void useZeroIndexedButtons()
	{
		_zeroIndexedButtons = true;
	}

	/*** @type Joystick */

	/***
	Constructor
	@static
	@function new
	@int vendorId
	@int productId
	@int[opt=0] deviceNum Specify this parameter if there are multiple devices with the same vendor and product IDs
	*/
	Joystick(lua_State* L, int vendorId, int productId, int deviceNum = 0)
		:L(L), vendorId(vendorId), productId(productId), deviceNum(deviceNum)
	{

		int currDevNum = 0;

		DuplicateHandle(GetCurrentProcess(), GetCurrentThread(),
						GetCurrentProcess(), &threadHandle,
						0, false, DUPLICATE_SAME_ACCESS);

		for (auto& device : enumerateDevices()) {
			if (device.productId == productId && device.vendorId == vendorId
				&& currDevNum++ == deviceNum) {
				auto handle = CreateFile(
					device.devicePath.c_str(),
					FILE_GENERIC_READ,
					FILE_SHARE_WRITE | FILE_SHARE_READ,
					NULL,
					OPEN_EXISTING,
					FILE_FLAG_OVERLAPPED,
					NULL
				);
				if (handle == INVALID_HANDLE_VALUE)
					break;
				this->device = handle;
				deviceInfo = device;
				logName = deviceInfo.product + L" " + std::to_wstring(deviceNum);
			}
		}

		if (!device) {
			std::stringstream ss;
			ss << "Failed to open device - vendord ID: 0x"
				<< std::hex << std::setfill('0') << std::setw(4) << std::uppercase << vendorId
				<< ", product ID : 0x" << std::setfill('0') << std::setw(4) << productId
				<< ", device: " << deviceNum;
			throw std::runtime_error(ss.str());
		}

		initDevice();

		stopAndJoinBufferThread();
		joysticks().push_back(this);
		startBufferThread();
	}

	void setLogName(const std::wstring& logName)
	{
		this->logName = logName;
	}

	/***
	Returns the properties of an axis by its name.
	@function axisProps
	@string axisName
	@int[opt=0] index
	@return <a href="#Class_AxisProperties">AxisProperties</a>
	*/
	AxisProperties& axisProps(std::string axisName, int index)
	{
		return axisProps(getUsageIdForAxisName(axisName), index);
	}

	AxisProperties& axisProps(std::string axisName)
	{
		return axisProps(axisName, 0);
	}

	/***
	Returns the properties of an axis by its usage ID.
	@function axisProps
	@int usageID
	@int[opt=0] index
	@return <a href="#Class_AxisProperties">AxisProperties</a>
	*/
	AxisProperties& axisProps(int usageID, int index)
	{
		return axes.at(findDataIndexForAxis(usageID, index)).props;
	}

	AxisProperties& axisProps(int usageID)
	{
		return axisProps(usageID, 0);
	}

	/***
	Binds a callback to a button press.
	@function onPress
	@int buttonNum
	@param callback A function or object with a __call metamethod. You can also call other methods on the object (see below), in which case it doesn't need to have a __call metamethod.
	@param ... Arguments that will be passed to the callback. If the callback is an object and the first argument is a string that matches a method name, the method will be called on the object, with the arguments following the method name string forwarded to the call.
	*/
	void onPress(size_t buttonNum, ButtonCallback callback)
	{
		auto dataIndex = findDataIndexForButtonNum(buttonNum);
		onPressCallbacks.at(dataIndex).push_back(callback);
	}

	/***
	Same as `onPress`, but the callback will be called repeatedly while the button is depressed.
	@function onPressRepeat
	@int buttonNum
	@param callback See `onPress`
	@param ... See `onPress`
	*/
	void onPressRepeat(size_t buttonNum, ButtonCallback callback)
	{
		auto dataIndex = findDataIndexForButtonNum(buttonNum);
		onPressRepeatCallbacks.at(dataIndex).push_back({ callback });
	}

	/***
	Same as `onPress`, but the callback will be called repeatedly while the button is depressed.
	@function onPressRepeat
	@int buttonNum
	@int repeatInterval Interval between callback invocations in milliseconds.
	@param callback See `onPress`
	@param ... See `onPress`
	*/
	void onPressRepeat(size_t buttonNum, int repeatInterval, ButtonCallback callback)
	{
		auto dataIndex = findDataIndexForButtonNum(buttonNum);
		onPressRepeatCallbacks.at(dataIndex).push_back({ callback, repeatInterval });
	}

	/***
	Binds a callback to a button release.
	@function onRelease
	@int buttonNum
	@param callback See `onPress`
	@param ... See `onPress`
	*/
	void onRelease(size_t buttonNum, ButtonCallback callback)
	{
		auto dataIndex = findDataIndexForButtonNum(buttonNum);
		onReleaseCallbacks.at(dataIndex).push_back(callback);
	}


	/***
	Binds a callback to an axis.
	@function onAxis
	@string axisName One of these: X, Y, Z, Rx, Ry, Rz, Slider, Dial
	@tparam function callback A function to be called when the axis changes its value. The callback will receive the current value (percent from 0-100) as the argument.
	*/
	AxisCallback& onAxis(std::string axisName, std::function<void(double)> callback)
	{
		return onAxis(axisName, 0, callback);
	}

	/***
	Binds a callback to an axis.
	@function onAxis
	@string axisName One of these: X, Y, Z, Rx, Ry, Rz, Slider, Dial
	@int axisIndex Specify this parameter if there are multiple axes with the same name.
	@tparam function callback A function to be called when the axis changes its value. The callback will receive the current value (percent from 0-100) as the argument.
	*/
	AxisCallback& onAxis(
		std::string axisName,
		int axisIndex,
		std::function<void(double)> callback
	)
	{
		int usageId = axisNames()[axisName];
		if (!usageId) {
			std::string err = "Invalid axis name: ";
			err += axisName;
			throw std::runtime_error(err);
		}
		try {
			return onAxis(usageId, axisIndex, callback);
		} catch (InvalidUsageId & ex) {
			std::string err = "This joystick has no '";
			err += axisName;
			err += "' axes.";
			throw std::runtime_error(err);
		}
	}

	/***
	Binds a callback to axis by the axis' HID usage ID. You're probably not going to need this.
	@function onAxis
	@int usageId
	@tparam function callback A function to be called when the axis changes its value. The callback will receive the current value (percent from 0-100) as the argument.
	*/
	AxisCallback& onAxis(int usageId, std::function<void(double)> callback)
	{
		return onAxis(usageId, 0, callback);
	}

	/***
	Binds a callback to axis by the axis' HID usage ID. You're probably not going to need this.
	@function onAxis
	@int usageId
	@int axisIndex Specify this parameter if there are multiple axes with a given usage ID.
	@tparam function callback A function to be called when the axis changes its value. The callback will receive the current value (percent from 0-100) as the argument.
	*/
	AxisCallback& onAxis(
		int usageId,
		int axisIndex,
		std::function<void(double)> callback
	)
	{
		size_t dataIndex = findDataIndexForAxis(usageId, axisIndex);
		return axes.at(dataIndex).callbacks.emplace_back(AxisCallback{ callback });
	}

	/***
	Continuously reads the data for all joysticks and never returns.
	@function read
	@static
	*/
	static void read(sol::this_state s)
	{
		std::vector<Joystick*> _joysticks;

		for (Joystick* joystick : joysticks())
			if (joystick->L == s.L) _joysticks.push_back(joystick);

		const size_t numEvents = _joysticks.size() * 2;

		HANDLE* events = new HANDLE[numEvents]();

		size_t i = 0;
		for (Joystick* joystick : _joysticks)
			events[i++] = joystick->bufferAvailableEvent;

		for (Joystick* joystick : _joysticks)
			events[i++] = joystick->timerHandle;

		while (true) {
			DWORD eventIdx = WaitForMultipleObjects(numEvents, events, false, INFINITE);
			_joysticks.at(eventIdx % (numEvents / 2))->getData();
		}
	}

	/***
	Reads the latest data for all joysticks and returns.
	@function peek
	@static
	*/
	static void peek(sol::this_state s)
	{
		for (Joystick* joystick : joysticks())
			if (joystick->L == s.L) joystick->getData();
	}

	/***
	Start printing into the console whenever a button is pressed or an axis is moved.
	@function startLogging
	*/
	void startLogging()
	{
		for (int i = 0; i < numButtonCaps; ++i) {
			auto cap = buttonCaps[i];
			auto range = cap.Range;
			for (int i = range.DataIndexMin; i <= range.DataIndexMax; ++i) {
				auto buttonNum = range.DataIndexMax - i + range.UsageMin;
				if (_zeroIndexedButtons)
					buttonNum--;
				onPress(buttonNum, [this, buttonNum](size_t, size_t, unsigned short) {
					std::wstringstream ss;
					ss << L"   Joystick = " << logName  << L"   |   Button " << buttonNum << " pressed";
					log(ss.str());
				});
				onRelease(buttonNum, [this, buttonNum](size_t, size_t, unsigned short) {
					std::wstringstream ss;
					ss << L"   Joystick = " << logName  << L"   |   Button " << buttonNum << " released";
					log(ss.str());
				});
			}
		}

		std::map<int, int> axisIndices;
		for (auto& axis : axes) {
			auto& caps = axis.caps;
			if (!caps.NotRange.Usage)
				continue;
			auto axisIndex = axisIndices[caps.NotRange.Usage]++;
			std::stringstream ss;
			ss << std::hex << "usage ID: 0x" << caps.NotRange.Usage << ", index: ";
			std::string axisName = ss.str();
			auto& axisNames = this->axisNames();
			bool nameFound = false;
			for (auto axis : axisNames) {
				if (axis.second == caps.NotRange.Usage) {
					axisName = axis.first;
					nameFound = true;
					break;
				}
			}
			auto callback = [axisName, this, axisIndex](double value) {
				std::wstringstream ss;
				ss << L"   Joystick = " << logName 
					<< "   |   Axis = " << axisName.c_str() 
					<< std::setw(8 - axisName.length()) << std::left << axisIndex << "   |   "
					<< std::fixed << std::right << std::setw(6) << std::setprecision(2) << value << " %";
				log(ss.str());
			};
			if (nameFound) {
				onAxis(axisName, axisIndex, callback).props();
			} else {
				onAxis(caps.NotRange.Usage, axisIndex, callback).props();
			}
		}
	}

	/***
	Calls `startLogging` for all registered Joysticks.
	@function logAllJoysticks
	@static
	*/
	static void logAllJoysticks(sol::this_state s)
	{
		auto& joysticks = Joystick::joysticks();
		for (Joystick* joystick : joysticks) {
			if (s.L == joystick->L)
				joystick->startLogging();
		}
	}

	static void makeLuaBindings(sol::state_view& lua)
	{

		auto JoystickType = lua.new_usertype<Joystick>(
			"Joystick",
			sol::factories([&](sol::this_state s, int vendorId, int productId) {
				try {
					return std::make_shared<Joystick>(s.L, vendorId, productId);
				} catch (std::exception& ex) {
					throw ex;
				}
			}, [&](sol::this_state s, int vendorId, int productId, int devNum) {
				try {
					return std::make_shared<Joystick>(s.L, vendorId, productId, devNum);
				} catch (std::exception& ex) {
					throw ex;
				}
			})
		);

		auto axisProps = sol::overload(
			static_cast<AxisProperties & (Joystick::*)(int, int)>(&Joystick::axisProps),
			static_cast<AxisProperties& (Joystick::*)(int)>(&Joystick::axisProps),
			static_cast<AxisProperties& (Joystick::*)(std::string, int)>(&Joystick::axisProps),
			static_cast<AxisProperties& (Joystick::*)(std::string)>(&Joystick::axisProps)
		);

		lua_State* L = lua.lua_state();
		*logger() = [L](const std::wstring& msg) {
			std::string _msg = std::string(msg.begin(), msg.end());
			lua_getglobal(L, "print");
			lua_pushstring(L, _msg.c_str());
			lua_call(L, 1, 0);
		};

		JoystickType["axisProps"] = axisProps;

		auto AxisCallbackType = lua.new_usertype<AxisCallback>("AxisCallback");
		AxisCallbackType["props"] = &AxisCallback::props;

		auto AxisPropsType			= lua.new_usertype<AxisProperties>("AxisProps");
		AxisPropsType["bounds"]		= &AxisProperties::bounds;
		AxisPropsType["nullzone"]	= &AxisProperties::nullZone;
		AxisPropsType["invert"]		= &AxisProperties::invert;
		AxisPropsType["delta"]		= &AxisProperties::delta;

		JoystickType["info"] = &Joystick::deviceInfo;
		JoystickType["setLogName"] = &Joystick::setLogName;

		JoystickType["enumerateDevices"] = [] { return sol::as_table(Joystick::enumerateDevices()); };
		auto DeviceInfoType = lua.new_usertype<DeviceInfo>("DeviceInfo");

		DeviceInfoType["product"]		= &DeviceInfo::product;
		DeviceInfoType["manufacturer"]	= &DeviceInfo::manufacturer;
		DeviceInfoType["vendorId"]		= &DeviceInfo::vendorId;
		DeviceInfoType["productId"]		= &DeviceInfo::productId;

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
				sol::function f = va[0];
				return f;
			}
			if (va.leftover_count() == 1 || va[1].get_type() == sol::type::nil) {
				if (va[0].get_type() == sol::type::function) {
					sol::function f = va[0];
					return [f](size_t, size_t, unsigned short) {f(); };
				}
				if (va[0].get_type() == sol::type::table) {
					sol::table obj = va[0];
					if (obj[sol::metatable_key].get_type() == sol::type::table) {
						sol::table mt = obj[sol::metatable_key];
						if (mt["__call"].get_type() == sol::type::function) {
							sol::function __call = mt["__call"];
							return [__call, obj](size_t, size_t, unsigned short) { __call(obj); };
						}
					}
				}
			}
			auto args = std::vector<sol::object>(va.begin(), va.end());
			return lua["Bind"]["makeSingleFunc"](lua["Bind"], sol::as_table(args));
		};

		JoystickType["onPress"] = [parseCallbackArgs](Joystick& joy, int buttonNum, sol::variadic_args va) {
			joy.onPress(buttonNum, parseCallbackArgs(va));
		};

		JoystickType["onRelease"] = [parseCallbackArgs](Joystick& joy, int buttonNum, sol::variadic_args va) {
			joy.onRelease(buttonNum, parseCallbackArgs(va));
		};

		JoystickType["onPressRepeat"] = sol::overload(
			[parseCallbackArgs](Joystick& joy, int buttonNum, int repeatInterval, sol::variadic_args va) {
				joy.onPressRepeat(buttonNum, repeatInterval, parseCallbackArgs(va));
			},
			[parseCallbackArgs](Joystick& joy, int buttonNum, sol::variadic_args va) {
				joy.onPressRepeat(buttonNum, parseCallbackArgs(va));
			}
		);

		JoystickType["useZeroIndexedButtons"] = &Joystick::useZeroIndexedButtons;

		JoystickType["onAxis"] = sol::overload(
			static_cast<AxisCallback& (Joystick::*)(std::string, int, std::function<void(double)>)>(&Joystick::onAxis),
			static_cast<AxisCallback& (Joystick::*)(std::string, std::function<void(double)>)>(&Joystick::onAxis),

			static_cast<AxisCallback& (Joystick::*)(int, int, std::function<void(double)>)>(&Joystick::onAxis),
			static_cast<AxisCallback& (Joystick::*)(int, std::function<void(double)>)>(&Joystick::onAxis)
		);

		JoystickType["read"] = &Joystick::read;
		JoystickType["peek"] = &Joystick::peek;

		JoystickType["startLogging"] = &Joystick::startLogging;
		JoystickType["logAllJoysticks"] = &Joystick::logAllJoysticks;
	}

	~Joystick()
	{
		stopAndJoinBufferThread();
		joysticks().erase(std::remove(joysticks().begin(), joysticks().end(), this), joysticks().end());
		if (!joysticks().empty())
			startBufferThread();
	}
};