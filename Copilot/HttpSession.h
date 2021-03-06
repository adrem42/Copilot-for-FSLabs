#pragma comment(lib, "winhttp.lib")
#pragma once

#include <windows.h>
#include <Winhttp.h>
#include <string>
#include <optional>
#include <iostream>
#include <cmath>

class HttpSession {

    HINTERNET  hSession = NULL;
    HINTERNET  hConnect = NULL;
    HINTERNET hRequest = NULL;
    std::wstring url;
    URL_COMPONENTS urlComp;
    unsigned int receiveTimeout;
    void initRequest();

public:

    DWORD lastError;
    HttpSession(const std::wstring& url, unsigned int receiveTimeout = 1000);
    ~HttpSession();
    void setPort(int newPort);
    std::string makeRequest();
};

