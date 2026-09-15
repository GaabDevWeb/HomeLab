import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Command Palette — ações do rice/HomeLab (NÃO apps).
// SUPER+SHIFT+Space → IPC pill commands. Separada do Launcher (SUPER+A/D).
FocusScope {
    id: view
    property var sys

    property string query: ""
    property int index: 0

    implicitHeight: col.implicitHeight

    // Ações reais → handlers existentes em shell.qml / Homelab / Hyprland.
    readonly property var catalog: [
        { id: "cal",           cat: "Calendar",  name: "Open Calendar",         keys: "cal calendar today events month day deadline" },
        { id: "cal-today",     cat: "Calendar",  name: "Calendar Today",        keys: "today agora agora hoje" },
        { id: "cal-next",      cat: "Calendar",  name: "Next Event",            keys: "next event próximo evento" },
        { id: "audio",         cat: "Sound",     name: "Open Sound",            keys: "sound audio volume mixer equalizer eq" },
        { id: "clip",          cat: "Clipboard", name: "Open Clipboard",        keys: "clipboard clip copy paste history" },
        { id: "sysload",       cat: "System",    name: "Open System Monitor",   keys: "system sysload cpu ram gpu processes monitor load" },
        { id: "sys-history",   cat: "System",    name: "System History",        keys: "history metrics 5m 15m 30m sparkline" },
        { id: "sys-happening", cat: "System",    name: "What's Happening",      keys: "happening now activity what" },
        { id: "homelab",       cat: "System",    name: "Open Homelab",          keys: "homelab hub console" },
        { id: "net",           cat: "Network",   name: "Open Network",          keys: "network net wifi ip gateway dns latency" },
        { id: "wifi",          cat: "Network",   name: "Open Wi-Fi",            keys: "wifi wireless ssid" },
        { id: "docker",        cat: "Docker",    name: "Open Docker",           keys: "docker containers podman" },
        { id: "services",      cat: "Services",  name: "Open Services",         keys: "services systemd background run" },
        { id: "projects",      cat: "Projects",  name: "Open Projects",         keys: "projects project git shell code" },
        { id: "bonsai",        cat: "Bonsai",    name: "Ask Bonsai",            keys: "bonsai agent ai ask thinking" },
        { id: "ws1",           cat: "Workspaces", name: "Go to Workspace 1",    keys: "workspace 1 ws1 desk" },
        { id: "ws2",           cat: "Workspaces", name: "Go to Workspace 2",    keys: "workspace 2 ws2 desk" },
        { id: "ws3",           cat: "Workspaces", name: "Go to Workspace 3",    keys: "workspace 3 ws3 desk" },
        { id: "ws4",           cat: "Workspaces", name: "Go to Workspace 4",    keys: "workspace 4 ws4 desk" },
        { id: "ws5",           cat: "Workspaces", name: "Go to Workspace 5",    keys: "workspace 5 ws5 desk" },
        { id: "controls",      cat: "System",    name: "Open Control Center",   keys: "controls panel main tiles" },
        { id: "notif",         cat: "System",    name: "Open Notifications",   keys: "notifications notif dnd" },
        { id: "shortcuts",     cat: "System",    name: "Show Shortcuts",        keys: "shortcuts keys binds help ?" }
    ]

    readonly property var filtered: {
        var q = String(view.query || "").trim().toLowerCase()
        var out = []
        for (var i = 0; i < view.catalog.length; i++) {
            var a = view.catalog[i]
            var hay = (a.name + " " + a.cat + " " + a.keys).toLowerCase()
            var score = 0
            if (!q.length) {
                score = 1
            } else if (a.name.toLowerCase().indexOf(q) === 0) {
                score = 100 - i
            } else if (a.name.toLowerCase().indexOf(q) >= 0) {
                score = 80 - i
            } else if (a.cat.toLowerCase().indexOf(q) === 0) {
                score = 70 - i
            } else if (hay.indexOf(q) >= 0) {
                score = 50 - i
            } else {
                // token match
                var toks = q.split(/\s+/)
                var ok = true
                for (var t = 0; t < toks.length; t++) {
                    if (hay.indexOf(toks[t]) < 0) { ok = false; break }
                }
                if (ok) score = 40 - i
            }
            if (score > 0) out.push({ a: a, score: score })
        }
        out.sort(function (x, y) { return y.score - x.score })
        var rows = []
        for (var j = 0; j < out.length && j < 10; j++) rows.push(out[j].a)
        return rows
    }

    function clampIndex() {
        var n = view.filtered.length
        if (n <= 0) { view.index = 0; return }
        if (view.index < 0) view.index = 0
        if (view.index >= n) view.index = n - 1
    }

    function run(id) {
        id = String(id || "")
        var s = view.sys
        if (!s) return

        if (id === "cal") { s.togglePage("cal"); if (s.calRefresh) s.calRefresh(); return }
        if (id === "cal-today") {
            if (s.patchUiMemory) s.patchUiMemory({ calMode: "day", calJumpToday: true })
            s.togglePage("cal")
            if (s.calRefresh) s.calRefresh()
            return
        }
        if (id === "cal-next") {
            s.togglePage("cal")
            if (s.calRefresh) s.calRefresh()
            return
        }
        if (id === "audio") { s.togglePage("audio"); return }
        if (id === "clip") { s.togglePage("clip"); return }
        if (id === "sysload") {
            if (s.patchUiMemory) s.patchUiMemory({ sysloadTab: "current" })
            s.togglePage("sysload"); return
        }
        if (id === "sys-history") {
            if (s.patchUiMemory) s.patchUiMemory({ sysloadTab: "history" })
            s.togglePage("sysload"); return
        }
        if (id === "sys-happening") {
            if (s.patchUiMemory) s.patchUiMemory({ sysloadTab: "happening" })
            s.togglePage("sysload"); return
        }
        if (id === "homelab") { s.openHomelab("hub"); return }
        if (id === "net") { s.openHomelab("net"); return }
        if (id === "wifi") { s.togglePage("wifi"); if (s.refreshWifiList) s.refreshWifiList(); if (s.scanWifi) s.scanWifi(); return }
        if (id === "docker") { s.openHomelab("docker"); return }
        if (id === "services") { s.openHomelab("run"); return }
        if (id === "projects") { s.openHomelab("dev"); return }
        if (id === "bonsai") { s.togglePage("bonsai"); return }
        if (id === "ws1") { s.gotoWorkspace(1); s.collapse(); return }
        if (id === "ws2") { s.gotoWorkspace(2); s.collapse(); return }
        if (id === "ws3") { s.gotoWorkspace(3); s.collapse(); return }
        if (id === "ws4") { s.gotoWorkspace(4); s.collapse(); return }
        if (id === "ws5") { s.gotoWorkspace(5); s.collapse(); return }
        if (id === "controls") { s.togglePage("main"); return }
        if (id === "notif") { s.togglePage("notif"); return }
        if (id === "shortcuts") { s.toggleKeysWindow(); s.collapse(); return }
    }

    function activate() {
        view.clampIndex()
        var rows = view.filtered
        if (!rows.length) return
        view.run(rows[view.index].id)
    }

    onQueryChanged: { view.index = 0; view.clampIndex() }
    onFilteredChanged: view.clampIndex()

    FocusGrabber { target: input }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 9

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.06)
            border.color: input.activeFocus ? Qt.rgba(1, 1, 1, 0.22) : view.sys.colLine
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 9

                Text {
                    text: ">"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize; bold: true }
                }

                TextField {
                    id: input
                    focus: true
                    Layout.fillWidth: true
                    placeholderText: "type a command…"
                    color: view.sys.colFg
                    placeholderTextColor: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                    background: null
                    onTextEdited: view.query = text

                    Keys.onEscapePressed: view.sys.collapse()
                    Keys.onReturnPressed: view.activate()
                    Keys.onEnterPressed: view.activate()
                    Keys.onDownPressed: { view.index = Math.min(view.index + 1, Math.max(0, view.filtered.length - 1)) }
                    Keys.onUpPressed: { view.index = Math.max(view.index - 1, 0) }
                }

                Text {
                    text: "⌘⇧␣"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 9 }
                }
            }
        }

        Text {
            visible: view.filtered.length === 0
            text: "No matching commands."
            color: view.sys.colMuted
            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
            Layout.leftMargin: 4
        }

        Repeater {
            model: view.filtered
            delegate: Rectangle {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                height: 36
                radius: 10
                color: index === view.index
                       ? Qt.rgba(1, 1, 1, 0.12)
                       : (rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        text: modelData.cat.toUpperCase()
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 9; letterSpacing: 0.6 }
                        Layout.preferredWidth: 72
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        elide: Text.ElideRight
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                    }
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: view.index = index
                    onClicked: view.run(modelData.id)
                }
            }
        }
    }
}
