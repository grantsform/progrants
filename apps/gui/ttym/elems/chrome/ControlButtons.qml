// ControlButtons.qml — chrome overlay: lock button (top-right), quit button
// (bottom-left), settings gear (top-centre), alarm clock (top-left), add-event
// FAB (bottom-right), input blocker overlay, and hamburger button.
//
// All pop-ups are opened via signals so shell.qml remains in control of them.
import QtQuick
import QtQuick.Controls

Item {
    id: root
    anchors.fill: parent

    // ── Required context ──────────────────────────────────────────────────────
    required property QtObject appState

    // ── Signals ───────────────────────────────────────────────────────────────
    signal settingsRequested()
    signal alarmSettingsRequested()
    signal addEventRequested()
    signal addTodoRequested()
    signal hamburgerRequested()

    // ── Scaling ───────────────────────────────────────────────────────────────
    property real dpiScale: 1.0

    // ─────────────────────────────────────────────────────────────────────────
    // Input-lock overlay (highest z, below button chrome)
    // ─────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: inputBlocker
        anchors.fill: parent
        visible: appState.inputLocked
        color:   appState.inputLocked ? "#00000040" : "transparent"
        z: 10000

        MouseArea {
            anchors.fill: parent
            enabled:      appState.inputLocked
            hoverEnabled: true
            cursorShape:  Qt.ForbiddenCursor
            onPressed: { /* consume */ }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lock button — top-right
    // ─────────────────────────────────────────────────────────────────────────
    Button {
        id: lockBtn
        text: appState.inputLocked ? "🔓" : "🔒"
        anchors.top:   parent.top
        anchors.right: parent.right
        anchors.topMargin:   12
        anchors.rightMargin: 12
        width: 44; height: 44
        hoverEnabled: true
        z: 10001

        contentItem: Text {
            text: lockBtn.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment:   Text.AlignVCenter
            anchors.fill: parent
            color: "#ffffff"
            font.pixelSize: 22 * root.dpiScale
        }
        background: Rectangle {
            color:        "#333333"; radius: 6
            border.color: appState.inputLocked ? "#ff4444"
                        : (lockBtn.hovered    ? "#ff4444" : "#ffffff")
            border.width: (appState.inputLocked || lockBtn.hovered) ? 3 : 1

            Rectangle {
                anchors.left:   parent.left
                anchors.top:    parent.top
                anchors.bottom: parent.bottom
                width:   parent.width * appState.lockHoldProgress
                color:   "#00ff00"
                radius:  6
                opacity: appState.lockHoldProgress > 0 ? 0.8 : 0
            }
        }

        onPressed: {
            if (appState.inputLocked)
                appState.startUnlockHold();
        }
        onReleased: {
            if (appState.lockHoldActive)
                appState.stopUnlockHold();
        }
        onClicked: {
            if (!appState.inputLocked && !appState.lockUnlockCooldown)
                appState.inputLocked = true;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Quit button — bottom-left
    // ─────────────────────────────────────────────────────────────────────────
    Button {
        id: quitBtn
        text: "❌"
        anchors.left:   parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin:   12
        anchors.bottomMargin: 12
        width: 44; height: 44
        hoverEnabled: true
        z: 5

        contentItem: Text {
            text: quitBtn.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment:   Text.AlignVCenter
            anchors.fill: parent
            color: "#ffffff"
            font.pixelSize: 22 * root.dpiScale
        }
        background: Rectangle {
            color:        "#333333"; radius: 6
            border.color: quitBtn.hovered ? "#ff4444" : "#ffffff"
            border.width: quitBtn.hovered ? 3 : 1

            Rectangle {
                anchors.left:   parent.left
                anchors.top:    parent.top
                anchors.bottom: parent.bottom
                width:   parent.width * appState.quitHoldProgress
                color:   "#ff4444"; radius: 6
                opacity: appState.quitHoldProgress > 0 ? 0.8 : 0
            }
        }

        onPressed:  appState.startQuitHold()
        onReleased: appState.stopQuitHold()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Settings gear — top-centre
    // ─────────────────────────────────────────────────────────────────────────
    Button {
        id: settingsGearBtn
        text: "⚙️"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top:    parent.top
        anchors.topMargin: 12
        width: 44; height: 44
        hoverEnabled: true
        z: 5

        contentItem: Text {
            text: settingsGearBtn.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment:   Text.AlignVCenter
            anchors.fill: parent
            color: "#ffffff"
            font.pixelSize: 22 * root.dpiScale
        }
        background: Rectangle {
            color:        "#333333"; radius: 6
            border.color: settingsGearBtn.hovered ? "#ff4444" : "#ffffff"
            border.width: settingsGearBtn.hovered ? 3 : 1
        }
        onClicked: root.settingsRequested()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Alarm clock button — top-left (inside the content card)
    // Exposed so shell.qml can position it relative to the card
    // ─────────────────────────────────────────────────────────────────────────
    Button {
        id: topLeftAlarmBtn
        text: "🕒"
        anchors.left: parent.left
        anchors.top:  parent.top
        anchors.margins: 8
        width:  44 * root.dpiScale
        height: 44 * root.dpiScale
        hoverEnabled: true
        z: 1

        contentItem: Text {
            text: topLeftAlarmBtn.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment:   Text.AlignVCenter
            anchors.fill: parent
            color: "#ffffff"
            font.pixelSize: 22 * root.dpiScale
        }
        background: Rectangle {
            color:        "#333333"; radius: 6
            border.color: topLeftAlarmBtn.hovered ? "#ff4444" : "#ffffff"
            border.width: topLeftAlarmBtn.hovered ? 3 : 1
        }
        onClicked: root.alarmSettingsRequested()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Add-event FAB — bottom-right
    // ─────────────────────────────────────────────────────────────────────────
    Button {
        id: addEventFAB
        width:  42 * root.dpiScale
        height: 42 * root.dpiScale
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin:  12
        anchors.bottomMargin: 12
        hoverEnabled: true
        z: 5

        contentItem: Text {
            text: "📅"
            font.pixelSize: 24 * root.dpiScale
            color: "#ffffff"; font.bold: true
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment:   Text.AlignVCenter
            z: 1; opacity: 1.0
        }
        background: Rectangle {
            color:        "#ff4444"; radius: 21
            border.color: addEventFAB.hovered ? "#ff4444" : "#ffffff"
            border.width: addEventFAB.hovered ? 3 : 1
        }
        onClicked: root.addEventRequested()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Hamburger button — bottom-centre (reserved for future menu)
    // ─────────────────────────────────────────────────────────────────────────
    Button {
        id: hamburgerBtn
        width:  42 * root.dpiScale
        height: 42 * root.dpiScale
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom:       parent.bottom
        anchors.bottomMargin: 12
        hoverEnabled: true

        contentItem: Text {
            text: "☰"
            font.pixelSize: 24 * root.dpiScale
            color: "#ffffff"; font.bold: true
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment:   Text.AlignVCenter
        }
        background: Rectangle {
            color:        "#333333"; radius: width / 2
            border.color: hamburgerBtn.hovered ? "#ff4444" : "#ffffff"
            border.width: hamburgerBtn.hovered ? 3 : 1
        }
        onClicked: root.hamburgerRequested()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Add-todo button — bottom, midpoint between hamburger and add-event FAB
    // ─────────────────────────────────────────────────────────────────────────
    Button {
        id: addTodoBtn
        width:  42 * root.dpiScale
        height: 42 * root.dpiScale
        x: hamburgerBtn.x + hamburgerBtn.width + (addEventFAB.x - hamburgerBtn.x - hamburgerBtn.width) / 2 - width / 2
        anchors.bottom:       parent.bottom
        anchors.bottomMargin: 12
        hoverEnabled: true
        z: 5

        contentItem: Text {
            text: "✅"
            font.pixelSize: 22 * root.dpiScale
            color: "#ffffff"; font.bold: true
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment:   Text.AlignVCenter
        }
        background: Rectangle {
            color:        "#226622"; radius: width / 2
            border.color: addTodoBtn.hovered ? "#44ff44" : "#88cc88"
            border.width: addTodoBtn.hovered ? 3 : 1
        }
        onClicked: root.addTodoRequested()
    }
}
