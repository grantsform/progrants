// TodoStore.qml — independent todo list, persisted to todos.json.
// Todos are simple recurring daily checklist items with no event/date logic.
import QtQuick
import Quickshell.Io

QtObject {
    id: store

    // ── Public state ──────────────────────────────────────────────────────────
    property var   todos:        []
    property int   todoRevision: 0
    property ListModel todoModel: ListModel {}

    // ── Paths (set by AppState) ───────────────────────────────────────────────
    property string todosFilePath: ""
    property string storageDir:    ""

    // ── Dirty flags ───────────────────────────────────────────────────────────
    property bool updatingFromDisk: false
    property bool writing:          false

    // ── Id generator ─────────────────────────────────────────────────────────

    function _makeId(title) {
        var base = (title || "") + "|" + Date.now().toString() + "|" + Math.random().toString();
        var h = 0;
        for (var i = 0; i < base.length; i++)
            h = (Math.imul(31, h) + base.charCodeAt(i)) >>> 0;
        return "todo-" + h.toString(16);
    }

    // ── Refresh model from array ──────────────────────────────────────────────

    function refresh(now) {
        var todayStr = Qt.formatDate(now || new Date(), "yyyy-MM-dd");
        store.todoModel.clear();
        for (var i = 0; i < store.todos.length; i++) {
            var t = store.todos[i];
            var copy = {
                todoId:    t.todoId    || "",
                title:     t.title    || "",
                comment:   t.comment  || "",
                doneToday: (t.doneDates || []).indexOf(todayStr) >= 0
            };
            store.todoModel.append(copy);
        }
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    function add(title, comment) {
        if (!title || !title.trim()) return;
        var item = {
            todoId:    store._makeId(title),
            title:     title.trim(),
            comment:   (comment || "").trim(),
            doneDates: []
        };
        store.todos.push(item);
        store.todoRevision += 1;
        store.refresh();
        store.saveToFile();
    }

    function update(todoId, title, comment) {
        for (var i = 0; i < store.todos.length; i++) {
            if (store.todos[i].todoId === todoId) {
                store.todos[i].title   = (title   || "").trim();
                store.todos[i].comment = (comment || "").trim();
                break;
            }
        }
        store.todoRevision += 1;
        store.refresh();
        store.saveToFile();
    }

    function remove(todoId) {
        store.todos = store.todos.filter(function(t) { return t.todoId !== todoId; });
        store.todoRevision += 1;
        store.refresh();
        store.saveToFile();
    }

    function toggleDone(todoId, dateStr) {
        for (var i = 0; i < store.todos.length; i++) {
            if (store.todos[i].todoId !== todoId) continue;
            var dates = store.todos[i].doneDates ? store.todos[i].doneDates.slice() : [];
            var idx = dates.indexOf(dateStr);
            if (idx >= 0) dates.splice(idx, 1);
            else          dates.push(dateStr);
            store.todos[i].doneDates = dates;
            break;
        }
        store.todoRevision += 1;
        store.refresh();
        store.saveToFile();
    }

    function isTodoDoneOnDate(todoId, dateStr) {
        for (var i = 0; i < store.todos.length; i++) {
            if (store.todos[i].todoId === todoId)
                return (store.todos[i].doneDates || []).indexOf(dateStr) >= 0;
        }
        return false;
    }

    function readFromFile() {
        if (!store.todosFilePath || store.todosFilePath === "") return;
        if (store.writing) return;
        store.updatingFromDisk = true;
        var text = "";
        if (todosFileView.loaded) {
            text = (typeof todosFileView.text === "function")
                   ? (function() { try { return todosFileView.text(); } catch(e) { return ""; } })()
                   : todosFileView.text;
        }
        if (!todosFileView.loaded || !text) {
            store.todos = [];
            store.todoRevision += 1;
            store.refresh();
            store.updatingFromDisk = false;
            return;
        }
        try {
            var parsed = JSON.parse(text.trim());
            var arr = (parsed instanceof Array) ? parsed
                    : (parsed && parsed.todos instanceof Array) ? parsed.todos : null;
            store.todos = arr || [];
            for (var i = 0; i < store.todos.length; i++) {
                if (!store.todos[i].doneDates) store.todos[i].doneDates = [];
                if (!store.todos[i].todoId)    store.todos[i].todoId    = store._makeId(store.todos[i].title || "");
            }
        } catch(e) {
            console.warn("Failed to parse todos.json", e);
            store.todos = [];
        }
        store.todoRevision += 1;
        store.refresh();
        store.updatingFromDisk = false;
    }

    function saveToFile() {
        if (!store.todosFilePath || store.todosFilePath === "" || store.updatingFromDisk) return;
        try {
            _ensureDir.exec({ command: ["mkdir", "-p", store.storageDir] });
            store.writing = true;
            todosFileView.setText(JSON.stringify(store.todos, null, 2));
            try { todosFileView.waitForJob(); } catch(e) { console.warn("waitForJob failed", e); }
        } catch(e) {
            console.warn("Failed to save todos.json", e);
            store.writing = false;
        }
    }

    // ── Internal objects ──────────────────────────────────────────────────────

    property Process _ensureDir: Process { id: _todoEnsureDir }

    property FileView _fileView: FileView {
        id: todosFileView
        path: store.todosFilePath !== "" ? ("file://" + store.todosFilePath) : ""
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
        onLoaded: store.readFromFile()
    }

    property Timer _reloadTimer: Timer {
        id: _reloadTimer
        interval: 300
        repeat:   false
        onTriggered: todosFileView.reload()
    }
}
