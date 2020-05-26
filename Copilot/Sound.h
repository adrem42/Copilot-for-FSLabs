#pragma once
#include <string>
#include <queue>
#include <chrono>
#include <mutex>
#include <memory>
#include "bass/bass.h"
#include "FSUIPC/include/FSUIPC_User64.h"

using TimePoint = std::chrono::time_point<std::chrono::system_clock>;

class Sound {
	HSTREAM stream;
	int length;
	float fileRelVolume;
	void setVolume(double volume);
	static TimePoint nextFreeSlot;
	static std::queue<std::pair<Sound*, TimePoint>> soundQueue;
	static std::mutex mtx;
	static double globalVolume, volKnobPos;
	static double getVolumeKnobPos();
	static constexpr double zeroVolumeThreshold = 0.7;
	static Sound* prevSound;
	static struct {
		const char* knobLvar;
		const char* switchLvar;
	} volumeKnob;
	void playNow();
public:
	Sound(const std::string& path, int length, double fileRelVolume);
	Sound(const std::string& path, int length);
	Sound(const std::string& path);
	void play(int delay);
	void play();

	static void setGlobalVolume(double volume);
	static void init(int side, int device = -1);
	static void processQueue();
};
