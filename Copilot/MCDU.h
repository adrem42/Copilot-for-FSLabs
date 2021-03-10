#pragma once
#include "HttpSession.h"
#include <memory>

class MCDU {

    std::unique_ptr<HttpSession> session;

public:

    static constexpr int defaultPort = 8080;

    MCDU(unsigned int side, unsigned int timeout, unsigned int port = defaultPort);

    std::optional<std::string> getString();

    std::string getRaw();

    DWORD lastError();

};

