#include "Joystick.h"
#include "Button.h"

Joystick::Joystick(int vendorId, int productId, int deviceNum)
	:L(L), vendorId(vendorId), productId(productId), deviceNum(deviceNum)
{

	int currDevNum = 0;

	for (auto& device : enumerateDevices()) {
		if (device.productId == productId && device.vendorId == vendorId
			&& currDevNum++ == deviceNum) {
			auto handle = CreateFile(
				device.devicePath.c_str(),
				FILE_GENERIC_READ,
				FILE_SHARE_WRITE | FILE_SHARE_READ,
				NULL,
				OPEN_EXISTING,
				FILE_FLAG_OVERLAPPED,
				NULL
			);
			if (handle == INVALID_HANDLE_VALUE)
				break;
			this->device = handle;
			deviceInfo = std::make_shared<DeviceInfo>(device);
			logName = deviceInfo->product + L" " + std::to_wstring(deviceNum);
		}
	}

	if (!device) {
		std::stringstream ss;
		ss << "Failed to open device - vendord ID: 0x"
			<< std::hex << std::setfill('0') << std::setw(4) << std::uppercase << vendorId
			<< ", product ID : 0x" << std::setfill('0') << std::setw(4) << productId
			<< ", device: " << deviceNum;
		throw std::runtime_error(ss.str());
	}

	initDevice();
}

void Joystick::initDevice()
{
	HidD_GetPreparsedData(device, &preparsedData);
	initCaps();
	initButtonCaps();
	initValueCaps();

	buffSize = caps.InputReportByteLength;

	dataListSize = HidP_MaxDataListLength(HidP_Input, preparsedData);
	dataList = new HIDP_DATA[dataListSize]();
}

NTSTATUS Joystick::initCaps()
{
	return HidP_GetCaps(preparsedData, &caps);
}

NTSTATUS Joystick::initButtonCaps()
{
	numButtonCaps = caps.NumberInputButtonCaps;
	buttonCaps = new HIDP_BUTTON_CAPS[numButtonCaps];
	auto status = HidP_GetButtonCaps(HidP_Input, buttonCaps, &numButtonCaps, preparsedData);
	int largestDataIndex = 0;
	if (status == HIDP_STATUS_SUCCESS) {
		for (int i = 0; i < numButtonCaps; ++i) {
			auto cap = buttonCaps[i];
			auto range = cap.Range;
			largestDataIndex = std::max<size_t>(largestDataIndex, range.DataIndexMax + 1);
			for (int buttonNum = cap.Range.UsageMin, dataIndex = cap.Range.DataIndexMin;
				 buttonNum <= cap.Range.UsageMax;
				 ++buttonNum, ++dataIndex) {
				buttons.emplace(dataIndex, Button(buttonNum, dataIndex));
			}
		}
	}

	return status;
}

NTSTATUS Joystick::initValueCaps()
{
	numValueCaps = caps.NumberInputValueCaps;
	valueCaps = new HIDP_VALUE_CAPS[numValueCaps];

	auto status = HidP_GetValueCaps(HidP_Input, valueCaps, &numValueCaps, preparsedData);
	int largestDataIndex = 0;
	if (status == HIDP_STATUS_SUCCESS) {
		for (int i = 0; i < numValueCaps; ++i) {
			auto& cap = valueCaps[i];
			axes.resize(std::max<size_t>(axes.size(), cap.NotRange.DataIndex + 1));
			axes.at(cap.NotRange.DataIndex).caps = cap;
			axisDataIndices.insert(cap.NotRange.DataIndex);
		}
	}
	return status;
}