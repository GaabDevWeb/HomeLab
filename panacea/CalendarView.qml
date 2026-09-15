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

    // quick add / edit fields
    property string fTitle: ""
    property string fDate: ""
    property string fStart: "09:00"
    property string fEnd: "10:00"
    property string fType: "EVENT"
    property string fDesc: ""
    property string fReminder: "10"     // none|at_time|5|10|15|30|60
    property string fRecurrence: "never" // never|daily|weekly|monthly
    property string fEditId: ""         // master id when editing
    property bool fAdvanced: false
    property string feedback: ""

    // day interaction
    property var detailEvent: null
    property string confirmDelete: ""   // occurrence_id or master id
    property string confirmMode: "series" // occurrence|series

    readonly property date today: new Date()
    readonly property string selYmd: {
        function z(n) { return (n < 10 ? "0" : "") + n }
        return selYear + "-" + z(selMonth + 1) + "-" + z(selDay)
    }

    readonly property var dayEvents: {
        var _ = view.sys.calEpoch
        return view.sys.calEventsForDay ? view.sys.calEventsForDay(view.selYmd) : []
    }

    readonly property var reminderOptions: [
        { id: "none", label: "NONE" },
        { id: "at_time", label: "AT TIME" },
        { id: "5", label: "5 MIN" },
        { id: "10", label: "10 MIN" },
        { id: "15", label: "15 MIN" },
        { id: "30", label: "30 MIN" },
        { id: "60", label: "1 HOUR" }
    ]
    readonly property var recurOptions: [
        { id: "never", label: "NEVER" },
        { id: "daily", label: "DAILY" },
        { id: "weekly", label: "WEEKLY" },
        { id: "monthly", label: "MONTHLY" }
    ]

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
        var mem = view.sys.uiMemory || {}
        if (mem.calMode === "day" || mem.calMode === "month" || mem.calMode === "add")
            view.mode = mem.calMode
        if (mem.calJumpToday) {
            view.goToday()
            if (view.sys.patchUiMemory) view.sys.patchUiMemory({ calJumpToday: false })
        } else if (mem.calDay && /^\d{4}-\d{2}-\d{2}$/.test(String(mem.calDay))) {
            var p = String(mem.calDay).split("-")
            view.openDay(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10))
        }
    }

    function rememberUi() {
        if (!view.sys || !view.sys.patchUiMemory) return
        view.sys.patchUiMemory({
            calMode: view.mode === "add" ? "day" : view.mode,
            calDay: view.selYmd
        })
    }

    onModeChanged: view.rememberUi()
    onSelYmdChanged: if (view.mode === "day") view.rememberUi()

    Keys.onEscapePressed: {
        if (view.confirmDelete) { view.confirmDelete = ""; return }
        if (view.detailEvent) { view.detailEvent = null; return }
        if (view.mode === "add") { view.mode = "day"; return }
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

    function nextPlausibleStart() {
        var n = new Date()
        var h = n.getHours()
        var m = n.getMinutes()
        // round up to next :00 or :30
        if (m > 0 && m <= 30) m = 30
        else if (m > 30) { m = 0; h = (h + 1) % 24 }
        else m = 0
        function z(x) { return (x < 10 ? "0" : "") + x }
        return z(h) + ":" + z(m)
    }

    function openAdd() {
        fEditId = ""
        fTitle = ""
        fDate = selYmd
        fStart = view.nextPlausibleStart()
        var sm = view.parseHm(fStart)
        var em = sm + 60
        function z(x) { return (x < 10 ? "0" : "") + x }
        fEnd = z(Math.floor(em / 60) % 24) + ":" + z(em % 60)
        fType = "EVENT"
        fDesc = ""
        fReminder = "10"
        fRecurrence = "never"
        fAdvanced = false
        detailEvent = null
        confirmDelete = ""
        mode = "add"
    }

    function openEdit(ev) {
        if (!ev) return
        fEditId = ev.series_id || ev.id || ""
        // strip @occurrence from id if present
        if (String(fEditId).indexOf("@") >= 0)
            fEditId = String(fEditId).split("@")[0]
        fTitle = ev.title || ""
        fDate = ev.date || selYmd
        fStart = ev.start_time || "09:00"
        fEnd = ev.end_time || fStart
        fType = ev.type || "EVENT"
        fDesc = ev.description || ""
        fReminder = ev.reminder || "10"
        fRecurrence = ev.recurrence || "never"
        fAdvanced = fRecurrence !== "never" || (fDesc && fDesc.length)
        detailEvent = null
        mode = "add"
    }

    function createEvent() {
        if (!fTitle.trim()) return
        var obj = {
            title: fTitle.trim(),
            date: fDate || selYmd,
            start_time: fStart || "09:00",
            end_time: fEnd || fStart || "09:00",
            type: fType,
            description: fDesc,
            reminder: fReminder || "10",
            recurrence: fRecurrence || "never"
        }
        if (fEditId) obj.id = fEditId
        view.sys.calCreate(obj)
        view.flash("✓ SAVED")
        mode = "day"
        var p = (fDate || selYmd).split("-")
        if (p.length === 3) {
            selYear = +p[0]; selMonth = +p[1] - 1; selDay = +p[2]
            viewYear = selYear; viewMonth = selMonth
        }
    }

    function flash(msg) {
        view.feedback = msg
        feedbackTimer.restart()
    }

    Timer { id: feedbackTimer; interval: 900; onTriggered: view.feedback = "" }

    function openDetail(ev) { view.detailEvent = ev; view.confirmDelete = "" }

    function askDelete(ev) {
        if (!ev) return
        var oid = ev.occurrence_id || ev.id
        view.confirmDelete = oid
        view.confirmMode = (ev.is_occurrence || (ev.recurrence && ev.recurrence !== "never"))
                           ? "occurrence" : "series"
    }

    function doDelete() {
        if (!view.confirmDelete) return
        view.sys.calDelete(view.confirmDelete, view.confirmMode)
        view.confirmDelete = ""
        view.detailEvent = null
        view.flash("✓ DELETED")
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
        if (sec <= 0) return "now"
        if (sec < 60) return "in " + sec + "s"
        if (sec < 3600) return "in " + Math.round(sec / 60) + " min"
        var h = Math.floor(sec / 3600)
        var m = Math.round((sec % 3600) / 60)
        return "in " + h + "h " + m + "m"
    }

    function reminderLabel(r) {
        r = String(r || "10")
        for (var i = 0; i < view.reminderOptions.length; i++)
            if (view.reminderOptions[i].id === r) return view.reminderOptions[i].label
        return r
    }

    function eventActive(ev) {
        if (!ev) return false
        if (ev.state === "ACTIVE") return true
        var t = new Date()
        if (ev.date !== view.sys.calYmd(t)) return false
        var now = t.getHours() * 60 + t.getMinutes()
        var sm = view.parseHm(ev.start_time)
        var em = view.parseHm(ev.end_time || ev.start_time)
        if (em < sm) em += 24 * 60
        return now >= sm && now <= em
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
                    text: (view.sys.calNext && view.sys.calNext.start_time) || ""
                    color: view.sys.colFg
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize; bold: true }
                }
                Text {
                    Layout.fillWidth: true
                    text: (view.sys.calNext && view.sys.calNext.title) || ""
                    color: view.sys.colFg
                    elide: Text.ElideRight
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 1 }
                }
                Text {
                    text: {
                        var _ = view.tick
                        var e = view.sys.calNext
                        if (!e) return ""
                        return view.fmtCountdown(e.starts_in_sec)
                    }
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                }
            }
        }

        Text {
            visible: view.feedback.length > 0
            text: view.feedback
            color: view.sys.colOk
            font { family: view.sys.fontFam; pixelSize: 10; bold: true }
            Layout.alignment: Qt.AlignRight
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

            // lista do dia — só eventos (hora + título), sem grelha de horas
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: view.dayEvents.length > 0

                Repeater {
                    model: view.dayEvents
                    delegate: Rectangle {
                        id: evRow
                        required property var modelData
                        readonly property bool active: view.eventActive(modelData)
                        Layout.fillWidth: true
                        height: 28
                        radius: 8
                        color: rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: 8
                            Text {
                                text: modelData.start_time || ""
                                color: view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: 12 }
                                Layout.preferredWidth: 40
                            }
                            Text {
                                text: "──"
                                color: Qt.rgba(1, 1, 1, 0.22)
                                font { family: view.sys.fontFam; pixelSize: 12 }
                            }
                            Text {
                                visible: evRow.active
                                text: "●"
                                color: view.sys.colOn
                                font { family: view.sys.fontFam; pixelSize: 11 }
                            }
                            Text {
                                visible: modelData.type === "DEADLINE"
                                text: "▲"
                                color: view.sys.colWarn
                                font { family: view.sys.fontFam; pixelSize: 11 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.title || ""
                                elide: Text.ElideRight
                                color: view.sys.colFg
                                font { family: view.sys.fontFam; pixelSize: 13 }
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    view.askDelete(modelData)
                                else
                                    view.openDetail(modelData)
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                visible: view.dayEvents.length === 0
                text: "No events scheduled."
                horizontalAlignment: Text.AlignHCenter
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; italic: true }
            }

            // detail / confirm
            Rectangle {
                Layout.fillWidth: true
                visible: view.detailEvent !== null && !view.confirmDelete
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.05)
                border.color: view.sys.colLine
                border.width: 1
                implicitHeight: detCol.implicitHeight + 16
                ColumnLayout {
                    id: detCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: (view.detailEvent && view.detailEvent.title) || ""
                        color: view.sys.colFg
                        elide: Text.ElideRight
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 1; bold: true }
                    }
                    Text {
                        text: {
                            var e = view.detailEvent
                            if (!e) return ""
                            return (e.start_time || "") + " → " + (e.end_time || "")
                                   + "   " + (e.type || "EVENT")
                        }
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 11 }
                    }
                    Text {
                        text: {
                            var e = view.detailEvent
                            if (!e) return ""
                            var line = "REMINDER  " + view.reminderLabel(e.reminder)
                            if (e.recurrence && e.recurrence !== "never")
                                line += "   ·   " + String(e.recurrence).toUpperCase()
                            return line
                        }
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 10 }
                    }
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            height: 26; radius: 8; width: editLbl.implicitWidth + 16
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Text { id: editLbl; anchors.centerIn: parent; text: "EDIT"; color: view.sys.colFg; font { family: view.sys.fontFam; pixelSize: 10 } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.openEdit(view.detailEvent) }
                        }
                        Rectangle {
                            height: 26; radius: 8; width: delLbl.implicitWidth + 16
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Text { id: delLbl; anchors.centerIn: parent; text: "DELETE"; color: view.sys.colCrit; font { family: view.sys.fontFam; pixelSize: 10 } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.askDelete(view.detailEvent) }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "✕"
                            color: view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: 12 }
                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: view.detailEvent = null }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: view.confirmDelete.length > 0
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.05)
                border.color: view.sys.colCrit
                border.width: 1
                implicitHeight: confDel.implicitHeight + 16
                ColumnLayout {
                    id: confDel
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    Text {
                        text: "DELETE EVENT?"
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 1; bold: true }
                    }
                    Text {
                        text: (view.detailEvent && view.detailEvent.title) || ""
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 11 }
                    }
                    RowLayout {
                        spacing: 6
                        visible: view.confirmMode === "occurrence"
                                 || (view.detailEvent && view.detailEvent.is_occurrence)
                        Rectangle {
                            height: 26; radius: 8; width: occLbl.implicitWidth + 14
                            color: view.confirmMode === "occurrence" ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.05)
                            Text { id: occLbl; anchors.centerIn: parent; text: "OCCURRENCE"; color: view.sys.colFg; font { family: view.sys.fontFam; pixelSize: 9 } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.confirmMode = "occurrence" }
                        }
                        Rectangle {
                            height: 26; radius: 8; width: serLbl.implicitWidth + 14
                            color: view.confirmMode === "series" ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.05)
                            Text { id: serLbl; anchors.centerIn: parent; text: "SERIES"; color: view.sys.colFg; font { family: view.sys.fontFam; pixelSize: 9 } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.confirmMode = "series" }
                        }
                    }
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            height: 28; radius: 8; width: cxlLbl.implicitWidth + 18
                            color: Qt.rgba(1, 1, 1, 0.06)
                            Text { id: cxlLbl; anchors.centerIn: parent; text: "CANCEL"; color: view.sys.colMuted; font { family: view.sys.fontFam; pixelSize: 10 } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.confirmDelete = "" }
                        }
                        Rectangle {
                            height: 28; radius: 8; width: confLbl.implicitWidth + 18
                            color: Qt.rgba(view.sys.colCrit.r, view.sys.colCrit.g, view.sys.colCrit.b, 0.2)
                            Text { id: confLbl; anchors.centerIn: parent; text: "DELETE"; color: view.sys.colCrit; font { family: view.sys.fontFam; pixelSize: 10; bold: true } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.doDelete() }
                        }
                    }
                }
            }
        }

        // ---------------- QUICK ADD / EDIT
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: view.mode === "add"

            Text {
                text: view.fEditId ? "EDIT EVENT" : "NEW EVENT"
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
                Keys.onReturnPressed: view.createEvent()
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

            Text {
                text: "TYPE"
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: 9; letterSpacing: 1 }
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

            Text {
                text: "REMINDER"
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: 9; letterSpacing: 1 }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: view.reminderOptions
                    delegate: Rectangle {
                        required property var modelData
                        height: 22; radius: 8
                        width: remLbl.implicitWidth + 12
                        color: view.fReminder === modelData.id ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.04)
                        Text {
                            id: remLbl
                            anchors.centerIn: parent
                            text: modelData.label
                            color: view.fReminder === modelData.id ? view.sys.colFg : view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: 9 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.fReminder = modelData.id
                        }
                    }
                }
            }

            Text {
                text: view.fAdvanced ? "ADVANCED ▾" : "ADVANCED ▸"
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: 9; letterSpacing: 1 }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.fAdvanced = !view.fAdvanced
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: view.fAdvanced
                Text {
                    text: "REPEAT"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 9; letterSpacing: 1 }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: view.recurOptions
                        delegate: Rectangle {
                            required property var modelData
                            height: 22; radius: 8
                            width: recLbl.implicitWidth + 12
                            color: view.fRecurrence === modelData.id ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.04)
                            Text {
                                id: recLbl
                                anchors.centerIn: parent
                                text: modelData.label
                                color: view.fRecurrence === modelData.id ? view.sys.colFg : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: 9 }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.fRecurrence = modelData.id
                            }
                        }
                    }
                }
                TextField {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    placeholderText: "DESCRIPTION (optional)"
                    text: view.fDesc
                    onTextChanged: view.fDesc = text
                    color: view.sys.colFg
                    placeholderTextColor: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                    background: Rectangle { radius: 10; color: Qt.rgba(1, 1, 1, 0.06); border.color: view.sys.colLine }
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
                        text: view.fEditId ? "SAVE" : "CREATE"
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
                        onClicked: view.mode = "day"
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
