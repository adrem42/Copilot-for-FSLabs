#include "Sound.h"
#include "Copilot.h"
#include <cmath>


TimePoint Sound::nextFreeSlot = std::chrono::system_clock::now();
std::queue<std::pair<Sound*, TimePoint>> Sound::soundQueue;
Sound* Sound::prevSound;
ISpVoice* Sound::voice = nullptr;
std::mutex Sound::mtx;
double Sound::userVolume = 1, Sound::globalVolume = 0, Sound::volKnobPos = -1;

std::string Sound::knobLvar;
std::string Sound::switchLvar;

Sound::Sound(const std::string& path, int length, double fileRelVolume)
	:length(length), fileRelVolume(fileRelVolume)
{
	stream = BASS_StreamCreateFile(FALSE, path.c_str(), 0, 0, 0);
	if (!length) {
		size_t bytes = BASS_ChannelGetLength(stream, BASS_POS_BYTE);
		this->length = BASS_ChannelBytes2Seconds(stream, bytes) * 1000 + 300;
	}

	auto err = BASS_ErrorGetCode();
	if (err != BASS_OK)
		copilot::logger->error("Error {} initializing sound file {}", err, path.c_str());
	adjustVolumeFromGlobal();
}

Sound::Sound(const std::string& path, int length)
	:Sound(path, length, 1)
{
}

Sound::Sound(const std::string& path)
	:Sound(path, 0, 1)
{
}

void Sound::enqueue(int delay)
{
	std::lock_guard<std::mutex> lock(mtx);
	auto now = std::chrono::system_clock::now();
	if (delay == -1 && now < nextFreeSlot) {
		Sleep((nextFreeSlot - now).count());
	}
	if (delay > 0 || now < nextFreeSlot) {
		auto playTime = now + std::chrono::milliseconds(delay);
		if (playTime < nextFreeSlot) {
			playTime = nextFreeSlot;
		}
		soundQueue.emplace(this, playTime);
		nextFreeSlot = playTime + std::chrono::milliseconds(length);
	} else {
		playNow();
		if (delay == -1) {
			Sleep(length);
		}
		nextFreeSlot = now + std::chrono::milliseconds(length);
	}
}

void Sound::enqueue()
{
	enqueue(0);
}

void Sound::playNow()
{
	adjustVolumeFromGlobal();
	BASS_ChannelPlay(stream, true);
	prevSound = this;
}

void Sound::init(int devNum, int pmSide, double userVolume, ISpVoice* voice)
{
	if (pmSide == 1) {
		knobLvar = "VC_PED_COMM_2_INT_Knob";
		switchLvar = "VC_PED_COMM_2_INT_Switch";
	} else if (pmSide == 2) {
		knobLvar = "VC_PED_COMM_1_INT_Knob";
		switchLvar = "VC_PED_COMM_1_INT_Switch";
	}

	Sound::voice = voice;

	nextFreeSlot = std::chrono::system_clock::now();
	Sound::userVolume = userVolume;
	volKnobPos = -1; // to force a volume update
	BASS_Init(devNum, 44100, BASS_DEVICE_STEREO, 0, NULL);
}

void Sound::update(bool isFslAircraft)
{
	double newVolKnobPos = isFslAircraft ? getVolumeKnobPos() / 270 : volKnobPos;
	bool volumeChanged = volKnobPos != newVolKnobPos;
	if (!soundQueue.empty() || volumeChanged) {
		std::lock_guard<std::mutex> lock(mtx);
		if (!soundQueue.empty()) {
			auto& currSound = soundQueue.front();
			if (std::chrono::system_clock::now() > currSound.second) {
				currSound.first->playNow();
				prevSound = currSound.first;
				soundQueue.pop();
			}
		}
		if (volumeChanged) {
			volKnobPos = newVolKnobPos;
			onVolumeChanged(volKnobPos);
		}
	}
}

void Sound::onVolumeChanged(double volKnobPos)
{
	globalVolume = 3.1623e-3 * exp(((1 - zeroVolumeThreshold) * volKnobPos + zeroVolumeThreshold) * 5.757) * userVolume;
	if (!soundQueue.empty())
		soundQueue.front().first->adjustVolumeFromGlobal();
	if (prevSound != nullptr) {
		prevSound->adjustVolumeFromGlobal();
	}
	if (voice)
		voice->SetVolume(globalVolume * 100);
}

void Sound::adjustVolumeFromGlobal()
{
	BASS_ChannelSetAttribute(stream, BASS_ATTRIB_VOL, (float)(globalVolume * fileRelVolume));
}

double Sound::getVolumeKnobPos()
{
	if (copilot::readLvar(switchLvar) != 10) {
		return copilot::readLvar(knobLvar);
	}
	return 0;
}
