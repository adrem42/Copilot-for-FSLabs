#include "MCDU.h"

MCDU::MCDU(unsigned int side, unsigned int timeout, unsigned int port)
{
    std::wstring url = L"http://localhost:";
    url += std::to_wstring(port) + L"/MCDU/Display/3CA" + std::to_wstring(side);
    session = std::make_unique<HttpSession>(url, timeout);
}

std::optional<std::string> MCDU::getString()
{
    auto response = session->makeRequest();

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

std::string MCDU::getRaw()
{
    return session->makeRequest();
}

DWORD MCDU::lastError()
{
    return session->lastError;
}