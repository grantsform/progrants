// AllDayPopup.qml — todo-list style popup showing today's all-day events.
// Open by setting visible = true.  Closes itself via closeRequested signal.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root

    required property QtObject appState

    signal closeRequested()
    signal editEventRequested(string eventId)
    signal addAllDayEventRequested()

    z: 9998

    // ── Dim overlay ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#88000000"
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    // ── Card ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        width:  Math.min(root.width * 0.55, 480)
        anchors.centerIn: parent
        height: cardCol.implicitHeight + 24
        color:  "#ee0d0d0d"
        radius: 12
        border.color: "#66ffffff"; border.width: 1

        // Swallow clicks on empty card space so the dim overlay doesn't close us
        MouseArea {
            anchors.fill: parent
            onClicked: {} // absorb
        }

        property int doneCount: {
            // depend on revision so this re-evaluates when events change
            var _dep = root.appState.eventsRevision;
            var n = 0;
            for (var i = 0; i < root.appState.allDayModel.count; i++)
                if (root.appState.allDayModel.get(i).doneToday) n++;
            return n;
        }

        ColumnLayout {
            id: cardCol
            anchors {
                top:   parent.top
                left:  parent.left
                right: parent.right
                margins: 16
            }
            spacing: 10

            // ── Title row ─────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "✅  Today's All-Day Events"
                    color: "#ffffff"; font.pixelSize: 17; font.bold: true
                    Layout.fillWidth: true
                }
                // Add button
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: addArea.containsMouse ? "#227722" : "#114411"
                    border.color: "#44aa44"; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "+"; color: "#ffffff"
                        font.pixelSize: 16; font.bold: true
                    }
                    MouseArea {
                        id: addArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.addAllDayEventRequested();
                            root.closeRequested();
                        }
                    }
                }
                // Close button
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeArea.containsMouse ? "#ff4444" : "#333333"
                    border.color: "#ffffff"; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "✕"; color: "#ffffff"
                        font.pixelSize: 13; font.bold: true
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#44ffffff" }

            // ── Empty state ───────────────────────────────────────────────────
            Text {
                visible: root.appState.allDayModel.count === 0
                text: "No all-day events today."
                color: "#888888"; font.pixelSize: 14
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
            }

            // ── Active event rows ─────────────────────────────────────────────
            Repeater {
                id: activeRepeater
                model: root.appState.allDayModel

                delegate: Rectangle {
                    id: activeDelegate
                    // capture model roles into local properties so nested items can read them
                    property string _eventId: model.eventId || ""
                    property string _title:   model.title   || ""
                    property string _comment: model.comment || ""
                    property bool   _done: {
                        var _r = root.appState.eventsRevision;
                        return model.doneToday === true;
                    }

                    Layout.fillWidth: true
                    visible: !_done
                    height:  _done ? 0 : (rowLayout.implicitHeight + 14)
                    radius: 6
                    color:  rowHover.hovered ? "#222222" : "#181818"
                    border.color: "#444444"; border.width: _done ? 0 : 1
                    clip: true

                    RowLayout {
                        id: rowLayout
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top; margins: 8
                        }
                        spacing: 8

                        // ── Checkbox ──────────────────────────────────────────
                            Rectangle {
                                width: 24; height: 24; radius: 4
                                color: "transparent"
                                border.color: "#888888"; border.width: 2
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.appState.toggleAllDayDoneById(activeDelegate._eventId)
                                }
                            }                        // ── Text block ────────────────────────────────────────
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: _title
                                color: "#ffffff"; font.pixelSize: 14; font.bold: true
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: _comment !== ""
                                text: _comment
                                color: "#aaaaaa"; font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }

                        // ── Edit button ───────────────────────────────────────
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: editBtnArea.containsMouse ? "#444444" : "#000000"
                            border.color: "#ffffff"; border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "✎"; color: "#ffffff"; font.pixelSize: 13
                            }
                            MouseArea {
                                id: editBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.editEventRequested(activeDelegate._eventId);
                                    root.closeRequested();
                                }
                            }
                        }
                    }

                    HoverHandler { id: rowHover }
                }
            }

            // ── Done section header (visible only when ≥1 done) ───────────────
            Rectangle {
                Layout.fillWidth: true; height: 1; color: "#336633"
                visible: card.doneCount > 0
            }
            Text {
                visible: card.doneCount > 0
                text: "✓  Done"
                color: "#559955"; font.pixelSize: 12; font.bold: true
            }

            // ── Done event rows ───────────────────────────────────────────────
            Repeater {
                model: root.appState.allDayModel

                delegate: Rectangle {
                    id: doneDelegate
                    property string _eventId: model.eventId || ""
                    property string _title:   model.title   || ""
                    property string _comment: model.comment || ""
                    property bool   _done: {
                        var _r = root.appState.eventsRevision;
                        return model.doneToday === true;
                    }

                    Layout.fillWidth: true
                    visible: _done
                    height:  _done ? (doneRowLayout.implicitHeight + 14) : 0
                    radius: 6
                    color: doneHover.hovered ? "#2a1a3a" : "#180d28"
                    border.color: "#6633aa"; border.width: _done ? 1 : 0
                    clip: true

                    RowLayout {
                        id: doneRowLayout
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top; margins: 8
                        }
                        spacing: 8

                        // ── Checked checkbox ──────────────────────────────────
                        Rectangle {
                            width: 24; height: 24; radius: 4
                            color: "#551188"
                            border.color: "#9944dd"; border.width: 2
                            Text {
                                anchors.centerIn: parent
                                text: "✓"; color: "#dd99ff"
                                font.pixelSize: 13; font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.appState.toggleAllDayDoneById(doneDelegate._eventId)
                            }
                        }

                        // ── Strikethrough text ────────────────────────────────
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: _title
                                color: "#775599"; font.pixelSize: 14
                                font.strikeout: true
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: _comment !== ""
                                text: _comment
                                color: "#553377"; font.pixelSize: 12
                                font.strikeout: true
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }

                    HoverHandler { id: doneHover }
                }
            }

            // bottom padding
            Item { height: 4 }
        }
    }
}
