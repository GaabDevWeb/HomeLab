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
    property string feedback: ""
    property int sel: 0   // índice flat: pins primeiro, depois recent

    readonly property string pinsPath: Quickshell.env("HOME") + "/.config/panacea/clipboard_pins.json"

    function flash(msg) {
        view.feedback = msg
        feedbackTimer.restart()
    }

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
        view.flash("✓ COPIED")
        feedbackClose.restart()
    }

    function copyAt(section, i) {
        var m = section === "pin" ? pinnedModel : recentModel
        if (i < 0 || i >= m.count) return
        var row = m.get(i)
        if (row.pinned) {
            view.copyText(row.full)
        } else {
            pCopy.command = ["sh", "-c",
                "printf '%s\\t' \"$1\" | cliphist decode | wl-copy", "_", row.cid]
            pCopy.running = true
            view.flash("✓ COPIED")
            feedbackClose.restart()
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
        view.flash("✓ PINNED")
    }

    function totalCount() { return pinnedModel.count + recentModel.count }

    function resolveSel() {
        var n = view.totalCount()
        if (n <= 0) { view.sel = 0; return null }
        if (view.sel < 0) view.sel = 0
        if (view.sel >= n) view.sel = n - 1
        if (view.sel < pinnedModel.count)
            return { section: "pin", i: view.sel }
        return { section: "recent", i: view.sel - pinnedModel.count }
    }

    function activateSel() {
        var r = view.resolveSel()
        if (!r) return
        view.copyAt(r.section, r.i)
    }

    function pinSel() {
        var r = view.resolveSel()
        if (!r) return
        if (r.section === "pin") return
        var row = recentModel.get(r.i)
        if (!row || row.isImage) return
        view.decodeThenPin(row.cid)
    }

    function deleteSel() {
        var r = view.resolveSel()
        if (!r) return
        if (r.section === "pin") view.unpinAt(r.i)
        else {
            var row = recentModel.get(r.i)
            if (row) view.deleteRecent(row.cid)
        }
    }

    Timer { id: feedbackTimer; interval: 700; onTriggered: view.feedback = "" }
    Timer {
        id: feedbackClose
        interval: 420
        onTriggered: view.sys.collapse()
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
                        onTextEdited: { view.query = text; view.sel = 0; view.reload() }

                        Keys.onEscapePressed: view.sys.collapse()
                        Keys.onReturnPressed: view.activateSel()
                        Keys.onEnterPressed: view.activateSel()
                        Keys.onDownPressed: {
                            if (view.totalCount() > 0)
                                view.sel = Math.min(view.sel + 1, view.totalCount() - 1)
                        }
                        Keys.onUpPressed: view.sel = Math.max(view.sel - 1, 0)
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                                view.pinSel(); event.accepted = true
                            } else if (event.key === Qt.Key_Delete) {
                                view.deleteSel(); event.accepted = true
                            }
                        }
                    }

                    Text {
                        visible: view.feedback.length > 0
                        text: view.feedback
                        color: view.sys.colOk
                        font { family: view.sys.fontFam; pixelSize: 10; bold: true }
                    }

                    Text {
                        visible: view.sys.cfg.featVault && view.feedback.length === 0
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
                color: (index === view.sel)
                       ? Qt.rgba(1, 1, 1, 0.12)
                       : (pinMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
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
                color: (index + pinnedModel.count === view.sel)
                       ? Qt.rgba(1, 1, 1, 0.12)
                       : (recMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
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
            text: view.query.length ? "nothing found" : "No clipped items."
            color: view.sys.colMuted
            horizontalAlignment: Text.AlignHCenter
            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
        }
    }
}
