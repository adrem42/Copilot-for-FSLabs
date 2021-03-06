#pragma once
#include <Windows.h>
#include <SimConnect.h>
#include "SimConnect.h"
#include <memory>
#include <string>
#include <optional>

namespace SimInterface {

    bool init();

    void close();

    void fireMouseMacro(size_t rectId, unsigned short clickType);

    void hideCursor();

    std::optional<double> readLvar(const std::string&);

    void writeLvar(const std::string&, double);

    void createLvar(const std::string&, double = 0);

    void sendFSControl(size_t, size_t = 0);
}