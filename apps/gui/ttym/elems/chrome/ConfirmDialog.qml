// ConfirmDialog.qml — generic confirmation dialog.
// Show it by setting the properties then setting visible = true.
// Connect to onAccepted / onRejected signals.
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    // ── Public API ────────────────────────────────────────────────────────────
    property string title:   "Confirm"
    property string message: "Are you sure?"

    // Optional detail block shown below the message (leave empty to hide)
    property string detail: ""

    // Button labels
    property string acceptLabel: "Yes"
    property string rejectLabel: "Cancel"

    // Colours for the accept button (override to match context)
    property color  acceptColor:        "#880000"
    property color  acceptHoverColor:   "#cc2222"
    property color  acceptBorderColor:  "#cc4444"

    // Minimum card width — override at usage site if the parent is narrow
    property real minCardWidth: 260

    signal accepted()
    signal rejected()

    z: 9999

    // ── Dim overlay ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#99000000"
        MouseArea { anchors.fill: parent; onClicked: { /* eat clicks */ } }
    }

    // ── Dialog card ───────────────────────────────────────────────────────────
    Rectangle {
        id: card
        width:  Math.max(root.minCardWidth, Math.min(root.width * 0.55, 520))
        height: col.implicitHeight + 36
        anchors.centerIn: parent
        color:  "#ee0d0d0d"
        radius: 12
        border.color: "#88ffffff"; border.width: 1

        ColumnLayout {
            id: col
            anchors {
                top:   parent.top
                left:  parent.left
                right: parent.right
                margins: 18
            }
            spacing: 12

            // Title
            Text {
                text:  root.title
                color: "#ffffff"
                font.pixelSize: 18; font.bold: true
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            // Separator
            Rectangle { Layout.fillWidth: true; height: 1; color: "#44ffffff" }

            // Message
            Text {
                text:  root.message
                color: "#cccccc"
                font.pixelSize: 14
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            // Detail block (event info etc.) — hidden if empty
            Rectangle {
                visible: root.detail !== ""
                Layout.fillWidth: true
                height: detailText.implicitHeight + 16
                color:  "#1affffff"
                radius: 6
                border.color: "#33ffffff"; border.width: 1

                Text {
                    id: detailText
                    anchors {
                        left: parent.left; right: parent.right
                        top:  parent.top
                        margins: 8
                    }
                    text:  root.detail
                    color: "#aaaaaa"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
            }

            // Button row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Spacer
                Item { Layout.fillWidth: true }

                // Cancel
                Rectangle {
                    width: rejectLbl.implicitWidth + 24; height: 34
                    radius: 6
                    color:  rejectArea.containsMouse ? "#3a3a3a" : "#222222"
                    border.color: "#666666"; border.width: 1
                    Text {
                        id: rejectLbl
                        anchors.centerIn: parent
                        text:  root.rejectLabel
                        color: "#cccccc"; font.pixelSize: 13
                    }
                    MouseArea {
                        id: rejectArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: root.rejected()
                    }
                }

                // Accept (destructive)
                Rectangle {
                    width: acceptLbl.implicitWidth + 24; height: 34
                    radius: 6
                    color:  acceptArea.containsMouse ? root.acceptHoverColor : root.acceptColor
                    border.color: root.acceptBorderColor; border.width: 1
                    Text {
                        id: acceptLbl
                        anchors.centerIn: parent
                        text:  root.acceptLabel
                        color: "#ffffff"; font.pixelSize: 13; font.bold: true
                    }
                    MouseArea {
                        id: acceptArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: root.accepted()
                    }
                }
            }

            // bottom padding
            Item { height: 2 }
        }
    }
}
