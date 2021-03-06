#pragma once
#include <stdint.h>
#include <Windows.h>
#include <functional>
#include <string>
#include "FSUIPC_User64.h"
#include "Copilot.h"

namespace FSUIPC {

	template <typename T>
	void write(DWORD offset, T value)
	{
		DWORD result;
		FSUIPC_Write(offset, sizeof(T), &value, &result);
		FSUIPC_Process(&result);
	}

	template<typename T>
	T read(DWORD offset)
	{
		DWORD result;
		T value = 0;
		FSUIPC_Read(offset, sizeof(T), &value, &result);
		FSUIPC_Process(&result);
		return value;
	}

	std::string errorString(DWORD res);

	void writeSTR(DWORD offset, const std::string& str, size_t length);

	void writeSTR(DWORD offset, const std::string& str);

	std::string readSTR(DWORD offset, size_t length);

	DWORD connect();
}