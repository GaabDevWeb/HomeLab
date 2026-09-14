import QtQuick
import QtQuick.Layouts

// Micro-barras WORKSPACE + SYSTEM STATUS — satélites da ilha principal.
// Mesmo DNA visual da capsule (colBg, pillH, radius, animFast); sem blur/borda.
// Não é taskbar: só “onde estou?” e “está tudo bem?”.
Item {
    id: sats

    property var sys
    property Item capsuleItem

    // Tokens herdados da navbar (fonte da verdade = capsule)
    readonly property real navH: sys ? sys.pillH : 38
    readonly property real navGap: {
        if (!sys) return 16
        // notch: islandGap=0 → gap mínimo entre ilha e satélites
        var g = Number(sys.cfg && sys.cfg.islandGap) || 0
        return Math.max(16, g > 0 ? g : 16)
    }
    readonly property real navEdge: {
        if (!sys) return 0
        return sys.cfg.notchMode ? 0 : (Number(sys.cfg.islandGap) || 12)
    }
    readonly property real edgeR: {
        if (!sys) return 19
        if (sys.settingsMode || !(sys.cfg && sys.cfg.notchMode))
            return (sys.cfg.islandRadius > 0 ? sys.cfg.islandRadius : 26)
        return 0
    }
    readonly property real freeR: {
        if (!sys) return 19
        if (sys.cfg.islandRadius > 0 && !(sys.cfg && sys.cfg.notchMode))
            return sys.cfg.islandRadius
        return navH / 2
    }

    // Âncoras horizontais: ~10% da borda (não colados à MAIN NAV)
    readonly property real sideInset: 0.10

    readonly property bool shown: {
        if (!sys || !capsuleItem) return false
        if (sys.pillSide) return false
        if (sys.pillHidden) return false
        if (sys.settingsMode) return false
        if (sys.wallsOpen) return false
        if (sys.osdActive || sys.toastActive) return false
        if (sys.btToastActive || sys.acToastActive) return false
        if (sys.recPickActive || sys.voxActive) return false
        // Permanecem visíveis com Homelab/páginas abertas (antes sumiam no expand)
        if (sys.fullscreenActive && !sys.expanded) return false
        if (!capsuleItem.visible || capsuleItem.opacity <= 0.01) return false
        if (!parent || parent.width < 900) return false
        return true
    }

    readonly property alias workspacePill: workspacePill
    readonly property alias statusPill: statusPill

    // Mesmo flare côncavo da ilha central (NotchCorner)
    readonly property bool notchFlare: {
        if (!sys || !sys.cfg) return false
        return !!sys.cfg.notchMode && Number(sys.cornerR) > 0
               && (sys.pillAtTop || sys.pillAtBottom)
    }
    readonly property real flareR: sys ? Number(sys.cornerR) : 0
    readonly property real flareOpacity: (shown && notchFlare && sys && sys.cornersOn) ? 1 : 0

    opacity: shown ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: sys ? sys.animFast : 120 } }

    // ----------------------------------------------------------- WORKSPACE
    Rectangle {
        id: workspacePill
        height: sats.navH
        width: Math.max(wsRow.implicitWidth + 28, 72)
        y: capsuleItem ? capsuleItem.y : sats.navEdge
        x: {
            if (!sats.parent) return sats.navGap
            var target = sats.parent.width * sats.sideInset - width / 2
            var minX = sats.navGap
            var maxX = sats.parent.width - width - sats.navGap
            if (capsuleItem && !(sys && sys.expanded && !(sys.cfg && sys.cfg.pillKeepVisible))) {
                maxX = Math.min(maxX, capsuleItem.x - sats.navGap - width)
            }
            return Math.max(minX, Math.min(target, maxX))
        }
        color: sys ? sys.colBg : "#000"
        topLeftRadius:     sys && sys.pillAtTop ? sats.edgeR : sats.freeR
        topRightRadius:    sys && sys.pillAtTop ? sats.edgeR : sats.freeR
        bottomLeftRadius:  sys && sys.pillAtBottom ? sats.edgeR : sats.freeR
        bottomRightRadius: sys && sys.pillAtBottom ? sats.edgeR : sats.freeR
        border.width: 0
        clip: true

        Behavior on x { NumberAnimation { duration: sys ? sys.animMs : 200; easing.type: Easing.InOutCubic } }
        Behavior on y { NumberAnimation { duration: sys ? sys.animMs : 200; easing.type: Easing.InOutCubic } }

        RowLayout {
            id: wsRow
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: (sys && sys.wsList && sys.wsList.length) ? sys.wsList : [1]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool here: sys && Number(modelData) === Number(sys.wsId)
                    property real len: here ? 17 : 6
                    property bool settled: false
                    Component.onCompleted: settled = true
                    Layout.preferredWidth: len
                    Layout.preferredHeight: 6
                    Layout.alignment: Qt.AlignVCenter
                    radius: 3
                    color: sys ? sys.colFg : "#fff"
                    opacity: here ? 1 : (wsMa.containsMouse ? 0.6 : 0.3)

                    Behavior on len {
                        enabled: settled
                        NumberAnimation { duration: sys ? sys.animMs : 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: sys ? sys.animFast : 120 }
                    }

                    MouseArea {
                        id: wsMa
                        anchors.fill: parent
                        anchors.margins: -5
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (sys) sys.gotoWorkspace(modelData)
                    }
                }
            }
        }
    }

    NotchCorner {
        side: "left"
        fill: sys ? sys.colBg : "#000"
        r: sats.flareR
        x: Math.round(workspacePill.x) - width
        y: sys && sys.pillAtBottom ? (sats.parent ? sats.parent.height - height : 0) : 0
        transform: Scale {
            origin.y: sats.flareR / 2
            yScale: (sys && sys.pillAtBottom) ? -1 : 1
        }
        opacity: sats.flareOpacity
        Behavior on opacity { NumberAnimation { duration: sys ? sys.animFast : 120 } }
    }
    NotchCorner {
        side: "right"
        fill: sys ? sys.colBg : "#000"
        r: sats.flareR
        x: Math.round(workspacePill.x + workspacePill.width)
        y: sys && sys.pillAtBottom ? (sats.parent ? sats.parent.height - height : 0) : 0
        transform: Scale {
            origin.y: sats.flareR / 2
            yScale: (sys && sys.pillAtBottom) ? -1 : 1
        }
        opacity: sats.flareOpacity
        Behavior on opacity { NumberAnimation { duration: sys ? sys.animFast : 120 } }
    }

    // ------------------------------------------------------- SYSTEM STATUS
    Rectangle {
        id: statusPill
        height: sats.navH
        width: Math.max(stRow.implicitWidth + 28, 96)
        y: capsuleItem ? capsuleItem.y : sats.navEdge
        x: {
            if (!sats.parent) return sats.navGap
            var target = sats.parent.width * (1 - sats.sideInset) - width / 2
            var minX = sats.navGap
            var maxX = sats.parent.width - width - sats.navGap
            if (capsuleItem && !(sys && sys.expanded && !(sys.cfg && sys.cfg.pillKeepVisible))) {
                minX = Math.max(minX, capsuleItem.x + capsuleItem.width + sats.navGap)
            }
            return Math.max(minX, Math.min(target, maxX))
        }
        color: sys ? sys.colBg : "#000"
        topLeftRadius:     sys && sys.pillAtTop ? sats.edgeR : sats.freeR
        topRightRadius:    sys && sys.pillAtTop ? sats.edgeR : sats.freeR
        bottomLeftRadius:  sys && sys.pillAtBottom ? sats.edgeR : sats.freeR
        bottomRightRadius: sys && sys.pillAtBottom ? sats.edgeR : sats.freeR
        border.width: 0
        clip: true

        Behavior on x { NumberAnimation { duration: sys ? sys.animMs : 200; easing.type: Easing.InOutCubic } }
        Behavior on y { NumberAnimation { duration: sys ? sys.animMs : 200; easing.type: Easing.InOutCubic } }

        RowLayout {
            id: stRow
            anchors.centerIn: parent
            spacing: 12

            Repeater {
                model: sys ? sys.navStatusItems : []
                delegate: Item {
                    required property var modelData
                    implicitWidth: stInner.implicitWidth
                    implicitHeight: stInner.implicitHeight
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        id: stInner
                        spacing: 5
                        anchors.centerIn: parent

                        Text {
                            text: modelData.label || ""
                            color: sys ? sys.colMuted : "#888"
                            font {
                                family: sys ? sys.fontBody : "sans"
                                pixelSize: sys ? Math.max(10, sys.fontSize - 4) : 10
                                letterSpacing: 0.6
                            }
                        }
                        Text {
                            text: modelData.glyph || "—"
                            color: modelData.color
                            font {
                                family: sys ? sys.fontBody : "sans"
                                pixelSize: sys ? Math.max(10, sys.fontSize - 3) : 10
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: !!(modelData.section && modelData.section.length)
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (sys && modelData.section)
                                sys.openHomelab(modelData.section)
                        }
                    }
                }
            }
        }
    }

    NotchCorner {
        side: "left"
        fill: sys ? sys.colBg : "#000"
        r: sats.flareR
        x: Math.round(statusPill.x) - width
        y: sys && sys.pillAtBottom ? (sats.parent ? sats.parent.height - height : 0) : 0
        transform: Scale {
            origin.y: sats.flareR / 2
            yScale: (sys && sys.pillAtBottom) ? -1 : 1
        }
        opacity: sats.flareOpacity
        Behavior on opacity { NumberAnimation { duration: sys ? sys.animFast : 120 } }
    }
    NotchCorner {
        side: "right"
        fill: sys ? sys.colBg : "#000"
        r: sats.flareR
        x: Math.round(statusPill.x + statusPill.width)
        y: sys && sys.pillAtBottom ? (sats.parent ? sats.parent.height - height : 0) : 0
        transform: Scale {
            origin.y: sats.flareR / 2
            yScale: (sys && sys.pillAtBottom) ? -1 : 1
        }
        opacity: sats.flareOpacity
        Behavior on opacity { NumberAnimation { duration: sys ? sys.animFast : 120 } }
    }
}
