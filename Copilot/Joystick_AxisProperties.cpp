#include "Joystick.h"
#include "Button.h"

Joystick::AxisProperties& Joystick::AxisProperties::delta(double delta)
{
	_delta = delta;
	return *this;
}

Joystick::AxisProperties& Joystick::AxisProperties::invert()
{
	_invert = true;
	return *this;
}

Joystick::AxisProperties& Joystick::AxisProperties::bounds(double lower, double upper)
{
	if (lower > upper)
		throw std::runtime_error("The value for the upper  bound must be greater than for the lower bound.");
	boundLower = lower / 100.0;
	boundUpper = upper / 100.0;
	return *this;
}

Joystick::AxisProperties& Joystick::AxisProperties::nullzone(double lower, double upper)
{
	if (lower > upper)
		throw std::runtime_error("The value for the upper null zone bound must be greater than for the lower bound.");
	nullzoneLower = lower / 100.0;
	nullzoneUpper = upper / 100.0;
	return *this;
}

bool Joystick::AxisProperties::valueChanged(double value)
{
	return fabs(value - prevValue) >= _delta;
}

double Joystick::AxisProperties::transformValue(double value)
{
	if (value < nullzoneLower) {
		if (value < boundLower)
			value = boundLower;
		value = (value - boundLower) / (nullzoneLower - boundLower) * 0.5;
	} else if (value <= nullzoneUpper) {
		value = 0.5;
	} else {
		if (value > boundUpper)
			value = boundUpper;
		value = ((value - nullzoneUpper) / (boundUpper - nullzoneUpper) * 0.5) + 0.5;
	}

	if (!_invert) {
		value *= AXIS_MAX_VALUE;
	} else {
		value = -(value * AXIS_MAX_VALUE) + AXIS_MAX_VALUE;
	}
	
	return value;
}