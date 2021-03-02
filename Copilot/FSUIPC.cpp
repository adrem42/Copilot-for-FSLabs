#include "FSUIPC.h"

const char* FSUIPCerrors[] =
{   "Okay",
	"Attempt to Open when already Open",
	"Cannot link to FSUIPC or WideClient",
	"Failed to Register common message with Windows",
	"Failed to create Atom for mapping filename",
	"Failed to create a file mapping object",
	"Failed to open a view to the file map",
	"Incorrect version of FSUIPC, or not FSUIPC",
	"Sim is not version requested",
	"Call cannot execute, link not Open",
	"Call cannot execute: no requests accumulated",
	"IPC timed out all retries",
	"IPC sendmessage failed all retries",
	"IPC request contains bad data",
	"Maybe running on WideClient, but FS not running on Server, or wrong FSUIPC",
	"Read or Write request cannot be added, memory for Process is full",
};

uint8_t FSUIPCmemory[1024];

namespace FSUIPC {

	DWORD connect()
	{
		DWORD result;
		
		FSUIPC_Open2(SIM_ANY, &result, FSUIPCmemory, sizeof(FSUIPCmemory));
		return result;
	}

	std::string errorString(DWORD res)
	{
		return FSUIPCerrors[res];
	}
}