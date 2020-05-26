#pragma comment(lib, "winhttp.lib")
#pragma once

#include <windows.h>
#include <Winhttp.h>
#include <string>
#include <optional>
#include <iostream>
#include <cmath>

class HttpRequest{

    HINTERNET  hSession = NULL;
    HINTERNET  hConnect = NULL;
    HINTERNET hRequest = NULL;
    std::wstring urlWstr;
    URL_COMPONENTS urlComp;

    void initRequest()
    {
        auto lpwHostName = urlComp.lpszHostName;
        auto hostName = std::wstring(lpwHostName);
        auto serverName = hostName.substr(0, urlComp.dwHostNameLength);
        if (hSession)
            hConnect = WinHttpConnect(hSession, serverName.c_str(),
                                      urlComp.nPort, 0);

        if (hConnect)
            hRequest = WinHttpOpenRequest(hConnect, L"GET", urlComp.lpszUrlPath,
                                          NULL, WINHTTP_NO_REFERER,
                                          WINHTTP_DEFAULT_ACCEPT_TYPES,
                                          NULL);
    }

public:

    HttpRequest(const std::string& url)
    {

        urlWstr = std::wstring(url.begin(), url.end());

        // Initialize the URL_COMPONENTS structure.
        ZeroMemory(&urlComp, sizeof(urlComp));
        urlComp.dwStructSize = sizeof(urlComp);

        // Set required component lengths to non-zero 
        // so that they are cracked.
        urlComp.dwSchemeLength = (DWORD)-1;
        urlComp.dwHostNameLength = (DWORD)-1;
        urlComp.dwUrlPathLength = (DWORD)-1;
        urlComp.dwExtraInfoLength = (DWORD)-1;

        LPCWSTR lpwstrUrl = urlWstr.c_str();

        WinHttpCrackUrl(lpwstrUrl, (DWORD)wcslen(lpwstrUrl), 0, &urlComp);

        hSession = WinHttpOpen(L"",
                               WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                               WINHTTP_NO_PROXY_NAME,
                               WINHTTP_NO_PROXY_BYPASS, 0);
        WinHttpSetTimeouts(hSession, 0, 60000, 30000, 1000);
        initRequest();
    }

    ~HttpRequest()
    {
        if (hRequest) WinHttpCloseHandle(hRequest);
        if (hConnect) WinHttpCloseHandle(hConnect);
        if (hSession) WinHttpCloseHandle(hSession);
    }

    void setPort(int newPort)
    {

        if (hRequest) WinHttpCloseHandle(hRequest);
        if (hConnect) WinHttpCloseHandle(hConnect);
        urlComp.nPort = newPort;
        initRequest();
    }

    std::string get()
    {
        BOOL  bResults = FALSE;
        DWORD dwSize = 0;
        DWORD dwDownloaded = 0;
        LPSTR pszOutBuffer;

        if (hRequest)
            bResults = WinHttpSendRequest(hRequest,
                                          WINHTTP_NO_ADDITIONAL_HEADERS,
                                          0, WINHTTP_NO_REQUEST_DATA, 0,
                                          0, 0);
        if (bResults)
            bResults = WinHttpReceiveResponse(hRequest, NULL);

        std::string result;

        if (bResults) {
            do {
                // Check for available data.
                dwSize = 0;
                if (!WinHttpQueryDataAvailable(hRequest, &dwSize)) {
                    break;
                }

                // No more available data.
                if (!dwSize)
                    break;

                // Allocate space for the buffer.
                pszOutBuffer = new char[dwSize + 1];
                if (!pszOutBuffer) {
                    break;
                }

                // Read the Data.
                ZeroMemory(pszOutBuffer, dwSize + 1);

                if (WinHttpReadData(hRequest, (LPVOID)pszOutBuffer,
                    dwSize, &dwDownloaded)) {
                    result.append(pszOutBuffer);
                }

                delete[] pszOutBuffer;

                if (!dwDownloaded)
                    break;

            } while (dwSize > 0);
        }
        return result;
    }
};

class Mcdu {

    std::unique_ptr<HttpRequest> request;

public:
    static constexpr int defaultPort = 8080;

    Mcdu(int side, int port = defaultPort)
    {
        std::string url = "http://localhost:";
        url += std::to_string(port) + "/MCDU/Display/3CA" + std::to_string(side);
        request = std::make_unique<HttpRequest>(url);
    }

    void setPort(int port)
    {
        request->setPort(port);
    }

    std::optional<std::string> getString()
    {
        auto response = request->get();

        if (response == "") return {};

        const char* jsonChar = response.c_str() + response.length() - 2;
        char curr;
        char prev = 0;
        const static int length = 337;
        char buff[length];
        int pos = length;
        buff[--pos] = '\0';

        do {
            curr = *--jsonChar;
            switch (prev) {
                case ']':
                    if (curr == '[') {
                        buff[--pos] = ' ';
                    } else {
                        curr = *(jsonChar -= 4);
                        int i = 0;
                        char _char = 0;
                        do {
                            _char += (curr - '0') * pow(10, i++);
                            curr = *--jsonChar;
                        } while (curr != '[');
                        buff[--pos] = _char;
                    }
                    break;
                case '[':
                    if (curr == '[') pos = 0;
                    break;
                default:
                    break;
            }
            prev = curr == ',' ? prev : curr;
        } while (pos > 0);

        return buff;
    }

    std::string getRaw()
    {
        return request->get();
    }

};
