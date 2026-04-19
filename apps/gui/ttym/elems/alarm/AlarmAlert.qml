// AlarmAlert.qml — flashing red alert shown when the alarm fires.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Popup {
    id: root

    // ── Required context ──────────────────────────────────────────────────────
    required property QtObject appState

    // ── Popup behaviour ───────────────────────────────────────────────────────
    modal:       false
    closePolicy: Popup.NoAutoClose
    z: 1

    x: 0; y: 0   // positioned by parent in shell.qml

    onOpened: {
        root.forceActiveFocus();
        if (appState.alarmAutoTimeout)
            _autoTimer.restart();
    }
    onClosed: _autoTimer.stop()

    Timer {
        id: _autoTimer
        interval: appState.alarmTimeoutMinutes * 60 * 1000
        repeat: false
        running: false
        onTriggered: {
            if (root.opened) {
                appState.stopAlarmSound();
                appState.dismissAlarm();
                root.close();
            }
        }
    }

    // Close if the alarm is dismissed externally (file change sets dismissed:true)
    Connections {
        target: root.appState
        function onSigAlarmDismissed() { if (root.opened) root.close(); }
    }

    // ── Content ───────────────────────────────────────────────────────────────
    Rectangle {
        id: popupRect
        width: 340; height: 260
        color:  "#ff0000"
        radius: 10
        border.color: "#ffffff"; border.width: 1

        // Lock overlay — swallows clicks while the lock is active
        Rectangle {
            anchors.fill: parent
            color:   "transparent"
            z: 99
            visible: appState.inputLocked || appState.lockHoldActive
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.ForbiddenCursor
                onPressed: { /* swallow */ }
            }
        }

        // Pulsing background colour
        ColorAnimation {
            target:   popupRect
            property: "color"
            from: "#ff0000"; to: "#000000"
            duration: 800
            loops: Animation.Infinite
            running: root.opened
            easing.type: Easing.InOutQuad
        }

        ColumnLayout {
            anchors.fill:    parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Alarm!"
                color: "#ff5555"; font.pixelSize: 24; font.bold: true
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Time: " + appState.alarmTime
                color: "#ffffff"; font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            Button {
                text: "Dismiss"
                Layout.alignment: Qt.AlignHCenter
                enabled: !(appState.inputLocked || appState.lockHoldActive)
                onClicked: {
                    if (appState.inputLocked || appState.lockHoldActive) return;
                    appState.stopAlarmSound();
                    appState.dismissAlarm();
                    root.close();
                }
            }
        }
    }
}
