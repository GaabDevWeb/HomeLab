import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// Clipboard History — cliphist (Wayland) + pins locais.
// SUPER+V e SUPER+C → togglePage("clip"). Tudo LOCAL.
FocusScope {
    id: view
    property var sys

    implicitHeight: col.implicitHeight

    ListModel { id: recentModel }
    ListModel { id: pinnedModel }
    property string query: ""
    property var pins: []   // [{text, ts}]
    property bool ignoreSensitive: true

    readonly property string pinsPath: Quickshell.env("HOME") + "/.config/panacea/clipboard_pins.json"

    function classify(text) {
        var t = String(text || "")
        if (/^https?:\/\//i.test(t.trim())) return "URL"
        if (/^(sudo\s+)?(docker|git|npm|pnpm|yarn|systemctl|ssh|curl|wget|python|pip|cargo|make)\b/i.test(t.trim())
            || (/^\S+$/.test(t.trim()) && t.indexOf(" ") < 0 && t.length < 80 && /^(ls|cd|pwd|ps|top)/.test(t)))
            return "COMMAND"
        if (t.indexOf("\n") >= 0 && /[{};]|def |function |class |=>|#!/i.test(t))
            return "CODE"
        return "TEXT"
    }

    function looksSensitive(text) {
        var t = String(text || "")
        return /BEGIN .*PRIVATE KEY|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|^(password|passwd|secret|token|api[_-]?key)\s*[:=]/i.test(t)
    }

    function loadPins() {
        pPinsRead.running = false
        pPinsRead.running = true
    }

    function savePins() {
        var payload = JSON.stringify({ ignore_sensitive: view.ignoreSensitive, pins: view.pins })
        pPinsWrite.command = ["sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
            "_", view.pinsPath, payload]
        pPinsWrite.running = false
        pPinsWrite.running = true
    }

    function rebuildPinnedModel() {
        pinnedModel.clear()
        var q = view.query.toLowerCase()
        for (var i = 0; i < view.pins.length; i++) {
            var it = view.pins[i]
            var text = String(it.text || "")
            if (q.length && text.toLowerCase().indexOf(q) < 0) continue
            pinnedModel.append({
                cid: "pin:" + i,
                pinIndex: i,
                preview: text.replace(/\n/g, " ").slice(0, 120),
                full: text,
                pinned: true,
                kind: view.classify(text),
                isImage: false
            })
        }
    }

    function reload() {
        recentModel.clear()
        view.rebuildPinnedModel()
        pList.running = false
        pList.running = true
    }

    function copyText(text) {
        pCopy.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", text]
        pCopy.running = true
        view.sys.collapse()
    }

    function copyAt(section, i) {
        var m = section === "pin" ? pinnedModel : recentModel
        if (i < 0 || i >= m.count) return
        var row = m.get(i)
        if (row.pinned)
            view.copyText(row.full)
        else {
            pCopy.command = ["sh", "-c",
                "printf '%s\\t' \"$1\" | cliphist decode | wl-copy", "_", row.cid]
            pCopy.running = true
            view.sys.collapse()
        }
    }

    function pinText(text) {
        text = String(text || "")
        if (!text.length) return
        if (view.ignoreSensitive && view.looksSensitive(text)) return
        // dedupe
        var next = []
        for (var i = 0; i < view.pins.length; i++)
            if (view.pins[i].text !== text) next.push(view.pins[i])
        next.unshift({ text: text, ts: Math.floor(Date.now() / 1000) })
        if (next.length > 50) next = next.slice(0, 50)
        view.pins = next
        view.savePins()
        view.rebuildPinnedModel()
    }

    function unpinAt(i) {
        if (i < 0 || i >= view.pins.length) return
        var next = view.pins.slice()
        next.splice(i, 1)
        view.pins = next
        view.savePins()
        view.rebuildPinnedModel()
    }

    function deleteRecent(cid) {
        pDel.command = ["sh", "-c", "printf '%s\\t' \"$1\" | cliphist delete", "_", cid]
        pDel.running = true
    }

    function decodeThenPin(cid) {
        pDecodePin.command = ["sh", "-c",
            "printf '%s\\t' \"$1\" | cliphist decode", "_", cid]
        pDecodePin.running = false
        pDecodePin.running = true
    }

    Process {
        id: pList
        command: ["sh", "-c", "cliphist list"]
        stdout: SplitParser {
            onRead: line => {
                var t = line.indexOf("\t")
                if (t < 0) return
                var id = line.substring(0, t)
                var preview = line.substring(t + 1).trim()
                if (!preview.length) return
                if (view.query.length &&
                    preview.toLowerCase().indexOf(view.query.toLowerCase()) < 0) return
                if (recentModel.count >= 120) return
                var isImage = /^\[\[\s*binary data/.test(preview)
                recentModel.append({
                    cid: id,
                    preview: preview,
                    full: "",
                    pinned: false,
                    kind: isImage ? "IMAGE" : view.classify(preview),
                    isImage: isImage
                })
            }
        }
    }

    Process { id: pCopy }
    Process {
        id: pDel
        stdout: StdioCollector { onStreamFinished: view.reload() }
    }
    Process {
        id: pWipe
        command: ["sh", "-c", "cliphist wipe"]
        stdout: StdioCollector { onStreamFinished: view.reload() }
    }
    Process {
        id: pDecodePin
        stdout: StdioCollector {
            onStreamFinished: {
                var t = String(text)
                if (t.length) view.pinText(t)
            }
        }
    }
    Process {
        id: pPinsRead
        command: ["sh", "-c", "test -f \"$1\" && cat \"$1\" || echo '{}'", "_", view.pinsPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    view.pins = Array.isArray(d.pins) ? d.pins : []
                    if (d.ignore_sensitive !== undefined)
                        view.ignoreSensitive = !!d.ignore_sensitive
                } catch (e) {
                    view.pins = []
                }
                view.rebuildPinnedModel()
            }
        }
    }
    Process { id: pPinsWrite }

    Component.onCompleted: {
        view.loadPins()
        view.reload()
    }
    FocusGrabber { target: input }

    function activeCopy() {
        if (pinnedModel.count > 0)
            view.copyAt("pin", 0)
        else if (recentModel.count > 0)
            view.copyAt("recent", 0)
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
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
                        text: "󰅍"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.iconSize - 2 }
                    }

                    TextField {
                        id: input
                        focus: true
                        Layout.fillWidth: true
                        placeholderText: "search clipboard…"
                        color: view.sys.colFg
                        placeholderTextColor: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                        background: null
                        onTextEdited: { view.query = text; view.reload() }

                        Keys.onEscapePressed: view.sys.collapse()
                        Keys.onReturnPressed: view.activeCopy()
                        Keys.onDownPressed: { /* lista via mouse; Enter copia topo filtrado */ }
                        Keys.onUpPressed: { }
                    }

                    Text {
                        visible: view.sys.cfg.featVault
                        text: String.fromCodePoint(view.sys.vaultUnlocked ? 0xF0FC6 : 0xF033E)
                        color: view.sys.vaultUnlocked ? view.sys.colOk : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.iconSize - 3 }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.sys.togglePage("vault")
                        }
                    }

                    Text {
                        text: "󰩹"
                        color: wipeMa.containsMouse ? view.sys.colCrit : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.iconSize - 3 }
                        MouseArea {
                            id: wipeMa
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { pWipe.running = true }
                        }
                    }
                }
            }
        }

        // PINNED
        Text {
            visible: pinnedModel.count > 0
            text: "PINNED"
            color: view.sys.colMuted
            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4; bold: true; letterSpacing: 1 }
        }
        Repeater {
            model: pinnedModel
            delegate: Rectangle {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                height: 40
                radius: 10
                color: pinMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    Text { text: "★"; color: view.sys.colOn; font { family: view.sys.fontFam; pixelSize: 12 } }
                    Text {
                        text: modelData.kind
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 9 }
                        Layout.preferredWidth: 52
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.preview
                        elide: Text.ElideRight
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                    }
                    Text {
                        text: "UNPIN"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 9 }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.unpinAt(modelData.pinIndex)
                        }
                    }
                }
                MouseArea {
                    id: pinMa
                    anchors.fill: parent
                    anchors.rightMargin: 56
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.copyAt("pin", index)
                }
            }
        }

        Text {
            text: "RECENT"
            color: view.sys.colMuted
            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4; bold: true; letterSpacing: 1 }
            Layout.topMargin: pinnedModel.count ? 4 : 0
        }

        Repeater {
            model: recentModel
            delegate: Rectangle {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                height: 40
                radius: 10
                color: recMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    Text {
                        text: modelData.isImage ? "󰋩" : "󰈙"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.iconSize - 3 }
                    }
                    Text {
                        text: modelData.kind
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 9 }
                        Layout.preferredWidth: 52
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.isImage ? "image" : modelData.preview
                        elide: Text.ElideRight
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                    }
                    Text {
                        visible: !modelData.isImage
                        text: "PIN"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 9 }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.decodeThenPin(modelData.cid)
                        }
                    }
                    Text {
                        text: "DEL"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 9 }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.deleteRecent(modelData.cid)
                        }
                    }
                }
                MouseArea {
                    id: recMa
                    anchors.fill: parent
                    anchors.rightMargin: 72
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.copyAt("recent", index)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: pinnedModel.count === 0 && recentModel.count === 0
            text: view.query.length ? "nothing found" : "clipboard empty"
            color: view.sys.colMuted
            horizontalAlignment: Text.AlignHCenter
            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
        }
    }
}
