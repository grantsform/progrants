// SettingsPopup.qml — application settings (clock format, auto-reload, lock).
// Plain Item overlay — no Popup, so button clicks always reach chrome.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root

    required property QtObject appState

    // Emit to request the parent flag be toggled off
    signal closeRequested()

    z: 9999

    Rectangle {
        width:  Math.min(root.width,  650)
        height: Math.min(root.height, 620)
        anchors.centerIn: parent
        color:  "#f0000000"
        radius: 10
        border.color: "#ffffff"; border.width: 1

        ColumnLayout {
            anchors.fill:      parent
            anchors.margins:   10
            anchors.topMargin: 8
            spacing: 8

            Text {
                text: "Settings"; color: "#ffffff"
                font.pixelSize: 28; font.bold: true
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 400
                contentWidth: availableWidth
                
                ColumnLayout {
                    width: parent.width
                    spacing: 8

            GridLayout {
                columns: 2
                columnSpacing: 12; rowSpacing: 8
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                Layout.leftMargin: 16; Layout.rightMargin: 16

                Text { text: "Setting"; color: "#999999"; font.pixelSize: 18; font.bold: true }
                Text { text: "Value";   color: "#999999"; font.pixelSize: 18; font.bold: true }

                Text { text: "Clock format"; color: "#ffffff"; font.pixelSize: 16 }
                RowLayout {
                    spacing: 8
                    Switch {
                        width: 70; height: 40
                        checked: appState.use24HourClock
                        onCheckedChanged: appState.use24HourClock = checked
                    }
                    Text {
                        text:  appState.use24HourClock ? "24-hour" : "12-hour"
                        color: "#cccccc"; font.pixelSize: 16
                    }
                }

                Text { text: "Lock By Default (On Startup)"; color: "#ffffff"; font.pixelSize: 16 }
                RowLayout {
                    spacing: 8
                    Switch {
                        width: 70; height: 40
                        checked: appState.lockByDefault
                        onCheckedChanged: appState.lockByDefault = checked
                    }
                    Text {
                        text:  appState.lockByDefault ? "Enabled" : "Disabled"
                        color: "#cccccc"; font.pixelSize: 16
                    }
                }

                Text { 
                    text: "Sound Settings (playerctl x mpv)"
                    color: "#ffaa44"; font.pixelSize: 16; font.bold: true
                    Layout.columnSpan: 2
                    Layout.topMargin: 8
                }

                Text { text: "Alarm Sounds"; color: "#ffffff"; font.pixelSize: 16 }
                RowLayout {
                    spacing: 8
                    Switch {
                        width: 70; height: 40
                        checked: appState.alarmSoundsEnabled
                        onCheckedChanged: appState.alarmSoundsEnabled = checked
                    }
                    Text {
                        text:  appState.alarmSoundsEnabled ? "Enabled" : "Disabled"
                        color: "#cccccc"; font.pixelSize: 16
                    }
                    Button {
                        text: "Test"
                        width: 60; height: 32
                        font.pixelSize: 14
                        enabled: appState.alarmSoundsEnabled
                        onClicked: appState.testAlarmSound()
                    }
                }

                Text { text: "  Custom Alarm Sound"; color: "#cccccc"; font.pixelSize: 14 }
                TextField {
                    placeholderText: "Sfx path (empty = builtin)"
                    text: appState.customAlarmSound
                    width: 300; height: 32
                    font.pixelSize: 12
                    onTextChanged: appState.customAlarmSound = text
                }

                Text { text: "Event Sounds"; color: "#ffffff"; font.pixelSize: 16 }
                RowLayout {
                    spacing: 8
                    Switch {
                        width: 70; height: 40
                        checked: appState.eventSoundsEnabled
                        onCheckedChanged: appState.eventSoundsEnabled = checked
                    }
                    Text {
                        text:  appState.eventSoundsEnabled ? "Enabled" : "Disabled"
                        color: "#cccccc"; font.pixelSize: 16
                    }
                    Button {
                        text: "Test"
                        width: 60; height: 32
                        font.pixelSize: 14
                        enabled: appState.eventSoundsEnabled
                        onClicked: appState.testEventSound()
                    }
                }

                Text { text: "  Custom Event Sound"; color: "#cccccc"; font.pixelSize: 14 }
                TextField {
                    placeholderText: "Sfx path (empty = builtin)"
                    text: appState.customEventSound
                    width: 300; height: 32
                    font.pixelSize: 12
                    onTextChanged: appState.customEventSound = text
                }

                Text { 
                    text: "Brightness Control (brightnessctl)"
                    color: "#ffaa44"; font.pixelSize: 16; font.bold: true
                    Layout.columnSpan: 2
                    Layout.topMargin: 8
                }

                Text { text: "Auto Brightness"; color: "#ffffff"; font.pixelSize: 16 }
                RowLayout {
                    spacing: 8
                    Switch {
                        width: 70; height: 40
                        checked: appState.brightnessEnabled
                        onCheckedChanged: appState.brightnessEnabled = checked
                    }
                    Text {
                        text: appState.brightnessEnabled ? "Enabled" : "Disabled"
                        color: "#cccccc"; font.pixelSize: 16
                    }
                    Button {
                        text: "Update Now"
                        width: 100; height: 32
                        font.pixelSize: 14
                        enabled: appState.brightnessEnabled
                        onClicked: appState.updateBrightness()
                    }
                }

                Text { text: "Dim Start Time"; color: "#cccccc"; font.pixelSize: 14; visible: appState.brightnessEnabled }
                TextField {
                    placeholderText: "18:00"
                    text: appState.dimStartTime
                    width: 80; height: 32
                    font.pixelSize: 14
                    visible: appState.brightnessEnabled
                    onTextChanged: appState.dimStartTime = text
                }

                Text { text: "Dim End Time"; color: "#cccccc"; font.pixelSize: 14; visible: appState.brightnessEnabled }
                TextField {
                    placeholderText: "21:00"
                    text: appState.dimEndTime
                    width: 80; height: 32
                    font.pixelSize: 14
                    visible: appState.brightnessEnabled
                    onTextChanged: appState.dimEndTime = text
                }

                Text { text: "Brighten Start"; color: "#cccccc"; font.pixelSize: 14; visible: appState.brightnessEnabled }
                TextField {
                    placeholderText: "05:00"
                    text: appState.brightenStartTime
                    width: 80; height: 32
                    font.pixelSize: 14
                    visible: appState.brightnessEnabled
                    onTextChanged: appState.brightenStartTime = text
                }

                Text { text: "Brighten End"; color: "#cccccc"; font.pixelSize: 14; visible: appState.brightnessEnabled }
                TextField {
                    placeholderText: "07:00"
                    text: appState.brightenEndTime
                    width: 80; height: 32
                    font.pixelSize: 14
                    visible: appState.brightnessEnabled
                    onTextChanged: appState.brightenEndTime = text
                }

                Text { text: "Min Brightness"; color: "#cccccc"; font.pixelSize: 14; visible: appState.brightnessEnabled }
                RowLayout {
                    spacing: 8
                    visible: appState.brightnessEnabled
                    SpinBox {
                        from: 1; to: 100; value: appState.minBrightness
                        width: 100; height: 32
                        onValueChanged: appState.minBrightness = value
                    }
                    Text {
                        text: "%"
                        color: "#cccccc"; font.pixelSize: 14
                    }
                }

                Text { text: "Max Brightness"; color: "#cccccc"; font.pixelSize: 14; visible: appState.brightnessEnabled }
                RowLayout {
                    spacing: 8
                    visible: appState.brightnessEnabled
                    SpinBox {
                        from: 1; to: 100; value: appState.maxBrightness
                        width: 100; height: 32
                        onValueChanged: appState.maxBrightness = value
                    }
                    Text {
                        text: "%"
                        color: "#cccccc"; font.pixelSize: 14
                    }
                }
            }
            
            } // End ColumnLayout for ScrollView content
            } // End ScrollView

            RowLayout {
                spacing: 8; Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                Button {
                    text: "Close"; width: 120; height: 40
                    font.pixelSize: 16
                    onClicked: root.closeRequested()
                }
            }
        }
    }
}
