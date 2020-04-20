#pragma comment(lib, "winhttp.lib")
#pragma once

#include <windows.h>
#include <Winhttp.h>
#include <string>
#include <nlohmann/json.hpp>
#include <optional>

using json = nlohmann::json;

class HttpRequest {

    HINTERNET  hSession = NULL;
    HINTERNET  hConnect = NULL;
    HINTERNET hRequest = NULL;

    std::wstring objectNameWstr;

    void initRequest(int port)
    {
        if (hSession)
            hConnect = WinHttpConnect(hSession, L"localhost",
                                      port, 0);

        if (hConnect)
            hRequest = WinHttpOpenRequest(hConnect, L"GET", objectNameWstr.c_str(),
                                          NULL, WINHTTP_NO_REFERER,
                                          WINHTTP_DEFAULT_ACCEPT_TYPES,
                                          NULL);
    }

public:

    HttpRequest(const std::string& sessionName, int port, const std::string& objectName)
    {
        auto sessionWstr = std::wstring(sessionName.begin(), sessionName.end());
        hSession = WinHttpOpen(sessionWstr.c_str(),
                               WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                               WINHTTP_NO_PROXY_NAME,
                               WINHTTP_NO_PROXY_BYPASS, 0);
        objectNameWstr = std::wstring(objectName.begin(), objectName.end()).c_str();
        initRequest(port);

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
        initRequest(newPort);

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

    std::optional<json> getJson()
    {
        auto response = request->get();
        if (response != "") {
            return std::optional<json>(json::parse(response).at("Value"));
        }
        return {};
    }

public:
    static constexpr int defaultPort = 8080;

    Mcdu(int side, int port = defaultPort)
    {
        std::string objectName = "MCDU/Display/3CA";
        request = std::make_unique<HttpRequest>("Mcdu", port, objectName + std::to_string(side));
    }

    void setPort(int port)
    {
        request->setPort(port);
    }

    std::optional<std::string> getString()
    {
        std::string s;
        s.reserve(340);
        auto j = getJson();
        if (j) {
            for (auto it = j->begin(); it != j->end(); it++) {
                auto c = it.value()[0];
                s += c.is_null() ? ' ' : (char)atoi(c.dump().c_str());
            }
            return std::optional<std::string>(s);
        }
        return {};
    }

    std::string getFromLua()
    {
        return request->get();
    }

};
