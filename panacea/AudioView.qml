import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Звук: общая громкость, устройство вывода, EasyEffects + спектр Cava.
Item {
    id: view
    property var sys

    implicitHeight: col.implicitHeight

    focus: true
    function goBack() { view.sys.page = "main"; return true; }
    Keys.onEscapePressed: view.goBack()

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var sinkAudio: sink ? sink.audio : null

    // EasyEffects (semantic bridge — não DSP próprio)
    property var ee: ({
        available: false, bypass: false, preset: "", presets: [],
        quick_presets: [], bands: [], eq: false, ok: true, error: ""
    })
    readonly property string eeSh: view.sys.scriptDir + "/easyeffects.sh"

    // EQ display state (interpolação local — sem polling EE por frame)
    property var displayGains: []
    property var animFrom: []
    property var animTo: []
    property real eeAnimT: 0
    property real eeSweep: 0
    property real eeLineOpacity: 0
    property bool eeAnimating: false
    property bool eeApplying: false
    property string eeApplyError: ""
    property int eeAnimToken: 0

    readonly property var quickPresetModel: {
        var q = view.ee.quick_presets || []
        if (q.length) return q
        return [
            { id: "volume_boost", label: "VOLUME BOOST", ee: "volume_boost" },
            { id: "quality", label: "QUALITY", ee: "quality" },
            { id: "bass", label: "BASS", ee: "bass" },
            { id: "detail", label: "DETAIL", ee: "detail" },
            { id: "gaming", label: "GAMING", ee: "gaming" }
        ]
    }

    function eeApplyPayload(d, animate) {
        var bands = d.bands || []
        var next = {
            available: d.available !== undefined ? !!d.available : view.ee.available,
            bypass: d.bypass !== undefined ? !!d.bypass : view.ee.bypass,
            preset: d.preset !== undefined ? (d.preset || "") : view.ee.preset,
            presets: d.presets !== undefined ? (d.presets || []) : view.ee.presets,
            quick_presets: d.quick_presets !== undefined ? (d.quick_presets || []) : view.ee.quick_presets,
            bands: bands,
            eq: d.eq !== undefined ? !!d.eq : (bands.length > 0),
            ok: d.ok !== undefined ? !!d.ok : true,
            error: d.error || ""
        }
        view.ee = next
        if (d.ok === false && d.error)
            view.eeApplyError = d.error
        else if (d.ok !== false)
            view.eeApplyError = ""

        if (bands.length) {
            if (animate && view.displayGains.length === bands.length)
                view.eeStartAnim(bands)
            else
                view.eeSnapGains(bands)
        }
    }

    function eeGainsFromBands(bands) {
        var g = []
        for (var i = 0; i < bands.length; i++)
            g.push(Number(bands[i].gain) || 0)
        return g
    }

    function eeSnapGains(bands) {
        eeAnim.stop()
        eeSweepAnim.stop()
        eeFadeAnim.stop()
        view.eeAnimating = false
        view.eeAnimT = 1
        view.eeSweep = 0
        view.eeLineOpacity = 0
        view.displayGains = view.eeGainsFromBands(bands)
        if (eqCanvas)
            eqCanvas.requestPaint()
    }

    function eeStartAnim(bands) {
        var to = view.eeGainsFromBands(bands)
        var from = view.displayGains.length === to.length
                   ? view.displayGains.slice()
                   : to.slice()
        view.animFrom = from
        view.animTo = to
        view.eeAnimToken++
        view.eeAnimating = true
        view.eeAnimT = 0
        view.eeSweep = 0
        view.eeLineOpacity = 0.85
        eeAnim.stop(); eeSweepAnim.stop(); eeFadeAnim.stop()
        eeAnim.start()
        eeSweepAnim.start()
    }

    function eeInterpGains(t) {
        var from = view.animFrom
        var to = view.animTo
        var out = []
        var n = Math.min(from.length, to.length)
        for (var i = 0; i < n; i++)
            out.push(from[i] + (to[i] - from[i]) * t)
        view.displayGains = out
        if (eqCanvas)
            eqCanvas.requestPaint()
    }

    function displayGainAt(i) {
        if (i >= 0 && i < view.displayGains.length)
            return view.displayGains[i]
        var bands = view.ee.bands || []
        if (i >= 0 && i < bands.length)
            return Number(bands[i].gain) || 0
        return 0
    }

    function eeIsQuickActive(id) {
        return String(view.ee.preset || "") === String(id)
    }

    Process {
        id: pEe
        command: ["bash", view.eeSh, "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    view.eeApplyPayload(d, false)
                } catch (e) {
                    view.ee = {
                        available: false, bypass: false, preset: "", presets: [],
                        quick_presets: [], bands: [], eq: false, ok: false, error: "parse"
                    }
                }
                view.eeApplying = false
            }
        }
    }
    Process {
        id: pEeAct
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text)
                    if (d.requested) {
                        // last-wins: descarta loads antigos
                        if (d.requested !== view._eePendingName)
                            return
                        view.eeApplying = false
                        if (d.ok === false) {
                            view.eeApplyError = d.error || "apply_failed"
                            view.eeApplyPayload(d, false)
                        } else {
                            view.eeApplyPayload(d, true)
                        }
                    } else {
                        view.eeApplying = false
                        view.eeApplyPayload(d, false)
                    }
                } catch (e) {
                    view.eeApplying = false
                    view.eeApplyError = "error"
                }
            }
        }
    }

    NumberAnimation {
        id: eeAnim
        target: view
        property: "eeAnimT"
        from: 0; to: 1
        duration: 420
        easing.type: Easing.OutCubic
        onStopped: {
            if (view.eeAnimT >= 0.999) {
                view.displayGains = view.animTo.slice()
                view.eeAnimating = false
                eeFadeAnim.start()
            }
        }
    }
    NumberAnimation {
        id: eeSweepAnim
        target: view
        property: "eeSweep"
        from: 0; to: 1
        duration: 420
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: eeFadeAnim
        target: view
        property: "eeLineOpacity"
        to: 0
        duration: 180
        easing.type: Easing.OutQuad
        onStopped: eqCanvas.requestPaint()
    }

    onEeAnimTChanged: {
        if (view.eeAnimating)
            view.eeInterpGains(view.eeAnimT)
    }
    onEeSweepChanged: eqCanvas.requestPaint()
    onEeLineOpacityChanged: eqCanvas.requestPaint()

    function eeRefresh() {
        pEe.running = false
        pEe.running = true
    }
    function eeBypassToggle() {
        if (!view.ee.available) return
        pEeAct.command = ["bash", view.eeSh, "bypass", "toggle"]
        pEeAct.running = false
        pEeAct.running = true
    }
    property int eeLoadToken: 0

    function eeLoad(name) {
        if (!view.ee.available || !name) return
        view.eeApplying = true
        view.eeApplyError = ""
        view.eeLoadToken++
        var token = view.eeLoadToken
        pEeAct.command = ["bash", view.eeSh, "load", name]
        pEeAct.running = false
        pEeAct.running = true
        // token capturado no stdout handler via property
        view._eePendingToken = token
        view._eePendingName = name
    }
    property int _eePendingToken: 0
    property string _eePendingName: ""
    function eeLoadQuick(id) {
        if (!view.ee.available || !id) return
        eeAnim.stop(); eeSweepAnim.stop(); eeFadeAnim.stop()
        view.eeAnimating = false
        view.eeLoad(id)
    }
    function eeSetBand(index, gainDb) {
        if (!view.ee.available) return
        // drag cancela transição
        eeAnim.stop(); eeSweepAnim.stop(); eeFadeAnim.stop()
        view.eeAnimating = false
        view.eeLineOpacity = 0

        view._eeBandIdx = index
        view._eeBandGain = gainDb
        var bands = (view.ee.bands || []).slice()
        var gains = view.displayGains.slice()
        for (var i = 0; i < bands.length; i++) {
            if (Number(bands[i].index) === Number(index)) {
                bands[i] = Object.assign({}, bands[i], { gain: gainDb })
                if (i < gains.length) gains[i] = gainDb
                break
            }
        }
        view.displayGains = gains
        view.ee = Object.assign({}, view.ee, { bands: bands })
        if (eqCanvas)
            eqCanvas.requestPaint()
        eeBandDebounce.restart()
    }
    property int _eeBandIdx: -1
    property real _eeBandGain: 0
    Timer {
        id: eeBandDebounce
        interval: 90
        onTriggered: {
            if (view._eeBandIdx < 0) return
            pEeAct.command = ["bash", view.eeSh, "band", String(view._eeBandIdx), String(view._eeBandGain)]
            pEeAct.running = false
            pEeAct.running = true
        }
    }
    function eeOpen() {
        pEeAct.command = ["bash", view.eeSh, "open"]
        pEeAct.running = false
        pEeAct.running = true
    }
    function eeFreqLabel(hz) {
        var n = Number(hz) || 0
        if (n >= 1000) return (n / 1000).toFixed(n % 1000 === 0 ? 0 : 1) + "k"
        return String(Math.round(n))
    }

    // poll leve só para sync se o usuário mudar preset no EE
    Timer {
        interval: 5000
        repeat: true
        running: view.visible && view.ee.available && !view.eeApplying && !view.eeAnimating
        onTriggered: {
            if (!pEe.running && !pEeAct.running) view.eeRefresh()
        }
    }

    Component.onCompleted: {
        forceActiveFocus();
        eeRefresh();
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            // назад к плиткам
            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 10
                color: backMa.containsMouse ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.06)
                Behavior on color { ColorAnimation { duration: 150 } }
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
                    onClicked: view.sys.page = "main"
                }
            }
            Text {
                Layout.fillWidth: true
                text: view.sys.tr("Звук")
                color: view.sys.colFg
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize + 1; bold: true }
            }
        }

        // ------------------------------------------------------- общая громкость
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                Layout.preferredWidth: 26
                horizontalAlignment: Text.AlignHCenter
                text: !view.sinkAudio ? String.fromCodePoint(0xF075F)
                    : view.sinkAudio.muted ? String.fromCodePoint(0xF075F)
                    : view.sinkAudio.volume < 0.34 ? String.fromCodePoint(0xF057F)
                    : view.sinkAudio.volume < 0.67 ? String.fromCodePoint(0xF0580)
                                                   : String.fromCodePoint(0xF057E)
                color: view.sinkAudio && view.sinkAudio.muted ? view.sys.colMuted : view.sys.colFg
                font { family: view.sys.fontFam; pixelSize: view.sys.iconSize }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (view.sinkAudio) view.sinkAudio.muted = !view.sinkAudio.muted
                }
            }

            Item {
                id: sl
                Layout.fillWidth: true
                Layout.preferredHeight: 26

                readonly property real pos: view.sinkAudio ? Math.max(0, Math.min(1, view.sinkAudio.volume)) : 0
                readonly property real usable: width - knob.width

                function setFromX(x) {
                    if (!view.sinkAudio) return;
                    var r = Math.max(0, Math.min(1, (x - knob.width / 2) / Math.max(1, usable)));
                    // Полностью плавная регулировка без ступенек
                    view.sinkAudio.volume = r;
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: knob.width / 2
                    width: parent.usable
                    height: 6
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.12)
                    Rectangle {
                        width: parent.width * sl.pos
                        height: parent.height
                        radius: 3
                        color: view.sys.colOn
                    }
                }
                Rectangle {
                    id: knob
                    width: 18; height: 18; radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    x: sl.pos * sl.usable
                    color: "#ffffff"
                    border.color: view.sys.colBg
                    border.width: view.sys.themeNothing ? 2 : 0
                    scale: drag.pressed ? 1.25 : (drag.containsMouse ? 1.1 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                }
                MouseArea {
                    id: drag
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => sl.setFromX(mouse.x)
                    onPositionChanged: mouse => { if (pressed) sl.setFromX(mouse.x); }
                }
            }

            Text {
                Layout.preferredWidth: 46
                horizontalAlignment: Text.AlignRight
                text: view.sinkAudio ? Math.round(view.sinkAudio.volume * 100) + "%" : "—"
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
            }
        }

        // -------------------------------------------------------- устройства
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 2
            text: view.sys.tr("Устройство вывода")
            color: view.sys.colMuted
            font {
                family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4
                bold: true; capitalization: Font.AllUppercase; letterSpacing: 1
            }
        }

        Repeater {
            model: view.sys.audioSinks

            Rectangle {
                id: dev
                required property var modelData
                readonly property bool active: Pipewire.defaultAudioSink === dev.modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: 12
                color: dev.active
                       ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.16)
                       : (devMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                border.color: dev.active
                              ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.40)
                              : view.sys.colLine
                border.width: 1
                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on border.color { ColorAnimation { duration: 160 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 13
                    anchors.rightMargin: 13
                    spacing: 11

                    Text {
                        text: String.fromCodePoint(0xF057E)
                        color: dev.active ? view.sys.colOn : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.iconSize - 2 }
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: String(dev.modelData.nickname || dev.modelData.description
                                     || dev.modelData.name || "")
                        color: dev.active ? view.sys.colFg : view.sys.colMuted
                        elide: Text.ElideRight
                        font {
                            family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2
                            bold: dev.active
                        }
                    }
                    Text {
                        visible: dev.active
                        text: String.fromCodePoint(0xF012C)
                        color: view.sys.colOn
                        font { family: view.sys.fontFam; pixelSize: view.sys.iconSize - 4 }
                    }
                }

                MouseArea {
                    id: devMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.sys.setSink(dev.modelData)
                }
            }
        }

            Text {
                visible: view.sys.audioSinks.length === 0
                Layout.fillWidth: true
                text: view.sys.tr("Нет устройств")
                color: view.sys.colMuted
                horizontalAlignment: Text.AlignHCenter
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
            }

            // ------------------------------------------ EasyEffects (presets / bypass)
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8
                Text {
                    text: "EASYEFFECTS"
                    color: view.sys.colMuted
                    font {
                        family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4
                        bold: true; capitalization: Font.AllUppercase; letterSpacing: 1
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: !view.ee.available
                    text: "unavailable"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3; italic: true }
                }
            }

            Rectangle {
                visible: view.ee.available
                Layout.fillWidth: true
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.05)
                border.color: view.sys.colLine
                border.width: 1
                implicitHeight: eeCol.implicitHeight + 18

                ColumnLayout {
                    id: eeCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "PRESET"
                            color: view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: view.eeApplying ? "APPLYING…" : (view.ee.preset || "—")
                            color: view.sys.colFg
                            elide: Text.ElideRight
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; bold: true }
                        }
                        Text {
                            visible: view.eeApplyError.length > 0
                            text: "failed"
                            color: view.sys.colWarn
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                        }
                        Rectangle {
                            height: 26; radius: 8
                            width: bypassLbl.implicitWidth + 16
                            color: view.ee.bypass
                                   ? Qt.rgba(view.sys.colWarn.r, view.sys.colWarn.g, view.sys.colWarn.b, 0.22)
                                   : Qt.rgba(view.sys.colOk.r, view.sys.colOk.g, view.sys.colOk.b, 0.18)
                            Text {
                                id: bypassLbl
                                anchors.centerIn: parent
                                text: view.ee.bypass ? "BYPASS" : "ACTIVE"
                                color: view.ee.bypass ? view.sys.colWarn : view.sys.colOk
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3; bold: true }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.eeBypassToggle()
                            }
                        }
                        Rectangle {
                            height: 26; radius: 8
                            width: openEeLbl.implicitWidth + 16
                            color: Qt.rgba(1, 1, 1, 0.06)
                            Text {
                                id: openEeLbl
                                anchors.centerIn: parent
                                text: "OPEN"
                                color: view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.eeOpen()
                            }
                        }
                    }

                    // presets dinâmicos EE → Quick Presets abaixo do EQ

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        visible: !view.ee.eq
                        text: "EQ bands: N/A — open EasyEffects or load a preset with equalizer"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3; italic: true }
                    }

                    // 10-band EQ + linha de transição (interpolação local)
                    Item {
                        id: eqHost
                        visible: view.ee.eq
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120

                        RowLayout {
                            id: eqRow
                            anchors.fill: parent
                            spacing: 4

                            Repeater {
                                model: view.ee.bands || []
                                delegate: Item {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    property real gain: {
                                        var _g = view.displayGains
                                        return view.displayGainAt(index)
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: 2

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: (gain >= 0 ? "+" : "") + gain.toFixed(0)
                                            color: view.sys.colMuted
                                            font { family: view.sys.fontFam; pixelSize: 9 }
                                        }

                                        Item {
                                            id: bandSl
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true

                                            function gainFromY(y) {
                                                var r = 1 - Math.max(0, Math.min(1, y / Math.max(1, height)))
                                                return Math.round((r * 48 - 24) * 2) / 2
                                            }
                                            function yFromGain(g) {
                                                var r = (Math.max(-24, Math.min(24, g)) + 24) / 48
                                                return (1 - r) * height
                                            }

                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: 4
                                                height: parent.height
                                                radius: 2
                                                color: Qt.rgba(1, 1, 1, 0.10)
                                                Rectangle {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.bottom: parent.bottom
                                                    width: parent.width
                                                    height: Math.max(2, parent.height * ((gain + 24) / 48))
                                                    radius: 2
                                                    color: view.sys.colOn
                                                }
                                            }

                                            Rectangle {
                                                width: 12; height: 12; radius: 6
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: Math.max(0, Math.min(parent.height - height, bandSl.yFromGain(gain) - height / 2))
                                                color: "#ffffff"
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                preventStealing: true
                                                onPressed: mouse => {
                                                    gain = bandSl.gainFromY(mouse.y)
                                                    view.eeSetBand(modelData.index, gain)
                                                }
                                                onPositionChanged: mouse => {
                                                    if (!pressed) return
                                                    gain = bandSl.gainFromY(mouse.y)
                                                    view.eeSetBand(modelData.index, gain)
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: view.eeFreqLabel(modelData.freq)
                                            color: view.sys.colMuted
                                            font { family: view.sys.fontFam; pixelSize: 9 }
                                        }
                                    }
                                }
                            }
                        }

                        Canvas {
                            id: eqCanvas
                            anchors.fill: parent
                            readonly property real topPad: 14
                            readonly property real botPad: 14
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                var gains = view.displayGains
                                var n = gains.length
                                if (n < 2 || view.eeLineOpacity <= 0.01) return

                                var usableH = height - topPad - botPad
                                function yOf(g) {
                                    var r = (Math.max(-24, Math.min(24, g)) + 24) / 48
                                    return topPad + (1 - r) * usableH
                                }

                                var pts = []
                                for (var i = 0; i < n; i++) {
                                    var x = (i + 0.5) * (width / n)
                                    pts.push({ x: x, y: yOf(gains[i]) })
                                }

                                var maxX = width * Math.max(0, Math.min(1, view.eeSweep))
                                ctx.beginPath()
                                ctx.strokeStyle = Qt.rgba(
                                    view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b,
                                    view.eeLineOpacity * 0.9
                                )
                                ctx.lineWidth = 1.5
                                ctx.lineJoin = "round"
                                ctx.lineCap = "round"

                                var started = false
                                for (var j = 0; j < pts.length; j++) {
                                    var p = pts[j]
                                    if (p.x > maxX) {
                                        if (j > 0 && started) {
                                            var prev = pts[j - 1]
                                            var t = (maxX - prev.x) / Math.max(0.001, p.x - prev.x)
                                            ctx.lineTo(maxX, prev.y + (p.y - prev.y) * t)
                                        }
                                        break
                                    }
                                    if (!started) { ctx.moveTo(p.x, p.y); started = true }
                                    else ctx.lineTo(p.x, p.y)
                                }
                                ctx.stroke()
                            }
                        }
                    }

                    Text {
                        visible: view.ee.available
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        text: "QUICK PRESETS"
                        color: view.sys.colMuted
                        font {
                            family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4
                            bold: true; letterSpacing: 1
                        }
                    }

                    Flow {
                        visible: view.ee.available
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: view.quickPresetModel
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool active: view.eeIsQuickActive(modelData.id || modelData.ee)
                                height: 26
                                radius: 8
                                width: qpRow.implicitWidth + 16
                                color: active
                                       ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.22)
                                       : Qt.rgba(1, 1, 1, 0.06)
                                border.width: active ? 1 : 0
                                border.color: active
                                              ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.45)
                                              : "transparent"

                                Row {
                                    id: qpRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: modelData.label || modelData.id
                                        color: active ? view.sys.colOn : view.sys.colFg
                                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                                    }
                                    Text {
                                        visible: active
                                        text: "ACTIVE"
                                        color: view.sys.colOn
                                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4; bold: true }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: view.eeLoadQuick(modelData.id || modelData.ee)
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------ espectro ao vivo (Cava)
            WaveBars {
                Layout.fillWidth: true
                Layout.preferredHeight: 88
                Layout.topMargin: 4
                barCount: 40
                gap: 2
                barColor: view.sys.colOn
                active: view.visible
            }
    }
}
