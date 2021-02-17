#include "Joystick.h"

void Joystick::AxisCallback::operator()(double value)
{
	callback(value);
}

std::shared_ptr<Joystick::AxisProperties> Joystick::AxisCallback::props()
{
	axisProps = std::make_shared<Joystick::AxisProperties>();
	return axisProps;
}