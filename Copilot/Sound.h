#pragma once
#include <string>
#include <queue>
#include <chrono>
#include <mutex>
#include <optional>
#include <memory>
#include <sapi.h>
#include "bass/bass.h"

using TimePoint = std::chrono::time_point<std::chrono::system_clock>;

class Sound {

	HSTREAM stream;
	int length;
	float fileRelVolume;
	void adjustVolumeFromGlobal();
	static TimePoint nextFreeSlot;
	static std::queue<std::pair<Sound*, TimePoint>> soundQueue;
	static std::mutex mtx;
	static double userVolume, globalVolume, volKnobPos;
	static double getVolumeKnobPos();
	static constexpr double zeroVolumeThreshold = 0.7;
	static Sound* prevSound;

	static std::string knobLvar;
	static std::string switchLvar;

	void playNow();

	static ISpVoice* voice;
	static bool volumeControl;

public:
	Sound(const std::string& path, int length, double fileRelVolume);
	Sound(const std::string& path, int length);
	Sound(const std::string& path);
	static std::string getDeviceName();
	void enqueue(int delay);
	void enqueue();
	static void init(std::optional<std::string> device, int side, double userVolume, bool volumeControl, ISpVoice* voice);
	static void update(bool);
	static void onVolumeChanged(double newVolume);
};
