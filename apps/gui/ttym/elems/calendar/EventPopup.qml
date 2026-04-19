// EventPopup.qml — add or edit a calendar event.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../chrome"

Popup {
    id: root

    // ── Required context ──────────────────────────────────────────────────────
    required property QtObject appState

    // ── Pending (uncommitted) edits ───────────────────────────────────────────
    property int    pendingDay:     appState.day
    property int    pendingMonth:   appState.month + 1
    property int    pendingYear:    appState.year
    property string pendingTitle:   ""
    property string pendingComment: ""
    property int    pendingHour:    appState.now.getHours()
    property int    pendingMinute:  (appState.now.getMinutes() + 10) % 60
    property int    pendingSecond:  0
    property bool   pendingAllDay:  false
    property string pendingEventId: ""   // empty → add mode; non-empty → edit mode
    property bool   pendingHasEndTime:  false
    property int    pendingEndHour:     (appState.now.getHours() + 1) % 24
    property int    pendingEndMinute:   0
    property int    pendingEndSecond:   0
    property bool   pendingAlert:   false
    property bool   pendingAlertSilent:         false
    property string pendingAlertSound:          ""
    property bool   pendingAlertAutoTimeout:    true
    property real   pendingAlertTimeoutMinutes: 5
    
    // Recurring event properties
    property bool   pendingRecurring: false
    property int    pendingRecurringWeeks: 1
    property var    pendingRecurringDays: []
    property string pendingRecurringEndDate: ""
    
    function loadEventForEditing(event) {
        pendingEventId = event.eventId || "";
        pendingTitle = event.title || "";
        pendingComment = event.comment || "";
        pendingAlert = !!event.alert;
        pendingAlertSilent         = !!event.alertSilent;
        pendingAlertSound          = event.alertSound || "";
        pendingAlertAutoTimeout    = (event.alertAutoTimeout    !== undefined) ? !!event.alertAutoTimeout    : true;
        pendingAlertTimeoutMinutes = (event.alertTimeoutMinutes !== undefined) ? parseFloat(event.alertTimeoutMinutes) : 5;
        pendingRecurring = !!event.recurring;
        pendingRecurringWeeks = event.recurringWeeks || 1;
        pendingRecurringDays = event.recurringDays || [];
        pendingRecurringEndDate = event.recurringEndDate || "";
        
        // Parse date
        if (event.date) {
            var parts = event.date.split("-");
            if (parts.length === 3) {
                pendingYear = parseInt(parts[0], 10);
                pendingMonth = parseInt(parts[1], 10);
                pendingDay = parseInt(parts[2], 10);
            }
        }
        
        // Parse time
        pendingAllDay = !!event.allDay;
        if (!pendingAllDay && event.time && event.time !== "All Day") {
            var timeParts = event.time.split(":");
            if (timeParts.length >= 2) {
                pendingHour = parseInt(timeParts[0] || "0", 10);
                pendingMinute = parseInt(timeParts[1] || "0", 10);
                pendingSecond = parseInt(timeParts[2] || "0", 10);
            }
        }
        // End time
        if (event.endTime && event.endTime !== "") {
            pendingHasEndTime = true;
            var ep = event.endTime.split(":");
            pendingEndHour   = parseInt(ep[0] || "0", 10);
            pendingEndMinute = parseInt(ep[1] || "0", 10);
            pendingEndSecond = parseInt(ep[2] || "0", 10);
        } else {
            pendingHasEndTime = false;
            pendingEndHour   = (pendingHour + 1) % 24;
            pendingEndMinute = 0;
            pendingEndSecond = 0;
        }
        Qt.callLater(syncEndTimeBoxes);
    }

    // Imperatively sync end-time ComboBox indices from pending* values.
    // Must be called after any bulk update to pendingEnd* or after open.
    function syncEndTimeBoxes() {
        endHourBox.currentIndex   = root.pendingEndHour;
        endMinuteBox.currentIndex = root.pendingEndMinute;
        endSecondBox.currentIndex = root.pendingEndSecond;
    }

    // ── Popup behaviour ───────────────────────────────────────────────────────
    signal deleteEventRequested(string eventId)

    property bool _confirmDeleteVisible: false

    modal: true
    closePolicy: Popup.NoAutoClose
    x: 0; y: 0   // positioned by parent

    Keys.onEscapePressed: root.close()

    onOpened: {
        if (!root.pendingEventId) {
            var now = new Date();
            // Detect a plain new-event open: caller passed all zeros (no pre-population)
            var plainNew = !pendingYear && !pendingMonth && !pendingDay;
            if (plainNew) {
                pendingAllDay = false;
                pendingAlert  = false;
                pendingRecurringWeeks = 1;
                pendingRecurringDays = [];
                pendingRecurringEndDate = "";
            }
            if (!pendingYear)  pendingYear    = now.getFullYear();
            if (!pendingMonth) pendingMonth   = now.getMonth() + 1;
            if (!pendingDay)   pendingDay     = now.getDate();
            if (!pendingHour && !pendingMinute) {
                var nowPlus10 = new Date(appState.now.getTime() + 10 * 60 * 1000); // Add 10 minutes
                pendingHour   = nowPlus10.getHours();
                pendingMinute = nowPlus10.getMinutes();
                pendingSecond = 0;  // Zero out seconds
            }
            pendingTitle   = "";
            pendingComment = "";
            eventTitleInput.text   = "";
            eventCommentInput.text = "";
        } else {
            eventTitleInput.text   = pendingTitle;
            eventCommentInput.text = pendingComment;
        }
        syncEndTimeBoxes();
        eventTitleInput.forceActiveFocus();
        root.forceActiveFocus();
    }

    // ── Content ───────────────────────────────────────────────────────────────
    Rectangle {
        width: 420; height: 580
        anchors.centerIn: parent
        color: "#000000"; radius: 10
        border.color: "#ffffff"; border.width: 1

        // Swallow clicks on empty space so the popup stays open
        MouseArea {
            anchors.fill: parent
            onClicked: {} // absorb
        }

        ColumnLayout {
            anchors.fill:    parent
            anchors.margins: 6
            spacing: 8

            Text {
                text:  root.pendingEventId ? "Edit Event" : "Add Event"
                color: "#ffffff"; font.pixelSize: 18; font.bold: true
            }

            // Date row
            Text { text: "Set Date"; color: "#cccccc"; font.pixelSize: 12 }
            RowLayout {
                spacing: 6; Layout.alignment: Qt.AlignVCenter
                ComboBox {
                    id: eventMonthBox
                    implicitWidth: 60
                    model: ["01","02","03","04","05","06","07","08","09","10","11","12"]
                    currentIndex: root.pendingMonth - 1
                    onCurrentIndexChanged: root.pendingMonth = currentIndex + 1
                }
                ComboBox {
                    id: eventDayBox
                    implicitWidth: 60
                    model: Array.from({length: appState.viewMonthDaysCount}, function(_, i) {
                        return (i + 1).toString().padStart(2, '0');
                    })
                    currentIndex: root.pendingDay - 1
                    onCurrentIndexChanged: root.pendingDay = currentIndex + 1
                }
                ComboBox {
                    id: eventYearBox
                    implicitWidth: 78
                    model: ["2025","2026","2027","2028","2029"]
                    currentIndex: model.indexOf(root.pendingYear.toString())
                    onCurrentIndexChanged: root.pendingYear = parseInt(model[currentIndex], 10)
                }
            }

            // Time row
            Text { text: "Set Time"; color: "#cccccc"; font.pixelSize: 12 }
            RowLayout {
                spacing: 6; Layout.alignment: Qt.AlignVCenter

                ComboBox {
                    id: eventHourBox
                    implicitWidth: 60
                    model: Array.from({length: 24}, function(_, i) { return i.toString().padStart(2, '0'); })
                    currentIndex: root.pendingHour
                    onCurrentIndexChanged: {
                        root.pendingHour = parseInt(model[currentIndex], 10);
                    }
                    enabled: !root.pendingAllDay
                    opacity: root.pendingAllDay ? 0.4 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }
                Text { text: ":"; color: "#ffffff" }
                ComboBox {
                    id: eventMinuteBox
                    implicitWidth: 60
                    model: Array.from({length: 60}, function(_, i) { return i.toString().padStart(2, '0'); })
                    currentIndex: root.pendingMinute
                    onCurrentIndexChanged: root.pendingMinute = parseInt(model[currentIndex], 10)
                    enabled: !root.pendingAllDay
                    opacity: root.pendingAllDay ? 0.4 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }
                Text { text: ":"; color: "#ffffff" }
                ComboBox {
                    id: eventSecondBox
                    implicitWidth: 60
                    model: Array.from({length: 60}, function(_, i) { return i.toString().padStart(2, '0'); })
                    currentIndex: root.pendingSecond
                    onCurrentIndexChanged: root.pendingSecond = parseInt(model[currentIndex], 10)
                    enabled: !root.pendingAllDay
                    opacity: root.pendingAllDay ? 0.4 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }
                CheckBox {
                    id: eventAllDayCheck
                    text: "All Day"
                    checked: root.pendingAllDay
                    onCheckedChanged: {
                        root.pendingAllDay = checked;
                        if (checked) root.pendingAlert = false;
                    }
                }
            }

            // End time row
            RowLayout {
                spacing: 6
                visible: !root.pendingAllDay
                opacity: root.pendingAllDay ? 0.0 : 1.0
                Behavior on opacity { NumberAnimation { duration: 180 } }

                CheckBox {
                    id: endTimeCheck
                    checked: root.pendingHasEndTime
                    onCheckedChanged: {
                        root.pendingHasEndTime = checked;
                        if (checked) {
                            var defH = Math.min(root.pendingHour + 1, 23);
                            root.pendingEndHour   = defH;
                            root.pendingEndMinute = (defH === root.pendingHour) ? root.pendingMinute : 0;
                            root.pendingEndSecond = 0;
                            root.syncEndTimeBoxes();
                        }
                    }
                }
                Text { text: "End:"; color: "#cccccc"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
                ComboBox {
                    id: endHourBox
                    implicitWidth: 60
                    model: Array.from({length: 24}, function(_, i) { return i.toString().padStart(2, '0'); })
                    // No declarative currentIndex binding — managed imperatively via syncEndTimeBoxes()
                    enabled: root.pendingHasEndTime && !root.pendingAllDay
                    opacity: root.pendingHasEndTime ? 1.0 : 0.4
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    onCurrentIndexChanged: {
                        // Only write back if this came from user interaction (index differs from pending)
                        if (currentIndex !== root.pendingEndHour)
                            root.pendingEndHour = currentIndex;
                    }
                    onActivated: function(idx) {
                        var h = idx;
                        if (h < root.pendingHour) { h = root.pendingHour; currentIndex = h; }
                        root.pendingEndHour = h;
                        // Clamp minute when hour dropped to start hour
                        var mn = endMinuteBox.currentIndex;
                        if (h === root.pendingHour && mn < root.pendingMinute) {
                            mn = root.pendingMinute;
                            endMinuteBox.currentIndex = mn;
                        }
                        root.pendingEndMinute = mn;
                        var s = endSecondBox.currentIndex;
                        if (h === root.pendingHour && mn === root.pendingMinute && s < root.pendingSecond) {
                            s = root.pendingSecond;
                            endSecondBox.currentIndex = s;
                        }
                        root.pendingEndSecond = s;
                    }
                }
                Text { text: ":"; color: "#ffffff" }
                ComboBox {
                    id: endMinuteBox
                    implicitWidth: 60
                    model: Array.from({length: 60}, function(_, i) { return i.toString().padStart(2, '0'); })
                    enabled: root.pendingHasEndTime && !root.pendingAllDay
                    opacity: root.pendingHasEndTime ? 1.0 : 0.4
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    onCurrentIndexChanged: {
                        if (currentIndex !== root.pendingEndMinute)
                            root.pendingEndMinute = currentIndex;
                    }
                    onActivated: function(idx) {
                        var mn = idx;
                        if (root.pendingEndHour === root.pendingHour && mn < root.pendingMinute) {
                            mn = root.pendingMinute; currentIndex = mn;
                        }
                        root.pendingEndMinute = mn;
                        var s = endSecondBox.currentIndex;
                        if (root.pendingEndHour === root.pendingHour && mn === root.pendingMinute && s < root.pendingSecond) {
                            s = root.pendingSecond;
                            endSecondBox.currentIndex = s;
                        }
                        root.pendingEndSecond = s;
                    }
                }
                Text { text: ":"; color: "#ffffff" }
                ComboBox {
                    id: endSecondBox
                    implicitWidth: 60
                    model: Array.from({length: 60}, function(_, i) { return i.toString().padStart(2, '0'); })
                    enabled: root.pendingHasEndTime && !root.pendingAllDay
                    opacity: root.pendingHasEndTime ? 1.0 : 0.4
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    onCurrentIndexChanged: {
                        if (currentIndex !== root.pendingEndSecond)
                            root.pendingEndSecond = currentIndex;
                    }
                    onActivated: function(idx) {
                        var s = idx;
                        if (root.pendingEndHour === root.pendingHour && root.pendingEndMinute === root.pendingMinute
                                && s < root.pendingSecond) {
                            s = root.pendingSecond; currentIndex = s;
                        }
                        root.pendingEndSecond = s;
                    }
                }
            }

            // Title
            TextField {
                id: eventTitleInput
                placeholderText: "Event title"
                text: root.pendingTitle
                Layout.fillWidth: true
                focus: true
                onTextChanged: root.pendingTitle = text
            }

            // Comment
            TextArea {
                id: eventCommentInput
                placeholderText: "Optional comment"
                text: root.pendingComment
                Layout.fillWidth: true
                height: 60
                wrapMode: Text.Wrap
                onTextChanged: root.pendingComment = text
            }

            // Alert toggle — hidden for all-day events
            RowLayout {
                spacing: 6
                visible: !root.pendingAllDay
                CheckBox {
                    id: eventAlertCheck
                    checked: root.pendingAlert
                    onCheckedChanged: {
                        root.pendingAlert = checked;
                        if (!checked) { root.pendingAlertSilent = false; root.pendingAlertSound = ""; }
                    }
                }
                Text {
                    text: "Alert when time is reached"
                    color: "#cccccc"; font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Alert sound options — visible when alert is on
            ColumnLayout {
                spacing: 4
                visible: root.pendingAlert && !root.pendingAllDay
                opacity: (root.pendingAlert && !root.pendingAllDay) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                CheckBox {
                    checked: root.pendingAlertSilent
                    text: "Silent (no sound)"
                    onCheckedChanged: root.pendingAlertSilent = checked
                }

                RowLayout {
                    spacing: 6
                    visible: !root.pendingAlertSilent
                    opacity: root.pendingAlertSilent ? 0.0 : 1.0
                    Layout.fillWidth: true
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Text { text: "SFX:"; color: "#cccccc"; font.pixelSize: 12 }
                    TextField {
                        placeholderText: "Custom sound path (empty = builtin)"
                        text: root.pendingAlertSound
                        Layout.fillWidth: true
                        height: 28
                        font.pixelSize: 11
                        onTextChanged: root.pendingAlertSound = text
                    }
                }

                CheckBox {
                    checked: root.pendingAlertAutoTimeout
                    text: "Auto-dismiss after timeout"
                    onCheckedChanged: root.pendingAlertAutoTimeout = checked
                }

                RowLayout {
                    spacing: 6
                    visible: root.pendingAlertAutoTimeout
                    opacity: root.pendingAlertAutoTimeout ? 1.0 : 0.0
                    Layout.fillWidth: true
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Text { text: "Timeout:"; color: "#cccccc"; font.pixelSize: 12 }
                    ComboBox {
                        id: eventTimeoutBox
                        property var _values: [0.25, 0.5, 1, 2, 5, 10, 15, 20, 30, 45, 60]
                        property var _labels: ["0.25", "0.5", "1", "2", "5", "10", "15", "20", "30", "45", "60"]
                        model: _labels
                        currentIndex: {
                            for (var i = 0; i < _values.length; ++i)
                                if (Math.abs(_values[i] - root.pendingAlertTimeoutMinutes) < 0.01) return i;
                            return 4; // default 5 min
                        }
                        implicitWidth: 80
                        onCurrentIndexChanged: root.pendingAlertTimeoutMinutes = _values[currentIndex]
                    }
                    Text { text: "min"; color: "#cccccc"; font.pixelSize: 12 }
                }
            }
            
            // Recurring event controls
            RowLayout {
                spacing: 6
                CheckBox {
                    id: recurringCheck
                    checked: root.pendingRecurring
                    onCheckedChanged: root.pendingRecurring = checked
                }
                Text {
                    text: "Recurring event"
                    color: "#cccccc"; font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                }
            }
            
            // Recurring options (visible when recurring is enabled)
            ColumnLayout {
                spacing: 4
                visible: root.pendingRecurring
                opacity: root.pendingRecurring ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                
                // Interval selection
                RowLayout {
                    spacing: 6
                    Text { text: "Every"; color: "#cccccc"; font.pixelSize: 12 }
                    ComboBox {
                        id: recurringWeeksBox
                        implicitWidth: 60
                        model: ["1", "2", "3", "4"]
                        currentIndex: root.pendingRecurringWeeks - 1
                        onCurrentIndexChanged: root.pendingRecurringWeeks = parseInt(model[currentIndex], 10)
                    }
                    Text { text: "week(s) on:"; color: "#cccccc"; font.pixelSize: 12 }
                }
                
                // Day selection
                GridLayout {
                    columns: 4
                    columnSpacing: 4
                    rowSpacing: 2
                    
                    CheckBox {
                        id: sunCheck
                        text: "Sun"
                        checked: root.pendingRecurringDays.indexOf(0) !== -1
                        onCheckedChanged: {
                            var days = root.pendingRecurringDays.slice();
                            if (checked && days.indexOf(0) === -1) days.push(0);
                            else if (!checked) days = days.filter(function(d) { return d !== 0; });
                            root.pendingRecurringDays = days;
                        }
                    }
                    CheckBox {
                        id: monCheck
                        text: "Mon"
                        checked: root.pendingRecurringDays.indexOf(1) !== -1
                        onCheckedChanged: {
                            var days = root.pendingRecurringDays.slice();
                            if (checked && days.indexOf(1) === -1) days.push(1);
                            else if (!checked) days = days.filter(function(d) { return d !== 1; });
                            root.pendingRecurringDays = days;
                        }
                    }
                    CheckBox {
                        id: tueCheck
                        text: "Tue"
                        checked: root.pendingRecurringDays.indexOf(2) !== -1
                        onCheckedChanged: {
                            var days = root.pendingRecurringDays.slice();
                            if (checked && days.indexOf(2) === -1) days.push(2);
                            else if (!checked) days = days.filter(function(d) { return d !== 2; });
                            root.pendingRecurringDays = days;
                        }
                    }
                    CheckBox {
                        id: wedCheck
                        text: "Wed"
                        checked: root.pendingRecurringDays.indexOf(3) !== -1
                        onCheckedChanged: {
                            var days = root.pendingRecurringDays.slice();
                            if (checked && days.indexOf(3) === -1) days.push(3);
                            else if (!checked) days = days.filter(function(d) { return d !== 3; });
                            root.pendingRecurringDays = days;
                        }
                    }
                    CheckBox {
                        id: thuCheck
                        text: "Thu"
                        checked: root.pendingRecurringDays.indexOf(4) !== -1
                        onCheckedChanged: {
                            var days = root.pendingRecurringDays.slice();
                            if (checked && days.indexOf(4) === -1) days.push(4);
                            else if (!checked) days = days.filter(function(d) { return d !== 4; });
                            root.pendingRecurringDays = days;
                        }
                    }
                    CheckBox {
                        id: friCheck
                        text: "Fri"
                        checked: root.pendingRecurringDays.indexOf(5) !== -1
                        onCheckedChanged: {
                            var days = root.pendingRecurringDays.slice();
                            if (checked && days.indexOf(5) === -1) days.push(5);
                            else if (!checked) days = days.filter(function(d) { return d !== 5; });
                            root.pendingRecurringDays = days;
                        }
                    }
                    CheckBox {
                        id: satCheck
                        text: "Sat"
                        checked: root.pendingRecurringDays.indexOf(6) !== -1
                        onCheckedChanged: {
                            var days = root.pendingRecurringDays.slice();
                            if (checked && days.indexOf(6) === -1) days.push(6);
                            else if (!checked) days = days.filter(function(d) { return d !== 6; });
                            root.pendingRecurringDays = days;
                        }
                    }
                }
                
                // End date (optional)
                RowLayout {
                    spacing: 6
                    Text { text: "Until (optional):"; color: "#cccccc"; font.pixelSize: 12 }
                    TextField {
                        id: recurringEndDateInput
                        placeholderText: "YYYY-MM-DD"
                        text: root.pendingRecurringEndDate
                        implicitWidth: 100
                        onTextChanged: root.pendingRecurringEndDate = text
                    }
                }
            }
            RowLayout {
                spacing: 8
                Layout.fillWidth: true

                // Delete button — edit mode only
                Rectangle {
                    visible: root.pendingEventId !== ""
                    width: 72; height: 28; radius: 6
                    color: delHov.containsMouse ? "#550000" : "transparent"
                    border.color: "#cc4444"; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "✕ Delete"; color: "#ff6666"
                        font.pixelSize: 12; font.bold: true
                    }
                    HoverHandler { id: delHov }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._confirmDeleteVisible = true
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Cancel"
                    onClicked: {
                        root.pendingAlertSilent        = false;
                        root.pendingAlertSound         = "";
                        root.pendingAlertAutoTimeout   = true;
                        root.pendingAlertTimeoutMinutes = 5;
                        root.pendingHasEndTime  = false;
                        root.pendingEndHour     = (appState.now.getHours() + 1) % 24;
                        root.pendingEndMinute   = 0;
                        root.pendingEndSecond   = 0;
                        root.pendingEventId = "";
                        root.close();
                    }
                }

                Button {
                    text: "Save"
                    onClicked: {
                        var evTime = root.pendingAllDay
                            ? ""
                            : (String(root.pendingHour).padStart(2, '0')   + ":" +
                               String(root.pendingMinute).padStart(2, '0') + ":" +
                               String(root.pendingSecond).padStart(2, '0'));
                        var evEndTime = (!root.pendingAllDay && root.pendingHasEndTime)
                            ? (String(root.pendingEndHour).padStart(2, '0')   + ":" +
                               String(root.pendingEndMinute).padStart(2, '0') + ":" +
                               String(root.pendingEndSecond).padStart(2, '0'))
                            : "";
                        var title   = root.pendingTitle.trim() !== "" ? root.pendingTitle : "Untitled Event";
                        var comment = root.pendingComment ? root.pendingComment.trim() : "";
                        
                        // Validate recurring events
                        var recurring = root.pendingRecurring;
                        var recurringDays = root.pendingRecurringDays;
                        if (recurring && (!recurringDays || recurringDays.length === 0)) {
                            console.warn("Recurring event must have at least one day selected");
                            return;
                        }
                        
                        console.log("[event] saving", {
                            day: root.pendingDay, 
                            month: root.pendingMonth, 
                            year: root.pendingYear, 
                            time: evTime, 
                            allDay: root.pendingAllDay, 
                            title: title,
                            recurring: recurring,
                            recurringWeeks: root.pendingRecurringWeeks,
                            recurringDays: recurringDays,
                            recurringEndDate: root.pendingRecurringEndDate
                        });

                        if (root.pendingEventId) {
                            appState.updateEventByEventId(
                                root.pendingEventId,
                                title,
                                evTime,
                                root.pendingAllDay,
                                root.pendingMonth,
                                root.pendingYear,
                                root.pendingDay,
                                comment,
                                root.pendingAlert,
                                recurring,
                                root.pendingRecurringWeeks,
                                recurringDays,
                                root.pendingRecurringEndDate,
                                root.pendingAlertSilent,
                                root.pendingAlertSound,
                                root.pendingAlertAutoTimeout,
                                root.pendingAlertTimeoutMinutes,
                                evEndTime
                            );
                        } else {
                            appState.addEvent(
                                title,
                                evTime,
                                root.pendingAllDay,
                                root.pendingMonth,
                                root.pendingYear,
                                root.pendingDay,
                                comment,
                                root.pendingAlert,
                                recurring,
                                root.pendingRecurringWeeks,
                                recurringDays,
                                root.pendingRecurringEndDate,
                                root.pendingAlertSilent,
                                root.pendingAlertSound,
                                root.pendingAlertAutoTimeout,
                                root.pendingAlertTimeoutMinutes,
                                evEndTime
                            );
                        }
                        appState.saveEventsToFile();

                        // reset
                        root.pendingTitle   = "";
                        root.pendingComment = "";
                        root.pendingMonth   = appState.month + 1;
                        root.pendingYear    = appState.year;
                        root.pendingHour    = (appState.now.getMinutes() + 10 >= 60) ? (appState.now.getHours() + 1) % 24 : appState.now.getHours();
                        root.pendingMinute  = (appState.now.getMinutes() + 10) % 60;
                        root.pendingSecond  = 0;
                        root.pendingAllDay  = false;
                        root.pendingAlert              = false;
                        root.pendingAlertSilent        = false;
                        root.pendingAlertSound         = "";
                        root.pendingAlertAutoTimeout   = true;
                        root.pendingAlertTimeoutMinutes = 5;
                        root.pendingHasEndTime  = false;
                        root.pendingEndHour     = (appState.now.getHours() + 1) % 24;
                        root.pendingEndMinute   = 0;
                        root.pendingEndSecond   = 0;
                        root.pendingEventId = "";
                        root.pendingRecurring = false;
                        root.pendingRecurringWeeks = 1;
                        root.pendingRecurringDays = [];
                        root.pendingRecurringEndDate = "";
                        root.close();
                    }
                }
            }
        }  // end ColumnLayout

        // ── Delete confirmation ─────────────────────────────────────────
        ConfirmDialog {
            anchors.fill: parent
            visible: root._confirmDeleteVisible
            z: 99999
            minCardWidth: 400
            title:   "Delete Event"
            message: "Delete \"" + root.pendingTitle + "\"?"
            detail:  root.pendingRecurring ? "This is a recurring event. All occurrences will be deleted." : ""
            acceptLabel: "Delete"
            rejectLabel: "Cancel"
            acceptColor:       "#880000"
            acceptHoverColor:  "#cc2222"
            acceptBorderColor: "#cc4444"
            onAccepted: {
                root._confirmDeleteVisible = false;
                var eid = root.pendingEventId;
                root.pendingEventId = "";
                root.close();
                root.deleteEventRequested(eid);
            }
            onRejected: root._confirmDeleteVisible = false
        }
    }  // end Rectangle
}
