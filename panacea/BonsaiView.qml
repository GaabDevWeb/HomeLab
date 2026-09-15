import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Stub de estado do agente Bonsai — sem mocks inventados.
// Lê ~/.config/gaab-homelab/bonsai/status.json se existir; senão OFFLINE.
Item {
    id: view
    property var sys

    property var status: ({
        state: "OFFLINE",
        model: "",
        context: "",
        last_action: "",
        last_response_ago: "",
        connected: false
    })

    implicitHeight: col.implicitHeight
    focus: true

    function goBack() { view.sys.page = "main"; return true }
    Keys.onEscapePressed: view.goBack()

    readonly property string statusPath: Quickshell.env("HOME") + "/.config/gaab-homelab/bonsai/status.json"

    function refresh() {
        pSt.running = false
        pSt.running = true
    }

    function glyph(st) {
        st = String(st || "").toUpperCase()
        if (st === "IDLE" || st === "READY") return "●"
        if (st === "THINKING") return "◌"
        if (st === "EXECUTING") return "◐"
        if (st === "DONE") return "✓"
        if (st === "ERROR") return "!"
        return "○"
    }

    function colorOf(st) {
        st = String(st || "").toUpperCase()
        if (st === "ERROR") return view.sys.colCrit
        if (st === "DONE" || st === "IDLE" || st === "READY") return view.sys.colOk
        if (st === "THINKING" || st === "EXECUTING") return view.sys.colWarn
        return view.sys.colMuted
    }

    Process {
        id: pSt
        command: ["sh", "-c",
            "if [ -f \"$1\" ]; then cat \"$1\"; else echo '{\"state\":\"OFFLINE\",\"connected\":false}'; fi",
            "_", view.statusPath]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    view.status = {
                        state: String(d.state || "OFFLINE").toUpperCase(),
                        model: d.model || "",
                        context: d.context || "",
                        last_action: d.last_action || "",
                        last_response_ago: d.last_response_ago || "",
                        connected: !!d.connected
                    }
                } catch (e) {
                    view.status = {
                        state: "OFFLINE", model: "", context: "",
                        last_action: "", last_response_ago: "", connected: false
                    }
                }
            }
        }
    }

    Timer {
        interval: 4000
        repeat: true
        running: view.visible
        onTriggered: view.refresh()
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
                text: "BONSAI"
                color: view.sys.colFg
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize + 1; bold: true }
            }
            Text {
                text: view.glyph(view.status.state) + "  " + (view.status.state || "OFFLINE")
                color: view.colorOf(view.status.state)
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 1; bold: true }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.04)
            border.color: view.sys.colLine
            border.width: 1
            implicitHeight: body.implicitHeight + 20
            ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: {
                        if (!view.status.connected && view.status.state === "OFFLINE")
                            return "STATUS   NOT CONNECTED\n\nAguarda o agente Bonsai escrever\n~/.config/gaab-homelab/bonsai/status.json\n\nO rice partilha métricas via\nmetricsHistory (mesma fonte do SYSTEM)."
                        return "STATUS   " + (view.status.state || "—") + "\n"
                            + "MODEL    " + (view.status.model || "—") + "\n"
                            + "CONTEXT  " + (view.status.context || "—") + "\n"
                            + "ACTION   " + (view.status.last_action || "—") + "\n"
                            + "LAST     " + (view.status.last_response_ago || "—")
                    }
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Clipboard NÃO é partilhado com o Bonsai."
            color: view.sys.colMuted
            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3; italic: true }
        }
    }
}
