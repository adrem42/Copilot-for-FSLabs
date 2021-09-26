#include "Joystick.h"
#include "Button.h"

Joystick::AxisProperties& Joystick::AxisProperties::delta(double delta)
{
	_delta = delta / 100;
	return *this;
}

Joystick::AxisProperties& Joystick::AxisProperties::scale(double scale)
{
	_scale = scale;
	if (_scale <= 0)
		throw std::runtime_error("Bad argument");
	return *this;
}

Joystick::AxisProperties& Joystick::AxisProperties::curve(double curve)
{
	if (curve > 1) {
		curve = 1;
	} else if (curve < -1) {
		curve = -1;
	}
	curveFactor = curve;
	return *this;
}

Joystick::AxisProperties& Joystick::AxisProperties::isSigned(int flags)
{
	if (flags == SIGNED_POST)
		_signed = SIGNED_POST;
	else
		_signed = SIGNED_PRE;
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
	return fabs(value - prevValue) >= _delta * _scale;
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

	if (_invert) {
		value = -(value - 1);
	}

	if (_signed == SIGNED_PRE) {
		value = (value - 0.5) * 2;
	}

	if (curveFactor) {
		value = value * (1 - curveFactor) + curveFactor * pow(value, 3);
		if (value > 1) value = 1; else if (value < -1) value = -1;
	}

	if (_signed == SIGNED_POST) {
		value = (value - 0.5) * 2;
	}

	value *= _scale;

	return value;
}