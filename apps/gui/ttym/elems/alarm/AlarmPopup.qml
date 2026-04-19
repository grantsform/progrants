// AlarmPopup.qml — edit alarm time, weekday recurrence, and toggle.
// Plain Item overlay — no Popup, so button clicks always reach chrome.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root

    required property QtObject appState

    signal ringRepaintRequested()
    signal closeRequested()

    z: 9999

    property string pendingAlarmTime:     appState.alarmTime !== "" ? appState.alarmTime : (function() { var h = new Date().getHours(); return h.toString().padStart(2,'0') + ":00:00"; })()
    property bool   pendingAlarmEnabled:  appState.alarmEnabled
    property var    pendingAlarmWeekdays: appState.alarmWeekdays.slice(0)
    property bool   pendingAlarmSilent:         appState.alarmSilent
    property string pendingAlarmSound:          appState.alarmSound
    property bool   pendingAlarmAutoTimeout:    appState.alarmAutoTimeout
    property real   pendingAlarmTimeoutMinutes: appState.alarmTimeoutMinutes

    function selectedDaysLabel() {
        var names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
        var selected = [];
        for (var i = 0; i < pendingAlarmWeekdays.length; ++i)
            if (pendingAlarmWeekdays[i]) selected.push(names[i]);
        return selected.length ? selected.join(" ") : "Every day";
    }

    // Call when made visible to sync pending state
    function syncFromAppState() {
        pendingAlarmTime     = appState.alarmTime;
        pendingAlarmEnabled  = appState.alarmEnabled;
        pendingAlarmWeekdays = appState.alarmWeekdays.slice(0);
        pendingAlarmSilent          = appState.alarmSilent;
        pendingAlarmSound           = appState.alarmSound;
        pendingAlarmAutoTimeout    = appState.alarmAutoTimeout;
        pendingAlarmTimeoutMinutes = appState.alarmTimeoutMinutes;
        var parts = pendingAlarmTime.split(":");
        var ph = parseInt(parts[0] || "0", 10);
        var pm = parseInt(parts[1] || "0", 10);
        var ps = parseInt(parts[2] || "0", 10);
        alarmHourBox.currentIndex   = Math.max(0, Math.min(23, ph));
        alarmMinuteBox.currentIndex = Math.max(0, Math.min(59, pm));
        alarmSecondBox.currentIndex = Math.max(0, Math.min(59, ps));
        _syncPendingTime();
    }

    onVisibleChanged: { if (visible) syncFromAppState(); }

    function _syncPendingTime() {
        var hh = alarmHourBox.model[alarmHourBox.currentIndex];
        var mm = alarmMinuteBox.model[alarmMinuteBox.currentIndex];
        var ss = alarmSecondBox.model[alarmSecondBox.currentIndex];
        pendingAlarmTime = hh + ":" + mm + ":" + ss;
    }

    Rectangle {
        width:  300
        height: 500
        anchors.centerIn: parent
        color:  "#dd000000"
        radius: 10
        border.color: "#ffffff"; border.width: 1

        ColumnLayout {
            anchors.fill:    parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "Edit Alarm"; color: "#ffffff"
                font.pixelSize: 20; font.bold: true
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            CheckBox {
                id: alarmSettingsEnabled
                checked: root.pendingAlarmEnabled
                text: "Enabled"
                onCheckedChanged: root.pendingAlarmEnabled = checked
            }

            RowLayout {
                spacing: 8
                Label { text: "Time"; color: "#ffffff" }
                ComboBox {
                    id: alarmHourBox
                    model: ["00","01","02","03","04","05","06","07","08","09",
                            "10","11","12","13","14","15","16","17","18","19",
                            "20","21","22","23"]
                    implicitWidth: 60
                    onCurrentIndexChanged: root._syncPendingTime()
                }
                ComboBox {
                    id: alarmMinuteBox
                    model: Array.from({length: 60}, function(_, i) { return i.toString().padStart(2, '0'); })
                    implicitWidth: 60
                    onCurrentIndexChanged: root._syncPendingTime()
                }
                ComboBox {
                    id: alarmSecondBox
                    model: Array.from({length: 60}, function(_, i) { return i.toString().padStart(2, '0'); })
                    implicitWidth: 60
                    onCurrentIndexChanged: root._syncPendingTime()
                }
            }

            Text {
                text: "Reoccurring?"; color: "#ffffff"; font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            RowLayout {
                spacing: 4
                Repeater {
                    model: 7
                    ColumnLayout {
                        spacing: 2; width: 34
                        Text {
                            text: appState.weekdayName(index)
                            color: "#ffffff"; font.pixelSize: 10
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }
                        CheckBox {
                            checked: root.pendingAlarmWeekdays[index]
                            onCheckedChanged: root.pendingAlarmWeekdays[index] = checked
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            Text {
                text: "Days: " + root.selectedDaysLabel()
                color: "#bbbbbb"; font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            CheckBox {
                id: alarmSilentCheck
                checked: root.pendingAlarmSilent
                text: "Silent (no sound)"
                onCheckedChanged: root.pendingAlarmSilent = checked
            }

            ColumnLayout {
                spacing: 4
                visible: !root.pendingAlarmSilent
                opacity: root.pendingAlarmSilent ? 0.0 : 1.0
                Layout.fillWidth: true
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Text { text: "SFX:"; color: "#cccccc"; font.pixelSize: 12 }
                TextField {
                    placeholderText: "Custom sound path (empty = builtin)"
                    text: root.pendingAlarmSound
                    Layout.fillWidth: true
                    height: 28
                    font.pixelSize: 11
                    onTextChanged: root.pendingAlarmSound = text
                }
            }

            CheckBox {
                id: alarmAutoTimeoutCheck
                checked: root.pendingAlarmAutoTimeout
                text: "Auto-dismiss after timeout"
                onCheckedChanged: root.pendingAlarmAutoTimeout = checked
            }

            RowLayout {
                spacing: 6
                visible: root.pendingAlarmAutoTimeout
                opacity: root.pendingAlarmAutoTimeout ? 1.0 : 0.0
                Layout.fillWidth: true
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Text { text: "Timeout:"; color: "#cccccc"; font.pixelSize: 12 }
                ComboBox {
                    id: alarmTimeoutBox
                    property var _values: [0.25, 0.5, 1, 2, 5, 10, 15, 20, 30, 45, 60]
                    property var _labels: ["0.25", "0.5", "1", "2", "5", "10", "15", "20", "30", "45", "60"]
                    model: _labels
                    currentIndex: {
                        for (var i = 0; i < _values.length; ++i)
                            if (Math.abs(_values[i] - root.pendingAlarmTimeoutMinutes) < 0.01) return i;
                        return 6; // default 15 min
                    }
                    implicitWidth: 80
                    onCurrentIndexChanged: root.pendingAlarmTimeoutMinutes = _values[currentIndex]
                }
                Text { text: "min"; color: "#cccccc"; font.pixelSize: 12 }
            }

            Text {
                text:  root.pendingAlarmEnabled ? "Alarm is enabled" : "Alarm is disabled"
                color: root.pendingAlarmEnabled ? "#aaffaa" : "#ffaaaa"
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            RowLayout {
                spacing: 8; Layout.fillWidth: true
                Button {
                    text: "Save"
                    Layout.alignment: Qt.AlignRight
                    onClicked: {
                        appState.alarmTime     = root.pendingAlarmTime;
                        appState.alarmEnabled  = root.pendingAlarmEnabled;
                        appState.alarmWeekdays = root.pendingAlarmWeekdays.slice(0);
                        appState.alarmSilent          = root.pendingAlarmSilent;
                        appState.alarmSound            = root.pendingAlarmSound;
                        appState.alarmAutoTimeout      = root.pendingAlarmAutoTimeout;
                        appState.alarmTimeoutMinutes   = root.pendingAlarmTimeoutMinutes;
                        appState.alarmFiredToday = false;
                        appState.updateAlarmProgress();
                        appState.updateRecurringAlarmState();
                        root.ringRepaintRequested();
                        appState.saveAlarmsToFile();
                        root.closeRequested();
                    }
                }
                Button {
                    text: "Cancel"
                    Layout.alignment: Qt.AlignRight
                    onClicked: root.closeRequested()
                }
            }
        }
    }
}
