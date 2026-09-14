import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// Calendar 2.0 — MONTH / DAY / events / deadlines / quick add.
// Visual do mês preservado; estado partilhado via sys.cal* (calendar.sh).
Item {
    id: view
    property var sys

    implicitHeight: col.implicitHeight
    focus: true

    property string mode: "month"   // month | day | add
    property int viewYear: (new Date()).getFullYear()
    property int viewMonth: (new Date()).getMonth()
    property int selYear: (new Date()).getFullYear()
    property int selMonth: (new Date()).getMonth()
    property int selDay: (new Date()).getDate()
    property int tick: 0            // força update da linha de hora / countdown

    // quick add fields
    property string fTitle: ""
    property string fDate: ""
    property string fStart: "09:00"
    property string fEnd: "10:00"
    property string fType: "EVENT"
    property string fDesc: ""
    property bool fAdvanced: false

    readonly property date today: new Date()
    readonly property string selYmd: {
        function z(n) { return (n < 10 ? "0" : "") + n }
        return selYear + "-" + z(selMonth + 1) + "-" + z(selDay)
    }

    readonly property var dayEvents: {
        var _ = view.sys.calEpoch
        return view.sys.calEventsForDay ? view.sys.calEventsForDay(view.selYmd) : []
    }

    readonly property var monthsRu: ["Январь","Февраль","Март","Апрель","Май","Июнь",
                                     "Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"]
    readonly property var monthsEn: ["January","February","March","April","May","June",
                                     "July","August","September","October","November","December"]
    readonly property var dowRu: ["Пн","Вт","Ср","Чт","Пт","Сб","Вс"]
    readonly property var dowEn: ["Mo","Tu","We","Th","Fr","Sa","Su"]
    readonly property var dowFullEn: ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    readonly property var dowFullRu: ["Воскресенье","Понедельник","Вторник","Среда","Четверг","Пятница","Суббота"]

    Component.onCompleted: {
        forceActiveFocus()
        view.sys.calRefresh()
        view.sys.calRefreshMonth(view.viewYear, view.viewMonth)
        view.fDate = view.sys.calYmd(new Date())
    }

    Keys.onEscapePressed: {
        if (view.mode === "add") { view.mode = "month"; return }
        if (view.mode === "day") { view.mode = "month"; return }
        view.sys.page = "main"
    }
    Keys.onLeftPressed: {
        if (view.mode === "day") view.shiftDay(-1)
        else view.shiftMonth(-1)
    }
    Keys.onRightPressed: {
        if (view.mode === "day") view.shiftDay(1)
        else view.shiftMonth(1)
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_T) { view.goToday(); event.accepted = true }
        else if (event.key === Qt.Key_Plus || (event.key === Qt.Key_Equal && (event.modifiers & Qt.ShiftModifier))) {
            view.openAdd(); event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (view.mode === "month") { view.openDay(view.selYear, view.selMonth, view.selDay); event.accepted = true }
        }
    }

    Timer {
        interval: 30000
        running: view.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: view.tick++
    }

    Connections {
        target: view.sys
        function onCalEpochChanged() {
            view.sys.calRefreshMonth(view.viewYear, view.viewMonth)
        }
    }

    function shiftMonth(delta) {
        var m = viewMonth + delta
        var y = viewYear
        while (m < 0)  { m += 12; y-- }
        while (m > 11) { m -= 12; y++ }
        viewMonth = m; viewYear = y
        view.sys.calRefreshMonth(viewYear, viewMonth)
    }

    function shiftDay(delta) {
        var d = new Date(selYear, selMonth, selDay + delta)
        selYear = d.getFullYear(); selMonth = d.getMonth(); selDay = d.getDate()
        viewYear = selYear; viewMonth = selMonth
        view.sys.calRefreshMonth(viewYear, viewMonth)
    }

    function goToday() {
        var t = new Date()
        viewYear = t.getFullYear(); viewMonth = t.getMonth()
        selYear = viewYear; selMonth = viewMonth; selDay = t.getDate()
        view.sys.calRefreshMonth(viewYear, viewMonth)
        if (view.mode === "add") view.mode = "month"
    }

    function openDay(y, m, d) {
        selYear = y; selMonth = m; selDay = d
        viewYear = y; viewMonth = m
        mode = "day"
    }

    function openAdd() {
        fTitle = ""
        fDate = selYmd
        fStart = "09:00"
        fEnd = "10:00"
        fType = "EVENT"
        fDesc = ""
        fAdvanced = false
        mode = "add"
    }

    function createEvent() {
        if (!fTitle.trim()) return
        view.sys.calCreate({
            title: fTitle.trim(),
            date: fDate || selYmd,
            start_time: fStart || "09:00",
            end_time: fEnd || fStart || "09:00",
            type: fType,
            description: fDesc
        })
        mode = "day"
        // sync sel to event date
        var p = (fDate || selYmd).split("-")
        if (p.length === 3) {
            selYear = +p[0]; selMonth = +p[1] - 1; selDay = +p[2]
            viewYear = selYear; viewMonth = selMonth
        }
    }

    function markFor(dayNum) {
        var marks = view.sys.calMarks || {}
        return marks[String(dayNum)] || null
    }

    function minsNow() {
        var _ = view.tick
        var n = new Date()
        return n.getHours() * 60 + n.getMinutes()
    }

    function parseHm(hm) {
        var p = String(hm || "0:0").split(":")
        return (+p[0] || 0) * 60 + (+p[1] || 0)
    }

    function fmtCountdown(sec) {
        sec = Number(sec) || 0
        if (sec <= 0) return "STARTED"
        if (sec < 60) return "in " + sec + "s"
        if (sec < 3600) return "in " + Math.round(sec / 60) + " min"
        var h = Math.floor(sec / 3600)
        var m = Math.round((sec % 3600) / 60)
        return "in " + h + "h " + m + "m"
    }

    readonly property var cells: {
        var _ = view.sys.calEpoch
        var first = new Date(viewYear, viewMonth, 1)
        var lead = (first.getDay() + 6) % 7
        var start = new Date(viewYear, viewMonth, 1 - lead)
        var out = []
        for (var i = 0; i < 42; i++) {
            var d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
            var inMonth = d.getMonth() === viewMonth
            var dayNum = d.getDate()
            var mk = inMonth ? view.markFor(dayNum) : null
            out.push({
                day: dayNum,
                y: d.getFullYear(),
                m: d.getMonth(),
                inMonth: inMonth,
                isToday: d.getFullYear() === today.getFullYear()
                         && d.getMonth() === today.getMonth()
                         && d.getDate() === today.getDate(),
                isSel: d.getFullYear() === selYear && d.getMonth() === selMonth && d.getDate() === selDay,
                weekend: i % 7 >= 5,
                hasEvent: mk && (mk.events > 0 || mk.tasks > 0),
                hasDeadline: mk && mk.deadlines > 0,
                multi: mk && ((mk.events || 0) + (mk.tasks || 0) + (mk.deadlines || 0)) > 1
            })
        }
        return out
    }

    component NavBtn: Rectangle {
        property string sym: ""
        signal pressedAction()
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        radius: 10
        color: navMa.containsMouse ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.06)
        Behavior on color { ColorAnimation { duration: 150 } }
        Text {
            anchors.centerIn: parent
            text: parent.sym
            color: view.sys.colMuted
            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize }
        }
        MouseArea {
            id: navMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.pressedAction()
        }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        // mode tabs + add
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { id: "month", label: "MONTH" },
                    { id: "day", label: "DAY" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    height: 24; radius: 8
                    width: tabLbl.implicitWidth + 14
                    color: view.mode === modelData.id ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.04)
                    Text {
                        id: tabLbl
                        anchors.centerIn: parent
                        text: modelData.label
                        color: view.mode === modelData.id ? view.sys.colFg : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.mode = modelData.id
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                height: 24; radius: 8
                width: plusLbl.implicitWidth + 14
                color: Qt.rgba(1, 1, 1, 0.06)
                Text {
                    id: plusLbl
                    anchors.centerIn: parent
                    text: "+"
                    color: view.sys.colFg
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.openAdd()
                }
            }
        }

        // NEXT EVENT
        Rectangle {
            Layout.fillWidth: true
            visible: view.mode !== "add" && view.sys.calNext && view.sys.calNext.title
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.05)
            border.color: view.sys.colLine
            border.width: 1
            implicitHeight: nextCol.implicitHeight + 16
            ColumnLayout {
                id: nextCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 2
                Text {
                    text: "NEXT EVENT"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 10; letterSpacing: 1; bold: true }
                }
                Text {
                    Layout.fillWidth: true
                    text: (view.sys.calNext && view.sys.calNext.title) || ""
                    color: view.sys.colFg
                    elide: Text.ElideRight
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 1; bold: true }
                }
                Text {
                    text: {
                        var _ = view.tick
                        var e = view.sys.calNext
                        if (!e) return ""
                        return (e.start_time || "") + "  ·  " + view.fmtCountdown(e.starts_in_sec)
                    }
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                }
            }
        }

        // ---------------- MONTH
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: view.mode === "month"
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                NavBtn { sym: "‹"; onPressedAction: view.shiftMonth(-1) }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -2
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: (view.sys.isEn ? view.monthsEn : view.monthsRu)[view.viewMonth]
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize + 2; bold: true }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: view.viewYear
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                    }
                }
                NavBtn { sym: "›"; onPressedAction: view.shiftMonth(1) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: view.sys.isEn ? view.dowEn : view.dowRu
                    Text {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: index >= 5 ? Qt.rgba(1, 0.42, 0.42, 0.55) : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4; bold: true }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 7
                rowSpacing: 4
                columnSpacing: 4
                Repeater {
                    model: view.cells
                    Rectangle {
                        id: cell
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 10
                        color: cell.modelData.isToday
                               ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.22)
                               : (cell.modelData.isSel
                                  ? Qt.rgba(1, 1, 1, 0.10)
                                  : (cellMa.containsMouse && cell.modelData.inMonth
                                     ? Qt.rgba(1, 1, 1, 0.08) : "transparent"))
                        border.color: cell.modelData.isToday ? view.sys.colOn
                                    : (cell.modelData.isSel ? Qt.rgba(1, 1, 1, 0.25) : "transparent")
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 140 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: cell.modelData.day
                                color: !cell.modelData.inMonth ? Qt.rgba(1, 1, 1, 0.18)
                                     : cell.modelData.isToday  ? view.sys.colFg
                                     : cell.modelData.weekend  ? Qt.rgba(1, 0.42, 0.42, 0.85)
                                                               : view.sys.colFg
                                font {
                                    family: view.sys.fontFam
                                    pixelSize: view.sys.fontSize - 2
                                    bold: cell.modelData.isToday
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: cell.modelData.inMonth && (cell.modelData.hasEvent || cell.modelData.hasDeadline)
                                text: cell.modelData.hasDeadline
                                      ? (cell.modelData.multi ? "▲•" : "▲")
                                      : (cell.modelData.multi ? "••" : "•")
                                color: cell.modelData.hasDeadline ? view.sys.colWarn : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: 8 }
                            }
                        }

                        MouseArea {
                            id: cellMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: cell.modelData.inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (!cell.modelData.inMonth) return
                                view.openDay(cell.modelData.y, cell.modelData.m, cell.modelData.day)
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 118
                Layout.preferredHeight: 28
                radius: 10
                visible: view.viewMonth !== view.today.getMonth()
                         || view.viewYear !== view.today.getFullYear()
                color: todayMa.containsMouse ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.06)
                Text {
                    anchors.centerIn: parent
                    text: view.sys.tr("Сегодня")
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                }
                MouseArea {
                    id: todayMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.goToday()
                }
            }
        }

        // ---------------- DAY
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.mode === "day"
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                NavBtn { sym: "‹"; onPressedAction: view.shiftDay(-1) }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -2
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            var d = new Date(view.selYear, view.selMonth, view.selDay)
                            return (view.sys.isEn ? view.dowFullEn : view.dowFullRu)[d.getDay()].toUpperCase()
                        }
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3; letterSpacing: 1 }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: view.selDay + " " + (view.sys.isEn ? view.monthsEn : view.monthsRu)[view.selMonth].toUpperCase()
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize; bold: true }
                    }
                }
                NavBtn { sym: "›"; onPressedAction: view.shiftDay(1) }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                height: 24; radius: 8
                width: todayDayLbl.implicitWidth + 16
                color: Qt.rgba(1, 1, 1, 0.06)
                Text {
                    id: todayDayLbl
                    anchors.centerIn: parent
                    text: "TODAY"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { view.goToday(); view.mode = "day" }
                }
            }

            // timeline hours 8–22
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                readonly property int startMin: 8 * 60
                readonly property int endMin: 22 * 60
                readonly property int span: endMin - startMin

                function yOf(min) {
                    var t = Math.max(startMin, Math.min(endMin, min))
                    return (t - startMin) / span * height
                }

                Repeater {
                    model: [8, 10, 12, 14, 16, 18, 20, 22]
                    Rectangle {
                        required property int modelData
                        width: parent.width
                        height: 1
                        y: parent.yOf(modelData * 60)
                        color: Qt.rgba(1, 1, 1, 0.06)
                        Text {
                            anchors.left: parent.left
                            anchors.bottom: parent.top
                            anchors.bottomMargin: 1
                            text: (modelData < 10 ? "0" : "") + modelData + ":00"
                            color: view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: 9 }
                        }
                    }
                }

                // events
                Repeater {
                    model: view.dayEvents
                    Rectangle {
                        required property var modelData
                        readonly property int sm: view.parseHm(modelData.start_time)
                        readonly property int em: Math.max(sm + 30, view.parseHm(modelData.end_time || modelData.start_time))
                        x: 44
                        width: parent.width - 48
                        y: parent.yOf(sm)
                        height: Math.max(28, parent.yOf(em) - parent.yOf(sm))
                        radius: 8
                        color: modelData.type === "DEADLINE"
                               ? Qt.rgba(view.sys.colWarn.r, view.sys.colWarn.g, view.sys.colWarn.b, 0.16)
                               : Qt.rgba(1, 1, 1, 0.07)
                        border.color: view.sys.colLine
                        border.width: 1
                        Column {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 1
                            Text {
                                width: parent.width
                                text: (modelData.type === "DEADLINE" ? "▲ " : "") + (modelData.title || "")
                                elide: Text.ElideRight
                                color: view.sys.colFg
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3; bold: true }
                            }
                            Text {
                                width: parent.width
                                text: (modelData.start_time || "") + " → " + (modelData.end_time || "")
                                color: view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: 9 }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: view.sys.calDelete(modelData.id)
                        }
                    }
                }

                // current time line (only if selected day is today)
                Rectangle {
                    visible: {
                        var _ = view.tick
                        var t = new Date()
                        return view.selYear === t.getFullYear()
                            && view.selMonth === t.getMonth()
                            && view.selDay === t.getDate()
                            && view.minsNow() >= parent.startMin
                            && view.minsNow() <= parent.endMin
                    }
                    width: parent.width
                    height: 1
                    y: parent.yOf(view.minsNow())
                    color: view.sys.colOn
                    opacity: 0.85
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -8
                        text: {
                            var _ = view.tick
                            var n = new Date()
                            function z(x) { return (x < 10 ? "0" : "") + x }
                            return z(n.getHours()) + ":" + z(n.getMinutes())
                        }
                        color: view.sys.colOn
                        font { family: view.sys.fontFam; pixelSize: 9; bold: true }
                    }
                    Rectangle {
                        width: 6; height: 6; radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        x: 38
                        color: view.sys.colOn
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: view.dayEvents.length === 0
                    text: "No events scheduled.\nClear day"
                    horizontalAlignment: Text.AlignHCenter
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; italic: true }
                }
            }
        }

        // ---------------- QUICK ADD
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.mode === "add"

            Text {
                text: "NEW EVENT"
                color: view.sys.colFg
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize; bold: true }
            }

            TextField {
                id: titleField
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                placeholderText: "TITLE"
                text: view.fTitle
                onTextChanged: view.fTitle = text
                color: view.sys.colFg
                placeholderTextColor: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                background: Rectangle {
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: view.sys.colLine
                }
                Component.onCompleted: forceActiveFocus()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    placeholderText: "DATE YYYY-MM-DD"
                    text: view.fDate
                    onTextChanged: view.fDate = text
                    color: view.sys.colFg
                    placeholderTextColor: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                    background: Rectangle { radius: 10; color: Qt.rgba(1, 1, 1, 0.06); border.color: view.sys.colLine }
                }
                TextField {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 34
                    placeholderText: "START"
                    text: view.fStart
                    onTextChanged: view.fStart = text
                    color: view.sys.colFg
                    placeholderTextColor: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                    background: Rectangle { radius: 10; color: Qt.rgba(1, 1, 1, 0.06); border.color: view.sys.colLine }
                }
                TextField {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 34
                    placeholderText: "END"
                    text: view.fEnd
                    onTextChanged: view.fEnd = text
                    color: view.sys.colFg
                    placeholderTextColor: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                    background: Rectangle { radius: 10; color: Qt.rgba(1, 1, 1, 0.06); border.color: view.sys.colLine }
                }
            }

            RowLayout {
                spacing: 6
                Repeater {
                    model: ["EVENT", "DEADLINE", "TASK"]
                    delegate: Rectangle {
                        required property string modelData
                        height: 24; radius: 8
                        width: typeLbl.implicitWidth + 14
                        color: view.fType === modelData ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.04)
                        Text {
                            id: typeLbl
                            anchors.centerIn: parent
                            text: modelData
                            color: view.fType === modelData ? view.sys.colFg : view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: 10 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.fType = modelData
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    height: 32; radius: 10
                    width: createLbl.implicitWidth + 20
                    color: Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.22)
                    Text {
                        id: createLbl
                        anchors.centerIn: parent
                        text: "CREATE"
                        color: view.sys.colOn
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; bold: true }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.createEvent()
                    }
                }
                Rectangle {
                    height: 32; radius: 10
                    width: cancelLbl.implicitWidth + 20
                    color: Qt.rgba(1, 1, 1, 0.06)
                    Text {
                        id: cancelLbl
                        anchors.centerIn: parent
                        text: "CANCEL"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.mode = "month"
                    }
                }
                Item { Layout.fillWidth: true }
            }

            Text {
                visible: view.sys.calError.length > 0
                text: "save: " + view.sys.calError
                color: view.sys.colWarn
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
            }
        }

        // TODAY SUMMARY
        Rectangle {
            Layout.fillWidth: true
            visible: view.mode !== "add"
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.04)
            border.color: view.sys.colLine
            border.width: 1
            implicitHeight: sumCol.implicitHeight + 16
            ColumnLayout {
                id: sumCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4
                Text {
                    text: "TODAY"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 10; letterSpacing: 1; bold: true }
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: {
                        var s = view.sys.calSummary || {}
                        var line = (s.events || 0) + " EVENTS  ·  "
                                 + (s.deadlines || 0) + " DEADLINE  ·  "
                                 + (s.tasks || 0) + " TASKS"
                        var n = s.next
                        if (n && n.title)
                            line += "\nNEXT  " + n.title + " — " + (n.start_time || "")
                        else if (!(s.total > 0))
                            line += "\nClear day"
                        return line
                    }
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                }
            }
        }
    }
}
