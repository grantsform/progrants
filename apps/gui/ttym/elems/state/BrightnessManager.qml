// BrightnessManager.qml — automatic brightness control using brightnessctl
import QtQuick
import Quickshell.Io

QtObject {
    id: brightnessManager

    required property QtObject settingsStore

    // Check brightness every minute
    property Timer brightnessTimer: Timer {
        interval: 60000  // 1 minute
        running: settingsStore.brightnessEnabled
        repeat: true
        onTriggered: updateBrightness()
    }

    property bool brightnessEnabled: settingsStore.brightnessEnabled
    onBrightnessEnabledChanged: {
        brightnessTimer.running = brightnessEnabled;
        if (!brightnessEnabled) {
            setBrightness(100);
        } else {
            updateBrightness();
        }
    }

    // Process for running brightnessctl commands
    property Process brightnessProcess: Process {
        id: brightnessProcess
        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) {
                console.warn("brightnessctl command failed with exit code:", exitCode, "status:", exitStatus);
            }
        }
    }

    function updateBrightness() {
        if (!settingsStore.brightnessEnabled) return;
        
        var now = new Date();
        var currentTime = Qt.formatTime(now, "hh:mm");
        var targetBrightness = calculateTargetBrightness(currentTime);
        
        setBrightness(targetBrightness);
    }

    function calculateTargetBrightness(currentTime) {
        var dimStart = settingsStore.dimStartTime;
        var dimEnd = settingsStore.dimEndTime;
        var brightenStart = settingsStore.brightenStartTime;
        var brightenEnd = settingsStore.brightenEndTime;
        
        var currentMinutes = timeToMinutes(currentTime);
        var dimStartMinutes = timeToMinutes(dimStart);
        var dimEndMinutes = timeToMinutes(dimEnd);
        var brightenStartMinutes = timeToMinutes(brightenStart);
        var brightenEndMinutes = timeToMinutes(brightenEnd);
        
        // Handle day boundary crossings
        if (dimStartMinutes > dimEndMinutes) dimEndMinutes += 1440; // Add 24 hours
        if (brightenStartMinutes > brightenEndMinutes) brightenEndMinutes += 1440;
        if (currentMinutes < 12 * 60) currentMinutes += 1440; // If it's AM, add 24 hours for comparison
        
        // Dimming phase (6 PM to 9 PM)
        if (currentMinutes >= dimStartMinutes && currentMinutes <= dimEndMinutes) {
            var dimProgress = (currentMinutes - dimStartMinutes) / (dimEndMinutes - dimStartMinutes);
            return Math.round(settingsStore.maxBrightness - (dimProgress * (settingsStore.maxBrightness - settingsStore.minBrightness)));
        }
        
        // Night phase (9 PM to 5 AM) - stay at minimum
        if (currentMinutes > dimEndMinutes && currentMinutes < (brightenStartMinutes + 1440)) {
            return settingsStore.minBrightness;
        }
        
        // Brightening phase (5 AM to 7 AM)
        if (currentMinutes >= (brightenStartMinutes + 1440) && currentMinutes <= (brightenEndMinutes + 1440)) {
            var brightenProgress = (currentMinutes - (brightenStartMinutes + 1440)) / ((brightenEndMinutes + 1440) - (brightenStartMinutes + 1440));
            return Math.round(settingsStore.minBrightness + (brightenProgress * (settingsStore.maxBrightness - settingsStore.minBrightness)));
        }
        
        // Day phase (7 AM to 6 PM) - stay at maximum
        return settingsStore.maxBrightness;
    }

    function timeToMinutes(timeString) {
        var parts = timeString.split(":");
        return parseInt(parts[0]) * 60 + parseInt(parts[1]);
    }

    function setBrightness(percentage) {
        console.log("Setting brightness to", percentage + "%");
        brightnessProcess.exec({
            command: ["brightnessctl", "set", percentage + "%"]
        });
    }

    // Manual brightness control functions
    function setBrightnessManual(percentage) {
        setBrightness(Math.max(1, Math.min(100, percentage)));
    }

    function getCurrentBrightness(callback) {
        var process = Process.exec({
            command: ["brightnessctl", "get"],
            onFinished: function() {
                if (process.exitCode === 0) {
                    var current = parseInt(process.stdout.trim());
                    var maxProcess = Process.exec({
                        command: ["brightnessctl", "max"],
                        onFinished: function() {
                            if (maxProcess.exitCode === 0) {
                                var max = parseInt(maxProcess.stdout.trim());
                                var percentage = Math.round((current / max) * 100);
                                callback(percentage);
                            }
                        }
                    });
                }
            }
        });
    }

    // Initialize brightness on startup
    Component.onCompleted: {
        if (brightnessEnabled) {
            updateBrightness();
        } else {
            setBrightness(100);
        }
    }
}