// SfxManager.qml — sound via mpv for playback, playerctl to pause active player
import QtQuick
import Quickshell.Io

QtObject {
    id: soundManager

    required property QtObject settingsStore

    property string _builtinAlarm: "/tios/face/ttym/sounds/alarm.wav"
    property string _builtinEvent: "/tios/face/ttym/sounds/event.wav"

    function _alarmFile() { return (settingsStore.customAlarmSound !== "") ? settingsStore.customAlarmSound : _builtinAlarm; }
    function _eventFile() { return (settingsStore.customEventSound !== "") ? settingsStore.customEventSound : _builtinEvent; }

    property Process _alarmProc: Process { id: _alarmProc }
    property Process _eventProc: Process { id: _eventProc }
    property Process _stopProc:  Process { id: _stopProc  }

    property string _activeAlarmFile: _builtinAlarm
    property string _activeEventFile: _builtinEvent

    property Timer alarmLoopTimer: Timer {
        interval: 3000
        running: false
        repeat: true
        onTriggered: { if (settingsStore.alarmSoundsEnabled) _playFile(_alarmProc, soundManager._activeAlarmFile); }
    }

    property Timer eventLoopTimer: Timer {
        interval: 5000
        running: false
        repeat: true
        onTriggered: { if (settingsStore.eventSoundsEnabled) _playFile(_eventProc, soundManager._activeEventFile); }
    }

    function _playFile(proc, path) {
        proc.exec({ command: ["mpv", "--no-terminal", "--volume=70", path] });
    }

    function playAlarmSound(soundOverride) {
        if (!settingsStore.alarmSoundsEnabled) return;
        _activeAlarmFile = (soundOverride && soundOverride !== "") ? soundOverride : _alarmFile();
        _playFile(_alarmProc, _activeAlarmFile);
        alarmLoopTimer.start();
    }

    function stopAlarmSound() {
        alarmLoopTimer.stop();
        _alarmProc.exec({ command: ["sh", "-c", "kill $(pgrep -f 'mpv.*alarm') 2>/dev/null; true"] });
    }

    function playEventSound(soundOverride) {
        if (!settingsStore.eventSoundsEnabled) return;
        _activeEventFile = (soundOverride && soundOverride !== "") ? soundOverride : _eventFile();
        _playFile(_eventProc, _activeEventFile);
        eventLoopTimer.start();
    }

    function stopEventSound() {
        eventLoopTimer.stop();
        _eventProc.exec({ command: ["sh", "-c", "kill $(pgrep -f 'mpv.*event') 2>/dev/null; true"] });
    }

    function testAlarmSound() { _playFile(_alarmProc, _alarmFile()); }
    function testEventSound() { _playFile(_eventProc, _eventFile()); }
}

