#pragma once
#include <Windows.h>
#include <string>
#include <sstream>
#include <optional>
#include <queue>
#include "Exceptions.h"

class LogReader {

	HANDLE fileHandle = 0;
	std::string nextLineStart;
	std::queue<std::string> lines;

	size_t readLines()
	{
		while (true) {
			char buff[1024] = {};
			DWORD bytesRead;
			if (!ReadFile(fileHandle, buff, sizeof buff, &bytesRead, NULL))
				break;
			if (!bytesRead) break;
			const char* curr = buff;
			size_t bytesLeft = bytesRead;
			while (const char* lineBreak = reinterpret_cast<const char*>(memchr(curr, '\n', bytesLeft))) {
				std::string s = std::string(curr, lineBreak - curr);
				if (!nextLineStart.empty()) {
					s = nextLineStart + std::string(curr, lineBreak - curr);
					nextLineStart = std::string();
				}
				lines.push(s);
				bytesLeft -= lineBreak - curr + 1;
				curr = lineBreak + 1;
			}
			if (curr < buff + bytesRead)
				nextLineStart = std::string(curr, bytesLeft);
		}
		return lines.size();
	}

public:

	LogReader(const std::wstring& path)
	{
		fileHandle = CreateFileW(
			path.c_str(),
			FILE_GENERIC_READ,
			FILE_SHARE_WRITE | FILE_SHARE_READ | FILE_SHARE_DELETE,
			NULL, OPEN_EXISTING, 0, NULL);
		std::cout << GetLastError() << std::endl;
		if (fileHandle == INVALID_HANDLE_VALUE)
			throw InvalidHandleException(GetLastError(), path);
	}

	std::string nextLine()
	{
		if (lines.empty() && !readLines())
			return "";
		std::string line = lines.front();
		lines.pop();
		return line;
	}

	~LogReader()
	{
		CloseHandle(fileHandle);
	}
};