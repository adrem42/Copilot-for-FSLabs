#include "Sound.h"
#include "Copilot.h"
#include <cmath>

TimePoint Sound::nextFreeSlot = std::chrono::system_clock::now();
std::queue<std::pair<Sound*, TimePoint>> Sound::soundQueue;
Sound* Sound::prevSound;
std::mutex Sound::mtx;
double Sound::globalVolume = 0, Sound::volKnobPos = -1;

Sound::Sound(const std::string& path, int length, double fileRelVolume)
	:length(length), fileRelVolume(fileRelVolume)
{
	stream = BASS_StreamCreateFile(FALSE, path.c_str(), 0, 0, 0);
	BASS_ChannelSetAttribute(stream, BASS_ATTRIB_VOL, (float)(fileRelVolume * globalVolume));
}

Sound::Sound(const std::string& path, int length)
	:Sound(path, length, 1)
{
}

Sound::Sound(const std::string& path)
	:Sound(path, 0, 1)
{
}

void Sound::play(int delay)
{
	std::lock_guard<std::mutex> lock(mtx);
	auto now = std::chrono::system_clock::now();
	if (delay > 0 || now < nextFreeSlot) {
		auto playTime = now + std::chrono::milliseconds(delay);
		if (playTime < nextFreeSlot) {
			playTime = nextFreeSlot;
		}
		soundQueue.emplace(this, playTime);
		nextFreeSlot = playTime + std::chrono::milliseconds(length);
	} else {
		playNow();
		nextFreeSlot = now + std::chrono::milliseconds(length);
	}
}

void Sound::play()
{
	play(0);
}

void Sound::playNow()
{
	setVolume(fileRelVolume * globalVolume);
	BASS_ChannelPlay(stream, true);
	prevSound = this;
}

void Sound::setGlobalVolume(double volume)
{
	globalVolume = volume / 100;
}

void Sound::init(int device, int pmSide)
{
	if (pmSide == 1) {
		volumeKnob.knobLvar = "VC_PED_COMM_2_INT_Knob";
		volumeKnob.switchLvar = "VC_PED_COMM_2_INT_Switch";
	} else if (pmSide == 2) {
		volumeKnob.knobLvar = "VC_PED_COMM_1_INT_Knob";
		volumeKnob.switchLvar = "VC_PED_COMM_1_INT_Switch";
	}

	nextFreeSlot = std::chrono::system_clock::now();
	
	BASS_Init(device, 44100, BASS_DEVICE_STEREO, 0, NULL);
}

void Sound::processQueue()
{
	double newVolKnobPos = getVolumeKnobPos() / 270;
	bool volumeChanged = volKnobPos != newVolKnobPos;
	if (!soundQueue.empty() || volumeChanged) {
		std::lock_guard<std::mutex> lock(mtx);
		if (!soundQueue.empty()) {
			auto currSound = soundQueue.front();
			if (std::chrono::system_clock::now() > currSound.second) {
				currSound.first->playNow();
				prevSound = currSound.first;
				soundQueue.pop();
			}
		}
		if (volumeChanged) {
			volKnobPos = newVolKnobPos;
			globalVolume = 3.1623e-3 * exp(((1 - zeroVolumeThreshold) * volKnobPos + zeroVolumeThreshold) * 5.757);
			if (!soundQueue.empty())
				soundQueue.front().first->setVolume(globalVolume);
			if (prevSound != nullptr) {
				prevSound->setVolume(globalVolume);
			}
		}
	}
}

void Sound::setVolume(double volume)
{
	BASS_ChannelSetAttribute(stream, BASS_ATTRIB_VOL, (float)(volume * fileRelVolume));
}

double Sound::getVolumeKnobPos()
{
	if (copilot::readLvar(volumeKnob.switchLvar) != 10) {
		return copilot::readLvar(volumeKnob.knobLvar);
	}
	return 0;
}
