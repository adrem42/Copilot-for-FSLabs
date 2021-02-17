#include "Joystick.h"

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
	boundLower = lower;
	boundUpper = upper;
	return *this;
}

Joystick::AxisProperties& Joystick::AxisProperties::nullzone(double lower, double upper)
{
	if (lower > upper)
		throw std::runtime_error("The value for the upper null zone bound must be greater than for the lower bound.");
	nullzoneLower = lower;
	nullzoneUpper = upper;
	return *this;
}

bool Joystick::AxisProperties::valueChanged(double value)
{
	return fabs(value - prevValue) >= _delta;
}

bool Joystick::AxisProperties::isInNullzone(double value)
{
	return value > nullzoneLower&& value < nullzoneUpper;
}

double Joystick::AxisProperties::transformValue(double value)
{
	value = std::max<double>(value, boundLower);
	value = std::min<double>(value, boundUpper);
	value = (value - boundLower - (std::min<double>(value, nullzoneUpper) - std::min<double>(value, nullzoneLower))) / (boundUpper - boundLower - (nullzoneUpper - nullzoneLower));
	value *= AXIS_MAX_VALUE;
	if (_invert)
		value = -value + AXIS_MAX_VALUE;
	return value;
}