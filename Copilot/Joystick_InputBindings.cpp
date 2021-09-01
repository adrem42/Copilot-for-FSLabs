#include "Joystick.h"
#include "JoystickExceptions.h"
#include "Button.h"

void Joystick::onPress(size_t buttonNum, ButtonCallback callback)
{
	auto dataIndex = findDataIndexForButtonNum(buttonNum);
	buttons.at(dataIndex).onPressCallbacks.push_back(callback);
}

void Joystick::onPressRepeat(size_t buttonNum, ButtonCallback callback)
{
	auto dataIndex = findDataIndexForButtonNum(buttonNum);
	buttons.at(dataIndex).onPressRepeatCallbacks.push_back(Button::OnPressRepeatCallback{ callback });
}

void Joystick::onPressRepeat(size_t buttonNum, int repeatInterval, ButtonCallback callback)
{
	auto dataIndex = findDataIndexForButtonNum(buttonNum);
	buttons.at(dataIndex).onPressRepeatCallbacks
		.emplace_back(Button::OnPressRepeatCallback{ callback, repeatInterval });
}

void Joystick::onRelease(size_t buttonNum, ButtonCallback callback)
{
	auto dataIndex = findDataIndexForButtonNum(buttonNum);
	buttons.at(dataIndex).onReleasecallbacks.push_back(callback);
}

void Joystick::useZeroIndexedButtons()
{
	zeroIndexedButtons = true;
}

void Joystick::setButtonStatesUnknown()
{
	for (auto& [_, button] : buttons)
		button.setStateUnknown();
}

void Joystick::setButtonStateUnknown(int buttonNum)
{
	for (auto& [_, button] : buttons) {
		if (button.buttonNum == buttonNum)
			button.setStateUnknown();
	}
}

Joystick::AxisCallback& Joystick::onAxis(std::string axisName, std::function<void(double)> callback)
{
	return onAxis(axisName, 0, callback);
}

Joystick::AxisCallback& Joystick::onAxis(std::string axisName, int axisIndex, std::function<void(double)> callback)
{
	int usageId = axisNamesToUsageId[axisName];
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

Joystick::AxisCallback& Joystick::onAxis(int usageId, std::function<void(double)> callback)
{
	return onAxis(usageId, 0, callback);
}

Joystick::AxisCallback& Joystick::onAxis(int usageId, int axisIndex, std::function<void(double)> callback)
{
	size_t dataIndex = findDataIndexForAxis(usageId, axisIndex);
	return axes.at(dataIndex).callbacks.emplace_back(AxisCallback{ callback });
}

Joystick::AxisProperties& Joystick::axisProps(std::string axisName, int index)
{
	return axisProps(axisNamesToUsageId[axisName], index);
}

Joystick::AxisProperties& Joystick::axisProps(std::string axisName)
{
	return axisProps(axisName, 0);
}

Joystick::AxisProperties& Joystick::axisProps(int usageID, int index)
{
	return axes.at(findDataIndexForAxis(usageID, index)).props;
}

Joystick::AxisProperties& Joystick::axisProps(int usageID)
{
	return axisProps(usageID, 0);
}