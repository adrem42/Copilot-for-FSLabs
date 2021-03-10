#pragma once
#include <stdint.h>
#include <Windows.h>
#include <functional>
#include <string>
#include "FSUIPC_User64.h"
#include "Copilot.h"
#include "mutex"


namespace FSUIPC {

	extern std::mutex mutex;

	template <typename T>
	void write(DWORD offset, T value)
	{
		std::lock_guard<std::mutex> lock(mutex);
		DWORD result;
		FSUIPC_Write(offset, sizeof(T), &value, &result);
		FSUIPC_Process(&result);
	}

	template<typename T>
	T read(DWORD offset)
	{
		std::lock_guard<std::mutex> lock(mutex);
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