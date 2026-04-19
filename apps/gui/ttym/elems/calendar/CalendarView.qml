// CalendarView.qml — month-navigation header and day grid.
// Upcoming events list is in UpcomingView.qml, embedded at the bottom.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

ColumnLayout {
    id: root

    // ── Required context ──────────────────────────────────────────────────────
    required property QtObject appState

    // ── Scaling helpers ───────────────────────────────────────────────────────
    property real cellScale: 1.25
    property real dpiScale:  1.0

    // ── Signal: user clicked the floating add-event button ────────────────────
    signal addEventRequested()
    signal editEventRequested(string eventId)
    signal addRecurringEventRequested()
    signal addTodoRequested()
    signal todoDeleteRequested(string todoId, string todoTitle)
    signal allDayStripClicked()

    function openTodoAdd() {
        upcomingView.openTodoAdd();
    }
    signal dayClicked(int year, int month, int day)

    spacing: 0

    // ── Month navigation row ──────────────────────────────────────────────────
    RowLayout {
        id: navRow
        Layout.alignment: Qt.AlignHCenter
        spacing: 4
        width: (7 * 40 + 6 * 4) * root.cellScale

        Button {
            width:  36 * root.cellScale
            height: 36 * root.cellScale
            contentItem: Text {
                text: "<"
                color: "#ffffff"
                font.pixelSize: 16 * root.cellScale
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment:   Text.AlignVCenter
                anchors.fill: parent
            }
            background: Rectangle {
                color: "#333333"; radius: width / 2
                border.color: parent.hovered ? "#ff4444" : "#ffffff"
                border.width: parent.hovered ? 3 : 1
            }
            onClicked: appState.jumpCalendarMonth(-1)
        }

        Text {
            text: appState.monthName() + " " + appState.viewYear
            color: "#ffffff"
            font.pixelSize: 24
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 220
        }

        Button {
            width:  36 * root.cellScale
            height: 36 * root.cellScale
            contentItem: Text {
                text: ">"
                color: "#ffffff"
                font.pixelSize: 16 * root.cellScale
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment:   Text.AlignVCenter
                anchors.fill: parent
            }
            background: Rectangle {
                color: "#333333"; radius: width / 2
                border.color: parent.hovered ? "#ff4444" : "#ffffff"
                border.width: parent.hovered ? 3 : 1
            }
            onClicked: appState.jumpCalendarMonth(1)
        }
    }

    // ── Calendar grid ─────────────────────────────────────────────────────────
    Item {
        id: calendarArea
        Layout.preferredWidth:  7 * 52 + 6 * 6
        Layout.preferredHeight: calendarGrid.implicitHeight + 2
        width:  7 * 52 + 6 * 6
        Layout.alignment: Qt.AlignHCenter

        // «Home» button positioned to the left of the grid
        Button {
            id: calendarHomeButton
            width:  36 * root.cellScale
            height: 36 * root.cellScale
            x: -width - 40
            y: 44 + 4 + 2 * (44 + 4) - 17
            contentItem: Text {
                text: "⌂"
                color: "#ffffff"
                font.pixelSize: 16 * root.cellScale
                font.family: "monospace"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment:   Text.AlignVCenter
                anchors.fill: parent
            }
            background: Rectangle {
                color: "#333333"; radius: width / 2
                border.color: calendarHomeButton.hovered ? "#ff4444" : "#ffffff"
                border.width: calendarHomeButton.hovered ? 3 : 1
            }
            onClicked: appState.goToCurrentMonth()
        }

        GridLayout {
            id: calendarGrid
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 7
            rowSpacing:    4
            columnSpacing: 6
            Layout.alignment: Qt.AlignHCenter

            // Weekday headers
            Repeater {
                model: 7
                Text {
                    text: appState.weekdayName(index)
                    font.pixelSize: 14 * root.cellScale
                    color: "#cccccc"
                    width: 52
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment:   Text.AlignVCenter
                }
            }

            // Day cells (always 6 rows × 7)
            Repeater {
                model: 42

                Rectangle {
                    property int dayNumber: index - appState.viewMonthFirstWeekday + 1
                    width:  52
                    height: 44
                    color: (dayNumber === appState.day
                            && dayNumber >= 1 && dayNumber <= appState.viewMonthDaysCount
                            && appState.viewYear  === appState.year
                            && appState.viewMonth === appState.month)
                           ? "#44ffffff" : "transparent"
                    radius: 6

                    // Event-dot indicators
                    Item {
                        visible: appState.eventCountOnDay(dayNumber, appState.eventsRevision) > 0
                        width: parent.width; height: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            
                            property var dayEventTypes: (dayNumber >= 1 && dayNumber <= appState.viewMonthDaysCount && appState.eventsRevision >= 0) 
                                ? appState.getEventTypesForDay(appState.viewYear, appState.viewMonth, dayNumber)
                                : { hasRegular: false, hasAllDayNonRecurring: false, hasRecurring: false }
                            
                            // Green dot for regular events
                            Rectangle {
                                visible: parent.dayEventTypes.hasRegular
                                width: 6; height: 6
                                color: "#22cc22"
                                radius: width / 2
                            }
                            
                            // Purple dot for all-day non-recurring events
                            Rectangle {
                                visible: parent.dayEventTypes.hasAllDayNonRecurring
                                width: 6; height: 6
                                color: "#aa22aa"
                                radius: width / 2
                            }
                            
                            // Blue dot for recurring events
                            Rectangle {
                                visible: parent.dayEventTypes.hasRecurring
                                width: 6; height: 6
                                color: "#2288cc"
                                radius: width / 2
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: (dayNumber >= 1 && dayNumber <= appState.viewMonthDaysCount)
                              ? (dayNumber < 10 ? "0" + dayNumber : dayNumber)
                              : ""
                        color: (dayNumber === appState.day
                                && dayNumber >= 1 && dayNumber <= appState.viewMonthDaysCount
                                && appState.viewYear  === appState.year
                                && appState.viewMonth === appState.month)
                               ? "#ffffff" : "#dddddd"
                        font.pixelSize: 14 * root.cellScale
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                    }
                    
                    // MouseArea for day clicks
                    MouseArea {
                        anchors.fill: parent
                        enabled: dayNumber >= 1 && dayNumber <= appState.viewMonthDaysCount
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (dayNumber >= 1 && dayNumber <= appState.viewMonthDaysCount) {
                                root.dayClicked(appState.viewYear, appState.viewMonth, dayNumber);
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Upcoming events ───────────────────────────────────────────────────────
    UpcomingView {
        id: upcomingView
        appState:   root.appState
        cellScale:  root.cellScale
        Layout.fillWidth: true
        onEditEventRequested:        function(eventId) { root.editEventRequested(eventId); }
        onAllDayStripClicked:         root.allDayStripClicked()
        onAddRecurringEventRequested: root.addRecurringEventRequested()
        onAddTodoRequested:           root.addTodoRequested()
        onTodoDeleteRequested:        function(todoId, todoTitle) { root.todoDeleteRequested(todoId, todoTitle); }
    }
}
