#include "Joystick.h"
#include "Button.h"
#include "JoystickExceptions.h"

std::mutex Joystick::bufferThreadMutex;

size_t Joystick::gcd(size_t a, size_t b)
{
	if (a == 0)
		return b;
	return gcd(b % a, a);
}

size_t Joystick::getTimestamp()
{
	auto now = std::chrono::high_resolution_clock::now();
	return std::chrono::duration_cast<std::chrono::milliseconds>(now - startTime).count();
}

std::vector<Joystick::DeviceInfo> Joystick::enumerateDevices()
{
	GUID hidGuid;
	HidD_GetHidGuid(&hidGuid);
	auto devInfo = SetupDiGetClassDevs(&hidGuid, NULL, NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);

	int memberIndex = 0;
	int currentDeviceNum = 0;

	std::vector<DeviceInfo> devices;
	while (true) {

		SP_DEVICE_INTERFACE_DATA deviceInterFaceData = {};
		deviceInterFaceData.cbSize = sizeof(SP_DEVICE_INTERFACE_DATA);
		bool res = SetupDiEnumDeviceInterfaces(
			devInfo,
			NULL,
			&hidGuid,
			memberIndex,
			&deviceInterFaceData
		);
		if (!res && GetLastError() == ERROR_NO_MORE_ITEMS)
			break;
		SP_DEVINFO_DATA devInfoData = {};
		devInfoData.cbSize = sizeof(SP_DEVINFO_DATA);

		DWORD requiredSize;
		auto result = SetupDiGetDeviceInterfaceDetail(
			devInfo,
			&deviceInterFaceData,
			NULL,
			NULL,
			&requiredSize,
			&devInfoData
		);

		auto detailData = reinterpret_cast<PSP_DEVICE_INTERFACE_DETAIL_DATA>(calloc(1, requiredSize));
		detailData->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA);

		result = SetupDiGetDeviceInterfaceDetail(
			devInfo,
			&deviceInterFaceData,
			detailData,
			requiredSize,
			NULL,
			&devInfoData
		);

		auto deviceHandle = CreateFile(
			detailData->DevicePath,
			FILE_GENERIC_READ,
			FILE_SHARE_WRITE | FILE_SHARE_READ,
			NULL,
			OPEN_EXISTING,
			FILE_FLAG_OVERLAPPED,
			NULL
		);

		if (deviceHandle != INVALID_HANDLE_VALUE) {
			HIDD_ATTRIBUTES attr = {};
			if (HidD_GetAttributes(deviceHandle, &attr)) {
				WCHAR productString[127] = {};
				HidD_GetProductString(deviceHandle, productString, sizeof(productString));
				WCHAR manufacturerString[127] = {};
				HidD_GetManufacturerString(deviceHandle, manufacturerString, sizeof(productString));
				devices.push_back(DeviceInfo{ std::wstring(productString), std::wstring(manufacturerString), attr.VendorID, attr.ProductID, std::wstring(detailData->DevicePath) });
			}
		}

		free(detailData);

		memberIndex++;
	}
	return devices;
}

void Joystick::stopAndJoinBufferThread()
{
	SetEvent(eventStopReadingBuffers);
	if (bufferThread.joinable())
		bufferThread.join();
	ResetEvent(eventStopReadingBuffers);
}

void Joystick::startBufferThread()
{
	bufferThread = std::thread(readBuffers);
}

bool Joystick::isButtonDataIndex(int dataIndex) const
{
	return !isAxisDataIndex(dataIndex);
}

bool Joystick::isAxisDataIndex(int dataIndex) const
{
	return axisDataIndices.find(dataIndex) != axisDataIndices.end();
}

int Joystick::findDataIndexForAxis(int usageId, int index) const
{
	int currIndex = 0;
	for (int i = 0; i < numValueCaps; ++i) {
		auto cap = valueCaps[i];
		if (cap.NotRange.Usage == usageId) {
			if (currIndex == index)
				return cap.NotRange.DataIndex;
			currIndex++;
		}
	}
	if (currIndex == 0) throw InvalidUsageId(usageId);
	throw InvalidIndex(index);
}

int Joystick::findDataIndexForButtonNum(size_t buttonNum) const
{
	if (zeroIndexedButtons)
		buttonNum++;
	for (int i = 0; i < numButtonCaps; ++i) {
		auto cap = buttonCaps[i];
		auto range = cap.Range;
		if (buttonNum >= range.UsageMin && buttonNum <= range.UsageMax) {
			int dataIndex = range.DataIndexMin + buttonNum - range.UsageMin;
			return dataIndex;
		}
	}
	std::string error = "Invalid button number: ";
	error += std::to_string(buttonNum);
	throw std::runtime_error(error);
}