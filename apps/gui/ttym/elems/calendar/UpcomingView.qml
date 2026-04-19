// UpcomingView.qml — scrollable list of upcoming events with delete, edit,
// and countdown badge.  All-day events appear as a clickable strip above.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../chrome"

ColumnLayout {
    id: root

    // ── Required context ────────────────────────────────────────────────────────────────
    required property QtObject appState

    // ── Scaling helpers ───────────────────────────────────────────────────────────────
    property real cellScale: 1.25

    // ── Hide button hold state ───────────────────────────────────────────────────────
    property int hideHoldingIndex: -1
    property real hideHoldProgress: 0.0
    
    Timer {
        id: hideHoldTimer
        interval: 100
        repeat: true
        running: root.hideHoldingIndex >= 0
        onTriggered: {
            root.hideHoldProgress += 0.1;
            if (root.hideHoldProgress >= 1.0) {
                root.hideHoldProgress = 1.0;
                hideHoldTimer.stop();
                if (root.hideHoldingIndex >= 0) {
                    let model = appState.eventModel;
                    if (root.hideHoldingIndex < model.count) {
                        let eventId = model.get(root.hideHoldingIndex).eventId;
                        console.log("Hiding event:", eventId, "Count before:", model.count);
                        
                        // First, let's see the event before hiding
                        let originalEvent = model.get(root.hideHoldingIndex);
                        console.log("Original event hidden status:", originalEvent.hidden);
                        
                        appState.hideEventById(eventId);
                        
                        console.log("Calling refreshEventModel...");
                        appState.refreshEventModel();
                        
                        Qt.callLater(function() {
                            console.log("Count after refresh:", appState.eventModel.count);
                            // Check if the specific event is still in the model
                            let found = false;
                            for (let i = 0; i < appState.eventModel.count; i++) {
                                let ev = appState.eventModel.get(i);
                                if (ev.eventId === eventId) {
                                    found = true;
                                    console.log("Found event", eventId, "with hidden =", ev.hidden);
                                    break;
                                }
                            }
                            console.log("Event", eventId, "still in model:", found);
                        });
                    }
                }
                root.hideHoldingIndex = -1;
                root.hideHoldProgress = 0.0;
            }
        }
    }

    // ── Signals ───────────────────────────────────────────────────────────────
    signal editEventRequested(string eventId)
    signal allDayStripClicked()
    signal addRecurringEventRequested()
    signal addTodoRequested()
    signal todoDeleteRequested(string todoId, string todoTitle)

    function openTodoAdd() {
        todoSection.expanded = true;
        todoSection.openAdd();
    }

    property int todoLeftCount: {
        var _dep = appState.todoRevision;
        var n = 0;
        for (var i = 0; i < appState.todoModel.count; i++)
            if (!appState.todoModel.get(i).doneToday) n++;
        return n;
    }

    spacing: 4

    // ── Heading ───────────────────────────────────────────────────────────────
    Text {
        text: "Upcoming Events"
        color: "#ffffff"; font.pixelSize: 18 * root.cellScale; font.bold: true
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignHCenter
    }

    Text {
        text: "Upcoming Event Count: " + appState.eventModel.count
        color: "#aaaaaa"; font.pixelSize: 12 * root.cellScale
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignHCenter
    }

    // ── All-day strip (visible only when there are all-day events today) ──────
    Rectangle {
        id: allDayStrip
        visible: appState.allDayModel.count > 0
        Layout.fillWidth: true
        height: visible ? (36 * root.cellScale) : 0
        radius: 6
        color: allDayStripArea.containsMouse ? "#ccffffff" : "#99ffffff"
        border.color: "#ddffffff"; border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Text {
                text: "✅"
                font.pixelSize: 16 * root.cellScale
            }
            Text {
                text: appState.allDayModel.count === 1
                    ? appState.allDayModel.get(0).title
                    : appState.allDayModel.count + " all-day events today"
                color: "#111111"; font.pixelSize: 13 * root.cellScale
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: "▸"
                color: "#000000"; font.pixelSize: 14 * root.cellScale
            }
        }

        MouseArea {
            id: allDayStripArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.allDayStripClicked()
        }
    }

    // ── Todo section (expandable) ─────────────────────────────────────────────
    ColumnLayout {
        id: todoSection
        Layout.fillWidth: true
        spacing: 2

        property bool   expanded:           false
        property int    editingIndex:        -1
        property string editingTodoId:       ""
        property bool   addingNew:           false

        property int doneCount: {
            var _dep = appState.todoRevision;
            var n = 0;
            for (var i = 0; i < appState.todoModel.count; i++)
                if (appState.todoModel.get(i).doneToday) n++;
            return n;
        }

        function openAdd() {
            editingIndex  = -1;
            editingTodoId = "";
            addingNew     = true;
            Qt.callLater(function() {
                todoFormTitleField.text   = "";
                todoFormCommentField.text = "";
                todoFormTitleField.forceActiveFocus();
            });
        }

        function openEdit(idx, id, title, comment) {
            addingNew     = false;
            editingIndex  = idx;
            editingTodoId = id;
            Qt.callLater(function() {
                todoFormTitleField.text   = title;
                todoFormCommentField.text = comment;
                todoFormTitleField.forceActiveFocus();
            });
        }

        function saveForm() {
            var t = todoFormTitleField.text.trim();
            if (editingIndex !== -1) {
                if (t) appState.updateTodo(editingTodoId, t, todoFormCommentField.text.trim());
                editingIndex  = -1;
                editingTodoId = "";
            } else {
                if (t) appState.addTodo(t, todoFormCommentField.text.trim());
                addingNew = false;
            }
        }

        function cancelForm() {
            editingIndex  = -1;
            editingTodoId = "";
            addingNew     = false;
        }

        // ── Header strip ─────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 36 * root.cellScale
            radius: 6
            color: todoHdrArea.containsMouse ? "#cc8822cc" : "#888822cc"
            border.color: "#dd8822ff"; border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Text { text: "✅"; font.pixelSize: 16 * root.cellScale }
                Text {
                    text: root.todoLeftCount === 0 && appState.todoModel.count > 0
                        ? "✓  ALL DONE"
                        : "[ " + root.todoLeftCount + " ] TODO"
                    color: "#eeddff"; font.pixelSize: 13 * root.cellScale; font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: todoSection.expanded ? "▾" : "▸"
                    color: "#ddaaff"; font.pixelSize: 14 * root.cellScale
                }
            }

            MouseArea {
                id: todoHdrArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: todoSection.expanded = !todoSection.expanded
            }
        }

        // ── Expanded body ────────────────────────────────────────────────
        Rectangle {
            visible: todoSection.expanded
            Layout.fillWidth: true
            implicitHeight: todoBodyCol.implicitHeight + 12
            radius: 6
            color: "#cc0e0520"
            border.color: "#443322aa"; border.width: 1
            clip: true

            property int maxRows: 6

            ColumnLayout {
                id: todoBodyCol
                width: parent.width
                spacing: 0
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 6; topMargin: 6 }

                // ── Active todo rows ──────────────────────────────────────
                ScrollView {
                    id: todoActiveScroll
                    Layout.fillWidth: true
                    contentWidth: availableWidth
                    height: Math.max(
                        1,
                        Math.min(
                            appState.todoModel.count * (44 * root.cellScale + 4),
                            parent.parent.maxRows * (44 * root.cellScale + 4)
                        )
                    )
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    clip: true
                    visible: appState.todoModel.count > 0

                    ColumnLayout {
                        width: todoActiveScroll.availableWidth
                        spacing: 4

                        Repeater {
                            model: appState.todoModel

                            delegate: Rectangle {
                                id: todoRowItem
                                property string _todoId:  model.todoId  || ""
                                property string _title:   model.title   || ""
                                property string _comment: model.comment || ""
                                property bool   _done: {
                                    var _r = appState.todoRevision;
                                    return model.doneToday === true;
                                }

                                Layout.fillWidth: true
                                visible: !_done
                                height:  !_done ? (taLayout.implicitHeight + 14) : 0
                                radius: 6
                                color: taHov.hovered ? "#2d0f3f" : "#1a0828"
                                border.color: "#3d1a55"; border.width: 1
                                clip: true

                                RowLayout {
                                    id: taLayout
                                    anchors { fill: parent; margins: 8 }
                                    spacing: 8

                                    Rectangle {
                                        width: 22; height: 22; radius: 4
                                        color: "transparent"; border.color: "#442266"; border.width: 2
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: appState.toggleTodoDoneById(todoRowItem._todoId)
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text { text: todoRowItem._title; color: "#e8ccff"; font.pixelSize: 13 * root.cellScale; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                        Text { visible: todoRowItem._comment !== ""; text: todoRowItem._comment; color: "#b07acc"; font.pixelSize: 11 * root.cellScale; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    }
                                    Rectangle {
                                        width: 24 * root.cellScale; height: 24 * root.cellScale; radius: width / 2
                                        color: taEditH.containsMouse ? "#3a1a5a" : "transparent"
                                        border.color: "#3d1a55"; border.width: 1
                                        Text { anchors.centerIn: parent; text: "✎"; color: "#cc88ff"; font.pixelSize: 12 * root.cellScale }
                                        HoverHandler { id: taEditH }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: todoSection.openEdit(index, todoRowItem._todoId, todoRowItem._title, todoRowItem._comment)
                                        }
                                    }
                                    Rectangle {
                                        width: 24 * root.cellScale; height: 24 * root.cellScale; radius: width / 2
                                        color: taDelH.containsMouse ? "#3a1010" : "transparent"
                                        border.color: "#ff4444"; border.width: 1
                                        Text { anchors.centerIn: parent; text: "✕"; color: "#ff6666"; font.pixelSize: 11 * root.cellScale }
                                        HoverHandler { id: taDelH }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: {
                                            root.todoDeleteRequested(todoRowItem._todoId, todoRowItem._title);
                                        }}
                                    }
                                }
                                HoverHandler { id: taHov }
                            }
                        }

                        // ── Done section ──────────────────────────────────────
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#331133aa"; visible: todoSection.doneCount > 0 }
                        Text {
                            visible: todoSection.doneCount > 0
                            text: "✓  Done"
                            color: "#6622aa"; font.pixelSize: 12 * root.cellScale; font.bold: true
                            leftPadding: 4
                        }

                        Repeater {
                            model: appState.todoModel

                            delegate: Rectangle {
                                id: tdRow
                                property string _todoId:  model.todoId  || ""
                                property string _title:   model.title   || ""
                                property string _comment: model.comment || ""
                                property bool   _done: {
                                    var _r = appState.todoRevision;
                                    return model.doneToday === true;
                                }

                                Layout.fillWidth: true
                                visible: _done
                                height:  _done ? (tdLayout.implicitHeight + 14) : 0
                                radius: 6; color: tdHov.hovered ? "#261238" : "#160826"
                                border.color: "#331166"; border.width: _done ? 1 : 0
                                clip: true

                                RowLayout {
                                    id: tdLayout
                                    anchors { fill: parent; margins: 8 }
                                    spacing: 8

                                    Rectangle {
                                        width: 22; height: 22; radius: 4
                                        color: "#221144"; border.color: "#5522aa"; border.width: 2
                                        Text { anchors.centerIn: parent; text: "✓"; color: "#9966cc"; font.pixelSize: 12 * root.cellScale; font.bold: true }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: appState.toggleTodoDoneById(tdRow._todoId) }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text { text: tdRow._title; color: "#664488"; font.pixelSize: 13 * root.cellScale; font.strikeout: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                        Text { visible: tdRow._comment !== ""; text: tdRow._comment; color: "#443355"; font.pixelSize: 11 * root.cellScale; font.strikeout: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    }
                                }
                                HoverHandler { id: tdHov }
                            }
                        }

                        Item { height: 4 }
                    }
                }

                // ── Toolbar: empty state text + add button ────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 4

                    Text {
                        visible: appState.todoModel.count === 0 && !todoSection.addingNew
                        text: "No todos yet."
                        color: "#664488"; font.pixelSize: 12 * root.cellScale
                        leftPadding: 2
                        Layout.fillWidth: true
                    }
                    Item { visible: appState.todoModel.count > 0; Layout.fillWidth: true }

                    Rectangle {
                        width: 22; height: 22; radius: 11
                        color: addTodoHov.containsMouse ? "#331a1a5a" : "transparent"
                        border.color: "#8822cc"; border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "+"; color: "#cc88ff"
                            font.pixelSize: 15 * root.cellScale; font.bold: true
                        }
                        HoverHandler { id: addTodoHov }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: todoSection.openAdd()
                        }
                    }
                }

                // ── Inline add / edit form ────────────────────────────────
                Rectangle {
                    id: todoFormArea
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    height: (todoSection.addingNew || todoSection.editingIndex !== -1) ? (todoFormCol.implicitHeight + 16) : 0
                    visible: todoSection.addingNew || todoSection.editingIndex !== -1
                    clip: true
                    radius: 6; color: "#1a0828"
                    border.color: "#6622aa"; border.width: 1

                    ColumnLayout {
                        id: todoFormCol
                        anchors { fill: parent; margins: 8 }
                        spacing: 6

                        TextField {
                            id: todoFormTitleField
                            placeholderText: todoSection.editingIndex !== -1 ? "Title" : "New todo title…"
                            Layout.fillWidth: true
                            color: "#ffffff"; font.pixelSize: 13 * root.cellScale
                            background: Rectangle { color: "#2a1a3a"; radius: 4; border.color: "#6622aa"; border.width: 1 }
                            Keys.onReturnPressed: todoSection.saveForm()
                            Keys.onEscapePressed: todoSection.cancelForm()
                        }
                        TextField {
                            id: todoFormCommentField
                            placeholderText: "Comment (optional)"
                            Layout.fillWidth: true
                            color: "#aaaaaa"; font.pixelSize: 11 * root.cellScale
                            background: Rectangle { color: "#2a1a3a"; radius: 4; border.color: "#551a77"; border.width: 1 }
                            Keys.onReturnPressed: todoSection.saveForm()
                            Keys.onEscapePressed: todoSection.cancelForm()
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: 60; height: 24; radius: 4
                                color: todoFormSaveH.containsMouse ? "#1a5a2a" : "#0a3a1a"
                                border.color: "#44aa44"; border.width: 1
                                Text { anchors.centerIn: parent; text: todoSection.editingIndex !== -1 ? "Save" : "Add"; color: "#88ffaa"; font.pixelSize: 12 * root.cellScale }
                                HoverHandler { id: todoFormSaveH }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: todoSection.saveForm() }
                            }
                            Rectangle {
                                width: 60; height: 24; radius: 4
                                color: todoFormCancelH.containsMouse ? "#3a1010" : "#1a0a0a"
                                border.color: "#884444"; border.width: 1
                                Text { anchors.centerIn: parent; text: "Cancel"; color: "#ff8888"; font.pixelSize: 12 * root.cellScale }
                                HoverHandler { id: todoFormCancelH }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: todoSection.cancelForm() }
                            }
                        }
                    }
                }

                Item { height: 4 }
            }
        }
    }

    // ── Recurring events section ──────────────────────────────────────────────
    ColumnLayout {
        id: recurringSection
        Layout.fillWidth: true
        spacing: 2
        clip: false

        property bool expanded: false
        property int  filterMode: 0  // 0=All, 1=Timed, 2=All-day
        property int  maxRows: 2

        property var allItems: {
            var _dep = appState.eventsRevision;
            var result = [];
            for (var i = 0; i < appState.recurringTodayModel.count; i++) {
                var ev = appState.recurringTodayModel.get(i);
                result.push({ title: ev.title || "", time: ev.time || "" });
            }
            return result;
        }

        // Index of the soonest upcoming (or in-progress) timed recurring instance today
        property int nextTimedIdx: {
            var _dep = appState.eventsRevision;
            var nowMs = appState.now.getTime();
            var bestIdx = -1;
            var bestDiff = Infinity;
            for (var i = 0; i < appState.recurringTodayModel.count; i++) {
                var ev = appState.recurringTodayModel.get(i);
                if (!ev.time || ev.time === "" || ev.time === "All Day") continue;
                var evDate = ev.date || "";
                if (!evDate) continue;
                var dp = evDate.split("-");
                var tp = ev.time.split(":");
                var evMs = new Date(
                    parseInt(dp[0],10), parseInt(dp[1],10)-1, parseInt(dp[2],10),
                    parseInt(tp[0]||"0",10), parseInt(tp[1]||"0",10), parseInt(tp[2]||"0",10)
                ).getTime();
                var diff = evMs - nowMs;
                if (diff >= 0 && diff < bestDiff) {
                    bestIdx = i;
                    bestDiff = diff;
                }
            }
            return bestIdx;
        }

        visible: appState.recurringTodayModel.count > 0

        // ── Header strip ─────────────────────────────────────────────────
        Rectangle {
            id: recurringHeader
            Layout.fillWidth: true
            height: 36 * root.cellScale
            radius: 6
            color: recurringHdrArea.containsMouse ? "#cc1a5a8a" : "#991a4a7a"
            border.color: "#882299cc"; border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Text {
                    text: "↻"
                    color: "#88ccff"; font.pixelSize: 15 * root.cellScale; font.bold: true
                }
                Text {
                    text: recurringSection.allItems.length === 1
                        ? recurringSection.allItems[0].title
                        : "[ " + recurringSection.allItems.length + " ] RECURRING TODAY"
                    color: "#cceeff"; font.pixelSize: 13 * root.cellScale; font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                // Countdown pill for the most upcoming recurring event
                Rectangle {
                    visible: recurringSection.nextTimedIdx >= 0 && !recurringSection.expanded
                    width: 90; height: 22
                    radius: 6
                    color: "#ffffff"
                    border.color: "#1166aa"; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (recurringSection.nextTimedIdx < 0) return "";
                            var ev = appState.recurringTodayModel.get(recurringSection.nextTimedIdx);
                            return appState.eventTimeLeftString({date: ev.date, time: ev.time}, appState.now);
                        }
                        color: "#1166aa"
                        font.pixelSize: 11 * root.cellScale; font.bold: true
                    }
                }
                Text {
                    text: recurringSection.expanded ? "▾" : "▸"
                    color: "#88ccff"; font.pixelSize: 14 * root.cellScale
                }
            }

            MouseArea {
                id: recurringHdrArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: recurringSection.expanded = !recurringSection.expanded
            }
        }

        // ── Expanded body ────────────────────────────────────────────────
        Rectangle {
            visible: recurringSection.expanded
            Layout.fillWidth: true
            implicitHeight: recurringBodyCol.implicitHeight + 12
            radius: 6
            color: "#cc061428"
            border.color: "#441a4a7a"; border.width: 1
            clip: true

            ColumnLayout {
                id: recurringBodyCol
                width: parent.width
                spacing: 0
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 6; topMargin: 6 }

                // Filter pills
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                    spacing: 4

                    Repeater {
                        model: ["All", "Timed", "All-day"]
                        delegate: Rectangle {
                            height: 22
                            width:  filterLabel.implicitWidth + 16
                            radius: 11
                            color:  recurringSection.filterMode === index
                                    ? "#661a5a8a" : pillHov.containsMouse ? "#331a4a6a" : "transparent"
                            border.color: recurringSection.filterMode === index ? "#2299cc" : "#224466"
                            border.width: 1
                            Text {
                                id: filterLabel
                                anchors.centerIn: parent
                                text: modelData
                                color: recurringSection.filterMode === index ? "#cceeff" : "#6699aa"
                                font.pixelSize: 11 * root.cellScale
                            }
                            HoverHandler { id: pillHov }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: recurringSection.filterMode = index
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // Row-count picker
                    RowLayout {
                        spacing: 3
                        Text {
                            text: "rows:"
                            color: "#6699aa"
                            font.pixelSize: 11 * root.cellScale
                        }
                        Repeater {
                            model: 5
                            delegate: Rectangle {
                                width: 20; height: 20; radius: 4
                                color: recurringSection.maxRows === (index + 1)
                                       ? "#661a5a8a" : rowPickHov.containsMouse ? "#221a4a6a" : "transparent"
                                border.color: recurringSection.maxRows === (index + 1) ? "#2299cc" : "#224466"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: index + 1
                                    color: recurringSection.maxRows === (index + 1) ? "#cceeff" : "#6699aa"
                                    font.pixelSize: 11 * root.cellScale
                                }
                                HoverHandler { id: rowPickHov }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        recurringSection.maxRows = index + 1;
                                        recurringScrollView.contentItem.contentY = 0;
                                    }
                                }
                            }
                        }
                    }
                    // Add recurring event button
                    Rectangle {
                        width: 22; height: 22; radius: 11
                        color: addRecHov.containsMouse ? "#331a5a8a" : "transparent"
                        border.color: "#2299cc"; border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "+"; color: "#88ccff"
                            font.pixelSize: 15 * root.cellScale; font.bold: true
                        }
                        HoverHandler { id: addRecHov }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addRecurringEventRequested()
                        }
                    }
                }

                // Scrollable event rows
                ScrollView {
                    id: recurringScrollView
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(
                        appState.recurringTodayModel.count * (36 * root.cellScale + 3),
                        recurringSection.maxRows * (36 * root.cellScale + 3)
                    )
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 3

                        Repeater {
                            model: appState.recurringTodayModel
                            delegate: Rectangle {
                                property bool isTimed: model.time !== "" && model.time !== "All Day"
                                property bool passFilter: recurringSection.filterMode === 0
                                                       || (recurringSection.filterMode === 1 && isTimed)
                                                       || (recurringSection.filterMode === 2 && !isTimed)
                                property string evId: model.originalEventId || model.eventId || ""

                                Layout.fillWidth: true
                                visible: passFilter
                                height:  passFilter ? (36 * root.cellScale) : 0

                                radius: 4
                                color: evRowHov.hovered ? "#1a2e4a" : "#0e1e33"
                                border.color: "#1a3050"; border.width: 1
                                clip: true

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 6; topMargin: 4; bottomMargin: 4 }
                                    spacing: 6

                                    Text {
                                        text: isTimed ? model.time.substring(0, 5) : "all-day"
                                        color: "#88bbdd"; font.pixelSize: 11 * root.cellScale
                                        font.bold: true
                                        Layout.preferredWidth: 46
                                    }
                                    Text {
                                        text: model.title || ""
                                        color: "#cce8ff"; font.pixelSize: 12 * root.cellScale
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    // Countdown pill — only on the most upcoming timed row
                                    Rectangle {
                                        visible: index === recurringSection.nextTimedIdx && isTimed
                                        width: 82; height: 22
                                        radius: 6
                                        color: "#ffffff"
                                        border.color: "#1166aa"; border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: {
                                                if (!isTimed || !model.date || !model.time) return "";
                                                return appState.eventTimeLeftString({date: model.date, time: model.time}, appState.now);
                                            }
                                            color: "#1166aa"
                                            font.pixelSize: 10 * root.cellScale; font.bold: true
                                        }
                                    }
                                    Rectangle {
                                        width: 24 * root.cellScale; height: 24 * root.cellScale; radius: width / 2
                                        color: editRecHov.containsMouse ? "#224466" : "transparent"
                                        border.color: "#ffffff"; border.width: 1
                                        visible: evId !== ""
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✎"; color: "#ffffff"
                                            font.pixelSize: 13 * root.cellScale
                                        }
                                        HoverHandler { id: editRecHov }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.editEventRequested(evId)
                                        }
                                    }
                                }
                                HoverHandler { id: evRowHov }
                            }
                        }
                    }
                }

                Item { height: 4 }
            }
        }
    }

    // ── Timed upcoming list ───────────────────────────────────────────────────
    ListView {
        id: listView
        model: appState.eventModel
        Layout.fillWidth: true
        clip: true
        interactive: true
        height: 4 * (60 * root.cellScale) + 8

        delegate: Rectangle {
            width:  listView.width
            height: 60 * root.cellScale
            color:  index === 0 ? "#004400"
                  : index === 1 ? "#1e1e1e"
                  : index === 2 ? "#282828"
                  : "#333333"

            // ── Hide button ───────────────────────────────────────────────────
            Rectangle {
                id: listDeleteBtn
                width:  26 * root.cellScale
                height: 26 * root.cellScale
                anchors.verticalCenter: parent.verticalCenter
                anchors.left:       parent.left
                anchors.leftMargin: 8
                radius: height / 2
                color:  index === 0 ? "#006600" : "#000000"
                border.color: "#ffffff"; border.width: 2
                z: 2; scale: 1.0

                // White fill animation (similar to red fill on quit button)
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * (root.hideHoldingIndex === index ? root.hideHoldProgress : 0)
                    height: parent.height
                    radius: parent.radius
                    color: "#ffffff"
                    opacity: root.hideHoldingIndex === index && root.hideHoldProgress > 0 ? 0.8 : 0
                    z: 1  // Above background, below text and mouse area
                    
                    // Ensure this rectangle doesn't intercept mouse events
                    MouseArea {
                        anchors.fill: parent
                        enabled: false  // Disable mouse interaction on fill
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "−"; color: "#ffffff"
                    font.pixelSize: 18 * root.cellScale; font.bold: true
                    z: 2  // Above fill animation
                }
                
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: false  // Disable hover to reduce interference
                    cursorShape: Qt.PointingHandCursor
                    z: 3  // Highest z-order
                    preventStealing: true  // Prevent other elements from stealing mouse events
                    
                    onPressed: {
                        root.hideHoldingIndex = index;
                        root.hideHoldProgress = 0.0;
                    }
                    
                    onReleased: {
                        root.hideHoldingIndex = -1;
                        root.hideHoldProgress = 0.0;
                    }
                }
            }

            // ── Event label ───────────────────────────────────────────────────
            Text {
                property string shortDate: date && date.length >= 10 ? date.substring(5) : date
                text:  shortDate + ", " + (time && time !== "" ? time : "All Day") + " - " + title
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter
                anchors.left:       parent.left
                anchors.leftMargin: 44 * root.cellScale
                anchors.right:      index === 0 ? listCountdownBadge.left : listEditBtn.left
                anchors.rightMargin: 6
                font.pixelSize: 14 * root.cellScale
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            // ── Optional comment ──────────────────────────────────────────────
            Text {
                property string itemComment: (typeof comment !== 'undefined' && comment !== null ? comment : "")
                visible: itemComment && itemComment.trim() !== ""
                text: itemComment; color: "#999999"
                anchors.left:       parent.left
                anchors.leftMargin: 44 * root.cellScale
                anchors.top:        parent.top
                anchors.topMargin:  34 * root.cellScale
                font.pixelSize: 12 * root.cellScale; wrapMode: Text.WordWrap
            }

            // ── Edit button ───────────────────────────────────────────────────
            Button {
                id: listEditBtn
                width:  26 * root.cellScale
                height: 26 * root.cellScale
                anchors.verticalCenter: parent.verticalCenter
                anchors.right:       parent.right
                anchors.rightMargin: 8
                text: "✎"
                hoverEnabled: true
                contentItem: Text {
                    text: listEditBtn.text; anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment:   Text.AlignVCenter
                    color: "#ffffff"; font.pixelSize: 14 * root.cellScale
                }
                background: Rectangle {
                    color:  listEditBtn.hovered ? (index === 0 ? "#33aa33" : "#444444")
                                                : (index === 0 ? "#006600" : "#000000")
                    radius: width / 2
                    border.color: "#ffffff"; border.width: 1
                }
                onClicked: root.editEventRequested(eventId)
            }

            // ── Countdown badge (first event only) — sits left of edit button ─
            Rectangle {
                id: listCountdownBadge
                visible: listCountdownBadge.hasEndTime || index === 0
                property string evEndTime: (typeof endTime !== 'undefined' && endTime !== null) ? endTime : ""
                property bool hasEndTime: evEndTime !== "" && time && time !== "" && time !== "All Day"
                width:  hasEndTime ? 190 : 90
                height: 26 * root.cellScale
                radius: 6
                color: "transparent"
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: listEditBtn.left
                anchors.rightMargin: 6

                // Ends at pill
                Rectangle {
                    visible: listCountdownBadge.hasEndTime
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    width: 100
                    height: parent.height * 0.8
                    radius: 6
                    color: "#a8dba8"
                    border.color: "#44cc44"; border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Ends at: " + listCountdownBadge.evEndTime.substring(0, 5)
                        color: "#005500"
                        font.pixelSize: 10 * root.cellScale; font.bold: true
                    }
                }

                // Countdown pill
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    width: 90
                    height: parent.height * 0.8
                    radius: 6
                    color: "#ffffff"
                    border.color: "#44cc44"; border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: {
                            var et = listCountdownBadge.evEndTime;
                            if (et !== "" && time && time !== "" && time !== "All Day") {
                                var nowMs = appState.now.getTime();
                                var dateParts = date ? date.split("-") : [];
                                if (dateParts.length === 3) {
                                    var tp = time.split(":");
                                    var startMs = new Date(
                                        parseInt(dateParts[0],10), parseInt(dateParts[1],10)-1, parseInt(dateParts[2],10),
                                        parseInt(tp[0]||"0",10), parseInt(tp[1]||"0",10), parseInt(tp[2]||"0",10)
                                    ).getTime();
                                    var ep = et.split(":");
                                    var endMs = new Date(
                                        parseInt(dateParts[0],10), parseInt(dateParts[1],10)-1, parseInt(dateParts[2],10),
                                        parseInt(ep[0]||"0",10), parseInt(ep[1]||"0",10), parseInt(ep[2]||"0",10)
                                    ).getTime();
                                    if (nowMs < startMs) {
                                        return "UPCOMING";
                                    }
                                    if (nowMs >= startMs && endMs > nowMs) {
                                        return appState.eventTimeLeftString({date: date, time: et}, appState.now);
                                    }
                                }
                            }
                            return appState.eventTimeLeftString({date: date, time: time}, appState.now);
                        }
                        color: "#005500"
                        font.pixelSize: 12 * root.cellScale; font.bold: true
                    }
                }
            }
        }
    }
}
