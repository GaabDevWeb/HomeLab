import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Gaab Homelab console — extends Panacea (Agents-style: script JSON → cards).
// Does NOT invent a new aesthetic: colFg/colMuted/colOn/colOk/colCrit, radius 14, Set*-like rows.
Item {
    id: view
    property var sys
    property string section: "hub"   // hub|sys|net|dev|run|logs|docker|ai|storage
    property string detail: ""       // selected service/container/project name
    property var hub: ({ sections: [] })
    property var payload: ({})
    property var logLines: []
    property bool loaded: false
    property string confirmAction: ""   // "stop:name" | "restart:name" | ""
    property string applyState: ""      // QUERYING | APPLYING | ""

    // Create-service form
    property bool creating: false
    property string formName: ""
    property string formDir: ""
    property string formCmd: ""
    property string formPort: ""
    // SYS process list: "cpu" | "mem"
    property string procSort: "cpu"
    property int procDetailPid: 0
    readonly property var procList: {
        // force rebind when sort/payload change
        var _s = view.procSort
        var _p = view.payload
        return view.sortedProcesses()
    }

    implicitHeight: col.implicitHeight

    readonly property string sh: view.sys.scriptDir + "/homelab.sh"

    // Background-terminal surface tokens (Panacea-native, not a new palette)
    readonly property int termRadius: 14
    readonly property int termPadX: 16
    readonly property int termPadY: 14
    readonly property int termGap: 10
    readonly property int termInnerGap: 6
    readonly property int termAccentW: 3
    readonly property int termLogPreviewMax: 1

    function goBack() {
        if (view.creating) { view.creating = false; return true }
        if (view.detail !== "") { view.detail = ""; view.refresh(); return true }
        if (view.section !== "hub") { view.section = "hub"; view.refresh(); return true }
        return false
    }

    function refresh() {
        view.loaded = false
        if (view.section === "hub") {
            pHub.running = false
            pHub.running = true
            return
        }
        var cmd = ["bash", view.sh, "sys"]
        if (view.section === "net") cmd = ["bash", view.sh, "net"]
        else if (view.section === "storage") cmd = ["bash", view.sh, "storage"]
        else if (view.section === "docker") cmd = ["bash", view.sh, "docker"]
        else if (view.section === "ai") cmd = ["bash", view.sh, "ai"]
        else if (view.section === "dev") cmd = ["bash", view.sh, "projects"]
        else if (view.section === "run") cmd = ["bash", view.sh, "services"]
        else if (view.section === "logs") cmd = ["bash", view.sh, "logs", view.detail || "system"]
        pSec.command = cmd
        pSec.running = false
        pSec.running = true
    }

    function openSection(id) {
        view.section = id
        view.detail = ""
        view.creating = false
        view.logLines = []
        view.refresh()
    }

    function runAction(argv) {
        view.applyState = "EXECUTING"
        pAct.command = ["bash", view.sh].concat(argv)
        pAct.running = false
        pAct.running = true
    }

    function askConfirm(kind, name) {
        view.confirmAction = kind + ":" + name
    }
    function clearConfirm() { view.confirmAction = "" }
    function doConfirm() {
        var parts = String(view.confirmAction || "").split(":")
        if (parts.length < 2) { view.clearConfirm(); return }
        var kind = parts[0]
        var name = parts.slice(1).join(":")
        view.clearConfirm()
        if (kind === "stop") view.runAction(["docker-action", "stop", name])
        else if (kind === "restart") view.runAction(["docker-action", "restart", name])
        else if (kind === "svc-stop") view.runAction(["service-stop", name])
        else if (kind === "svc-restart") view.runAction(["service-restart", name])
    }

    function rateBars(bps) {
        // spark discreto de 6 células a partir da taxa (bytes/s)
        var n = Number(bps) || 0
        var levels = "▁▂▃▄▅▆▇"
        var out = ""
        var scale = Math.max(1, Math.log10(n + 1) / 7)
        for (var i = 0; i < 6; i++) {
            var t = (i + 1) / 6
            var idx = Math.min(6, Math.floor(scale * t * 6))
            out += levels.charAt(idx)
        }
        return out
    }

    function containerGlyph(c) {
        var st = String(c.state || "").toLowerCase()
        var status = String(c.status || "").toLowerCase()
        if (status.indexOf("unhealthy") >= 0) return "◐"
        if (st === "running" || c.running) return "●"
        if (st === "dead" || (status.indexOf("exited") >= 0 && status.indexOf("(1)") >= 0)) return "!"
        if (st === "restarting") return "◌"
        return "○"
    }
    function containerColor(c) {
        var g = view.containerGlyph(c)
        if (g === "!") return view.sys.colCrit
        if (g === "◐" || g === "◌") return view.sys.colWarn
        if (g === "●") return view.sys.colOk
        return view.sys.colMuted
    }

    function dockerSummary() {
        var list = view.payload.containers || []
        var run = 0, unhealthy = 0, stopped = 0
        for (var i = 0; i < list.length; i++) {
            var c = list[i]
            var g = view.containerGlyph(c)
            if (g === "◐") unhealthy++
            else if (c.running) run++
            else stopped++
        }
        return { run: run, unhealthy: unhealthy, stopped: stopped, total: list.length }
    }

    function openTerm(cwd) {
        var dir = cwd && cwd.length ? cwd : Quickshell.env("HOME")
        Quickshell.execDetached(["footclient"], { workingDirectory: dir })
    }

    Process {
        id: pHub
        command: ["bash", view.sh, "hub"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { view.hub = JSON.parse(text) } catch (e) { view.hub = { sections: [] } }
                view.loaded = true
            }
        }
    }
    Process {
        id: pSec
        command: ["bash", view.sh, "sys"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    view.payload = JSON.parse(text)
                    if (view.payload.lines) view.logLines = view.payload.lines
                } catch (e) { view.payload = {} }
                view.loaded = true
            }
        }
    }
    Process {
        id: pAct
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    if (d.lines) view.logLines = d.lines
                } catch (e) {}
                view.applyState = ""
                view.refresh()
            }
        }
    }

    Connections {
        target: view.sys
        function onHomelabEpochChanged() {
            var s = view.sys.homelabSection || "hub"
            view.section = s
            view.detail = ""
            view.creating = false
            view.logLines = []
            view.refresh()
        }
    }

    Timer {
        interval: view.section === "run" ? 8000 : 15000
        repeat: true
        running: true
        onTriggered: if (view.section === "hub" || view.section === "sys" || view.section === "run"
                         || view.section === "net" || view.section === "docker") view.refresh()
    }

    function statusGlyph(st) {
        var s = String(st || "").toUpperCase()
        if (s === "RUNNING") return "●"
        if (s === "FAILED") return "!"
        if (s === "STARTING" || s === "RESTARTING" || s === "STOPPING") return "◌"
        return "○"
    }
    function statusColorOf(st) {
        var s = String(st || "").toUpperCase()
        if (s === "RUNNING") return view.sys.colOk
        if (s === "FAILED") return view.sys.colCrit
        if (s === "STARTING" || s === "RESTARTING" || s === "STOPPING") return view.sys.colWarn
        return view.sys.colMuted
    }
    function selectedService() {
        var list = view.payload.services || []
        for (var i = 0; i < list.length; i++)
            if (list[i].name === view.detail) return list[i]
        return null
    }
    function sectionTitle() {
        if (view.creating) return view.sys.tr("NEW SERVICE")
        if (view.detail !== "") return view.detail.toUpperCase()
        if (view.section === "hub") return view.sys.tr("HOMELAB")
        if (view.section === "run") return view.sys.tr("BACKGROUND")
        return view.section.toUpperCase()
    }

    function pctBar(pct) {
        var p = Math.max(0, Math.min(100, Number(pct) || 0))
        return p
    }
    function statusColor(ok) {
        return ok ? view.sys.colOk : view.sys.colWarn
    }
    function bytesHuman(n) {
        n = Number(n) || 0
        if (n > 1e9) return (n / 1e9).toFixed(1) + " GB"
        if (n > 1e6) return (n / 1e6).toFixed(1) + " MB"
        if (n > 1e3) return (n / 1e3).toFixed(0) + " KB"
        return n + " B"
    }
    function sortedProcesses() {
        var list = (view.payload.processes || []).slice()
        var key = view.procSort === "mem" ? "rss_kb" : "cpu"
        list.sort(function (a, b) {
            return (Number(b[key]) || 0) - (Number(a[key]) || 0)
        })
        return list
    }
    function processByPid(pid) {
        var list = view.payload.processes || []
        for (var i = 0; i < list.length; i++)
            if (Number(list[i].pid) === Number(pid)) return list[i]
        return null
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                width: 32; height: 32; radius: 10
                color: backMa.containsMouse ? Qt.rgba(1,1,1,0.08) : "transparent"
                visible: view.section !== "hub" || view.detail !== "" || view.creating
                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    color: view.sys.colFg
                    font { family: view.sys.fontBody; pixelSize: view.sys.fontSize + 4 }
                }
                MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: view.goBack() }
            }
            Text {
                Layout.fillWidth: true
                text: view.sectionTitle()
                color: view.sys.colFg
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize; letterSpacing: 1.2 }
            }
            Rectangle {
                width: 32; height: 32; radius: 10
                color: refMa.containsMouse ? Qt.rgba(1,1,1,0.08) : "transparent"
                Glyph {
                    anchors.centerIn: parent
                    glyph: String.fromCodePoint(0xF0450)
                    color: view.sys.colMuted
                    fontFam: view.sys.fontFam
                    size: view.sys.iconSize
                }
                MouseArea { id: refMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: view.refresh() }
            }
        }

        // ---------------- HUB
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.section === "hub" && !view.creating
            Text {
                text: (view.hub.hostname || "") + " · " +
                      (view.hub.ssh ? "SSH ●" : "SSH ○") + " · " +
                      (view.hub.docker ? "DOCKER ●" : "DOCKER ○") + " · " +
                      (view.hub.ollama ? "AI ●" : "AI ○")
                color: view.sys.colMuted
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
            }
            Repeater {
                model: view.hub.sections || []
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 44
                    radius: 14
                    color: rowMa.containsMouse ? Qt.rgba(1,1,1,0.06) : Qt.rgba(1,1,1,0.03)
                    border.color: view.sys.colLine
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 16
                        Text {
                            text: "●"
                            color: view.statusColor(modelData.ok)
                            font.pixelSize: 12
                        }
                        Text {
                            text: modelData.label
                            color: view.sys.colFg
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1; letterSpacing: 1 }
                            // Coluna larga o bastante para BACKGROUND (antes 72 colidia com o hint)
                            Layout.preferredWidth: 128
                            Layout.minimumWidth: 128
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            text: modelData.hint || ""
                            color: view.sys.colMuted
                            elide: Text.ElideRight
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.openSection(modelData.id)
                    }
                }
            }
        }

        // ---------------- SYS
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.section === "sys"

            Repeater {
                model: [
                    { k: "CPU", v: (view.payload.cpu_pct || 0).toFixed(0) + "%", t: view.payload.cpu_temp },
                    { k: "RAM", v: (view.payload.mem_pct || 0).toFixed(0) + "%", t: 0 },
                    { k: "GPU", v: (view.payload.gpu_pct || 0).toFixed(0) + "%", t: view.payload.gpu_temp }
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 52
                    radius: 14
                    color: Qt.rgba(1,1,1,0.04)
                    border.color: view.sys.colLine; border.width: 1
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: modelData.k; color: view.sys.colMuted; font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2; letterSpacing: 1 } }
                            Item { Layout.fillWidth: true }
                            Text { text: modelData.v; color: view.sys.colFg; font { family: view.sys.fontBody; pixelSize: view.sys.fontSize } }
                            Text {
                                visible: Number(modelData.t) > 0
                                text: Number(modelData.t).toFixed(0) + "°C"
                                color: Number(modelData.t) >= 80 ? view.sys.colCrit : view.sys.colMuted
                                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: Qt.rgba(1,1,1,0.08)
                            Rectangle {
                                width: parent.width * (view.pctBar(parseFloat(modelData.v)) / 100)
                                height: parent.height
                                radius: 2
                                color: view.sys.colOn
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: {
                    var la = view.payload.loadavg || []
                    var loadStr = la.length >= 3
                        ? (Number(la[0]).toFixed(2) + "  " + Number(la[1]).toFixed(2) + "  " + Number(la[2]).toFixed(2))
                        : "—"
                    var freq = Number(view.payload.cpu_freq_mhz) > 0
                        ? (Number(view.payload.cpu_freq_mhz).toFixed(0) + " MHz") : "N/A"
                    var ramLine = view.payload.mem_total
                        ? (view.bytesHuman(view.payload.mem_used) + " / " + view.bytesHuman(view.payload.mem_total)
                           + "  avail " + view.bytesHuman(view.payload.mem_avail))
                        : "—"
                    var swapLine = Number(view.payload.swap_total) > 0
                        ? (view.bytesHuman(view.payload.swap_used) + " / " + view.bytesHuman(view.payload.swap_total))
                        : "none"
                    return "LOAD    " + loadStr + "\n"
                        + "FREQ    " + freq + "\n"
                        + "RAM     " + ramLine + "\n"
                        + "SWAP    " + swapLine + "\n"
                        + "UPTIME  " + (view.payload.uptime || "—") + "\n"
                        + "KERNEL  " + (view.payload.kernel || "—") + "\n"
                        + "HOST    " + (view.payload.hostname || "—") + "\n"
                        + "OS      " + (view.payload.os || "—")
                        + (view.payload.vram ? ("\nVRAM    " + view.payload.vram) : "")
                }
                color: view.sys.colMuted
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
            }

            // Process list header
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                Text {
                    text: "PROCESSES"
                    color: view.sys.colMuted
                    font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 4; bold: true; letterSpacing: 1 }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    height: 22; radius: 8
                    width: sortCpuLbl.implicitWidth + 14
                    color: view.procSort === "cpu" ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.04)
                    Text {
                        id: sortCpuLbl
                        anchors.centerIn: parent
                        text: "CPU"
                        color: view.procSort === "cpu" ? view.sys.colFg : view.sys.colMuted
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.procSort = "cpu"
                    }
                }
                Rectangle {
                    height: 22; radius: 8
                    width: sortMemLbl.implicitWidth + 14
                    color: view.procSort === "mem" ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.04)
                    Text {
                        id: sortMemLbl
                        anchors.centerIn: parent
                        text: "RAM"
                        color: view.procSort === "mem" ? view.sys.colFg : view.sys.colMuted
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.procSort = "mem"
                    }
                }
                Rectangle {
                    height: 22; radius: 8
                    width: refreshLbl.implicitWidth + 14
                    color: Qt.rgba(1,1,1,0.04)
                    Text {
                        id: refreshLbl
                        anchors.centerIn: parent
                        text: "↻"
                        color: view.sys.colMuted
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.refresh()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { Layout.preferredWidth: 52; text: "PID"; color: view.sys.colMuted; font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 } }
                Text { Layout.fillWidth: true; text: "PROCESS"; color: view.sys.colMuted; font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 } }
                Text { Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight; text: "CPU"; color: view.sys.colMuted; font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 } }
                Text { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: "RAM"; color: view.sys.colMuted; font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 } }
            }

            Repeater {
                model: view.procList
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 30
                    radius: 8
                    color: view.procDetailPid === modelData.pid
                           ? Qt.rgba(1,1,1,0.08) : (rowMa.containsMouse ? Qt.rgba(1,1,1,0.05) : "transparent")
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 6
                        Text {
                            Layout.preferredWidth: 52
                            text: String(modelData.pid)
                            color: view.sys.colMuted
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.name || "—"
                            elide: Text.ElideRight
                            color: view.sys.colFg
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                        }
                        Text {
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                            text: Number(modelData.cpu || 0).toFixed(1) + "%"
                            color: view.sys.colFg
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                        }
                        Text {
                            Layout.preferredWidth: 64
                            horizontalAlignment: Text.AlignRight
                            text: view.bytesHuman((Number(modelData.rss_kb) || 0) * 1024)
                            color: view.sys.colMuted
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.procDetailPid = (view.procDetailPid === modelData.pid) ? 0 : modelData.pid
                    }
                }
            }

            // Detalhe sob demanda (sem kill)
            Rectangle {
                visible: view.procDetailPid > 0 && view.processByPid(view.procDetailPid) !== null
                Layout.fillWidth: true
                radius: 12
                color: Qt.rgba(1,1,1,0.04)
                border.color: view.sys.colLine; border.width: 1
                implicitHeight: procDetailCol.implicitHeight + 20
                ColumnLayout {
                    id: procDetailCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: {
                            var p = view.processByPid(view.procDetailPid)
                            if (!p) return ""
                            return "PID " + p.pid + "  " + (p.name || "") + "\n"
                                + "CPU  " + Number(p.cpu || 0).toFixed(1) + "%\n"
                                + "RAM  " + view.bytesHuman((Number(p.rss_kb) || 0) * 1024)
                                + "  (" + Number(p.mem || 0).toFixed(1) + "%)"
                        }
                        color: view.sys.colMuted
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                    }
                }
            }

            Text {
                visible: !(view.payload.processes && view.payload.processes.length)
                Layout.fillWidth: true
                text: "no process data"
                color: view.sys.colMuted
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2; italic: true }
            }
        }

        // ---------------- NET
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.section === "net"
            Text {
                visible: !view.loaded
                text: "◌ QUERYING"
                color: view.sys.colWarn
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "IFACE   " + (view.payload.iface || "—") + "\n"
                    + "STATE   " + (view.payload.state || "—") + "  LINK " + (view.payload.link || "—") + "\n"
                    + "SPEED   " + (view.payload.speed || "N/A") + "\n"
                    + "IPv4    " + (view.payload.ip || "—") + "\n"
                    + "IPv6    " + (view.payload.ip6 || "N/A") + "\n"
                    + "GATEWAY " + (view.payload.gateway || "—") + "\n"
                    + "DNS     " + (view.payload.dns || "—") + "\n"
                    + "RX      " + view.bytesHuman(view.payload.rx_bytes)
                    + "  (" + view.bytesHuman(view.payload.rx_rate) + "/s)  "
                    + view.rateBars(view.payload.rx_rate) + "\n"
                    + "TX      " + view.bytesHuman(view.payload.tx_bytes)
                    + "  (" + view.bytesHuman(view.payload.tx_rate) + "/s)  "
                    + view.rateBars(view.payload.tx_rate)
                color: view.sys.colMuted
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
            }
            Repeater {
                model: [
                    { k: "SSH", ok: view.payload.ssh },
                    { k: "Internet", ok: view.payload.internet },
                    { k: "DNS", ok: view.payload.dns_ok }
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Text {
                        text: modelData.k
                        color: view.sys.colFg
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
                        Layout.preferredWidth: 90
                    }
                    Text {
                        text: modelData.ok ? "● ONLINE" : "○ OFFLINE"
                        color: view.statusColor(modelData.ok ? true : false)
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        // ---------------- STORAGE
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.section === "storage"
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: {
                    function diskLine(label, d) {
                        if (!d) return label + "  N/A"
                        return label + "  " + (d.pct || 0) + "%  "
                            + view.bytesHuman((d.used_kb || 0) * 1024) + " / "
                            + view.bytesHuman((d.size_kb || 0) * 1024)
                            + "  free " + view.bytesHuman((d.avail_kb || 0) * 1024)
                    }
                    return diskLine("ROOT", view.payload.root) + "\n"
                        + diskLine("/srv", view.payload.srv) + "\n"
                        + "I/O     " + (view.payload.io_dev || "N/A") + "\n"
                        + "READ    " + view.bytesHuman(view.payload.read_bps) + "/s\n"
                        + "WRITE   " + view.bytesHuman(view.payload.write_bps) + "/s\n"
                        + "HEALTH  " + (view.payload.health || "—")
                }
                color: view.sys.colMuted
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
            }
            Repeater {
                model: view.payload.disks || []
                delegate: Text {
                    required property var modelData
                    Layout.fillWidth: true
                    text: (modelData.name || "") + "  " + (modelData.size || "") + "  " + (modelData.model || "")
                    color: view.sys.colMuted
                    font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                    elide: Text.ElideRight
                }
            }
        }

        // ---------------- AI
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: view.section === "ai"
            Text {
                text: "OLLAMA  " + (view.payload.online ? "● ONLINE" : "○ OFFLINE")
                color: view.statusColor(!!view.payload.online)
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "ENDPOINT  " + (view.payload.endpoint || "—") + "\n"
                    + "MODELS    " + (view.payload.model_count || 0) + " installed\n"
                    + "GPU       " + (view.payload.gpu || "—") + "\n\n"
                    + (view.payload.note || "")
                color: view.sys.colMuted
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
            }
            Repeater {
                model: view.payload.models || []
                delegate: Text {
                    required property string modelData
                    text: "· " + modelData
                    color: view.sys.colFg
                    font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                }
            }
            RowLayout {
                spacing: 8
                HomelabBtn { label: "LOGS"; onClicked: { view.section = "logs"; view.detail = "ollama"; view.refresh() } }
                HomelabBtn { label: "TERMINAL"; onClicked: view.openTerm("") }
            }
        }

        // ---------------- DOCKER list
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: view.section === "docker" && view.detail === ""
            Text {
                visible: !view.loaded
                text: "◌ QUERYING"
                color: view.sys.colWarn
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
            }
            Text {
                visible: view.loaded && !(view.payload.ok)
                text: "! SERVICE UNAVAILABLE\ndocker daemon / socket\n[ open Terminal to inspect ]"
                color: view.sys.colCrit
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
            }
            Text {
                visible: view.loaded && view.payload.ok
                text: {
                    var s = view.dockerSummary()
                    var g = s.unhealthy > 0 ? "◐" : (s.run > 0 ? "●" : "○")
                    var line = "DOCKER " + g + "  " + s.run + " running"
                    if (s.unhealthy) line += "  " + s.unhealthy + " unhealthy"
                    if (s.stopped) line += "  " + s.stopped + " stopped"
                    return line
                }
                color: view.sys.colFg
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
            }
            Text {
                visible: view.loaded && view.payload.ok && (view.payload.containers || []).length === 0
                text: "No containers."
                color: view.sys.colMuted
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
            }
            Repeater {
                model: view.payload.containers || []
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 44
                    radius: 14
                    color: dMa.containsMouse ? Qt.rgba(1,1,1,0.06) : Qt.rgba(1,1,1,0.03)
                    border.color: view.sys.colLine; border.width: 1
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 8
                        Text {
                            text: view.containerGlyph(modelData)
                            color: view.containerColor(modelData)
                        }
                        Text {
                            text: modelData.name
                            color: view.sys.colFg
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: modelData.state ? modelData.state : ""
                            color: view.sys.colMuted
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                            elide: Text.ElideRight
                            Layout.preferredWidth: 90
                        }
                    }
                    MouseArea {
                        id: dMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: view.detail = modelData.name
                    }
                }
            }
        }

        // DOCKER detail
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.section === "docker" && view.detail !== ""
            Text {
                text: view.detail
                color: view.sys.colFg
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize }
            }
            Text {
                visible: view.applyState.length > 0
                text: "◌ " + view.applyState
                color: view.sys.colWarn
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
            }
            // confirmação destrutiva
            Rectangle {
                Layout.fillWidth: true
                visible: view.confirmAction === ("stop:" + view.detail)
                         || view.confirmAction === ("restart:" + view.detail)
                height: confCol.implicitHeight + 16
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.06)
                border.color: view.sys.colCrit
                border.width: 1
                ColumnLayout {
                    id: confCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 10
                    spacing: 8
                    Text {
                        text: (view.confirmAction.indexOf("stop:") === 0 ? "STOP CONTAINER?" : "RESTART CONTAINER?")
                              + "\n" + view.detail
                        color: view.sys.colFg
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
                    }
                    RowLayout {
                        spacing: 8
                        HomelabBtn { label: "CANCEL"; onClicked: view.clearConfirm() }
                        HomelabBtn { label: view.confirmAction.indexOf("stop:") === 0 ? "STOP" : "RESTART"; onClicked: view.doConfirm() }
                    }
                }
            }
            RowLayout {
                spacing: 8
                visible: view.confirmAction === ""
                HomelabBtn { label: "LOGS"; onClicked: view.runAction(["docker-action", "logs", view.detail]) }
                HomelabBtn { label: "RESTART"; onClicked: view.askConfirm("restart", view.detail) }
                HomelabBtn { label: "STOP"; onClicked: view.askConfirm("stop", view.detail) }
                HomelabBtn { label: "SHELL"; onClicked: Quickshell.execDetached(["footclient", "-e", "docker", "exec", "-it", view.detail, "sh"]) }
            }
            Repeater {
                model: view.logLines
                delegate: Text {
                    required property string modelData
                    Layout.fillWidth: true
                    text: modelData
                    color: view.sys.colMuted
                    wrapMode: Text.Wrap
                    font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                }
            }
        }

        // ---------------- DEV
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: view.section === "dev" && view.detail === ""
            Repeater {
                model: view.payload.projects || []
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 48
                    radius: 14
                    color: pMa.containsMouse ? Qt.rgba(1,1,1,0.06) : Qt.rgba(1,1,1,0.03)
                    border.color: view.sys.colLine; border.width: 1
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 2
                        Text { text: modelData.name; color: view.sys.colFg; font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 } }
                        Text {
                            text: (modelData.git ? (modelData.branch + (modelData.clean ? " · clean" : " · dirty")) : "no git")
                            color: view.sys.colMuted
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                        }
                    }
                    MouseArea {
                        id: pMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { view.detail = modelData.path; view.payload._sel = modelData }
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.section === "dev" && view.detail !== ""
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "PATH\n" + view.detail + "\n\nGIT\n"
                    + ((view.payload._sel && view.payload._sel.branch) || "—") + " · "
                    + ((view.payload._sel && view.payload._sel.clean) ? "clean" : "dirty")
                color: view.sys.colMuted
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
            }
            RowLayout {
                spacing: 8
                HomelabBtn { label: "TERMINAL"; onClicked: view.openTerm(view.detail) }
                HomelabBtn {
                    label: "RUN AS SERVICE"
                    onClicked: {
                        view.creating = true
                        view.formName = (view.payload._sel && view.payload._sel.name) || ""
                        view.formDir = view.detail
                        view.formCmd = "npm run dev"
                        view.section = "run"
                    }
                }
            }
        }

        // ---------------- RUN / BACKGROUND TERMINALS
        ColumnLayout {
            Layout.fillWidth: true
            spacing: view.termGap
            visible: view.section === "run" && !view.creating && view.detail === ""

            Text {
                text: view.sys.tr("Persistent via systemd — Terminal is only a window into the process")
                color: view.sys.colMuted
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
            }

            HomelabBtn {
                label: "+ NEW SERVICE"
                primary: true
                onClicked: {
                    view.creating = true
                    view.formName = ""
                    view.formDir = Quickshell.env("HOME") + "/dev/projects"
                    view.formCmd = "npm run dev"
                    view.formPort = "3000"
                }
            }

            // Compact service surfaces (background terminals)
            Repeater {
                model: view.payload.services || []
                delegate: Rectangle {
                    id: termCard
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: termBody.implicitHeight + view.termPadY * 2
                    radius: view.termRadius
                    color: termMa.containsMouse
                           ? Qt.rgba(1, 1, 1, 0.06)
                           : Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.04)
                    border.color: view.sys.colLine
                    border.width: 1

                    // Subtle live pulse — only when RUNNING (opacity, not blink)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: view.termAccentW
                        radius: 2
                        visible: String(termCard.modelData.status || "") === "RUNNING"
                        color: view.sys.colOk
                        SequentialAnimation on opacity {
                            running: String(termCard.modelData.status || "") === "RUNNING"
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.35; to: 0.85; duration: 1600; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.85; to: 0.35; duration: 1600; easing.type: Easing.InOutSine }
                        }
                    }

                    ColumnLayout {
                        id: termBody
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: view.termPadX; rightMargin: view.termPadY
                        }
                        spacing: view.termInnerGap

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: view.statusGlyph(termCard.modelData.status)
                                color: view.statusColorOf(termCard.modelData.status)
                                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
                            }
                            Text {
                                text: String(termCard.modelData.name || "").toUpperCase()
                                color: view.sys.colFg
                                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1; letterSpacing: 0.8 }
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: String(termCard.modelData.status || "").toUpperCase()
                                color: view.statusColorOf(termCard.modelData.status)
                                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3; letterSpacing: 0.6 }
                            }
                        }

                        Text {
                            visible: String(termCard.modelData.command || "").length > 0
                            text: "$ " + (termCard.modelData.command || "")
                            color: view.sys.colMuted
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
                        }

                        Text {
                            visible: String(termCard.modelData.last_log || "").length > 0
                            text: "> " + (termCard.modelData.last_log || "")
                            color: Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.55)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Text {
                                visible: Number(termCard.modelData.port) > 0
                                text: ":" + termCard.modelData.port
                                color: view.sys.colMuted
                                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                            }
                            Text {
                                visible: Number(termCard.modelData.pid) > 0
                                text: "PID " + termCard.modelData.pid
                                color: view.sys.colMuted
                                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                            }
                            Text {
                                visible: String(termCard.modelData.uptime || "").length > 0
                                text: "UP " + (termCard.modelData.uptime || "")
                                color: view.sys.colMuted
                                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    MouseArea {
                        id: termMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.logLines = []
                            view.detail = termCard.modelData.name
                        }
                    }
                }
            }

            Text {
                visible: !(view.payload.services && view.payload.services.length)
                text: view.sys.tr("No background services yet")
                color: view.sys.colMuted
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
            }
        }

        // RUN detail — focused background terminal surface
        ColumnLayout {
            Layout.fillWidth: true
            spacing: view.termGap
            visible: view.section === "run" && !view.creating && view.detail !== ""

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: focusBody.implicitHeight + view.termPadY * 2 + 4
                radius: view.termRadius
                color: Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.045)
                border.color: view.sys.colLine
                border.width: 1

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: view.termAccentW
                    radius: 2
                    color: view.statusColorOf(view.selectedService() ? view.selectedService().status : "")
                    opacity: 0.85
                }

                ColumnLayout {
                    id: focusBody
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: view.termPadX + 2; rightMargin: view.termPadY
                    }
                    spacing: view.termInnerGap + 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: view.statusGlyph(view.selectedService() ? view.selectedService().status : "")
                            color: view.statusColorOf(view.selectedService() ? view.selectedService().status : "")
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize }
                        }
                        Text {
                            text: String(view.selectedService() ? view.selectedService().status : "").toUpperCase()
                            color: view.statusColorOf(view.selectedService() ? view.selectedService().status : "")
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2; letterSpacing: 1 }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Text {
                        text: "$ " + ((view.selectedService() && view.selectedService().command) || "—")
                        color: view.sys.colFg
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
                    }

                    Text {
                        visible: !!(view.selectedService() && view.selectedService().directory)
                        text: (view.selectedService() && view.selectedService().directory) || ""
                        color: view.sys.colMuted
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                    }

                    Text {
                        visible: !!(view.selectedService() && view.selectedService().last_log)
                        text: "> " + ((view.selectedService() && view.selectedService().last_log) || "")
                        color: Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.6)
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: view.sys.colMuted
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                        text: {
                            var s = view.selectedService()
                            if (!s) return ""
                            var parts = []
                            if (s.pid) parts.push("PID " + s.pid)
                            if (Number(s.port) > 0) parts.push("PORT " + s.port)
                            if (s.uptime) parts.push("UP " + s.uptime)
                            if (s.restarts) parts.push("RESTARTS " + s.restarts)
                            if (s.last_exit && s.last_exit !== "success") parts.push("EXIT " + s.last_exit)
                            return parts.join("   ·   ")
                        }
                    }
                }
            }

            RowLayout {
                spacing: 8
                HomelabBtn {
                    label: "TERMINAL"
                    primary: true
                    onClicked: {
                        var s = view.selectedService()
                        view.openTerm(s && s.directory ? s.directory : "")
                    }
                }
                HomelabBtn {
                    label: "LOGS"
                    onClicked: {
                        view.runAction(["service-logs", view.detail])
                    }
                }
                HomelabBtn {
                    label: "RESTART"
                    onClicked: view.runAction(["service-restart", view.detail])
                }
                HomelabBtn {
                    label: (view.selectedService() && view.selectedService().running) ? "STOP" : "START"
                    onClicked: {
                        var s = view.selectedService()
                        if (s && s.running) view.runAction(["service-stop", view.detail])
                        else view.runAction(["service-start", view.detail])
                    }
                }
            }

            // Full log tail when LOGS was requested (keeps context of focused service)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: view.logLines && view.logLines.length > 0
                Text {
                    text: view.sys.tr("JOURNAL")
                    color: view.sys.colMuted
                    font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3; letterSpacing: 1 }
                }
                Repeater {
                    model: view.logLines
                    delegate: Text {
                        required property string modelData
                        Layout.fillWidth: true
                        text: modelData
                        color: view.sys.colMuted
                        wrapMode: Text.WrapAnywhere
                        font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                    }
                }
            }
        }

        // NEW SERVICE form
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.section === "run" && view.creating
            HomelabField { label: "NAME"; text: view.formName; onEdited: view.formName = text }
            HomelabField { label: "DIRECTORY"; text: view.formDir; onEdited: view.formDir = text }
            HomelabField { label: "COMMAND"; text: view.formCmd; onEdited: view.formCmd = text }
            HomelabField { label: "PORT"; text: view.formPort; onEdited: view.formPort = text }
            Text {
                text: "Creates systemd --user unit (survives Terminal / Panacea / Hyprland restart)."
                color: view.sys.colMuted
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
            }
            HomelabBtn {
                label: "CREATE"
                primary: true
                enabled: view.formName.length > 0 && view.formCmd.length > 0
                onClicked: {
                    view.runAction(["service-create", view.formName, view.formDir, view.formCmd, view.formPort || "0", "true", "on-failure"])
                    view.creating = false
                    view.detail = ""
                }
            }
        }

        // ---------------- LOGS
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: view.section === "logs"
            RowLayout {
                spacing: 6
                Repeater {
                    model: ["system", "docker", "ssh", "ollama"]
                    delegate: HomelabBtn {
                        required property string modelData
                        label: modelData.toUpperCase()
                        onClicked: { view.detail = modelData; view.refresh() }
                    }
                }
            }
            Repeater {
                model: view.logLines
                delegate: Text {
                    required property string modelData
                    Layout.fillWidth: true
                    text: modelData
                    color: view.sys.colMuted
                    wrapMode: Text.WrapAnywhere
                    font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                }
            }
        }
    }

    // ---- tiny local components matching Panacea language ----
    component HomelabBtn: Rectangle {
        property string label: ""
        property bool primary: false
        signal clicked()
        Layout.preferredHeight: 34
        Layout.preferredWidth: Math.max(72, lab.implicitWidth + 20)
        radius: 12
        color: primary
               ? (bMa.containsMouse ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.36)
                                    : Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.24))
               : (bMa.containsMouse ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04))
        border.width: 1
        border.color: primary ? view.sys.colOn : view.sys.colLine
        Text {
            id: lab
            anchors.centerIn: parent
            text: label
            color: view.sys.colFg
            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2; letterSpacing: 0.6 }
        }
        MouseArea {
            id: bMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component HomelabField: ColumnLayout {
        property string label: ""
        property alias text: tin.text
        signal edited(string text)
        Layout.fillWidth: true
        spacing: 4
        Text {
            text: label
            color: view.sys.colMuted
            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3; letterSpacing: 1 }
        }
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 12
            color: Qt.rgba(1,1,1,0.04)
            border.color: view.sys.colLine
            border.width: 1
            TextInput {
                id: tin
                anchors.fill: parent
                anchors.margins: 10
                color: view.sys.colFg
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
                clip: true
                onTextChanged: parent.parent.edited(text)
            }
        }
    }
}
