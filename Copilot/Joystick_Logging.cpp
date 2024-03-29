#include "Joystick.h"
#include "Button.h"
#include "JoystickManager.h"

void Joystick::setLogName(const std::wstring& logName)
{
	this->logName = logName;
}

void Joystick::log(const std::wstring& msg)
{
	logger->info(msg);
}

void Joystick::startLogging(size_t axisDelta)
{
	for (int i = 0; i < numButtonCaps; ++i) {
		auto cap = buttonCaps[i];
		auto range = cap.Range;
		for (int i = range.DataIndexMin; i <= range.DataIndexMax; ++i) {
			auto buttonNum = range.DataIndexMax - i + range.UsageMin;
			if (zeroIndexedButtons)
				buttonNum--;
			onPress(buttonNum, [this, buttonNum](size_t, size_t, unsigned short) {
				std::wstringstream ss;
				ss << L"Joystick = " << logName << L"   |   Button " << buttonNum << " pressed";
				log(ss.str());
			});
			onRelease(buttonNum, [this, buttonNum](size_t, size_t, unsigned short) {
				std::wstringstream ss;
				ss << L"Joystick = " << logName << L"   |   Button " << buttonNum << " released";
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
		bool nameFound = false;
		for (auto [name, usageId] : axisNamesToUsageId) {
			if (usageId == caps.NotRange.Usage) {
				axisName = name;
				nameFound = true;
				break;
			}
		}
		auto callback = [axisName, this, axisIndex](double value) {
			std::wstringstream ss;
			ss << L"Joystick = " << logName
				<< "   |   Axis = " << axisName.c_str()
				<< std::setw(8 - axisName.length()) << std::left << axisIndex << "   |   "
				<< std::fixed << std::right << std::setw(6) << std::setprecision(2) << value << " %";
			log(ss.str());
		};
		if (nameFound) {
			auto props = onAxis(axisName, axisIndex, callback).props();
			if (axisDelta != -1) props->delta(axisDelta);
		} else {
			auto props = onAxis(caps.NotRange.Usage, axisIndex, callback).props();
			if (axisDelta != -1) props->delta(axisDelta);
		}
	}
}

void Joystick::logAllJoysticks(std::shared_ptr<JoystickManager> manager, size_t axisDelta)
{
	for (auto& joystick : manager->joysticks) {
		joystick->startLogging(axisDelta);
	}
}

