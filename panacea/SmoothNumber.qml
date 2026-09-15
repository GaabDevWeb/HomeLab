import QtQuick

// Número com interpolação visual curta (apresentação, não atraso semântico).
// target muda → displayed anima ~120–180ms em direção ao valor real.
Text {
    id: root
    property real target: 0
    property int decimals: 0
    property string suffix: ""
    property string prefix: ""
    property var sys
    property int duration: 140

    property real displayed: 0

    text: root.prefix + root.displayed.toFixed(root.decimals) + root.suffix
    color: root.sys ? root.sys.colFg : "#ffffff"
    font {
        family: root.sys ? root.sys.fontFam : "JetBrainsMono Nerd Font"
        pixelSize: root.sys ? root.sys.fontSize - 1 : 14
    }

    Behavior on displayed {
        NumberAnimation {
            duration: (root.sys && root.sys.noMotion) ? 0 : root.duration
            easing.type: Easing.OutCubic
        }
    }

    onTargetChanged: root.displayed = root.target
    Component.onCompleted: root.displayed = root.target
}
