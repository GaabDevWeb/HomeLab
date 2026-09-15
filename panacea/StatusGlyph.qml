import QtQuick

// Status language compartilhada do rice.
// state: operational | offline | degraded | error | loading | done
// glyph: ● ○ ◐ ! ◌ ✓
Text {
    id: root
    property string state: "offline"
    property var sys
    property int size: 12

    readonly property string glyph: {
        var s = String(root.state || "").toLowerCase()
        if (s === "operational" || s === "ok" || s === "running" || s === "idle" || s === "ready")
            return "●"
        if (s === "degraded" || s === "attention" || s === "unhealthy" || s === "warn"
                || s === "thinking" || s === "executing")
            return "◐"
        if (s === "error" || s === "failed" || s === "crit")
            return "!"
        if (s === "loading" || s === "querying" || s === "applying" || s === "connecting"
                || s === "starting" || s === "stopping" || s === "reading")
            return "◌"
        if (s === "done" || s === "success")
            return "✓"
        return "○"  // offline / inactive / stopped
    }

    readonly property color ink: {
        var s = String(root.state || "").toLowerCase()
        if (!root.sys) return "#ffffff"
        if (s === "error" || s === "failed" || s === "crit") return root.sys.colCrit
        if (s === "degraded" || s === "attention" || s === "unhealthy" || s === "warn"
                || s === "thinking" || s === "executing" || s === "loading"
                || s === "querying" || s === "applying" || s === "connecting")
            return root.sys.colWarn
        if (s === "operational" || s === "ok" || s === "running" || s === "idle"
                || s === "ready" || s === "done" || s === "success")
            return root.sys.colOk
        return root.sys.colMuted
    }

    text: root.glyph
    color: root.ink
    font {
        family: root.sys ? root.sys.fontFam : "JetBrainsMono Nerd Font"
        pixelSize: root.size
        bold: true
    }
}
