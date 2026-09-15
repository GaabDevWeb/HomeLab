import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// System state no Control Center: CURRENT | HISTORY | PROCESSES
// History usa root.metricsHistory (mesma fonte do LoadCard).
Item {
    id: view
    property var sys

    property var payload: ({})
    property string procSort: "cpu"
    property int procDetailPid: 0
    property bool loaded: false
    property string tab: "current"   // current | history | processes | happening
    property string tipText: ""
    property real metricsAgeSec: -1

    implicitHeight: col.implicitHeight
    focus: true

    function goBack() { view.sys.page = "main"; return true }
    Keys.onEscapePressed: view.goBack()

    function setTab(id) {
        view.tab = id
        if (view.sys && view.sys.patchUiMemory)
            view.sys.patchUiMemory({ sysloadTab: id })
    }

    function refreshAge() {
        var h = view.sys.metricsHistory || []
        if (!h.length) { view.metricsAgeSec = -1; return }
        var ts = Number(h[h.length - 1].ts) || 0
        if (!ts) { view.metricsAgeSec = -1; return }
        view.metricsAgeSec = Math.max(0, Math.floor(Date.now() / 1000 - ts))
    }

    function ageLabel() {
        var a = view.metricsAgeSec
        if (a < 0) return ""
        if (a <= 1) return "updated just now"
        if (a < 60) return "updated " + a + "s ago"
        return "updated " + Math.floor(a / 60) + "m ago"
    }

    readonly property string sh: view.sys.scriptDir + "/homelab.sh"
    readonly property var hist: view.sys.metricsSlice ? view.sys.metricsSlice() : []

    readonly property var procList: {
        var _s = view.procSort
        var _p = view.payload
        return view.sortedProcesses()
    }

    function refresh() {
        pSys.running = false
        pSys.running = true
    }

    function bytesHuman(n) {
        n = Number(n) || 0
        if (n > 1e9) return (n / 1e9).toFixed(1) + " GB"
        if (n > 1e6) return (n / 1e6).toFixed(1) + " MB"
        if (n > 1e3) return (n / 1e3).toFixed(0) + " KB"
        return n + " B"
    }

    function pctBar(pct) {
        return Math.max(0, Math.min(100, Number(pct) || 0))
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

    function fmtTime(ts) {
        var d = new Date((Number(ts) || 0) * 1000)
        function z(n) { return (n < 10 ? "0" : "") + n }
        return z(d.getHours()) + ":" + z(d.getMinutes()) + ":" + z(d.getSeconds())
    }

    Process {
        id: pSys
        command: ["bash", view.sh, "sys"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { view.payload = JSON.parse(text) } catch (e) { view.payload = {} }
                view.loaded = true
            }
        }
    }

    Timer {
        interval: 4000
        repeat: true
        running: view.visible && view.tab !== "history"
        onTriggered: if (!pSys.running) view.refresh()
    }

    Component.onCompleted: {
        forceActiveFocus()
        var mem = view.sys.uiMemory || {}
        if (mem.sysloadTab) view.tab = mem.sysloadTab
        view.refreshAge()
    }

    Timer {
        interval: 1000
        repeat: true
        running: view.visible
        onTriggered: view.refreshAge()
    }

    // ---------- sparkline reutilizável
    component Spark: Item {
        property var points: []
        property string key: "cpu_pct"
        property real maxY: 100
        property bool rateMode: false
        property string label: ""
        Layout.fillWidth: true
        Layout.preferredHeight: 72

        Canvas {
            id: c
            anchors.fill: parent
            anchors.topMargin: 16
            anchors.bottomMargin: 14
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var pts = parent.points || []
                var vals = []
                for (var i = 0; i < pts.length; i++) {
                    var v = pts[i][parent.key]
                    if (v === null || v === undefined) continue
                    vals.push({ i: i, v: Number(v), ts: pts[i].ts })
                }
                // grid
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.06)
                ctx.lineWidth = 1
                for (var g = 0; g <= 4; g++) {
                    var gy = height * g / 4
                    ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke()
                }
                if (vals.length < 2) return
                var mx = parent.maxY
                if (parent.rateMode) {
                    mx = 1
                    for (var j = 0; j < vals.length; j++)
                        if (vals[j].v > mx) mx = vals[j].v
                }
                ctx.strokeStyle = Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.85)
                ctx.lineWidth = 1.4
                ctx.lineJoin = "round"
                ctx.beginPath()
                for (var k = 0; k < vals.length; k++) {
                    var x = k * (width / Math.max(1, vals.length - 1))
                    var y = height * (1 - Math.max(0, Math.min(1, vals[k].v / mx)))
                    if (k === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                ctx.stroke()
            }
        }
        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: parent.label
            color: view.sys.colMuted
            font { family: view.sys.fontFam; pixelSize: 10; letterSpacing: 1 }
        }
        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            text: {
                var pts = parent.points || []
                if (!pts.length) return "—"
                var last = pts[pts.length - 1]
                var v = last[parent.key]
                if (v === null || v === undefined) return "N/A"
                if (parent.rateMode) return view.bytesHuman(v) + "/s"
                return Number(v).toFixed(0) + (parent.key.indexOf("temp") >= 0 ? "°" : "%")
            }
            color: view.sys.colFg
            font { family: view.sys.fontFam; pixelSize: 10 }
        }
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: "-" + (view.sys.metricsWindow || "15m")
            color: view.sys.colMuted
            font { family: view.sys.fontFam; pixelSize: 9 }
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: "NOW"
            color: view.sys.colMuted
            font { family: view.sys.fontFam; pixelSize: 9 }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: mouse => {
                var pts = parent.points || []
                if (pts.length < 1) { view.tipText = ""; return }
                var idx = Math.round(mouse.x / Math.max(1, width) * (pts.length - 1))
                idx = Math.max(0, Math.min(pts.length - 1, idx))
                var s = pts[idx]
                var v = s[parent.key]
                var val = (v === null || v === undefined) ? "N/A"
                        : (parent.rateMode ? view.bytesHuman(v) + "/s"
                           : Number(v).toFixed(1) + (parent.key.indexOf("temp") >= 0 ? "°" : "%"))
                view.tipText = view.fmtTime(s.ts) + "  " + parent.label + "  " + val
            }
            onExited: view.tipText = ""
        }
        Connections {
            target: view.sys
            function onMetricsHistoryChanged() { c.requestPaint() }
            function onMetricsWindowChanged() { c.requestPaint() }
        }
        onPointsChanged: c.requestPaint()
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 10
                color: backMa.containsMouse ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.06)
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF004D)
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.iconSize - 4 }
                }
                MouseArea {
                    id: backMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.goBack()
                }
            }
            Text {
                Layout.fillWidth: true
                text: "SYSTEM"
                color: view.sys.colFg
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize + 1; bold: true }
            }
            Text {
                visible: view.ageLabel().length > 0
                text: view.ageLabel()
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: 9 }
            }
        }

        // tabs
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { id: "current", label: "CURRENT" },
                    { id: "happening", label: "NOW" },
                    { id: "history", label: "HISTORY" },
                    { id: "processes", label: "PROCESSES" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    height: 24; radius: 8
                    width: tabLbl.implicitWidth + 14
                    color: view.tab === modelData.id ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.04)
                    Text {
                        id: tabLbl
                        anchors.centerIn: parent
                        text: modelData.label
                        color: view.tab === modelData.id ? view.sys.colFg : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.setTab(modelData.id)
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        // -------- CURRENT
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.tab === "current"

            Repeater {
                model: [
                    { k: "CPU", v: view.sys.loadCpu, t: view.sys.loadTempCpu },
                    { k: "RAM", v: view.sys.loadMem, t: 0 },
                    { k: "GPU", v: view.sys.loadGpu, t: view.sys.loadTempGpu }
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 48
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.color: view.sys.colLine
                    border.width: 1
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: modelData.k
                                color: view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; letterSpacing: 1 }
                            }
                            Item { Layout.fillWidth: true }
                            SmoothNumber {
                                target: Math.max(0, Number(modelData.v) || 0)
                                decimals: 0
                                suffix: "%"
                                sys: view.sys
                                visible: Number(modelData.v) >= 0
                            }
                            Text {
                                visible: Number(modelData.v) < 0
                                text: "—"
                                color: view.sys.colFg
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize }
                            }
                            Text {
                                visible: Number(modelData.t) > 0
                                text: Number(modelData.t).toFixed(0) + "°"
                                color: Number(modelData.t) >= 80 ? view.sys.colCrit : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Rectangle {
                                width: parent.width * (view.pctBar(Math.max(0, modelData.v)) / 100)
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
                    var ramLine = view.payload.mem_total
                        ? (view.bytesHuman(view.payload.mem_used) + " / " + view.bytesHuman(view.payload.mem_total))
                        : "—"
                    return "LOAD  " + loadStr + "\n"
                        + "RAM   " + ramLine + "\n"
                        + "UPTIME  " + (view.payload.uptime || "—")
                }
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
            }
        }

        // -------- WHAT'S HAPPENING (NOW)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.tab === "happening"

            Text {
                text: "WHAT'S HAPPENING?"
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: 10; letterSpacing: 1 }
            }

            Repeater {
                model: {
                    var h = view.sys.metricsHistory || []
                    var last = h.length ? h[h.length - 1] : {}
                    var tops = (view.payload.processes || []).slice(0, 3)
                    var rows = [
                        { k: "CPU", v: (Number(view.sys.loadCpu) >= 0 ? Number(view.sys.loadCpu).toFixed(0) + "%" : "—") },
                        { k: "RAM", v: (Number(view.sys.loadMem) >= 0 ? Number(view.sys.loadMem).toFixed(0) + "%" : "—") },
                        { k: "GPU", v: (Number(view.sys.loadGpu) >= 0 ? Number(view.sys.loadGpu).toFixed(0) + "%" : "—") },
                        { k: "NETWORK ↓", v: last.rx_rate !== undefined && last.rx_rate !== null ? view.bytesHuman(last.rx_rate) + "/s" : "—" },
                        { k: "NETWORK ↑", v: last.tx_rate !== undefined && last.tx_rate !== null ? view.bytesHuman(last.tx_rate) + "/s" : "—" },
                        { k: "DISK WRITE", v: last.write_bps !== undefined && last.write_bps !== null ? view.bytesHuman(last.write_bps) + "/s" : "—" }
                    ]
                    for (var i = 0; i < tops.length; i++) {
                        var p = tops[i]
                        rows.push({
                            k: "PROC  " + String(p.name || p.cmd || "?").slice(0, 18),
                            v: (Number(p.cpu) || 0).toFixed(1) + "%"
                        })
                    }
                    return rows
                }
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 32
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.04)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        Text {
                            text: modelData.k
                            color: view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                            Layout.fillWidth: true
                        }
                        Text {
                            text: modelData.v
                            color: view.sys.colFg
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 1 }
                        }
                    }
                }
            }

            Text {
                visible: !view.loaded
                text: "◌ READING"
                color: view.sys.colWarn
                font { family: view.sys.fontFam; pixelSize: 11 }
            }
        }

        // -------- HISTORY
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.tab === "history"

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: "WINDOW"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                }
                Repeater {
                    model: ["5m", "15m", "30m"]
                    delegate: Rectangle {
                        required property string modelData
                        height: 22; radius: 8
                        width: wLbl.implicitWidth + 12
                        color: view.sys.metricsWindow === modelData ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.04)
                        Text {
                            id: wLbl
                            anchors.centerIn: parent
                            text: modelData
                            color: view.sys.metricsWindow === modelData ? view.sys.colFg : view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.sys.metricsWindow = modelData
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: (view.hist.length || 0) + " samples"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 10 }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: view.tipText.length > 0
                text: view.tipText
                color: view.sys.colFg
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.04)
                border.color: view.sys.colLine
                border.width: 1
                implicitHeight: histCol.implicitHeight + 16
                ColumnLayout {
                    id: histCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    Spark { points: view.hist; key: "cpu_pct"; label: "CPU"; maxY: 100 }
                    Spark { points: view.hist; key: "mem_pct"; label: "RAM"; maxY: 100 }
                    Spark { points: view.hist; key: "gpu_pct"; label: "GPU"; maxY: 100 }
                    Spark { points: view.hist; key: "cpu_temp"; label: "CPU °C"; maxY: 100 }
                    Spark { points: view.hist; key: "rx_rate"; label: "NET RX"; rateMode: true }
                    Spark { points: view.hist; key: "tx_rate"; label: "NET TX"; rateMode: true }
                    Spark { points: view.hist; key: "read_bps"; label: "DISK R"; rateMode: true }
                    Spark { points: view.hist; key: "write_bps"; label: "DISK W"; rateMode: true }
                }
            }

            Text {
                visible: !(view.hist && view.hist.length)
                Layout.fillWidth: true
                text: "collecting… (wait a few seconds)"
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; italic: true }
            }
        }

        // -------- PROCESSES
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: view.tab === "processes"

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "PROCESSES"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4; bold: true; letterSpacing: 1 }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    height: 22; radius: 8; width: sortCpuLbl.implicitWidth + 14
                    color: view.procSort === "cpu" ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                    Text {
                        id: sortCpuLbl
                        anchors.centerIn: parent
                        text: "CPU"
                        color: view.procSort === "cpu" ? view.sys.colFg : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.procSort = "cpu"
                    }
                }
                Rectangle {
                    height: 22; radius: 8; width: sortMemLbl.implicitWidth + 14
                    color: view.procSort === "mem" ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                    Text {
                        id: sortMemLbl
                        anchors.centerIn: parent
                        text: "RAM"
                        color: view.procSort === "mem" ? view.sys.colFg : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.procSort = "mem"
                    }
                }
                Rectangle {
                    height: 22; radius: 8; width: 28
                    color: Qt.rgba(1, 1, 1, 0.04)
                    Text {
                        anchors.centerIn: parent
                        text: "↻"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
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
                Text { Layout.preferredWidth: 52; text: "PID"; color: view.sys.colMuted; font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 } }
                Text { Layout.fillWidth: true; text: "PROCESS"; color: view.sys.colMuted; font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 } }
                Text { Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight; text: "CPU"; color: view.sys.colMuted; font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 } }
                Text { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: "RAM"; color: view.sys.colMuted; font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 } }
            }

            Repeater {
                model: view.procList
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 30
                    radius: 8
                    color: view.procDetailPid === modelData.pid
                           ? Qt.rgba(1, 1, 1, 0.08)
                           : (rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 6
                        Text {
                            Layout.preferredWidth: 52
                            text: String(modelData.pid)
                            color: view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.name || "—"
                            elide: Text.ElideRight
                            color: view.sys.colFg
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                        }
                        Text {
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                            text: Number(modelData.cpu || 0).toFixed(1) + "%"
                            color: view.sys.colFg
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                        }
                        Text {
                            Layout.preferredWidth: 64
                            horizontalAlignment: Text.AlignRight
                            text: view.bytesHuman((Number(modelData.rss_kb) || 0) * 1024)
                            color: view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
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
        }
    }
}
