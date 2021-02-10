#pragma once
#pragma once
#include <Windows.h>
#include <string>
#include "Exceptions.h"

class DirectoryWatcher {

	HANDLE dirHandle;
	OVERLAPPED overlapped = {};
	char buff[1024];
	const std::wstring logFileName;
	DWORD bytesRead = 0;

public:

	DirectoryWatcher(const std::wstring& FSUIPCdir, const std::wstring& logFileName)
		:logFileName(logFileName)
	{
		dirHandle = CreateFile(
			FSUIPCdir.c_str(),
			FILE_GENERIC_READ,
			FILE_SHARE_WRITE | FILE_SHARE_READ,
			NULL,
			OPEN_EXISTING,
			FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
			NULL);

		overlapped.hEvent = CreateEvent(0, 0, 0, 0);

		if (dirHandle == INVALID_HANDLE_VALUE)
			throw InvalidHandleException(GetLastError(), FSUIPCdir);
	}

	HANDLE next()
	{
		ZeroMemory(buff, sizeof buff);
		ZeroMemory(&overlapped, sizeof overlapped);
		overlapped.hEvent = CreateEvent(0, 0, 0, 0);
		ReadDirectoryChangesW(
			dirHandle,
			&buff,
			sizeof buff,
			false,
			FILE_NOTIFY_CHANGE_FILE_NAME,
			&bytesRead,
			&overlapped,
			NULL
		);
		return overlapped.hEvent;
	}

	FILE_NOTIFY_INFORMATION getInfo()
	{
		return *reinterpret_cast<FILE_NOTIFY_INFORMATION*>(buff);
	}

};