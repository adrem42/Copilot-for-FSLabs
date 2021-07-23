#include "HttpSession.h"

HttpSession::HttpSession(const std::wstring& url, unsigned int receiveTimeout)
    :url(url), receiveTimeout(receiveTimeout)
{
    hSession = WinHttpOpen(TEXT(""),
                           WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                           WINHTTP_NO_PROXY_NAME,
                           WINHTTP_NO_PROXY_BYPASS, 0);

    WinHttpSetTimeouts(hSession, 0, 60000, 30000, receiveTimeout);

    initRequest();
}

void HttpSession::initRequest()
{
    URL_COMPONENTS urlComp = {};
    urlComp.dwStructSize = sizeof(urlComp);
    urlComp.dwSchemeLength = (DWORD)-1;
    urlComp.dwHostNameLength = (DWORD)-1;
    urlComp.dwUrlPathLength = (DWORD)-1;
    urlComp.dwExtraInfoLength = (DWORD)-1;

    WinHttpCrackUrl(url.c_str(), url.length(), 0, &urlComp);

    auto lpwHostName = urlComp.lpszHostName;
    auto hostName = std::wstring(lpwHostName);
    auto serverName = hostName.substr(0, urlComp.dwHostNameLength);
    if (hSession)
        hConnect = WinHttpConnect(
            hSession, serverName.c_str(),
            port != -1 ? port : urlComp.nPort, 0
        );

    if (hConnect)
        hRequest = WinHttpOpenRequest(hConnect, TEXT("GET"), urlComp.lpszUrlPath,
                                      NULL, WINHTTP_NO_REFERER,
                                      WINHTTP_DEFAULT_ACCEPT_TYPES,
                                      NULL);
}

void HttpSession::setPath(const std::wstring& path)
{
    if (hRequest) WinHttpCloseHandle(hRequest);
    if (hConnect)
        hRequest = WinHttpOpenRequest(hConnect, TEXT("GET"), path.c_str(),
                                      NULL, WINHTTP_NO_REFERER,
                                      WINHTTP_DEFAULT_ACCEPT_TYPES,
                                      NULL);
}

HttpSession::~HttpSession()
{
    if (hRequest) WinHttpCloseHandle(hRequest);
    if (hConnect) WinHttpCloseHandle(hConnect);
    if (hSession) WinHttpCloseHandle(hSession);
}

std::string HttpSession::makeRequest()
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
    lastError = 0;

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
    } else {
        lastError = GetLastError();
    }
    return result;
}