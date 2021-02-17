#pragma once
#include <exception>
#include <string>

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