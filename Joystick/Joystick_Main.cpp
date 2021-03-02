#include "Joystick.h"
#include "Button.h"

void Joystick::processButtonData(ULONG listSize, size_t timestamp)
{
	bool shouldStartButtonRepeatTimer = false;

	std::unordered_set<int> depressedButtons;

	for (int i = 0; i < listSize; ++i) {

		auto& data = dataList[i];

		if (!data.On || !isButtonDataIndex(data.DataIndex))
			continue;

		auto& button = buttons.find(data.DataIndex)->second;
		depressedButtons.insert(button.dataIndex);

		if (button.maybePress(timestamp))
			shouldStartButtonRepeatTimer = true;
	}

	for (auto& [_, button] : buttons) {
		bool isPressed = depressedButtons.find(button.dataIndex) != depressedButtons.end();
		if (!isPressed)
			button.maybeRelease(timestamp);
	}

	if (shouldStartButtonRepeatTimer) {
		LARGE_INTEGER dueTime = {};
		SetWaitableTimer(buttonRepeatTimerHandle, &dueTime, 10, 0, 0, true);
	} else if (depressedButtons.empty()) {
		CancelWaitableTimer(buttonRepeatTimerHandle);
	}

}

void Joystick::processAxisData(ULONG listSize)
{
	for (int i = 0; i < listSize; ++i) {
		auto& data = dataList[i];
		auto dataIndex = data.DataIndex;
		if (!isButtonDataIndex(dataIndex)) {
			auto& axis = axes.at(dataIndex);
			auto& info = axis.caps;
			double value = static_cast<double>(data.RawValue - static_cast<int64_t>(info.LogicalMin)) / (info.LogicalMax - static_cast<int64_t>(info.LogicalMin))* AxisProperties::AXIS_MAX_VALUE;
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
}

void Joystick::getData()
{
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

		InputBuffer& buff = bufferQueue.front();
		bufferQueue.pop();

		listSize = dataListSize;

		status = HidP_GetData(
			HidP_Input, dataList, &listSize,
			preparsedData, buff.buff, caps.InputReportByteLength
		);

		delete[] buff.buff;

		processButtonData(listSize, buff.timestamp);
	}

	processAxisData(listSize);

	memset(dataList, 0, sizeof(*dataList) * dataListSize);
}

void Joystick::readFile()
{
	buff = new char[buffSize]();
	bool readResult = ReadFile(device, buff, buffSize, NULL, &readOverlapped);
}

void Joystick::saveBuffer()
{
	std::lock_guard<std::mutex> lock(bufferMutex);
	if (bufferQueue.size() + 1 > MAX_NUM_BUFFERS) {
		delete[] bufferQueue.front().buff;
		bufferQueue.pop();
	}
	bufferQueue.emplace(InputBuffer{ buff });
	SetEvent(bufferAvailableEvent);
}

void Joystick::readBuffers()
{

	if (joysticks.empty())
		return;

	HANDLE* events = 0;
	size_t numEvents, numJoysticks, IDX_EVENT_STOP;

	auto setup = [&]() {

		numJoysticks = joysticks.size();
		numEvents = numJoysticks * 2 + 1;
		delete[] events;
		events = new HANDLE[numEvents]();
		IDX_EVENT_STOP = numEvents - 1;

		for (size_t i = 0; i < numJoysticks; ++i) {
			Joystick* joystick = joysticks.at(i);
			HANDLE* pEvent = &joystick->readOverlapped.hEvent;
			if (!*pEvent) *pEvent = CreateEvent(NULL, NULL, NULL, NULL);
			joystick->readFile();
			events[i] = *pEvent;
			events[numJoysticks + i] = joystick->threadHandle;
		}

		events[IDX_EVENT_STOP] = eventStopReadingBuffers;
	};

	setup();

	while (true) {
		DWORD eventIdx = WaitForMultipleObjects(numEvents, events, false, INFINITE);
		if (eventIdx == IDX_EVENT_STOP)
			break;
		if (eventIdx < numJoysticks) {
			Joystick* joystick = joysticks.at(eventIdx);
			joystick->saveBuffer();
			joystick->readFile();
		} else { // One of the lua threads is kill :(
			auto threadHandle = events[eventIdx];
			joysticks.erase(std::remove_if(joysticks.begin(), joysticks.end(), [&](Joystick* joy) {
				return joy->threadHandle == threadHandle;
			}), joysticks.end());
			setup();
		}
	}
	delete[] events;
}

void Joystick::onButtonRepeatTimer()
{
	auto timestamp = getTimestamp();
	for (auto& [_, button] : buttons) 
		button.onPressRepeatTimer(timestamp);
}

void Joystick::read(sol::this_state s)
{
	std::vector<Joystick*> _joysticks;

	for (Joystick* joystick : joysticks)
		if (joystick->L == s.L) _joysticks.push_back(joystick);

	const size_t numEvents = _joysticks.size() * 2;

	HANDLE* events = new HANDLE[numEvents]();

	size_t i = 0;
	for (Joystick* joystick : _joysticks)
		events[i++] = joystick->bufferAvailableEvent;

	for (Joystick* joystick : _joysticks)
		events[i++] = joystick->buttonRepeatTimerHandle;

	if (!numEvents)
		return;

	while (true) {

		DWORD eventIdx = WaitForMultipleObjects(numEvents, events, false, INFINITE);

		Joystick* joystick = _joysticks.at(eventIdx % (numEvents / 2));

		if (eventIdx < joysticks.size()) 
			joystick->getData();
		else 
			joystick->onButtonRepeatTimer();
	}
}

void Joystick::peek(sol::this_state s)
{
	for (Joystick* joystick : joysticks) {
		if (joystick->L == s.L) {
			joystick->getData();
			joystick->onButtonRepeatTimer();
		}
	}
}

Joystick::~Joystick()
{
	stopAndJoinBufferThread();
	joysticks.erase(std::remove(joysticks.begin(), joysticks.end(), this), joysticks.end());
	if (!joysticks.empty())
		startBufferThread();
}

std::map<std::string, int> Joystick::axisNamesToUsageId{
	{"X",		USAGE_ID_AXIS_X},
	{"Y",		USAGE_ID_AXIS_Y},
	{"Z",		USAGE_ID_AXIS_Z},
	{"Rx",		USAGE_ID_AXIS_Rx},
	{"Ry",		USAGE_ID_AXIS_Ry},
	{"Rz",		USAGE_ID_AXIS_Rz},
	{"Slider",	USAGE_ID_AXIS_Slider},
	{"Dial",	USAGE_ID_AXIS_Dial}
};

std::vector<Joystick*> Joystick::joysticks;

HANDLE Joystick::eventStopReadingBuffers = CreateEvent(NULL, NULL, NULL, NULL);

std::thread Joystick::bufferThread;

std::chrono::time_point<std::chrono::high_resolution_clock> Joystick::startTime = std::chrono::high_resolution_clock::now();