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

    // Create-service form
    property bool creating: false
    property string formName: ""
    property string formDir: ""
    property string formCmd: ""
    property string formPort: ""

    implicitHeight: col.implicitHeight

    readonly property string sh: view.sys.scriptDir + "/homelab.sh"

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
        var cmd = ["sh", view.sh, "sys"]
        if (view.section === "net") cmd = ["sh", view.sh, "net"]
        else if (view.section === "storage") cmd = ["sh", view.sh, "storage"]
        else if (view.section === "docker") cmd = ["sh", view.sh, "docker"]
        else if (view.section === "ai") cmd = ["sh", view.sh, "ai"]
        else if (view.section === "dev") cmd = ["sh", view.sh, "projects"]
        else if (view.section === "run") cmd = ["sh", view.sh, "services"]
        else if (view.section === "logs") cmd = ["sh", view.sh, "logs", view.detail || "system"]
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
        pAct.command = ["sh", view.sh].concat(argv)
        pAct.running = false
        pAct.running = true
    }

    function openTerm(cwd) {
        var dir = cwd && cwd.length ? cwd : Quickshell.env("HOME")
        Quickshell.execDetached(["footclient"], { workingDirectory: dir })
    }

    Process {
        id: pHub
        command: ["sh", view.sh, "hub"]
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
        command: ["sh", view.sh, "sys"]
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
                view.refresh()
            }
        }
    }

    Connections {
        target: view.sys
        function onHomelabEpochChanged() { view.section = "hub"; view.detail = ""; view.refresh() }
    }

    Timer {
        interval: 15000; repeat: true; running: true
        onTriggered: if (view.section === "hub" || view.section === "sys") view.refresh()
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
                text: view.creating ? view.sys.tr("NEW SERVICE")
                    : (view.detail !== "" ? view.detail.toUpperCase()
                    : (view.section === "hub" ? view.sys.tr("HOMELAB") : view.section.toUpperCase()))
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
                        spacing: 10
                        Text {
                            text: "●"
                            color: view.statusColor(modelData.ok)
                            font.pixelSize: 12
                        }
                        Text {
                            text: modelData.label
                            color: view.sys.colFg
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1; letterSpacing: 1 }
                            Layout.preferredWidth: 72
                        }
                        Text {
                            Layout.fillWidth: true
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
                text: "UPTIME  " + (view.payload.uptime || "—") + "\n"
                    + "KERNEL  " + (view.payload.kernel || "—") + "\n"
                    + "HOST    " + (view.payload.hostname || "—") + "\n"
                    + "OS      " + (view.payload.os || "—")
                    + (view.payload.vram ? ("\nVRAM    " + view.payload.vram) : "")
                color: view.sys.colMuted
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 2 }
            }
        }

        // ---------------- NET
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.section === "net"
            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "IFACE   " + (view.payload.iface || "—") + "\n"
                    + "IP      " + (view.payload.ip || "—") + "\n"
                    + "GATEWAY " + (view.payload.gateway || "—") + "\n"
                    + "DNS     " + (view.payload.dns || "—") + "\n"
                    + "RX      " + view.bytesHuman(view.payload.rx_bytes) + "\n"
                    + "TX      " + view.bytesHuman(view.payload.tx_bytes)
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
                text: "ROOT    " + ((view.payload.root && view.payload.root.pct) || "—") + "%\n"
                    + "/srv    " + ((view.payload.srv && view.payload.srv.pct) || "—") + "%\n"
                    + "HEALTH  " + (view.payload.health || "—")
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
                visible: !(view.payload.ok)
                text: view.sys.tr("Docker offline")
                color: view.sys.colWarn
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
                        Text { text: modelData.running ? "●" : "○"; color: modelData.running ? view.sys.colOk : view.sys.colMuted }
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
            RowLayout {
                spacing: 8
                HomelabBtn { label: "LOGS"; onClicked: view.runAction(["docker-action", "logs", view.detail]) }
                HomelabBtn { label: "RESTART"; onClicked: view.runAction(["docker-action", "restart", view.detail]) }
                HomelabBtn { label: "STOP"; onClicked: view.runAction(["docker-action", "stop", view.detail]) }
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

        // ---------------- RUN / SERVICES
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.section === "run" && !view.creating && view.detail === ""
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
            Text {
                text: view.sys.tr("Persistent via systemd --user · closing Terminal does not stop the process")
                color: view.sys.colMuted
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
            }
            Repeater {
                model: view.payload.services || []
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 52
                    radius: 14
                    color: sMa.containsMouse ? Qt.rgba(1,1,1,0.06) : Qt.rgba(1,1,1,0.03)
                    border.color: view.sys.colLine; border.width: 1
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: modelData.running ? "●" : "○"; color: modelData.running ? view.sys.colOk : (modelData.state === "failed" ? view.sys.colCrit : view.sys.colMuted) }
                            Text {
                                text: modelData.name
                                color: view.sys.colFg
                                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 1 }
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.state ? String(modelData.state).toUpperCase() : ""
                                color: view.sys.colMuted
                                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                            }
                        }
                        Text {
                            text: modelData.command || ""
                            color: view.sys.colMuted
                            elide: Text.ElideRight
                            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 3 }
                        }
                    }
                    MouseArea {
                        id: sMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: view.detail = modelData.name
                    }
                }
            }
        }

        // RUN detail
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.section === "run" && !view.creating && view.detail !== ""
            Text {
                text: view.detail.toUpperCase()
                color: view.sys.colFg
                font { family: view.sys.fontBody; pixelSize: view.sys.fontSize }
            }
            RowLayout {
                spacing: 8
                HomelabBtn { label: "START"; onClicked: view.runAction(["service-start", view.detail]) }
                HomelabBtn { label: "STOP"; onClicked: view.runAction(["service-stop", view.detail]) }
                HomelabBtn { label: "RESTART"; onClicked: view.runAction(["service-restart", view.detail]) }
            }
            RowLayout {
                spacing: 8
                HomelabBtn { label: "LOGS"; onClicked: view.runAction(["service-logs", view.detail]) }
                HomelabBtn {
                    label: "TERMINAL"
                    onClicked: {
                        var svc = null
                        var list = view.payload.services || []
                        for (var i = 0; i < list.length; i++) if (list[i].name === view.detail) svc = list[i]
                        view.openTerm(svc && svc.directory ? svc.directory : "")
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
