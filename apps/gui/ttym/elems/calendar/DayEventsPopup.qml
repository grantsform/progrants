// DayEventsPopup.qml — shows events and todos for a specific day, with tabs.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../chrome"

Popup {
    id: root

    required property QtObject appState

    property int    selectedYear:   0
    property int    selectedMonth:  0
    property int    selectedDay:    0
    property string selectedDateStr: ""
    property string selectedDateKey: Qt.formatDate(
        new Date(selectedYear, selectedMonth, selectedDay), "yyyy-MM-dd")

    property string activeTab: "events"

    signal editEventRequested(string eventId)
    signal addEventForDayRequested(int year, int month, int day)

    property string pendingDeleteId:          ""
    property string pendingDeleteTitle:       ""
    property bool   pendingDeleteIsRecurring: false

    property bool   todoAddingNew:    false
    property string todoEditingId:    ""
    property string todoFormTitle:    ""
    property string todoFormComment:  ""
    property string pendingDeleteTodoId:    ""
    property string pendingDeleteTodoTitle: ""

    modal: true

    function showDay(year, month, day) {
        selectedYear    = year;
        selectedMonth   = month;
        selectedDay     = day;
        selectedDateStr = Qt.formatDate(new Date(year, month, day), "dddd, MMMM d, yyyy");
        activeTab       = "events";
        todoAddingNew   = false;
        todoEditingId   = "";
        todoFormTitle   = "";
        todoFormComment = "";
        dayEventsModel.clear();
        var dayEvents = appState.eventsForDay(year, month, day);
        for (var i = 0; i < dayEvents.length; i++) {
            var ev = dayEvents[i];
            dayEventsModel.append({
                eventId:         ev.eventId         || "",
                title:           ev.title           || "Untitled Event",
                time:            ev.allDay           ? "All Day" : (ev.time || ""),
                comment:         ev.comment          || "",
                isRecurring:     !!ev.isRecurringInstance,
                originalEventId: ev.originalEventId  || ""
            });
        }
        open();
    }

    ListModel { id: dayEventsModel }

    Rectangle {
        width: 700
        height: Math.min(680, root.parent.height * 0.8)
        anchors.centerIn: parent
        color: "#dd000000"
        radius: 10
        border.color: "#ffffff"; border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 8

            // Header
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.selectedDateStr
                    color: "#ffffff"; font.pixelSize: 18; font.bold: true
                    Layout.fillWidth: true
                }
                Rectangle {
                    width: 30; height: 30; radius: 15
                    color: closeBtnHov.containsMouse ? "#ff4444" : "#333333"
                    border.color: "#ffffff"; border.width: 1
                    Text { anchors.centerIn: parent; text: "✕"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }
                    HoverHandler { id: closeBtnHov }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#44ffffff" }

            // Tab bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: ["Events", "Todos"]
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 32; radius: 6
                        color: root.activeTab === modelData.toLowerCase()
                               ? "#33ffffff"
                               : tabHov.containsMouse ? "#15ffffff" : "transparent"
                        border.color: root.activeTab === modelData.toLowerCase() ? "#88ffffff" : "#33ffffff"
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: modelData + (modelData === "Events"
                                              ? " (" + dayEventsModel.count + ")"
                                              : " (" + appState.todoModel.count + ")")
                            color: root.activeTab === modelData.toLowerCase() ? "#ffffff" : "#888888"
                            font.pixelSize: 13
                            font.bold: root.activeTab === modelData.toLowerCase()
                        }
                        HoverHandler { id: tabHov }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.activeTab     = modelData.toLowerCase();
                                root.todoAddingNew = false;
                                root.todoEditingId = "";
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#33ffffff" }

            // Tab content
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // EVENTS TAB
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.activeTab === "events"
                    spacing: 0

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        ListView {
                            model: dayEventsModel
                            spacing: 8

                            delegate: Rectangle {
                                width: ListView.view.width
                                height: 65
                                color: "#33ffffff"; radius: 6
                                border.color: "#66ffffff"; border.width: 1

                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10; spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 6
                                            Text {
                                                text: model.title; color: "#ffffff"
                                                font.pixelSize: 14; font.bold: true
                                                Layout.fillWidth: true; elide: Text.ElideRight
                                            }
                                            Rectangle {
                                                visible: model.isRecurring
                                                width: 16; height: 16; radius: 8; color: "#2288cc"
                                                Text { anchors.centerIn: parent; text: "R"; color: "#ffffff"; font.pixelSize: 9; font.bold: true }
                                            }
                                        }
                                        Text { text: model.time; color: "#cccccc"; font.pixelSize: 12 }
                                        Text {
                                            visible: model.comment !== ""
                                            text: model.comment; color: "#aaaaaa"; font.pixelSize: 11
                                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            maximumLineCount: 2; elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        width: 28; height: 28; radius: 14
                                        color: evEditHov.containsMouse ? "#666666" : "#444444"
                                        border.color: "#ffffff"; border.width: 1
                                        Text { anchors.centerIn: parent; text: "✎"; color: "#ffffff"; font.pixelSize: 13 }
                                        HoverHandler { id: evEditHov }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var idToEdit = model.isRecurring ? model.originalEventId : model.eventId;
                                                root.editEventRequested(idToEdit);
                                                root.close();
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 28; height: 28; radius: 14
                                        color: evDelHov.containsMouse ? "#3a1010" : "#1a0808"
                                        border.color: "#ff4444"; border.width: 1
                                        Text { anchors.centerIn: parent; text: "✕"; color: "#ff6666"; font.pixelSize: 12 }
                                        HoverHandler { id: evDelHov }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.pendingDeleteId          = model.isRecurring ? model.originalEventId : model.eventId;
                                                root.pendingDeleteTitle       = model.title;
                                                root.pendingDeleteIsRecurring = model.isRecurring;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // TODOS TAB
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.activeTab === "todos"
                    spacing: 6

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        ListView {
                            model: appState.todoModel
                            spacing: 6

                            delegate: Rectangle {
                                id: todoRow
                                width: ListView.view.width
                                height: 52
                                color: "#22ffffff"; radius: 6
                                border.color: "#44ffffff"; border.width: 1

                                property bool   doneOnDay: appState.isTodoDoneOnDate(model.todoId, root.selectedDateKey)
                                property string _todoId:   model.todoId
                                property string _title:    model.title

                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 8; spacing: 8

                                    Rectangle {
                                        width: 22; height: 22; radius: 4
                                        color: todoRow.doneOnDay ? "#226622" : "transparent"
                                        border.color: todoRow.doneOnDay ? "#44cc44" : "#666666"; border.width: 2
                                        Text {
                                            anchors.centerIn: parent; text: "✓"
                                            color: "#44cc44"; font.pixelSize: 13; font.bold: true
                                            visible: todoRow.doneOnDay
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: appState.toggleTodoDoneForDate(model.todoId, root.selectedDateKey)
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text {
                                            text: model.title
                                            color: todoRow.doneOnDay ? "#888888" : "#ffffff"
                                            font.pixelSize: 13; font.bold: true
                                            font.strikeout: todoRow.doneOnDay
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: model.comment !== ""
                                            text: model.comment; color: "#888888"; font.pixelSize: 11
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        width: 26; height: 26; radius: 13
                                        color: tdEditHov.containsMouse ? "#444466" : "transparent"
                                        border.color: "#888888"; border.width: 1
                                        Text { anchors.centerIn: parent; text: "✎"; color: "#cccccc"; font.pixelSize: 12 }
                                        HoverHandler { id: tdEditHov }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.todoEditingId   = model.todoId;
                                                root.todoAddingNew   = false;
                                                root.todoFormTitle   = model.title;
                                                root.todoFormComment = model.comment;
                                                Qt.callLater(function() { dtTodoTitleField.forceActiveFocus(); });
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 26; height: 26; radius: 13
                                        color: tdDelHov.containsMouse ? "#3a1010" : "transparent"
                                        border.color: "#ff4444"; border.width: 1
                                        Text { anchors.centerIn: parent; text: "✕"; color: "#ff6666"; font.pixelSize: 11 }
                                        HoverHandler { id: tdDelHov }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.pendingDeleteTodoId    = model.todoId;
                                                root.pendingDeleteTodoTitle = model.title;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Inline add/edit form
                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.todoAddingNew || root.todoEditingId !== ""
                        height: visible ? todoFormCol.implicitHeight + 16 : 0
                        color: "#1a2244"; radius: 6
                        border.color: "#334488"; border.width: 1

                        ColumnLayout {
                            id: todoFormCol
                            width: parent.width - 20
                            anchors.centerIn: parent
                            spacing: 6

                            TextField {
                                id: dtTodoTitleField
                                Layout.fillWidth: true
                                placeholderText: "Todo title"
                                text: root.todoFormTitle
                                onTextChanged: root.todoFormTitle = text
                                background: Rectangle { color: "#1a1a33"; radius: 4; border.color: "#446688"; border.width: 1 }
                                color: "#ffffff"; font.pixelSize: 13
                                placeholderTextColor: "#666688"
                            }

                            TextField {
                                id: dtTodoCommentField
                                Layout.fillWidth: true
                                placeholderText: "Comment (optional)"
                                text: root.todoFormComment
                                onTextChanged: root.todoFormComment = text
                                background: Rectangle { color: "#1a1a33"; radius: 4; border.color: "#446688"; border.width: 1 }
                                color: "#aaaacc"; font.pixelSize: 12
                                placeholderTextColor: "#555577"
                            }

                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: 70; height: 26; radius: 4
                                    color: dtSaveH.containsMouse ? "#226644" : "#113322"
                                    border.color: "#44aa66"; border.width: 1
                                    Text { anchors.centerIn: parent; text: root.todoAddingNew ? "Add" : "Save"; color: "#88ffcc"; font.pixelSize: 12; font.bold: true }
                                    HoverHandler { id: dtSaveH }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var t = root.todoFormTitle.trim();
                                            if (!t) return;
                                            if (root.todoAddingNew)
                                                appState.addTodo(t, root.todoFormComment.trim());
                                            else
                                                appState.updateTodo(root.todoEditingId, t, root.todoFormComment.trim());
                                            root.todoAddingNew   = false;
                                            root.todoEditingId   = "";
                                            root.todoFormTitle   = "";
                                            root.todoFormComment = "";
                                        }
                                    }
                                }
                                Rectangle {
                                    width: 70; height: 26; radius: 4
                                    color: dtCancelH.containsMouse ? "#441111" : "#221111"
                                    border.color: "#884444"; border.width: 1
                                    Text { anchors.centerIn: parent; text: "Cancel"; color: "#ff8888"; font.pixelSize: 12 }
                                    HoverHandler { id: dtCancelH }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.todoAddingNew   = false;
                                            root.todoEditingId   = "";
                                            root.todoFormTitle   = "";
                                            root.todoFormComment = "";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Footer
            Rectangle { Layout.fillWidth: true; height: 1; color: "#22ffffff" }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }

                Button {
                    visible: root.activeTab === "events"
                    text: "+ Add Event"
                    contentItem: Text {
                        text: parent.text
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        color: "#88ffcc"; font.pixelSize: 13; font.bold: true
                    }
                    background: Rectangle {
                        color: parent.hovered ? "#1a4a2a" : "#0a2a1a"; radius: 6
                        border.color: "#44aa66"; border.width: 1
                        implicitWidth: 110; implicitHeight: 28
                    }
                    onClicked: {
                        root.addEventForDayRequested(root.selectedYear, root.selectedMonth, root.selectedDay);
                        root.close();
                    }
                }

                Rectangle {
                    visible: root.activeTab === "todos" && !root.todoAddingNew && root.todoEditingId === ""
                    width: 110; height: 28; radius: 6
                    color: addTodoDayH.containsMouse ? "#2a1a4a" : "#1a0a2a"
                    border.color: "#8844aa"; border.width: 1
                    Text { anchors.centerIn: parent; text: "+ Add Todo"; color: "#cc88ff"; font.pixelSize: 13; font.bold: true }
                    HoverHandler { id: addTodoDayH }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.todoAddingNew   = true;
                            root.todoEditingId   = "";
                            root.todoFormTitle   = "";
                            root.todoFormComment = "";
                            Qt.callLater(function() { dtTodoTitleField.forceActiveFocus(); });
                        }
                    }
                }
            }
        }

        // Event delete confirm
        ConfirmDialog {
            anchors.fill: parent
            visible: root.pendingDeleteId !== ""
            z: 9999
            title: "Delete Event"
            message: "Delete \"" + root.pendingDeleteTitle + "\"?"
            detail: root.pendingDeleteIsRecurring
                    ? "This is a recurring event. Deleting it will remove all occurrences across every day."
                    : ""
            acceptLabel: "Delete"; rejectLabel: "Cancel"
            acceptColor: "#660000"; acceptHoverColor: "#aa2222"; acceptBorderColor: "#cc4444"
            onAccepted: {
                var evId = root.pendingDeleteId;
                root.pendingDeleteId = ""; root.pendingDeleteTitle = ""; root.pendingDeleteIsRecurring = false;
                appState.removeEventByEventId(evId);
                root.showDay(root.selectedYear, root.selectedMonth, root.selectedDay);
                if (dayEventsModel.count === 0 && root.activeTab === "events")
                    root.activeTab = "todos";
            }
            onRejected: {
                root.pendingDeleteId = ""; root.pendingDeleteTitle = ""; root.pendingDeleteIsRecurring = false;
            }
        }

        // Todo delete confirm
        ConfirmDialog {
            anchors.fill: parent
            visible: root.pendingDeleteTodoId !== ""
            z: 9999
            title: "Delete Todo"
            message: "Delete \"" + root.pendingDeleteTodoTitle + "\"?"
            acceptLabel: "Delete"; rejectLabel: "Cancel"
            acceptColor: "#660000"; acceptHoverColor: "#aa2222"; acceptBorderColor: "#cc4444"
            onAccepted: {
                appState.removeTodo(root.pendingDeleteTodoId);
                root.pendingDeleteTodoId = ""; root.pendingDeleteTodoTitle = "";
            }
            onRejected: {
                root.pendingDeleteTodoId = ""; root.pendingDeleteTodoTitle = "";
            }
        }
    }
}
