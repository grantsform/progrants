// EventAlert.qml — flashing alert shown when an event with alert=true fires.
// Similar to AlarmAlert but shows event details.  Open via open(), populated
// by setting the ev property before calling open().
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Popup {
    id: root

    // ── Required context ──────────────────────────────────────────────────────
    required property QtObject appState

    // ── Event data (set by shell.qml before open()) ───────────────────────────
    property var ev: null

    // ── Derived display strings ───────────────────────────────────────────────
    property string _title:   ev ? (ev.title   || "Event") : "Event"
    property string _comment: ev ? (ev.comment || "")      : ""
    property string _date:    ev ? (ev.date    || "")      : ""
    property string _time:    ev ? ((ev.allDay || !ev.time || ev.time === "" || ev.time === "All Day")
                                    ? "All Day" : ev.time) : ""

    // ── Popup behaviour ───────────────────────────────────────────────────────
    modal:       false
    closePolicy: Popup.NoAutoClose
    z: 1

    x: 0; y: 0   // positioned by parent in shell.qml

    property int _timeoutMinutes: ev ? (ev.alertTimeoutMinutes || 5) : 5
    property bool _autoTimeout:   ev ? (ev.alertAutoTimeout !== false) : true

    onOpened: {
        root.forceActiveFocus();
        if (root._autoTimeout)
            _autoTimer.restart();
    }
    onClosed: _autoTimer.stop()

    Timer {
        id: _autoTimer
        interval: root._timeoutMinutes * 60 * 1000
        repeat: false
        running: false
        onTriggered: {
            if (root.opened) {
                appState.stopEventSound();
                if (root.ev && root.ev.eventId)
                    appState.dismissEventAlertById(root.ev.eventId);
                root.close();
            }
        }
    }

    // Close if dismissed externally (file change sets dismissed:true on this event)
    Connections {
        target: root.appState
        function onSigEventAlertDismissed(eventId) {
            if (root.opened && root.ev && root.ev.eventId === eventId)
                root.close();
        }
    }

    // ── Flashing background ───────────────────────────────────────────────────
    Rectangle {
        id: alertRect
        width: 380; height: col.implicitHeight + 32
        color:  "#22cc22"
        radius: 10
        border.color: "#ffffff"; border.width: 1

        // Lock overlay
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

        // Green ↔ Black pulse (slower)
        ColorAnimation {
            target:   alertRect
            property: "color"
            from: "#22cc22"; to: "#000000"
            duration: 1200
            loops: Animation.Infinite
            running: root.opened
            easing.type: Easing.InOutQuad
        }

        ColumnLayout {
            id: col
            anchors {
                top:   parent.top
                left:  parent.left
                right: parent.right
                margins: 16
            }
            spacing: 10

            // ── Header ────────────────────────────────────────────────────────
            Text {
                text: "⏰  Event Alert"
                color: "#ffffff"; font.pixelSize: 20; font.bold: true
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#88ffffff" }

            // ── Title ─────────────────────────────────────────────────────────
            Text {
                text: root._title
                color: "#ffffff"; font.pixelSize: 22; font.bold: true
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // ── Date / time ───────────────────────────────────────────────────
            Text {
                text: root._date + (root._time !== "" ? "  " + root._time : "")
                color: "#ffdddd"; font.pixelSize: 15
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
                visible: root._date !== ""
            }

            // ── Comment ───────────────────────────────────────────────────────
            Text {
                text: root._comment
                color: "#ffcccc"; font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                visible: root._comment !== ""
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#44ffffff" }

            // ── Dismiss button ────────────────────────────────────────────────
            Button {
                text: "Dismiss"
                Layout.alignment: Qt.AlignHCenter
                enabled: !(appState.inputLocked || appState.lockHoldActive)
                contentItem: Text {
                    text: parent.text
                    color: parent.enabled ? "#ffffff" : "#888888"
                    font.pixelSize: 14; font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment:   Text.AlignVCenter
                }
                background: Rectangle {
                    color:  parent.hovered ? "#333333" : "#111111"
                    radius: 6
                    border.color: "#ffffff"; border.width: 1
                }
                onClicked: {
                    if (appState.inputLocked || appState.lockHoldActive) return;
                    appState.stopEventSound();
                    if (root.ev && root.ev.eventId)
                        appState.dismissEventAlertById(root.ev.eventId);
                    root.close();
                }
            }

            // bottom padding
            Item { height: 4 }
        }
    }
}
