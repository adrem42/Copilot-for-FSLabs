#pragma once
#include <exception>
#include <string>

class InvalidHandleException : std::exception {
public:
	const size_t errorCode;
	const std::wstring path;
	InvalidHandleException(size_t errorCode, const std::wstring& path)
		:errorCode(errorCode), path(path) {}
};