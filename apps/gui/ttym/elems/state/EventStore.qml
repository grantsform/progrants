// EventStore.qml — events array, ListModel, CRUD helpers, file persistence.
import QtQuick
import Quickshell.Io

QtObject {
    id: store

    // ── Public state ──────────────────────────────────────────────────────────
    property var    events:        []
    property int    eventsRevision: 0
    property ListModel eventModel:          ListModel {}
    property ListModel allDayModel:         ListModel {}
    property ListModel recurringTodayModel: ListModel {}

    // ── Paths (set by AppState) ───────────────────────────────────────────────
    property string eventsFilePath: ""
    property string storageDir:     ""

    // ── Dirty flags ───────────────────────────────────────────────────────────
    property bool updatingFromDisk: false
    property bool writing:          false

    // ── Signals ──────────────────────────────────────────────────────────────
    signal eventsRefreshed()
    signal requestRepaintRing()
    signal eventAlertTriggered(var ev)
    signal eventAlertDismissed(string eventId)

    // Track which event IDs have already fired an alert this session
    property var firedAlerts: ({})

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _makeId(title, date, time) {
        // Stable, human-readable id derived from the event's natural key.
        var base = (title || "") + "|" + (date || "") + "|" + (time || "");
        var h = 0;
        for (var i = 0; i < base.length; i++)
            h = (Math.imul(31, h) + base.charCodeAt(i)) >>> 0;
        return "ev-" + h.toString(16);
    }

    function _normalise(ev) {
        // Derive day from date if present; generate eventId from natural key.
        if (ev.date) {
            var p = ev.date.split("-");
            if (p.length === 3) ev.day = parseInt(p[2], 10);
        }
        var t = (ev.allDay || !ev.time || ev.time === "All Day") ? "" : (ev.time || "");
        ev.eventId = _makeId(ev.title, ev.date, t);
        // Ensure hidden property is always defined
        if (ev.hidden === undefined) ev.hidden = false;
        
        // Ensure recurring properties exist
        if (ev.recurring === undefined) ev.recurring = false;
        if (ev.recurringWeeks === undefined) ev.recurringWeeks = 1;
        if (ev.recurringDays === undefined) ev.recurringDays = [];
        if (ev.recurringEndDate === undefined) ev.recurringEndDate = "";
        if (ev.isRecurringInstance === undefined) ev.isRecurringInstance = false;
        if (ev.originalEventId === undefined) ev.originalEventId = "";
        if (ev.alertSilent === undefined) ev.alertSilent = false;
        if (ev.alertSound  === undefined) ev.alertSound  = "";
        if (ev.alertAutoTimeout    === undefined) ev.alertAutoTimeout    = true;
        if (ev.alertTimeoutMinutes === undefined) ev.alertTimeoutMinutes = 5.0;
        if (ev.endTime === undefined) ev.endTime = "";
        
        return ev;
    }

    onEventsRevisionChanged: {
        if (!store.updatingFromDisk) store.saveToFile();
    }

    // ── File I/O ──────────────────────────────────────────────────────────────

    function readFromFile() {
        if (!store.eventsFilePath || store.eventsFilePath === "") return;
        if (store.writing) return;
        store.updatingFromDisk = true;
        var text = "";
        if (eventsFileView.loaded) {
            text = (typeof eventsFileView.text === "function")
                   ? (function() { try { return eventsFileView.text(); } catch(e) { return ""; } })()
                   : eventsFileView.text;
        }
        if (!eventsFileView.loaded || !text) {
            store.events = [];
            store.eventsRevision += 1;
            store.refresh();
            store.updatingFromDisk = false;
            return;
        }
        var raw = text;
        if (raw.trim().startsWith("[") && !raw.trim().endsWith("]")) raw = raw.trim() + "]";
        try {
            var parsed = JSON.parse(raw);
            var arr = (parsed instanceof Array) ? parsed
                    : (parsed && parsed.events instanceof Array) ? parsed.events : null;
            if (arr) {
                for (var i = 0; i < arr.length; ++i)
                    store._normalise(arr[i]);
                store.events = arr;
                // If any event was dismissed externally (file change), close its alert
                for (var j = 0; j < arr.length; ++j) {
                    var ev = arr[j];
                    if (ev.dismissed && ev.alert && ev.eventId && store.firedAlerts[ev.eventId]) {
                        store.eventAlertDismissed(ev.eventId);
                    }
                }
            } else {
                store.events = [];
            }
            store.requestRepaintRing();
        } catch (e) {
            console.warn("Failed to parse events.json", e);
            if (store.events && store.events.length > 0) store.saveToFile();
            else eventsFileView.setText("[]");
            store.updatingFromDisk = false;
            return;
        }
        store.eventsRevision += 1;
        store.refresh();
        store.updatingFromDisk = false;
    }

    function saveToFile() {
        if (!store.eventsFilePath || store.eventsFilePath === "" || store.updatingFromDisk) return;
        try {
            _ensureDir.exec({ command: ["mkdir", "-p", store.storageDir] });
            var clean = store.events.map(function(ev) {
                var copy = {};
                for (var k in ev) {
                    if (!Object.prototype.hasOwnProperty.call(ev, k)) continue;
                    if (k === '_timeKey' || k === '_targetTime' || k === 'day' || k === 'eventId') continue;
                    copy[k] = ev[k];
                }
                return copy;
            });
            store.writing = true;
            eventsFileView.setText(JSON.stringify(clean, null, 2));
            try { eventsFileView.waitForJob(); } catch(e) { console.warn("waitForJob failed", e); }
        } catch(e) {
            console.warn("Failed to save events.json", e);
            store.writing = false;
        }
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    function add(title, time, allDay, month, year, day, comment, alert, recurring, recurringWeeks, recurringDays, recurringEndDate, alertSilent, alertSound, alertAutoTimeout, alertTimeoutMinutes, endTime) {
        if (!title || !month || !year || !day) return;
        var date = Qt.formatDate(new Date(year, month - 1, day), "yyyy-MM-dd");
        var item = {
            title:   title,
            date:    date,
            time:    allDay ? "All Day" : time,
            endTime: (!allDay && endTime) ? endTime : "",
            allDay:  !!allDay,
            comment: (comment && comment.toString().trim() !== "" ? comment.toString() : ""),
            alert:   !!alert,
            alertSilent: !!alertSilent,
            alertSound:  alertSound || "",
            alertAutoTimeout:    (alertAutoTimeout    !== undefined && alertAutoTimeout    !== null) ? !!alertAutoTimeout    : true,
            alertTimeoutMinutes: (alertTimeoutMinutes !== undefined && alertTimeoutMinutes !== null) ? alertTimeoutMinutes   : 5,
            recurring: !!recurring,
            recurringWeeks: recurringWeeks || 1,
            recurringDays: recurringDays || [],
            recurringEndDate: recurringEndDate || ""
        };
        store._normalise(item);
        store.events.push(item);
        store.eventsRevision += 1;
        store.refresh();
        store.saveToFile();
    }

    function update(eventId, title, time, allDay, month, year, day, comment, alert, recurring, recurringWeeks, recurringDays, recurringEndDate, alertSilent, alertSound, alertAutoTimeout, alertTimeoutMinutes, endTime) {
        if (!eventId) return;
        var date    = Qt.formatDate(new Date(year, month - 1, day), "yyyy-MM-dd");
        var oldComment = "";
        var oldEndTime = "";
        var oldAlert   = false;
        var oldAlertSilent = false;
        var oldAlertSound  = "";
        var oldAlertAutoTimeout    = true;
        var oldAlertTimeoutMinutes = 5;
        var oldRecurring = false;
        var oldRecurringWeeks = 1;
        var oldRecurringDays = [];
        var oldRecurringEndDate = "";
        for (var i = 0; i < store.events.length; ++i) {
            if (store.events[i].eventId !== eventId) continue;
            oldComment = store.events[i].comment || "";
            oldEndTime = store.events[i].endTime  || "";
            oldAlert   = !!store.events[i].alert;
            oldAlertSilent = !!store.events[i].alertSilent;
            oldAlertSound  = store.events[i].alertSound || "";
            oldAlertAutoTimeout    = (store.events[i].alertAutoTimeout    !== undefined) ? !!store.events[i].alertAutoTimeout    : true;
            oldAlertTimeoutMinutes = (store.events[i].alertTimeoutMinutes !== undefined) ? store.events[i].alertTimeoutMinutes   : 5;
            oldRecurring = !!store.events[i].recurring;
            oldRecurringWeeks = store.events[i].recurringWeeks || 1;
            oldRecurringDays = store.events[i].recurringDays || [];
            oldRecurringEndDate = store.events[i].recurringEndDate || "";
            var updated = {
                title:   title,
                date:    date,
                time:    allDay ? "All Day" : time,
                endTime: (endTime !== undefined && endTime !== null ? endTime : oldEndTime),
                allDay:  allDay,
                comment: (comment !== undefined && comment !== null ? comment : oldComment),
                alert:   (alert   !== undefined && alert   !== null ? !!alert   : oldAlert),
                alertSilent: (alertSilent !== undefined && alertSilent !== null ? !!alertSilent : oldAlertSilent),
                alertSound:  (alertSound  !== undefined && alertSound  !== null ? alertSound    : oldAlertSound),
                alertAutoTimeout:    (alertAutoTimeout    !== undefined && alertAutoTimeout    !== null ? !!alertAutoTimeout    : oldAlertAutoTimeout),
                alertTimeoutMinutes: (alertTimeoutMinutes !== undefined && alertTimeoutMinutes !== null ? alertTimeoutMinutes   : oldAlertTimeoutMinutes),
                recurring: (recurring !== undefined && recurring !== null ? !!recurring : oldRecurring),
                recurringWeeks: (recurringWeeks !== undefined && recurringWeeks !== null ? recurringWeeks : oldRecurringWeeks),
                recurringDays: (recurringDays !== undefined && recurringDays !== null ? recurringDays : oldRecurringDays),
                recurringEndDate: (recurringEndDate !== undefined && recurringEndDate !== null ? recurringEndDate : oldRecurringEndDate)
            };
            store._normalise(updated);
            store.events[i] = updated;
            break;
        }
        store.eventsRevision += 1;
        store.refresh();
        store.saveToFile();
    }

    function remove(eventId) {
        if (!eventId) return;
        var keep = store.events.filter(function(ev) { return ev.eventId !== eventId; });
        if (keep.length === store.events.length) return;
        store.events = keep;
        store.eventsRevision += 1;
        store.refresh();
    }

    function hideEvent(eventId) {
        if (!eventId) return;
        for (var i = 0; i < store.events.length; i++) {
            if (store.events[i].eventId === eventId) {
                store.events[i].hidden = true;
                break;
            }
        }
        store.eventsRevision += 1;
        store.refresh();
        store.saveToFile();
    }

    function unhideEvent(eventId) {
        if (!eventId) return;
        for (var i = 0; i < store.events.length; i++) {
            if (store.events[i].eventId === eventId) {
                store.events[i].hidden = false;
                break;
            }
        }
        store.eventsRevision += 1;
        store.refresh();
        store.saveToFile();
    }

    function toggleAllDayDone(eventId) {
        if (!eventId) return;
        for (var i = 0; i < store.events.length; i++) {
            if (store.events[i].eventId === eventId) {
                store.events[i].doneToday = !store.events[i].doneToday;
                break;
            }
        }
        store.refresh();
        store.saveToFile();
        store.eventsRevision += 1;
    }

    function checkEventAlerts(now) {
        // Fire an alert for any event that has alert=true, is not past,
        // and whose time has just been reached (within a 2-second window).
        var nowMs = now.getTime();
        var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        var todayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
        
        for (var i = 0; i < store.events.length; i++) {
            var ev = store.events[i];
            if (!ev.alert || ev.hidden) continue;
            
            var eventsToCheck = [];
            
            if (ev.recurring && !ev.isRecurringInstance) {
                // Generate recurring instances for today
                var instances = store._generateRecurringInstances(ev, todayStart, todayEnd);
                eventsToCheck = eventsToCheck.concat(instances);
            } else if (!ev.recurring) {
                // Regular events
                eventsToCheck.push(ev);
            }
            
            // Check alerts for all events (regular and recurring instances)
            for (var j = 0; j < eventsToCheck.length; j++) {
                var checkEv = eventsToCheck[j];
                var id = checkEv.eventId || "";
                if (!id) continue;
                
                // If dismissed in JSON, ensure firedAlerts tracks it and never re-fire
                if (checkEv.dismissed) { store.firedAlerts[id] = true; continue; }
                if (store.firedAlerts[id]) continue;
                
                // Build target timestamp
                var p = (checkEv.date || "").split("-");
                if (p.length !== 3) continue;
                var y = parseInt(p[0], 10), m = parseInt(p[1], 10) - 1, d = parseInt(p[2], 10);
                var target;
                if (checkEv.allDay || !checkEv.time || checkEv.time === "All Day" || checkEv.time === "") {
                    target = new Date(y, m, d, 0, 0, 0).getTime();
                } else {
                    var t = checkEv.time.split(":");
                    target = new Date(y, m, d,
                        parseInt(t[0]||"0",10), parseInt(t[1]||"0",10), parseInt(t[2]||"0",10)).getTime();
                }
                // Trigger if we're within a 2-second window past the target
                var diff = nowMs - target;
                if (diff >= 0 && diff < 2000) {
                    store.firedAlerts[id] = true;
                    store.eventAlertTriggered(checkEv);
                }
            }
        }
    }

    function dismissEventAlert(eventId) {
        if (!eventId) return;
        for (var i = 0; i < store.events.length; i++) {
            if (store.events[i].eventId === eventId) {
                store.events[i].dismissed = true;
                break;
            }
        }
        store.firedAlerts[eventId] = true;
        // Save without triggering a reload loop
        store.saveToFile();
        store.eventAlertDismissed(eventId);
    }

    function _generateRecurringInstances(baseEvent, startDate, endDate) {
        // Generate instances of a recurring event within the date range
        var instances = [];
        if (!baseEvent.recurring || !baseEvent.recurringDays || baseEvent.recurringDays.length === 0) {
            return instances;
        }
        
        var baseDate = new Date(baseEvent.date);
        var currentDate = new Date(Math.max(baseDate.getTime(), startDate.getTime()));
        var finalDate = endDate;
        
        // If recurring has an end date, respect it
        if (baseEvent.recurringEndDate && baseEvent.recurringEndDate !== "") {
            var recurEndDate = new Date(baseEvent.recurringEndDate);
            if (recurEndDate < finalDate) finalDate = recurEndDate;
        }
        
        // Find the first occurrence on or after startDate
        var weekStart = new Date(currentDate);
        weekStart.setDate(weekStart.getDate() - weekStart.getDay()); // Get Sunday of current week
        
        while (currentDate <= finalDate) {
            // Check if this week should have the event (based on interval)
            var weeksSinceBase = Math.floor((currentDate.getTime() - baseDate.getTime()) / (7 * 24 * 60 * 60 * 1000));
            if (weeksSinceBase % baseEvent.recurringWeeks === 0) {
                // Generate instances for each selected day of this week
                for (var i = 0; i < baseEvent.recurringDays.length; i++) {
                    var dayOfWeek = baseEvent.recurringDays[i]; // 0=Sunday, 1=Monday, etc.
                    var instanceDate = new Date(weekStart);
                    instanceDate.setDate(weekStart.getDate() + dayOfWeek);
                    
                    if (instanceDate >= startDate && instanceDate <= finalDate && instanceDate >= baseDate) {
                        var instance = {
                            title: baseEvent.title,
                            date: Qt.formatDate(instanceDate, "yyyy-MM-dd"),
                            time: baseEvent.time,
                            endTime: baseEvent.endTime || "",
                            allDay: baseEvent.allDay,
                            comment: baseEvent.comment,
                            alert: baseEvent.alert,
                            isRecurringInstance: true,
                            originalEventId: baseEvent.eventId,
                            recurring: false // instances are not recurring themselves
                        };
                        store._normalise(instance);
                        instances.push(instance);
                    }
                }
            }
            
            // Move to next week
            currentDate.setDate(currentDate.getDate() + 7);
            weekStart.setDate(weekStart.getDate() + 7);
        }
        
        return instances;
    }

    // ── Query helpers ─────────────────────────────────────────────────────────

    function nextUpcoming(now, limit, excludeAllDay) {
        var list = [];
        var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        var endDate = new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000); // Look ahead 1 year
        
        // Add regular events
        for (var i = 0; i < store.events.length; i++) {
            var ev = store.events[i];
            if (ev.hidden) continue;
            
            // Handle excludeAllDay logic
            if (excludeAllDay === true) {
                // Exclude all all-day events
                if (ev.allDay || !ev.time || ev.time === "All Day" || ev.time === "") continue;
            } else if (excludeAllDay === "selective") {
                // Only exclude non-recurring all-day events
                if ((ev.allDay || !ev.time || ev.time === "All Day" || ev.time === "") && !ev.recurring) continue;
            }
            // If excludeAllDay is false, include all events
            
            // Handle recurring events
            if (ev.recurring && !ev.isRecurringInstance) {
                // Use todayStart so in-progress recurring instances from earlier today are included
                var recurStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
                var instances = store._generateRecurringInstances(ev, recurStart, endDate);
                for (var j = 0; j < instances.length; j++) {
                    var inst = instances[j];
                    // Apply excludeAllDay filter to instances too
                    if (excludeAllDay === true && (inst.allDay || !inst.time || inst.time === "All Day" || inst.time === "")) continue;
                    // For selective mode, recurring all-day instances are allowed (they pass through)
                    
                    var p = inst.date.split("-");
                    if (p.length !== 3) continue;
                    var y = parseInt(p[0], 10), m = parseInt(p[1], 10) - 1, d = parseInt(p[2], 10);
                    var t, target;
                    if (inst.allDay || !inst.time || inst.time === "All Day") {
                        t = target = new Date(y, m, d).getTime();
                    } else {
                        var tt = inst.time.split(":");
                        t = target = new Date(y, m, d, parseInt(tt[0]||"0",10), parseInt(tt[1]||"0",10), parseInt(tt[2]||"0",10)).getTime();
                    }
                    if (y === now.getFullYear() && m === now.getMonth() && d === now.getDate()) {
                        if (inst.allDay) t = new Date(y, m, d, 23, 59, 59).getTime();
                        else if (t < now.getTime()) {
                            // Check if in-progress (endTime in future)
                            if (inst.endTime && inst.endTime !== "") {
                                var ett = inst.endTime.split(":");
                                var endMs2 = new Date(y, m, d, parseInt(ett[0]||"0",10), parseInt(ett[1]||"0",10), parseInt(ett[2]||"0",10)).getTime();
                                if (endMs2 > now.getTime()) { t = endMs2; } else { continue; }
                            } else { continue; }
                        }
                    }
                    if (t >= todayStart) { inst._timeKey = t; inst._targetTime = target; list.push(inst); }
                }
            } else if (!ev.recurring) {
                // Regular non-recurring events
                var p = ev.date.split("-");
                if (p.length !== 3) continue;
                var y = parseInt(p[0], 10), m = parseInt(p[1], 10) - 1, d = parseInt(p[2], 10);
                var t, target;
                if (ev.allDay || !ev.time || ev.time === "All Day") {
                    t = target = new Date(y, m, d).getTime();
                } else {
                    var tt = ev.time.split(":");
                    t = target = new Date(y, m, d, parseInt(tt[0]||"0",10), parseInt(tt[1]||"0",10), parseInt(tt[2]||"0",10)).getTime();
                }
                if (y === now.getFullYear() && m === now.getMonth() && d === now.getDate()) {
                    if (ev.allDay) t = new Date(y, m, d, 23, 59, 59).getTime();
                    else if (t < now.getTime()) {
                        // Check if in-progress (endTime in future)
                        if (ev.endTime && ev.endTime !== "") {
                            var ett = ev.endTime.split(":");
                            var endMs2 = new Date(y, m, d, parseInt(ett[0]||"0",10), parseInt(ett[1]||"0",10), parseInt(ett[2]||"0",10)).getTime();
                            if (endMs2 > now.getTime()) { t = endMs2; } else { continue; }
                        } else { continue; }
                    }
                }
                if (t >= todayStart) { ev._timeKey = t; ev._targetTime = target; list.push(ev); }
            }
        }
        list.sort(function(a, b) { return a._timeKey - b._timeKey; });
        return list.slice(0, limit || 7);
    }

    // Returns the ms-timestamp of the effective countdown target for the ring/pill:
    // – If we are currently inside an event window (past start AND endTime set AND before end)
    //   → count to endTime.
    // – Otherwise → count to nearest upcoming startTime (same as before).
    // Returns -1 when there is no relevant event.
    function nextEventTarget(now) {
        var nowMs = now.getTime();
        var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        var endLookAhead = new Date(nowMs + 365 * 24 * 60 * 60 * 1000);
        var best = -1;

        function _parseTimeMs(dateStr, timeStr) {
            var p = dateStr.split("-");
            if (p.length !== 3) return -1;
            var y = parseInt(p[0], 10), mo = parseInt(p[1], 10) - 1, d = parseInt(p[2], 10);
            if (!timeStr || timeStr === "All Day" || timeStr === "") {
                return new Date(y, mo, d).getTime();
            }
            var t = timeStr.split(":");
            return new Date(y, mo, d,
                parseInt(t[0]||"0",10), parseInt(t[1]||"0",10), parseInt(t[2]||"0",10)).getTime();
        }

        // Helper: evaluate a single concrete event object
        function _evalEv(ev) {
            if (ev.hidden) return;
            if (ev.allDay || !ev.time || ev.time === "All Day" || ev.time === "") return;
            var startMs = _parseTimeMs(ev.date || "", ev.time);
            if (startMs < 0) return;
            // Check if inside window
            if (ev.endTime && ev.endTime !== "") {
                var endMs = _parseTimeMs(ev.date || "", ev.endTime);
                if (endMs > nowMs && startMs <= nowMs) {
                    // We are inside — target is endMs
                    if (best < 0 || endMs < best) best = endMs;
                    return;
                }
            }
            // Not inside window: use startMs if in the future
            if (startMs >= nowMs) {
                if (best < 0 || startMs < best) best = startMs;
            }
        }

        for (var i = 0; i < store.events.length; i++) {
            var ev = store.events[i];
            if (ev.hidden) continue;
            // nextEventTarget: non-recurring timed events only
            if (!ev.recurring) {
                _evalEv(ev);
            }
        }
        return best;
    }

    // Returns the ms-timestamp of the effective countdown target for recurring events only.
    // Same logic as nextEventTarget but restricted to recurring event instances.
    function nextRecurringEventTarget(now) {
        var nowMs = now.getTime();
        var endLookAhead = new Date(nowMs + 365 * 24 * 60 * 60 * 1000);
        var best = -1;

        function _parseTimeMs(dateStr, timeStr) {
            var p = dateStr.split("-");
            if (p.length !== 3) return -1;
            var y = parseInt(p[0], 10), mo = parseInt(p[1], 10) - 1, d = parseInt(p[2], 10);
            if (!timeStr || timeStr === "All Day" || timeStr === "") {
                return new Date(y, mo, d).getTime();
            }
            var t = timeStr.split(":");
            return new Date(y, mo, d,
                parseInt(t[0]||"0",10), parseInt(t[1]||"0",10), parseInt(t[2]||"0",10)).getTime();
        }

        function _evalEv(ev) {
            if (ev.hidden) return;
            if (ev.allDay || !ev.time || ev.time === "All Day" || ev.time === "") return;
            var startMs = _parseTimeMs(ev.date || "", ev.time);
            if (startMs < 0) return;
            if (ev.endTime && ev.endTime !== "") {
                var endMs = _parseTimeMs(ev.date || "", ev.endTime);
                if (endMs > nowMs && startMs <= nowMs) {
                    if (best < 0 || endMs < best) best = endMs;
                    return;
                }
            }
            if (startMs >= nowMs) {
                if (best < 0 || startMs < best) best = startMs;
            }
        }

        for (var i = 0; i < store.events.length; i++) {
            var ev = store.events[i];
            if (ev.hidden) continue;
            if (ev.recurring && !ev.isRecurringInstance) {
                var todayStartDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
                var instances = store._generateRecurringInstances(ev, todayStartDate, endLookAhead);
                for (var j = 0; j < instances.length; j++) _evalEv(instances[j]);
            }
        }
        return best;
    }

    function countOnDay(viewYear, viewMonth, day, daysInMonth) {
        if (!day || day < 1 || day > daysInMonth) return 0;
        var target = Qt.formatDate(new Date(viewYear, viewMonth, day), "yyyy-MM-dd");
        var targetDate = new Date(viewYear, viewMonth, day);
        var n = 0;
        
        for (var i = 0; i < store.events.length; ++i) {
            var ev = store.events[i];
            if (ev.hidden) continue;
            
            if (ev.recurring && !ev.isRecurringInstance) {
                // Check if this recurring event has an instance on this day
                var instances = store._generateRecurringInstances(ev, targetDate, targetDate);
                n += instances.length;
            } else if (!ev.recurring && ev.date === target) {
                n++;
            }
        }
        return n;
    }

    function eventsOnDay(viewYear, viewMonth, day) {
        // Get all events (including recurring instances) for a specific day
        var target = Qt.formatDate(new Date(viewYear, viewMonth, day), "yyyy-MM-dd");
        var targetDate = new Date(viewYear, viewMonth, day);
        var dayEvents = [];
        
        for (var i = 0; i < store.events.length; ++i) {
            var ev = store.events[i];
            if (ev.hidden) continue;
            
            if (ev.recurring && !ev.isRecurringInstance) {
                // Add recurring instances for this day
                var instances = store._generateRecurringInstances(ev, targetDate, targetDate);
                dayEvents = dayEvents.concat(instances);
            } else if (!ev.recurring && ev.date === target) {
                // Add regular events
                dayEvents.push(ev);
            }
        }
        
        return dayEvents;
    }

    function getEventTypesOnDay(viewYear, viewMonth, day) {
        // Returns an object indicating what types of events exist on this day
        if (!day || day < 1) return { hasRegular: false, hasAllDayNonRecurring: false, hasRecurring: false };
        
        var dayEvents = store.eventsOnDay(viewYear, viewMonth, day);
        var hasRegular = false;
        var hasAllDayNonRecurring = false;
        var hasRecurring = false;
        
        for (var i = 0; i < dayEvents.length; i++) {
            var ev = dayEvents[i];
            var isAllDay = (ev.allDay || !ev.time || ev.time === "All Day" || ev.time === "");
            
            if (ev.isRecurringInstance) {
                hasRecurring = true;
            } else if (ev.recurring) {
                // This shouldn't happen since we generate instances, but just in case
                hasRecurring = true;
            } else if (isAllDay) {
                hasAllDayNonRecurring = true;
            } else {
                hasRegular = true;
            }
        }
        
        return {
            hasRegular: hasRegular,
            hasAllDayNonRecurring: hasAllDayNonRecurring,
            hasRecurring: hasRecurring
        };
    }

    function timeLeftString(ev, now) {
        if (!ev || !ev.date) return "";
        var datePart = ev.date, timePart = "23:59:59";
        if (ev._targetTime) {
            var td = new Date(ev._targetTime);
            if (!isNaN(td.getTime())) {
                datePart = td.getFullYear() + '-' + (td.getMonth()+1).toString().padStart(2,'0') + '-' + td.getDate().toString().padStart(2,'0');
                timePart = td.getHours().toString().padStart(2,'0') + ':' + td.getMinutes().toString().padStart(2,'0') + ':' + td.getSeconds().toString().padStart(2,'0');
            }
        } else if (ev.time && ev.time !== "All Day") {
            timePart = ev.time;
        }
        if (timePart.split(":").length === 2) timePart += ":00";
        try {
            var target = new Date(datePart + "T" + timePart);
            if (isNaN(target.getTime())) target = new Date(datePart + " " + timePart);
            var diff = target.getTime() - now.getTime();
            if (diff <= 0) return "00:00:00";
            var h = Math.floor(diff / 3600000), mn = Math.floor((diff % 3600000) / 60000), s = Math.floor((diff % 60000) / 1000);
            return h.toString().padStart(2,'0') + ":" + mn.toString().padStart(2,'0') + ":" + s.toString().padStart(2,'0');
        } catch(e) { return ""; }
    }

    function refresh(now) {
        var today = now || new Date();
        var todayStr = Qt.formatDate(today, "yyyy-MM-dd");
        var todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
        var todayEnd = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 23, 59, 59, 999);

        // ─ All-day events for today (non-recurring only) ──────────────────
        store.allDayModel.clear();
        for (var a = 0; a < store.events.length; a++) {
            var aev = store.events[a];
            if (aev.hidden || aev.recurring) continue;
            if ((aev.allDay || !aev.time || aev.time === "All Day" || aev.time === "") && aev.date === todayStr) {
                var acopy = Object.assign({}, aev);
                if (acopy.comment == null) acopy.comment = "";
                store.allDayModel.append(acopy);
            }
        }

        // ─ Recurring instances for today (skip past timed events) ────────────
        store.recurringTodayModel.clear();
        var nowSeconds = today.getHours() * 3600 + today.getMinutes() * 60 + today.getSeconds();
        var allRecurringToday = [];
        for (var r = 0; r < store.events.length; r++) {
            var rev = store.events[r];
            if (rev.hidden || !rev.recurring || rev.isRecurringInstance) continue;
            var rInstances = store._generateRecurringInstances(rev, todayStart, todayEnd);
            for (var ri = 0; ri < rInstances.length; ri++) {
                var rcopy = Object.assign({}, rInstances[ri]);
                if (rcopy.comment == null) rcopy.comment = "";
                // Compute a sort key: all-day events sort last (Infinity)
                var rTime = rcopy.time;
                if (!rTime || rTime === "" || rTime === "All Day") {
                    rcopy._sortKey = Infinity;
                } else {
                    var rtp = rTime.split(":");
                    rcopy._sortKey = parseInt(rtp[0]||"0",10) * 3600 + parseInt(rtp[1]||"0",10) * 60 + parseInt(rtp[2]||"0",10);
                    // Skip timed events that have already passed
                    if (rcopy._sortKey < nowSeconds) continue;
                }
                allRecurringToday.push(rcopy);
            }
        }
        allRecurringToday.sort(function(a, b) { return a._sortKey - b._sortKey; });
        for (var rs = 0; rs < allRecurringToday.length; rs++) {
            store.recurringTodayModel.append(allRecurringToday[rs]);
        }

        // ─ Upcoming events: timed + recurring all-day instances ────────────
        store.eventModel.clear();
        var upcoming = store.nextUpcoming(today, 7);
        for (var i = 0; i < upcoming.length; i++) {
            var ev = upcoming[i];
            var isAllDay = (ev.allDay || !ev.time || ev.time === "All Day" || ev.time === "");
            // Non-recurring all-day live in allDayModel; recurring events live in recurringTodayModel
            if (isAllDay && !ev.isRecurringInstance) continue;
            if (ev.isRecurringInstance || ev.recurring) continue;
            var item = Object.assign({}, ev);
            if (item.comment == null) item.comment = "";
            store.eventModel.append(item);
        }
        store.eventsRefreshed();
    }

    // ── Internal objects ──────────────────────────────────────────────────────

    property Process _ensureDir: Process { id: _ensureDir }

    property FileView _fileView: FileView {
        id: eventsFileView
        path: store.eventsFilePath !== "" ? ("file://" + store.eventsFilePath) : ""
        preload: true
        blockWrites: false
        atomicWrites: true
        watchChanges: true
        onFileChanged: {
            if (store.writing) {
                store.writing = false;
            } else {
                _reloadTimer.restart();
            }
        }
        onLoaded:     store.readFromFile()
        onLoadFailed: function(e) { console.log("events.json load failed", e); }
    }

    property Timer _reloadTimer: Timer {
        id: _reloadTimer
        interval: 150; repeat: false
        onTriggered: eventsFileView.reload()
    }
}
