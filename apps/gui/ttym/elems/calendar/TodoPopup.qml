// TodoPopup.qml — self-contained todo list popup.
// Separate from events.  Todos persist every day.  No event linkage.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../chrome"

Item {
    id: root

    required property QtObject appState

    signal closeRequested()

    z: 9998

    // Track which row is in edit mode (-1 = none, >=0 = index)
    property int    editingIndex:      -1
    property bool   addingNew:         false
    property string pendingDeleteId:   ""
    property string pendingDeleteTitle: ""

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
        width:  Math.min(root.width * 0.58, 500)
        anchors.centerIn: parent
        height: Math.min(cardScroll.contentHeight + titleRow.height + 32 + addArea.height, root.height * 0.85)
        color:  "#ee1a0a28"
        radius: 12
        border.color: "#556622aa"; border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        property int doneCount: {
            var _dep = root.appState.todoRevision;
            var n = 0;
            for (var i = 0; i < root.appState.todoModel.count; i++)
                if (root.appState.todoModel.get(i).doneToday) n++;
            return n;
        }

        // ── Title bar ─────────────────────────────────────────────────────────
        RowLayout {
            id: titleRow
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
            height: 36
            spacing: 8

            Text {
                text: "✅  Todos"
                color: "#cc88ff"; font.pixelSize: 17; font.bold: true
                Layout.fillWidth: true
            }
            // Add button
            Rectangle {
                width: 28; height: 28; radius: 14
                color: addBtnArea.containsMouse ? "#4a1a6a" : "#200a30"
                border.color: "#6622aa"; border.width: 1
                Text { anchors.centerIn: parent; text: "+"; color: "#cc88ff"; font.pixelSize: 18; font.bold: true }
                MouseArea {
                    id: addBtnArea
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.editingIndex = -1;
                        root.addingNew = true;
                        addTitleField.text = "";
                        addCommentField.text = "";
                        Qt.callLater(function() { addTitleField.forceActiveFocus(); });
                    }
                }
            }
            // Close button
            Rectangle {
                width: 28; height: 28; radius: 14
                color: closeBtnArea.containsMouse ? "#ff4444" : "#333333"
                border.color: "#ffffff"; border.width: 1
                Text { anchors.centerIn: parent; text: "✕"; color: "#ffffff"; font.pixelSize: 13; font.bold: true }
                MouseArea {
                    id: closeBtnArea
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }
        }

        Rectangle {
            id: divider
            anchors.top: titleRow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 4
            height: 1
            color: "#338822cc"
        }

        // ── Scrollable list ───────────────────────────────────────────────────
        ScrollView {
            id: cardScroll
            anchors {
                top: divider.bottom; left: parent.left; right: parent.right; bottom: addArea.top
                topMargin: 8; leftMargin: 8; rightMargin: 8; bottomMargin: 4
            }
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                id: listCol
                width: cardScroll.width - 4
                spacing: 6

                // ── Empty state ────────────────────────────────────────────────
                Text {
                    visible: root.appState.todoModel.count === 0 && !root.addingNew
                    text: "No todos yet. Press + to add one."
                    color: "#888888"; font.pixelSize: 13
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    topPadding: 8
                }

                // ── Active rows ────────────────────────────────────────────────
                Repeater {
                    id: activeRepeater
                    model: root.appState.todoModel

                    delegate: Loader {
                        id: rowLoader
                        property int   _idx:     index
                        property string _todoId:  model.todoId  || ""
                        property string _title:   model.title   || ""
                        property string _comment: model.comment || ""
                        property bool   _done: {
                            var _r = root.appState.todoRevision;
                            return model.doneToday === true;
                        }

                        Layout.fillWidth: true
                        visible: !_done
                        z: root.editingIndex === _idx ? 1 : 0

                        sourceComponent: root.editingIndex === _idx ? editRowComp : activeRowComp

                        Component {
                            id: activeRowComp
                            Rectangle {
                                width: listCol.width
                                height: activeRowLayout.implicitHeight + 14
                                radius: 6
                                color:  activeHover.hovered ? "#2d0f3f" : "#1a0828"
                                border.color: "#3d1a55"; border.width: 1

                                RowLayout {
                                    id: activeRowLayout
                                    anchors { fill: parent; margins: 8 }
                                    spacing: 8

                                    Rectangle {
                                        width: 22; height: 22; radius: 4
                                        color: "transparent"; border.color: "#442266"; border.width: 2
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.appState.toggleTodoDoneById(rowLoader._todoId)
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text { text: rowLoader._title; color: "#e8ccff"; font.pixelSize: 13; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                        Text { visible: rowLoader._comment !== ""; text: rowLoader._comment; color: "#b07acc"; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    }
                                    // Edit
                                    Rectangle {
                                        width: 24; height: 24; radius: 12
                                        color: editBtnH.containsMouse ? "#3a1a5a" : "transparent"
                                        border.color: "#3d1a55"; border.width: 1
                                        Text { anchors.centerIn: parent; text: "✎"; color: "#cc88ff"; font.pixelSize: 12 }
                                        HoverHandler { id: editBtnH }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.addingNew = false; root.editingIndex = rowLoader._idx; } }
                                    }
                                    // Delete
                                    Rectangle {
                                        width: 24; height: 24; radius: 12
                                        color: delBtnH.containsMouse ? "#3a1010" : "transparent"
                                        border.color: "#ff4444"; border.width: 1
                                        Text { anchors.centerIn: parent; text: "✕"; color: "#ff6666"; font.pixelSize: 11 }
                                        HoverHandler { id: delBtnH }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: {
                                            root.pendingDeleteId    = rowLoader._todoId;
                                            root.pendingDeleteTitle = rowLoader._title;
                                        }}
                                    }
                                }
                                HoverHandler { id: activeHover }
                            }
                        }

                        Component {
                            id: editRowComp
                            Rectangle {
                                id: editRect
                                width: listCol.width
                                height: editCol.implicitHeight + 16
                                radius: 6; color: "#221133"
                                border.color: "#4422aa"; border.width: 1

                                property string _editTitle:   rowLoader._title
                                property string _editComment: rowLoader._comment

                                ColumnLayout {
                                    id: editCol
                                    anchors { fill: parent; margins: 8 }
                                    spacing: 6

                                    TextField {
                                        id: editTitleField
                                        text: editRect._editTitle
                                        placeholderText: "Title"
                                        Layout.fillWidth: true
                                        color: "#ffffff"; font.pixelSize: 13
                                        background: Rectangle { color: "#2a1a3a"; radius: 4; border.color: "#4422aa"; border.width: 1 }
                                        Component.onCompleted: forceActiveFocus()
                                        Keys.onReturnPressed: saveEdit()
                                        Keys.onEscapePressed: root.editingIndex = -1
                                    }
                                    TextField {
                                        id: editCommentField
                                        text: editRect._editComment
                                        placeholderText: "Comment (optional)"
                                        Layout.fillWidth: true
                                        color: "#aaaaaa"; font.pixelSize: 11
                                        background: Rectangle { color: "#2a1a3a"; radius: 4; border.color: "#331588"; border.width: 1 }
                                        Keys.onReturnPressed: saveEdit()
                                        Keys.onEscapePressed: root.editingIndex = -1
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            width: 60; height: 24; radius: 4
                                            color: saveBtnH.containsMouse ? "#1a5a2a" : "#0a3a1a"
                                            border.color: "#44aa44"; border.width: 1
                                            Text { anchors.centerIn: parent; text: "Save"; color: "#88ffaa"; font.pixelSize: 12 }
                                            HoverHandler { id: saveBtnH }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: saveEdit() }
                                        }
                                        Rectangle {
                                            width: 60; height: 24; radius: 4
                                            color: cancelBtnH.containsMouse ? "#3a1010" : "#1a0a0a"
                                            border.color: "#884444"; border.width: 1
                                            Text { anchors.centerIn: parent; text: "Cancel"; color: "#ff8888"; font.pixelSize: 12 }
                                            HoverHandler { id: cancelBtnH }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.editingIndex = -1 }
                                        }
                                    }
                                }

                                function saveEdit() {
                                    var t = editTitleField.text.trim();
                                    if (t) root.appState.updateTodo(rowLoader._todoId, t, editCommentField.text.trim());
                                    root.editingIndex = -1;
                                }
                            }
                        }
                    }
                }

                // ── Done section ───────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true; height: 1; color: "#331133aa"
                    visible: card.doneCount > 0
                }
                Text {
                    visible: card.doneCount > 0
                    text: "✓  Done"
                    color: "#6622aa"; font.pixelSize: 12; font.bold: true
                    leftPadding: 4
                }

                Repeater {
                    model: root.appState.todoModel

                    delegate: Rectangle {
                        id: doneRow
                        property string _todoId:  model.todoId  || ""
                        property string _title:   model.title   || ""
                        property string _comment: model.comment || ""
                        property bool   _done: {
                            var _r = root.appState.todoRevision;
                            return model.doneToday === true;
                        }

                        Layout.fillWidth: true
                        visible: _done
                        height:  _done ? (doneLayout.implicitHeight + 14) : 0
                        radius: 6; color: doneHov.hovered ? "#261238" : "#160826"
                        border.color: "#331166"; border.width: _done ? 1 : 0
                        clip: true

                        RowLayout {
                            id: doneLayout
                            anchors { fill: parent; margins: 8 }
                            spacing: 8

                            Rectangle {
                                width: 22; height: 22; radius: 4
                                color: "#221144"; border.color: "#5522aa"; border.width: 2
                                Text { anchors.centerIn: parent; text: "✓"; color: "#9966cc"; font.pixelSize: 12; font.bold: true }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.appState.toggleTodoDoneById(doneRow._todoId) }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: doneRow._title; color: "#664488"; font.pixelSize: 13; font.strikeout: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                Text { visible: doneRow._comment !== ""; text: doneRow._comment; color: "#443355"; font.pixelSize: 11; font.strikeout: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                        }
                        HoverHandler { id: doneHov }
                    }
                }

                Item { height: 4 }
            }
        }

        // ── Inline add form (bottom of card) ──────────────────────────────────
        Rectangle {
            id: addArea
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 8; bottomMargin: 12 }
            height: root.addingNew ? (addFormCol.implicitHeight + 16) : 0
            visible: root.addingNew
            clip: true
            radius: 6; color: "#1a0828"
            border.color: "#6622aa"; border.width: 1

            ColumnLayout {
                id: addFormCol
                anchors { fill: parent; margins: 8 }
                spacing: 6

                TextField {
                    id: addTitleField
                    placeholderText: "New todo title…"
                    Layout.fillWidth: true
                    color: "#ffffff"; font.pixelSize: 13
                    background: Rectangle { color: "#2a1a3a"; radius: 4; border.color: "#6622aa"; border.width: 1 }
                    Keys.onReturnPressed: saveAdd()
                    Keys.onEscapePressed: root.addingNew = false
                }
                TextField {
                    id: addCommentField
                    placeholderText: "Comment (optional)"
                    Layout.fillWidth: true
                    color: "#aaaaaa"; font.pixelSize: 11
                    background: Rectangle { color: "#2a1a3a"; radius: 4; border.color: "#551a77"; border.width: 1 }
                    Keys.onReturnPressed: saveAdd()
                    Keys.onEscapePressed: root.addingNew = false
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 60; height: 24; radius: 4
                        color: addSaveH.containsMouse ? "#1a5a2a" : "#0a3a1a"
                        border.color: "#44aa44"; border.width: 1
                        Text { anchors.centerIn: parent; text: "Add"; color: "#88ffaa"; font.pixelSize: 12 }
                        HoverHandler { id: addSaveH }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: saveAdd() }
                    }
                    Rectangle {
                        width: 60; height: 24; radius: 4
                        color: addCancelH.containsMouse ? "#3a1010" : "#1a0a0a"
                        border.color: "#884444"; border.width: 1
                        Text { anchors.centerIn: parent; text: "Cancel"; color: "#ff8888"; font.pixelSize: 12 }
                        HoverHandler { id: addCancelH }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.addingNew = false }
                    }
                }
            }
        }
    }

    function saveAdd() {
        var t = addTitleField.text.trim();
        if (t) root.appState.addTodo(t, addCommentField.text.trim());
        root.addingNew = false;
    }

    // ── Delete confirmation dialog ────────────────────────────────────────────
    ConfirmDialog {
        anchors.fill: parent
        visible: root.pendingDeleteId !== ""
        z: 9999
        title: "Delete Todo"
        message: "Delete \"" + root.pendingDeleteTitle + "\"?"
        acceptLabel: "Delete"
        rejectLabel: "Cancel"
        acceptColor:       "#660000"
        acceptHoverColor:  "#aa2222"
        acceptBorderColor: "#cc4444"
        onAccepted: {
            root.appState.removeTodo(root.pendingDeleteId);
            root.pendingDeleteId    = "";
            root.pendingDeleteTitle = "";
        }
        onRejected: {
            root.pendingDeleteId    = "";
            root.pendingDeleteTitle = "";
        }
    }
}
