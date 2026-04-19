// AlarmRing.qml — circular day-progress / alarm-countdown ring with an
// embedded clock display in the centre.
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    // ── Required context (bound from shell.qml) ───────────────────────────────
    required property QtObject appState

    // ── Sizing helpers passed in from the parent ──────────────────────────────
    property real ringSize:       400
    property real innerScale:     0.80
    property real dpiScale:       1.0

    implicitWidth:  ringSize
    implicitHeight: ringSize

    // ── Public: drive a repaint from outside (AppState.requestPaintRing) ──────
    function repaint() { ringCanvas.requestPaint(); }

    // ── Ring canvas ───────────────────────────────────────────────────────────
    Canvas {
        id: ringCanvas
        anchors.centerIn: parent
        width:  root.ringSize
        height: root.ringSize

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var cx = width  / 2;
            var cy = height / 2;
            var r  = Math.min(width, height) / 2 - 8;

            // ── Helper: draw a full-circle background track ───────────────────
            function track(radius, color, lw) {
                ctx.beginPath();
                ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
                ctx.lineWidth   = lw;
                ctx.strokeStyle = color;
                ctx.stroke();
            }

            // ── Helper: countdown arc — starts at top, fills clockwise,
            //    shrinks from the end as fraction goes 1→0 ────────────────────
            function countdownArc(radius, fraction, color, lw) {
                if (fraction <= 0) return;
                var end = -Math.PI / 2 + 2 * Math.PI * Math.min(fraction, 1.0);
                ctx.beginPath();
                ctx.arc(cx, cy, radius, -Math.PI / 2, end, false);
                ctx.lineWidth   = lw;
                ctx.strokeStyle = color;
                ctx.stroke();
            }

            // ── Helper: dot at the tip of an arc ─────────────────────────────
            function tipDot(radius, fraction, color) {
                if (fraction <= 0) return;
                var angle = -Math.PI / 2 + 2 * Math.PI * Math.min(fraction, 1.0);
                ctx.beginPath();
                ctx.arc(cx + Math.cos(angle) * radius,
                        cy + Math.sin(angle) * radius, 3, 0, 2 * Math.PI);
                ctx.fillStyle = color;
                ctx.fill();
            }

            // ── Helper: label badge at 12 o'clock of a ring ──────────────────
            function ringLabel(radius, label, ringColor) {
                var badgeR   = Math.max(3, radius * 0.028);
                var bx       = cx;
                var by       = cy - radius;
                // filled circle
                ctx.beginPath();
                ctx.arc(bx, by, badgeR, 0, 2 * Math.PI);
                ctx.fillStyle = ringColor;
                ctx.fill();
                // letter
                var fontSize = Math.max(5, badgeR * 1.1);
                ctx.font         = "bold " + fontSize + "px sans-serif";
                ctx.fillStyle    = "#ffffff";
                ctx.textAlign    = "center";
                ctx.textBaseline = "middle";
                ctx.fillText(label, bx, by);
            }

            // ── Outer ring: full-day progress ─────────────────────────────────
            // Track
            track(r, "#333333", 10);
            // Arc: grows from top as day passes
            var dayFrac = appState.dayProgress;
            ctx.beginPath();
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * dayFrac, false);
            ctx.lineWidth   = 10;
            ctx.strokeStyle = "#ff4444";
            ctx.stroke();

            // ── Middle ring: recurring event countdown (light blue) ────────────
            var rRecurring = r - 14;
            track(rRecurring, "#1a2a33", 7);
            var secsToRecurring = appState.secondsToNextRecurringEvent();
            if (secsToRecurring >= 0) {
                var recurFrac = Math.min(secsToRecurring / 86400.0, 1.0);
                countdownArc(rRecurring, recurFrac, "#2288cc", 6);
                tipDot(rRecurring, recurFrac, "#55bbff");
            }
            ringLabel(rRecurring, "R", "#2288cc");

            // ── Next ring: timed event countdown (non-recurring, green) ────────
            var rEvent = r - 28;
            track(rEvent, "#222222", 7);
            var secsToEvent = appState.secondsToNextEventTarget();
            if (secsToEvent >= 0) {
                // fraction of 24 h remaining until event (capped at 1.0)
                var eventFrac = Math.min(secsToEvent / 86400.0, 1.0);
                countdownArc(rEvent, eventFrac, "#009900", 6);
                tipDot(rEvent, eventFrac, "#00cc00");
            }
            ringLabel(rEvent, "E", "#009900");

            // ── Inner ring: alarm countdown ───────────────────────────────────
            var rAlarm = r - 42;
            track(rAlarm, "#1a1a1a", 6);
            if (appState.alarmEnabled) {
                var secsToAlarm = appState.secondsToNextAlarm();
                if (secsToAlarm >= 0) {
                    var alarmFrac = Math.min(secsToAlarm / 86400.0, 1.0);
                    countdownArc(rAlarm, alarmFrac, "#ffaa22", 5);
                    tipDot(rAlarm, alarmFrac, "#ffcc66");
                }
            }
            ringLabel(rAlarm, "A", "#ffaa22");
        }
    }

    // ── Centre clock text ─────────────────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4
        width: root.ringSize * 0.85

        Text {
            visible: !appState.use24HourClock
            text:    appState.now.getHours() < 12 ? "AM" : "PM"
            color:   "#ff4444"
            font.pixelSize: Math.max(34, root.ringSize * 0.18 * root.innerScale)
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: appState.use24HourClock
                  ? Qt.formatTime(appState.now, "hh:mm:ss")
                  : Qt.formatTime(appState.now, "h:mm:ss")
            color:   "#ff4444"
            font.pixelSize: Math.max(26, root.ringSize * 0.23 * root.innerScale)
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text:  Qt.formatDate(appState.now, "dddd, MMMM d yyyy")
            color: "#eeeeee"
            font.pixelSize: Math.max(12, root.ringSize * 0.09 * root.innerScale)
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text:  appState.alarmCountdownString()
            color: "#999999"
            font.pixelSize: Math.max(10, root.ringSize * 0.07 * root.innerScale)
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text:    appState.alarmEnabled ? ("Recurring: " + appState.alarmWeekdaysLabel()) : ""
            color:   "#666666"
            font.pixelSize: Math.max(10, root.ringSize * 0.040 * root.innerScale)
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
