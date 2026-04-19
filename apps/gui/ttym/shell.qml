// shell.qml — entry point.  Hosts AppState (logic/persistence) and composes
// all visual elements.  No business logic lives here; everything is
// delegated to the appropriate component.
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell

import "elems/state"
import "elems/alarm"
import "elems/calendar"
import "elems/chrome"

PanelWindow {
    id: appRoot

    // ─────────────────────────────────────────────────────────────────────────
    // Responsive sizing (mirrors shell-orig.qml exactly)
    // ─────────────────────────────────────────────────────────────────────────
    property real baseWidth:  1850
    property real baseHeight: 1000
    property real baseDpi:    96
    property real screenDpi:  baseDpi
    property real screenWidth:  baseWidth
    property real screenHeight: baseHeight

    function activeScreen() {
        if (appRoot.screen) return appRoot.screen;
        if (Qt.application && Qt.application.primaryScreen) return Qt.application.primaryScreen;
        return null;
    }

    function updateScreenMetrics() {
        var s = appRoot.activeScreen();
        if (!s) { appRoot.screenDpi = baseDpi; appRoot.screenHeight = baseHeight; return; }
        var g = (s.availableGeometry && s.availableGeometry.width && s.availableGeometry.height)
                ? s.availableGeometry
                : s.geometry ? s.geometry : null;
        if (g) {
            appRoot.screenHeight = g.height;
        } else {
            appRoot.screenWidth  = (s.width && s.height) ? s.width  : baseWidth;
            appRoot.screenHeight = (s.height && s.width) ? s.height : baseHeight;
        }
    }

    property real dpiScale:    Math.min(1.0, baseDpi / screenDpi)
    property real resScale:    Math.min(1.0, screenWidth / baseWidth, screenHeight / baseHeight)
    property real windowScale: Math.max(0.30, Math.min(1.0, dpiScale * resScale))

    implicitWidth:  Math.max(300, Math.min(screenWidth  * 0.99, baseWidth  * windowScale))
    implicitHeight: Math.max(250, Math.min(screenHeight * 1.0285, baseHeight * windowScale))

    onScreenChanged: appRoot.updateScreenMetrics()
    color: "transparent"

    // ─────────────────────────────────────────────────────────────────────────
    // Derived sizing passed to child components
    // ─────────────────────────────────────────────────────────────────────────
    property real alarmClockSize:     Math.min(width * 0.55, height * 0.84, 760 * windowScale)
    property real alarmRingInnerScale: 0.80 * windowScale
    property real calendarCellScale:   1.25 * windowScale

    onWidthChanged:  alarmClockSize = Math.min(width * 0.55, height * 0.84, 760)
    onHeightChanged: alarmClockSize = Math.min(width * 0.55, height * 0.84, 760)

    // ─────────────────────────────────────────────────────────────────────────
    // State / logic singleton
    // ─────────────────────────────────────────────────────────────────────────
    AppState {
        id: appState

        // Wire the ring-repaint signal to the AlarmRing component
        onSigRepaintRing: alarmRing.repaint()

        // Wire the alarm-triggered signal to open the alert
        onSigAlarmTriggered: {
            alarmAlert.open();
            if (!appState.alarmSilent)
                appState.playAlarmSound(appState.alarmSound);
        }

        // Wire the event-alert signal to open the event alert popup
        onSigEventAlertTriggered: function(ev) {
            eventAlertPopup.ev = ev;
            eventAlertPopup.open();
            if (!ev.alertSilent)
                appState.playEventSound(ev.alertSound || "");
        }
    }

    Component.onCompleted: appState.init(appRoot.WlrLayershell)

    // ── Toggle flags for button-driven popups ─────────────────────────────────
    property bool settingsOpen:      false
    property bool alarmSettingsOpen: false
    property bool allEventsOpen:     false
    property bool allDayOpen:        false
    // ─────────────────────────────────────────────────────────────────────────
    // Popups  (declared before the main layout so z-order is correct)
    // ─────────────────────────────────────────────────────────────────────────

    AlarmAlert {
        id: alarmAlert
        appState: appState
        x: (appRoot.width  - 340) / 2
        y: (appRoot.height - 260) / 2
    }

    EventAlert {
        id: eventAlertPopup
        appState: appState
        x: (appRoot.width  - 380) / 2
        y: (appRoot.height - 300) / 2
    }

    AlarmPopup {
        id: alarmSettingsPopup
        appState: appState
        anchors.fill: parent
        visible: appRoot.alarmSettingsOpen
        onRingRepaintRequested: alarmRing.repaint()
        onCloseRequested: appRoot.alarmSettingsOpen = false
    }

    EventPopup {
        id: eventPopup
        appState: appState
        anchors.centerIn: parent
        onDeleteEventRequested: function(eventId) {
            appState.removeEventByEventId(eventId);
            appState.saveEventsToFile();
        }
    }

    DayEventsPopup {
        id: dayEventsPopup
        appState: appState
        anchors.centerIn: parent
        onEditEventRequested: function(eventId) {
            var ev = null;
            for (var i = 0; i < appState.events.length; ++i) {
                if (appState.events[i].eventId === eventId) { 
                    ev = appState.events[i]; 
                    break; 
                }
            }
            
            // Check if this is a recurring instance
            if (!ev) {
                for (var j = 0; j < appState.eventModel.count; ++j) {
                    var modelItem = appState.eventModel.get(j);
                    if (modelItem.eventId === eventId && modelItem.isRecurringInstance && modelItem.originalEventId) {
                        for (var k = 0; k < appState.events.length; ++k) {
                            if (appState.events[k].eventId === modelItem.originalEventId) {
                                ev = appState.events[k];
                                break;
                            }
                        }
                        break;
                    }
                }
            }
            
            if (!ev) return;
            eventPopup.pendingEventId = ev.eventId;
            eventPopup.pendingDay     = ev.day;
            eventPopup.pendingMonth   = ev.date ? parseInt(ev.date.split("-")[1], 10) : appState.month + 1;
            eventPopup.pendingYear    = ev.date ? parseInt(ev.date.split("-")[0], 10) : appState.year;
            eventPopup.pendingTitle   = ev.title   || "";
            eventPopup.pendingComment = ev.comment || "";
            eventPopup.pendingAllDay  = ev.allDay  || (ev.time === "");
            eventPopup.pendingAlert   = !!ev.alert;
            eventPopup.pendingRecurring = !!ev.recurring;
            eventPopup.pendingRecurringWeeks = ev.recurringWeeks || 1;
            eventPopup.pendingRecurringDays = ev.recurringDays || [];
            eventPopup.pendingRecurringEndDate = ev.recurringEndDate || "";
            if (!eventPopup.pendingAllDay && ev.time && ev.time.length >= 8) {
                var parts = ev.time.split(":");
                eventPopup.pendingHour   = parseInt(parts[0], 10);
                eventPopup.pendingMinute = parseInt(parts[1], 10);
                eventPopup.pendingSecond = parseInt(parts[2], 10);
            } else {
                eventPopup.pendingHour   = appState.now.getHours();
                eventPopup.pendingMinute = appState.now.getMinutes();
                eventPopup.pendingSecond = appState.now.getSeconds();
            }
            if (!eventPopup.pendingAllDay && ev.endTime && ev.endTime !== "") {
                var ep = ev.endTime.split(":");
                eventPopup.pendingHasEndTime  = true;
                eventPopup.pendingEndHour     = parseInt(ep[0] || "0", 10);
                eventPopup.pendingEndMinute   = parseInt(ep[1] || "0", 10);
                eventPopup.pendingEndSecond   = parseInt(ep[2] || "0", 10);
            } else {
                eventPopup.pendingHasEndTime  = false;
                eventPopup.pendingEndHour     = (eventPopup.pendingHour + 1) % 24;
                eventPopup.pendingEndMinute   = 0;
                eventPopup.pendingEndSecond   = 0;
            }
            eventPopup.open();
        }
        onAddEventForDayRequested: function(year, month, day) {
            eventPopup.pendingEventId   = "";
            eventPopup.pendingAllDay    = false;
            eventPopup.pendingAlert     = false;
            eventPopup.pendingRecurring = false;
            eventPopup.pendingYear      = year;
            eventPopup.pendingMonth     = month + 1;
            eventPopup.pendingDay       = day;
            eventPopup.pendingHour      = appState.now.getHours();
            eventPopup.pendingMinute    = appState.now.getMinutes();
            eventPopup.open();
        }
    }

    SettingsPopup {
        id: settingsPopup
        appState: appState
        anchors.fill: parent
        visible: appRoot.settingsOpen
        onCloseRequested: appRoot.settingsOpen = false
    }

    AllEventsPopup {
        id: allEventsPopup
        appState: appState
        anchors.fill: parent
        visible: appRoot.allEventsOpen
        onCloseRequested: appRoot.allEventsOpen = false
        onEditEventRequested: function(eventId) {
            var ev = null;
            for (var i = 0; i < appState.events.length; ++i) {
                if (appState.events[i].eventId === eventId) { 
                    ev = appState.events[i]; 
                    break; 
                }
            }
            
            // Check if this is a recurring instance
            if (!ev) {
                for (var j = 0; j < appState.eventModel.count; ++j) {
                    var modelItem = appState.eventModel.get(j);
                    if (modelItem.eventId === eventId && modelItem.isRecurringInstance && modelItem.originalEventId) {
                        for (var k = 0; k < appState.events.length; ++k) {
                            if (appState.events[k].eventId === modelItem.originalEventId) {
                                ev = appState.events[k];
                                break;
                            }
                        }
                        break;
                    }
                }
            }
            
            if (!ev) return;
            eventPopup.pendingEventId = ev.eventId;
            eventPopup.pendingDay     = ev.day;
            eventPopup.pendingMonth   = ev.date ? parseInt(ev.date.split("-")[1], 10) : appState.month + 1;
            eventPopup.pendingYear    = ev.date ? parseInt(ev.date.split("-")[0], 10) : appState.year;
            eventPopup.pendingTitle   = ev.title   || "";
            eventPopup.pendingComment = ev.comment || "";
            eventPopup.pendingAllDay  = ev.allDay  || (ev.time === "");
            eventPopup.pendingAlert   = !!ev.alert;
            eventPopup.pendingRecurring = !!ev.recurring;
            eventPopup.pendingRecurringWeeks = ev.recurringWeeks || 1;
            eventPopup.pendingRecurringDays = ev.recurringDays || [];
            eventPopup.pendingRecurringEndDate = ev.recurringEndDate || "";
            if (!eventPopup.pendingAllDay && ev.time && ev.time.length >= 8) {
                var parts = ev.time.split(":");
                eventPopup.pendingHour   = parseInt(parts[0], 10);
                eventPopup.pendingMinute = parseInt(parts[1], 10);
                eventPopup.pendingSecond = parseInt(parts[2], 10);
            } else {
                eventPopup.pendingHour   = appState.now.getHours();
                eventPopup.pendingMinute = appState.now.getMinutes();
                eventPopup.pendingSecond = appState.now.getSeconds();
            }
            if (!eventPopup.pendingAllDay && ev.endTime && ev.endTime !== "") {
                var ep = ev.endTime.split(":");
                eventPopup.pendingHasEndTime  = true;
                eventPopup.pendingEndHour     = parseInt(ep[0] || "0", 10);
                eventPopup.pendingEndMinute   = parseInt(ep[1] || "0", 10);
                eventPopup.pendingEndSecond   = parseInt(ep[2] || "0", 10);
            } else {
                eventPopup.pendingHasEndTime  = false;
                eventPopup.pendingEndHour     = (eventPopup.pendingHour + 1) % 24;
                eventPopup.pendingEndMinute   = 0;
                eventPopup.pendingEndSecond   = 0;
            }
            eventPopup.open();
        }
    }

    AllDayPopup {
        id: allDayPopup
        appState: appState
        anchors.fill: parent
        visible: appRoot.allDayOpen
        onCloseRequested: appRoot.allDayOpen = false
        onEditEventRequested: function(eventId) {
            appRoot.allDayOpen = false;
            var ev = null;
            for (var i = 0; i < appState.events.length; ++i) {
                if (appState.events[i].eventId === eventId) { ev = appState.events[i]; break; }
            }
            if (!ev) return;
            eventPopup.pendingEventId = eventId;
            eventPopup.pendingDay     = ev.day;
            eventPopup.pendingMonth   = ev.date ? parseInt(ev.date.split("-")[1], 10) : appState.month + 1;
            eventPopup.pendingYear    = ev.date ? parseInt(ev.date.split("-")[0], 10) : appState.year;
            eventPopup.pendingTitle   = ev.title   || "";
            eventPopup.pendingComment = ev.comment || "";
            eventPopup.pendingAllDay  = !!ev.allDay;
            eventPopup.pendingAlert   = !!ev.alert;
            eventPopup.pendingRecurring = !!ev.recurring;
            eventPopup.pendingRecurringWeeks = ev.recurringWeeks || 1;
            eventPopup.pendingRecurringDays = ev.recurringDays || [];
            eventPopup.pendingRecurringEndDate = ev.recurringEndDate || "";
            
            // Parse time if not all-day
            if (!ev.allDay && ev.time && ev.time !== "All Day") {
                var timeParts = ev.time.split(":");
                if (timeParts.length >= 2) {
                    eventPopup.pendingHour = parseInt(timeParts[0] || "0", 10);
                    eventPopup.pendingMinute = parseInt(timeParts[1] || "0", 10);
                    eventPopup.pendingSecond = parseInt(timeParts[2] || "0", 10);
                } else {
                    eventPopup.pendingHour    = appState.now.getHours();
                    eventPopup.pendingMinute  = appState.now.getMinutes();
                    eventPopup.pendingSecond  = appState.now.getSeconds();
                }
            } else {
                eventPopup.pendingHour    = appState.now.getHours();
                eventPopup.pendingMinute  = appState.now.getMinutes();
                eventPopup.pendingSecond  = appState.now.getSeconds();
            }
            if (!eventPopup.pendingAllDay && ev.endTime && ev.endTime !== "") {
                var epd = ev.endTime.split(":");
                eventPopup.pendingHasEndTime  = true;
                eventPopup.pendingEndHour     = parseInt(epd[0] || "0", 10);
                eventPopup.pendingEndMinute   = parseInt(epd[1] || "0", 10);
                eventPopup.pendingEndSecond   = parseInt(epd[2] || "0", 10);
            } else {
                eventPopup.pendingHasEndTime  = false;
                eventPopup.pendingEndHour     = (eventPopup.pendingHour + 1) % 24;
                eventPopup.pendingEndMinute   = 0;
                eventPopup.pendingEndSecond   = 0;
            }
            eventPopup.open();
        }
        onAddAllDayEventRequested: {
            appRoot.allDayOpen = false;
            var now = appState.now;
            eventPopup.pendingEventId = "";
            eventPopup.pendingAllDay  = true;
            eventPopup.pendingDay     = now.getDate();
            eventPopup.pendingMonth   = now.getMonth() + 1;
            eventPopup.pendingYear    = now.getFullYear();
            eventPopup.pendingTitle   = "";
            eventPopup.pendingComment = "";
            eventPopup.pendingAlert   = false;
            eventPopup.pendingHour    = now.getHours();
            eventPopup.pendingMinute  = now.getMinutes();
            eventPopup.pendingSecond  = now.getSeconds();
            eventPopup.open();
        }
    }
    // ───────────────────────────────────────────────────────────────────────────────
    // Main content card
    // ─────────────────────────────────────────────────────────────────────────
    property string _pendingDelTodoId:    ""
    property string _pendingDelTodoTitle: ""

    Rectangle {
        anchors.fill: parent
        color:  "#bb000000"
        radius: 16
        border.color: "#66ffffff"; border.width: 1

        RowLayout {
            anchors.fill:    parent
            anchors.margins: 16
            spacing: 16

            // ── Left column: ring + clock ─────────────────────────────────────
            Item {
                Layout.preferredWidth: appRoot.alarmClockSize + 40
                Layout.minimumWidth:   Math.min(appRoot.alarmClockSize + 40, parent ? parent.width : appRoot.alarmClockSize + 40)
                Layout.maximumWidth:   appRoot.alarmClockSize + 40
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.top:              parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    width: parent.width

                    AlarmRing {
                        id: alarmRing
                        appState:   appState
                        ringSize:   appRoot.alarmClockSize
                        innerScale: appRoot.alarmRingInnerScale
                        dpiScale:   appRoot.dpiScale
                        Layout.preferredWidth:  appRoot.alarmClockSize
                        Layout.preferredHeight: appRoot.alarmClockSize
                        Layout.minimumWidth:    Math.min(appRoot.alarmClockSize, parent ? parent.width  : appRoot.alarmClockSize)
                        Layout.minimumHeight:   Math.min(appRoot.alarmClockSize, parent ? parent.height : appRoot.alarmClockSize)
                        Layout.maximumWidth:    appRoot.alarmClockSize
                        Layout.maximumHeight:   appRoot.alarmClockSize
                    }
                }
            }

            // ── Right column: calendar + events ───────────────────────────────
            CalendarView {
                id: calendarView
                appState:   appState
                cellScale:  appRoot.calendarCellScale
                dpiScale:   appRoot.dpiScale
                Layout.fillWidth:  true
                Layout.fillHeight: false
                Layout.alignment:  Qt.AlignTop

                onAllDayStripClicked:         appRoot.allDayOpen = true
                onAddRecurringEventRequested: {
                    eventPopup.pendingEventId        = "";
                    eventPopup.pendingAllDay         = false;
                    eventPopup.pendingAlert          = false;
                    eventPopup.pendingYear           = 0;
                    eventPopup.pendingMonth          = 0;
                    eventPopup.pendingDay            = 0;
                    eventPopup.pendingHour           = appState.now.getHours();
                    eventPopup.pendingMinute         = appState.now.getMinutes();
                    eventPopup.pendingRecurring      = true;
                    eventPopup.pendingRecurringWeeks = 1;
                    eventPopup.pendingRecurringDays  = [];
                    eventPopup.open();
                }
                onAddEventRequested: {
                    eventPopup.pendingEventId   = "";
                    eventPopup.pendingAllDay    = false;
                    eventPopup.pendingAlert     = false;
                    eventPopup.pendingYear      = 0;
                    eventPopup.pendingMonth     = 0;
                    eventPopup.pendingDay       = 0;
                    eventPopup.pendingHour      = 0;
                    eventPopup.pendingMinute    = 0;
                    eventPopup.pendingRecurring = false;
                    eventPopup.open();
                }
                onDayClicked: function(year, month, day) {
                    dayEventsPopup.showDay(year, month, day);
                }
                onEditEventRequested: function(eventId) {
                    // Populate popup from appState and open
                    var ev = null;
                    
                    // First, try to find the event directly
                    for (var i = 0; i < appState.events.length; ++i) {
                        if (appState.events[i].eventId === eventId) { 
                            ev = appState.events[i]; 
                            break; 
                        }
                    }
                    
                    // If not found, check if this is a recurring instance by looking in eventModel
                    if (!ev) {
                        for (var j = 0; j < appState.eventModel.count; ++j) {
                            var modelItem = appState.eventModel.get(j);
                            if (modelItem.eventId === eventId && modelItem.isRecurringInstance && modelItem.originalEventId) {
                                // Find the original recurring event
                                for (var k = 0; k < appState.events.length; ++k) {
                                    if (appState.events[k].eventId === modelItem.originalEventId) {
                                        ev = appState.events[k];
                                        break;
                                    }
                                }
                                break;
                            }
                        }
                    }
                    
                    if (!ev) return;
                    eventPopup.pendingEventId = ev.eventId; // Use original event ID for editing
                    eventPopup.pendingDay     = ev.day;
                    eventPopup.pendingMonth   = ev.date ? parseInt(ev.date.split("-")[1], 10) : appState.month + 1;
                    eventPopup.pendingYear    = ev.date ? parseInt(ev.date.split("-")[0], 10) : appState.year;
                    eventPopup.pendingTitle   = ev.title   || "";
                    eventPopup.pendingComment = ev.comment || "";
                    eventPopup.pendingAllDay  = ev.allDay  || (ev.time === "");
                    eventPopup.pendingAlert   = !!ev.alert;
                    eventPopup.pendingRecurring = !!ev.recurring;
                    eventPopup.pendingRecurringWeeks = ev.recurringWeeks || 1;
                    eventPopup.pendingRecurringDays = ev.recurringDays || [];
                    eventPopup.pendingRecurringEndDate = ev.recurringEndDate || "";
                    if (!eventPopup.pendingAllDay && ev.time && ev.time.length >= 8) {
                        var parts = ev.time.split(":");
                        eventPopup.pendingHour   = parseInt(parts[0], 10);
                        eventPopup.pendingMinute = parseInt(parts[1], 10);
                        eventPopup.pendingSecond = parseInt(parts[2], 10);
                    } else {
                        eventPopup.pendingHour   = appState.now.getHours();
                        eventPopup.pendingMinute = appState.now.getMinutes();
                        eventPopup.pendingSecond = appState.now.getSeconds();
                    }
                    if (!eventPopup.pendingAllDay && ev.endTime && ev.endTime !== "") {
                        var epc = ev.endTime.split(":");
                        eventPopup.pendingHasEndTime  = true;
                        eventPopup.pendingEndHour     = parseInt(epc[0] || "0", 10);
                        eventPopup.pendingEndMinute   = parseInt(epc[1] || "0", 10);
                        eventPopup.pendingEndSecond   = parseInt(epc[2] || "0", 10);
                    } else {
                        eventPopup.pendingHasEndTime  = false;
                        eventPopup.pendingEndHour     = (eventPopup.pendingHour + 1) % 24;
                        eventPopup.pendingEndMinute   = 0;
                        eventPopup.pendingEndSecond   = 0;
                    }
                    eventPopup.open();
                }
                onTodoDeleteRequested: function(todoId, todoTitle) {
                    appRoot._pendingDelTodoId    = todoId;
                    appRoot._pendingDelTodoTitle = todoTitle;
                }
            }
        }

        // ── Todo delete confirmation ───────────────────────────────────────
        ConfirmDialog {
            anchors.fill: parent
            visible: appRoot._pendingDelTodoId !== ""
            z: 99999
            title: "Delete Todo"
            message: "Delete \"" + appRoot._pendingDelTodoTitle + "\"?"
            acceptLabel: "Delete"
            rejectLabel: "Cancel"
            acceptColor:       "#660000"
            acceptHoverColor:  "#aa2222"
            acceptBorderColor: "#cc4444"
            onAccepted: {
                appState.removeTodo(appRoot._pendingDelTodoId);
                appRoot._pendingDelTodoId    = "";
                appRoot._pendingDelTodoTitle = "";
            }
            onRejected: {
                appRoot._pendingDelTodoId    = "";
                appRoot._pendingDelTodoTitle = "";
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    ControlButtons {
        id: controls
        appState: appState
        dpiScale: appRoot.dpiScale

        onSettingsRequested:      appRoot.settingsOpen      = !appRoot.settingsOpen
        onAlarmSettingsRequested: appRoot.alarmSettingsOpen = !appRoot.alarmSettingsOpen
        onAddEventRequested:      eventPopup.open()
        onHamburgerRequested:     appRoot.allEventsOpen     = !appRoot.allEventsOpen
        onAddTodoRequested:       calendarView.openTodoAdd()
    }
}
