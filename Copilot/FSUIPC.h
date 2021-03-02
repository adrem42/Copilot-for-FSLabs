#pragma once
#include <stdint.h>
#include <Windows.h>
#include <functional>
#include <string>
#include "FSUIPC/include/FSUIPC_User64.h"
#include "Copilot.h"

namespace FSUIPC {

	std::string errorString(DWORD res);

	template <typename T>
	inline void write(DWORD offset, T value)
	{
		DWORD result;
		FSUIPC_Write(offset, sizeof(T), &value, &result);
		FSUIPC_Process(&result);
	}

	template<typename T>
	inline T read(DWORD offset)
	{
		DWORD result;
		T value;
		FSUIPC_Read(offset, sizeof(T), &value, &result);
		FSUIPC_Process(&result);
		return value;
	}

	inline void writeSTR(DWORD offset, const std::string& str)
	{
		DWORD result;
		FSUIPC_Write(offset, str.length(), reinterpret_cast<void*>(const_cast<char*>(str.c_str())), &result);
		FSUIPC_Process(&result);
	}

	inline std::string readSTR(DWORD offset, size_t length)
	{
		DWORD result;
		char str[256] = {};
		FSUIPC_Read(offset, length, str, &result);
		FSUIPC_Process(&result);
		return str;
	}

	DWORD connect();
}