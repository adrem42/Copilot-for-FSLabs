#pragma once
#include <Windows.h>
#include <SimConnect.h>
#include "SimConnect.h"
#include <memory>
#include <string>
#include <optional>

namespace SimInterface {

    void createWindow();

    void onSimShutdown();

    void fireMouseMacro(size_t rectId, unsigned short clickType);

    void hideCursor();

    void initSimConnect();

    std::optional<double> readLvar(const std::string&);

    void writeLvar(const std::string&, double);

    void createLvar(const std::string&, double);
}