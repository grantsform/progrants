// AllEventsPopup.qml — full chronological list of every event in events.json,
// past, present and future.  Opened by the hamburger button.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../chrome"

Item {
    id: root

    required property QtObject appState

    signal closeRequested()
    signal editEventRequested(string eventId)

    // ── Pending-delete state (for confirm dialog) ─────────────────────────────
    property string _pendingId:      ""
    property string _pendingTitle:   ""
    property string _pendingDate:    ""
    property string _pendingTime:    ""
    property string _pendingComment: ""

    // ── Collapsed state for all-day date groups ───────────────────────────────
    property var _collapsed: ({})   // date string → true/false
    
    // ── Tab state ──────────────────────────────────────────────────────────────
    property int currentTab: 0  // 0 = Regular, 1 = Recur

    z: 9998

    onVisibleChanged: { if (visible) root._rebuild(); }

    // ── Sorted snapshot model ─────────────────────────────────────────────────
    ListModel { id: sortedModel }

    Connections {
        target: root.appState
        function onEventsRevisionChanged() { root._rebuild(); }
    }

    function _toggleCollapse(date) {
        var c = root._collapsed;
        c[date] = !c[date];
        root._collapsed = c;
        root._rebuild();
    }

    function _rebuild() {
        sortedModel.clear();
        var now = new Date();
        var todayStr = now.getFullYear() + "-"
            + String(now.getMonth() + 1).padStart(2, "0") + "-"
            + String(now.getDate()).padStart(2, "0");

        var evs = root.appState.events.slice();
        
        // Filter events based on current tab
        if (root.currentTab === 0) {
            // Regular tab: show non-recurring events
            evs = evs.filter(function(e) { return !e.recurring; });
        } else {
            // Recur tab: show only recurring events
            evs = evs.filter(function(e) { return e.recurring; });
        }
        
        evs.sort(function(a, b) { return root._ts(a) - root._ts(b); });

        // Separate all-day and timed
        var allDayEvs  = evs.filter(function(e) { return e.allDay || !e.time || e.time === "" || e.time === "All Day"; });
        var timedEvs   = evs.filter(function(e) { return !(e.allDay || !e.time || e.time === "" || e.time === "All Day"); });

        // Group all-day by date
        var allDayByDate = {};  // date → [ev, ...]
        var allDayDates  = [];
        for (var a = 0; a < allDayEvs.length; a++) {
            var ae = allDayEvs[a];
            var d = ae.date || "";
            if (!allDayByDate[d]) { allDayByDate[d] = []; allDayDates.push(d); }
            allDayByDate[d].push(ae);
        }
        allDayDates.sort();

        // Build merged list: interleave all-day headers at the right date position
        var firstFuture = true;
        var allDayDateIdx = 0;
        var timedIdx = 0;

        // We'll iterate by date order, emitting all-day headers then timed rows
        var allDates = [];
        for (var i = 0; i < allDayDates.length; i++) allDates.push({ date: allDayDates[i], kind: "allday" });
        for (var j = 0; j < timedEvs.length; j++)    allDates.push({ date: timedEvs[j].date || "", kind: "timed", ev: timedEvs[j] });
        allDates.sort(function(a, b) { 
            // First sort by date
            if (a.date < b.date) return -1;
            if (a.date > b.date) return 1;
            
            // Same date: all-day events come first
            if (a.kind === "allday" && b.kind === "timed") return -1;
            if (a.kind === "timed" && b.kind === "allday") return 1;
            
            // Both are timed events on the same date: sort by time
            if (a.kind === "timed" && b.kind === "timed") {
                return root._ts(a.ev) - root._ts(b.ev);
            }
            
            return 0;
        });

        // Deduplicate allday date headers and emit rows
        var emittedDates = {};
        for (var k = 0; k < allDates.length; k++) {
            var item = allDates[k];
            if (item.kind === "allday") {
                if (emittedDates[item.date]) continue;
                emittedDates[item.date] = true;
                var group = allDayByDate[item.date] || [];
                
                // For recurring events in Recur tab, create single thick rows
                if (root.currentTab === 1) {
                    for (var r = 0; r < group.length; r++) {
                        var re = group[r];
                        if (re.recurring) {
                            var recurDays = [];
                            if (re.recurSun) recurDays.push("Sun");
                            if (re.recurMon) recurDays.push("Mon");
                            if (re.recurTue) recurDays.push("Tue");
                            if (re.recurWed) recurDays.push("Wed");
                            if (re.recurThu) recurDays.push("Thu");
                            if (re.recurFri) recurDays.push("Fri");
                            if (re.recurSat) recurDays.push("Sat");
                            
                            var interval = re.recurWeekInterval || 1;
                            var startDate = re.date ? re.date.substring(5) : "";
                            var recurInfo = "Every " + (interval > 1 ? interval + " weeks on " : "") + 
                                          recurDays.join(", ");
                            if (re.recurEndDate) {
                                recurInfo += " until " + re.recurEndDate;
                            }
                            
                            var combinedComment = recurInfo + (re.comment ? " | " + re.comment : "");
                            
                            sortedModel.append({
                                rowKind:     "recurring",  // New row kind for thick recurring events
                                evDate:      startDate,
                                evTitle:     re.title || "",
                                evTime:      "All Day",
                                evComment:   combinedComment,
                                evId:        re.eventId || "",
                                evEndTime:   "",
                                evPast:      root._ts(re) < now.getTime(),
                                evToday:     (re.date || "") === todayStr,
                                evActive:    false,
                                evHidden:    !!re.hidden,
                                evAllDay:    true,
                                evCollapsed: false
                            });
                        }
                    }
                } else {
                    // Regular display for non-recurring events (header + individual rows)
                    var collapsed = !!root._collapsed[item.date];
                    sortedModel.append({
                        rowKind:     "header",
                        evDate:      item.date,
                        evTitle:     group.length + " all-day event" + (group.length !== 1 ? "s" : ""),
                        evTime:      "",
                        evComment:   "",
                        evId:        "",
                        evEndTime:   "",
                        evPast:      root._ts({ date: item.date, allDay: true }) < now.getTime(),
                        evToday:     item.date === todayStr,
                        evActive:    false,
                        evHidden:    false,
                        evAllDay:    true,
                        evCollapsed: collapsed
                    });
                    // Individual all-day rows (hidden when collapsed)
                    if (!collapsed) {
                        for (var m = 0; m < group.length; m++) {
                            var ge = group[m];
                            sortedModel.append({
                                rowKind:     "allday",
                                evDate:      ge.date    || "",
                                evTitle:     ge.title   || "",
                                evTime:      "All Day",
                                evComment:   ge.comment || "",
                                evId:        ge.eventId || "",
                                evEndTime:   "",
                                evPast:      root._ts(ge) < now.getTime(),
                                evToday:     (ge.date || "") === todayStr,
                                evActive:    false,
                                evHidden:    !!ge.hidden,
                                evAllDay:    true,
                                evCollapsed: false
                            });
                        }
                    }
                }
            } else {
                var ev = item.ev;
                var past = root._ts(ev) < now.getTime();
                var active = !past && !ev.hidden && firstFuture;
                if (active) firstFuture = false;
                
                // For recurring timed events in Recur tab, create thick rows
                if (root.currentTab === 1 && ev.recurring) {
                    var recurDays = [];
                    if (ev.recurSun) recurDays.push("Sun");
                    if (ev.recurMon) recurDays.push("Mon");
                    if (ev.recurTue) recurDays.push("Tue");
                    if (ev.recurWed) recurDays.push("Wed");
                    if (ev.recurThu) recurDays.push("Thu");
                    if (ev.recurFri) recurDays.push("Fri");
                    if (ev.recurSat) recurDays.push("Sat");
                    
                    var interval = ev.recurWeekInterval || 1;
                    var startDate = ev.date ? ev.date.substring(5) : "";
                    var recurInfo = "Every " + (interval > 1 ? interval + " weeks on " : "") + 
                                  recurDays.join(", ");
                    if (ev.recurEndDate) {
                        recurInfo += " until " + ev.recurEndDate;
                    }
                    
                    var combinedComment = recurInfo + (ev.comment ? " | " + ev.comment : "");
                    
                    sortedModel.append({
                        rowKind:     "recurring",
                        evDate:      startDate,
                        evTime:      ev.time    || "",
                        evTitle:     ev.title   || "",
                        evComment:   combinedComment,
                        evId:        ev.eventId || "",
                        evEndTime:   "",
                        evPast:      past,
                        evToday:     false,
                        evActive:    active,
                        evHidden:    !!ev.hidden,
                        evAllDay:    false,
                        evCollapsed: false
                    });
                } else {
                    // Regular timed events
                    sortedModel.append({
                        rowKind:     "timed",
                        evDate:      ev.date    || "",
                        evTime:      ev.time    || "",
                        evTitle:     ev.title   || "",
                        evComment:   ev.comment || "",
                        evId:        ev.eventId || "",
                        evEndTime:   ev.endTime || "",
                        evPast:      past,
                        evToday:     false,
                        evActive:    active,
                        evHidden:    !!ev.hidden,
                        evAllDay:    false,
                        evCollapsed: false
                    });
                }
        }
    }
            }

    function _ts(ev) {
        var p = (ev.date || "").split("-");
        if (p.length !== 3) return 0;
        var y = parseInt(p[0], 10), m = parseInt(p[1], 10) - 1, d = parseInt(p[2], 10);
        if (ev.allDay || !ev.time || ev.time === "" || ev.time === "All Day")
            return new Date(y, m, d, 23, 59, 59).getTime();
        var t = (ev.time || "00:00:00").split(":");
        return new Date(y, m, d,
            parseInt(t[0]||"0",10), parseInt(t[1]||"0",10), parseInt(t[2]||"0",10)).getTime();
    }

    // ── Confirm-delete dialog ─────────────────────────────────────────────────
    ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        visible: false
        z: 9999

        title:       "Delete Event"
        message:     "Are you sure you want to permanently delete this event?"
        detail:      [
            root._pendingDate + (root._pendingTime !== "All Day" ? "  " + root._pendingTime : ""),
            root._pendingTitle,
            root._pendingComment
        ].filter(function(s){ return s !== ""; }).join("\n")

        acceptLabel: "Delete"
        rejectLabel: "Cancel"

        onAccepted: {
            root.appState.removeEventByEventId(root._pendingId);
            root._rebuild();
            confirmDialog.visible = false;
        }
        onRejected: {
            confirmDialog.visible = false;
        }
    }

    // ── Background card ───────────────────────────────────────────────────────
    Rectangle {
        width:  Math.min(root.width  * 0.80, 900)
        height: Math.min(root.height * 0.85, 700)
        anchors.centerIn: parent
        color:  "#dd000000"
        radius: 14
        border.color: "#66ffffff"; border.width: 1

        ColumnLayout {
            anchors.fill:    parent
            anchors.margins: 14
            spacing: 10

            // ── Title row ─────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "All Events  (" + sortedModel.count + ")"
                    color: "#ffffff"; font.pixelSize: 22; font.bold: true
                    Layout.fillWidth: true
                }
                Button {
                    text: "✕"
                    width: 32; height: 32
                    contentItem: Text {
                        text: parent.text; anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                        color: "#ffffff"; font.pixelSize: 16
                    }
                    background: Rectangle {
                        color:  parent.hovered ? "#ff4444" : "#333333"
                        radius: width / 2
                        border.color: "#ffffff"; border.width: 1
                    }
                    onClicked: root.closeRequested()
                }
            }
            
            // ── Tab bar ───────────────────────────────────────────────────────
            TabBar {
                id: tabBar
                Layout.fillWidth: true
                currentIndex: root.currentTab
                onCurrentIndexChanged: {
                    root.currentTab = currentIndex;
                    root._rebuild();
                }
                
                TabButton {
                    text: "Regular"
                    width: implicitWidth
                }
                TabButton {
                    text: "Recur"
                    width: implicitWidth
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#44ffffff" }

            // ── Scrollable list ───────────────────────────────────────────────
            ListView {
                id: listView
                Layout.fillWidth:  true
                Layout.fillHeight: true
                model:       sortedModel
                clip:        true
                spacing:     2

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Item {
                    width:  listView.width
                    height: row.height

                    // ── All-day date group header ──────────────────────────────
                    Rectangle {
                        id: row
                        width:  parent.width
                        height: rowKind === "header"    ? 34
                              : rowKind === "allday"    ? 52
                              : rowKind === "recurring" ? 80
                              : 54
                        radius: 4

                        // Colors
                        color: rowKind === "header" ? (evPast && !evToday ? "#0d0d0d" : evPast ? "#0f0a1a" 
                                                     : root.currentTab === 1 ? "#0d1a2b" : "#1a0d2b")
                             : rowKind === "allday"  ? (evPast && !evToday ? "#0d0d0d"
                                                      : evHidden            ? "#130a15"
                                                      : evPast              ? "#0f0a1a"
                                                      : root.currentTab === 1 ? "#0d1a2b" : "#1a0d2b")
                             : rowKind === "recurring" ? (evPast && !evToday ? "#0d0d0d"
                                                        : evHidden            ? "#130a15" 
                                                        : evPast              ? "#0f1a2a"
                                                        : evActive            ? "#004488"
                                                        :                       "#0d1a2b")
                             : evHidden  ? "#111111"
                             : evPast    ? "#0d0d0d"
                             : evActive  ? (root.currentTab === 1 ? "#004488" : "#004400")
                             : root.currentTab === 1 ? "#1e2e3e" : "#1e1e1e"

                        border.color: rowKind === "header" ? (evPast && !evToday ? "#222222" : evPast ? "#442255" 
                                                         : root.currentTab === 1 ? "#3366aa" : "#6633aa")
                                    : rowKind === "allday"  ? (evPast && !evToday ? "#222222" : evPast ? "#331a44" 
                                                             : root.currentTab === 1 ? "#2255aa" : "#5522aa")
                                    : rowKind === "recurring" ? (evPast && !evToday ? "#222222" : evPast ? "#331a44"
                                                               : evActive ? "#44aacc" : "#2255aa")
                                    : evHidden ? "#2a2a2a"
                                    : evPast   ? "#222222"
                                    : evActive ? (root.currentTab === 1 ? "#44aacc" : "#44cc44") 
                                    : root.currentTab === 1 ? "#5588aa" : "#555555"
                        border.width: 1
                        opacity: (rowKind !== "header" && evHidden) ? 0.55 : 1.0

                        // ── Header row (all-day group) ─────────────────────────
                        RowLayout {
                            visible: rowKind === "header"
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6

                            Text {
                                text: evCollapsed ? "▸" : "▾"
                                color: (evPast && !evToday) ? "#555555" : root.currentTab === 1 ? "#55aaee" : "#aa55ee"; font.pixelSize: 13
                            }
                            Text {
                                text: evDate.length >= 10 ? evDate.substring(5) : evDate
                                color: (evPast && !evToday) ? "#666666" : evPast ? (root.currentTab === 1 ? "#447799" : "#774499") 
                                     : root.currentTab === 1 ? "#88ccff" : "#cc88ff"
                                font.pixelSize: 13; font.bold: true
                                Layout.preferredWidth: 56
                            }
                            Text {
                                text: "✅  " + evTitle
                                color: (evPast && !evToday) ? "#666666" : evPast ? (root.currentTab === 1 ? "#447799" : "#774499") 
                                     : root.currentTab === 1 ? "#99ddff" : "#dd99ff"
                                font.pixelSize: 13; font.bold: true
                                Layout.fillWidth: true
                            }
                            MouseArea {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._toggleCollapse(evDate)
                            }
                        }

                        // ── All-day individual row ─────────────────────────────
                        RowLayout {
                            visible: rowKind === "allday"
                            anchors.fill: parent
                            anchors.leftMargin: 20   // indent under header
                            anchors.rightMargin: 6
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            spacing: 8

                            Text {
                                text: "↳"
                                color: (evPast && !evToday) ? "#444444" : "#7733aa"; font.pixelSize: 12
                            }
                            Text {
                                text: evTitle + (evHidden ? "  🛉" : "")
                                color: (evPast && !evToday) ? "#666666" : evHidden ? (root.currentTab === 1 ? "#3377aa" : "#7733aa") 
                                     : evPast ? (root.currentTab === 1 ? "#447799" : "#774499") 
                                     : root.currentTab === 1 ? "#99ddff" : "#dd99ff"
                                font.pixelSize: 13; font.bold: !evPast && !evHidden
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text:  evComment
                                color: (evPast && !evToday) ? "#444444" : evHidden ? (root.currentTab === 1 ? "#225588" : "#442255") 
                                     : evPast ? (root.currentTab === 1 ? "#336677" : "#553377") 
                                     : root.currentTab === 1 ? "#77aacc" : "#aa77cc"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                Layout.preferredWidth: 120
                            }
                            // Restore button
                            Button {
                                visible: evHidden
                                width: 24; height: 24
                                contentItem: Text {
                                    text: "+"; anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment:   Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 14; font.bold: true
                                }
                                background: Rectangle {
                                    color: parent.hovered ? "#227722" : "#114411"
                                    radius: width / 2
                                    border.color: "#aa44dd"; border.width: 1
                                }
                                onClicked: { root.appState.unhideEventById(evId); root._rebuild(); }
                            }
                            // Edit button
                            Button {
                                visible: !evHidden
                                width: 24; height: 24
                                contentItem: Text {
                                    text: "✎"; anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 12; font.bold: true
                                }
                                background: Rectangle {
                                    color: parent.hovered ? (evPast ? "#2d2d2d" : "#6633aa") : (evPast ? "#0d0d0d" : "#442266")
                                    radius: width / 2
                                    border.color: evPast ? "#333333" : "#aa77cc"; border.width: 1
                                }
                                onClicked: {
                                    root.editEventRequested(evId);
                                }
                            }
                            // Delete button
                            Button {
                                visible: !evHidden
                                width: 24; height: 24
                                contentItem: Text {
                                    text: "×"; anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment:   Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 14; font.bold: true
                                }
                                background: Rectangle {
                                    color: parent.hovered ? "#ff4444" : "#000000"
                                    radius: width / 2
                                    border.color: evPast ? "#ffffff" : "#aa44dd"; border.width: 1
                                }
                                onClicked: {
                                    root._pendingId      = evId;
                                    root._pendingTitle   = evTitle;
                                    root._pendingDate    = evDate;
                                    root._pendingTime    = evTime;
                                    root._pendingComment = evComment;
                                    confirmDialog.visible = true;
                                }
                            }
                        }

                        // ── Timed event row ────────────────────────────────────
                        RowLayout {
                            visible: rowKind === "timed"
                            anchors.fill:    parent
                            anchors.margins: 6
                            spacing: 8

                            Text {
                                text:  evDate.length >= 10 ? evDate.substring(5) : evDate
                                color: (evPast || evHidden) ? "#888888" : "#dddddd"
                                font.pixelSize: 13
                                Layout.preferredWidth: 80
                            }
                            Text {
                                text:  evTime
                                color: (evPast || evHidden) ? "#666666" : "#aaaaaa"
                                font.pixelSize: 12
                                Layout.preferredWidth: 72
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text:  evTitle + (evHidden ? "  🛉" : "")
                                    color: (evPast || evHidden) ? "#888888" : "#ffffff"
                                    font.pixelSize: 13; font.bold: !evPast && !evHidden
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    visible: evComment !== ""
                                    text:  evComment
                                    color: (evPast || evHidden) ? "#555555" : "#888888"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            // Restore button
                            Button {
                                visible: evHidden
                                width: 24; height: 24
                                contentItem: Text {
                                    text: "+"; anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment:   Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 14; font.bold: true
                                }
                                background: Rectangle {
                                    color:  parent.hovered ? "#227722" : "#114411"
                                    radius: width / 2
                                    border.color: "#44aa44"; border.width: 1
                                }
                                onClicked: { root.appState.unhideEventById(evId); root._rebuild(); }
                            }
                            // Till label
                            Text {
                                visible: !evHidden && (typeof evEndTime !== 'undefined') && evEndTime !== ""
                                text: "Till: " + (evEndTime ? evEndTime.substring(0, 5) : "")
                                color: (evPast || evHidden) ? "#557755" : "#66cc66"
                                font.pixelSize: 11
                            }
                            // Edit button
                            Button {
                                visible: !evHidden
                                width: 24; height: 24
                                contentItem: Text {
                                    text: "✎"; anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 12; font.bold: true
                                }
                                background: Rectangle {
                                    color: parent.hovered ? (evHidden ? "#333333" : evPast ? "#2d2d2d" : "#3d3d3d") 
                                                         : (evHidden ? "#111111" : evPast ? "#0d0d0d" : "#1e1e1e")
                                    radius: width / 2
                                    border.color: evHidden ? "#444444" : evPast ? "#333333" : "#555555"; border.width: 1
                                }
                                onClicked: {
                                    root.editEventRequested(evId);
                                }
                            }
                            // Delete button
                            Button {
                                visible: !evHidden
                                width: 24; height: 24
                                contentItem: Text {
                                    text: "×"; anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment:   Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 14; font.bold: true
                                }
                                background: Rectangle {
                                    color:  parent.hovered ? "#ff4444" : "#000000"
                                    radius: width / 2
                                    border.color: evPast ? "#ffffff" : "#ffffff"; border.width: 1
                                }
                                onClicked: {
                                    root._pendingId      = evId;
                                    root._pendingTitle   = evTitle;
                                    root._pendingDate    = evDate;
                                    root._pendingTime    = evTime;
                                    root._pendingComment = evComment;
                                    confirmDialog.visible = true;
                                }
                            }
                        }

                        // ── Thick recurring event row ──────────────────────────
                        ColumnLayout {
                            visible: rowKind === "recurring"
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            // Top row: Date, Time, Title
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: evDate
                                    color: (evPast && !evToday) ? "#666666" : "#88ccff"
                                    font.pixelSize: 14; font.bold: true
                                    Layout.preferredWidth: 60
                                }
                                Text {
                                    text: evTime
                                    color: (evPast && !evToday) ? "#555555" : "#77aacc"
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 80
                                }
                                Text {
                                    text: evTitle + (evHidden ? "  🛉" : "")
                                    color: (evPast && !evToday) ? "#666666" : evHidden ? "#3377aa"
                                         : evPast ? "#447799" : "#99ddff"
                                    font.pixelSize: 16; font.bold: !evPast && !evHidden
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            // Bottom row: Recurrence info and buttons
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: evComment
                                    color: (evPast && !evToday) ? "#444444" : evHidden ? "#225588"
                                         : evPast ? "#336677" : "#77aacc"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                // Edit button
                                Button {
                                    visible: !evHidden
                                    width: 24; height: 24
                                    contentItem: Text {
                                        text: "✎"; anchors.fill: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        color: "#ffffff"; font.pixelSize: 12; font.bold: true
                                    }
                                    background: Rectangle {
                                        color: parent.hovered ? (evPast ? "#4488aa" : "#3366aa") : (evPast ? "#225588" : "#225588")
                                        radius: width / 2
                                        border.color: evPast ? "#447799" : "#77aacc"; border.width: 1
                                    }
                                    onClicked: {
                                        // Open edit popup for recurring event
                                        root.editEventRequested(evId);
                                    }
                                }

                                // Delete button
                                Button {
                                    visible: !evHidden
                                    width: 24; height: 24
                                    contentItem: Text {
                                        text: "×"; anchors.fill: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        color: "#ffffff"; font.pixelSize: 14; font.bold: true
                                    }
                                    background: Rectangle {
                                        color: parent.hovered ? (evPast ? "#4488aa" : "#3366aa") : (evPast ? "#225588" : "#225588")
                                        radius: width / 2
                                        border.color: evPast ? "#447799" : "#77aacc"; border.width: 1
                                    }
                                    onClicked: {
                                        root._pendingId = evId;
                                        root._pendingTitle = evTitle;
                                        root._pendingDate = evDate;
                                        root._pendingTime = evTime;
                                        root._pendingComment = evComment;
                                        confirmDialog.visible = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
