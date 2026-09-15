import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// Проводник в пилюле: слева закладки, справа список файлов.
// Клавиатура — основной способ управления: стрелки, Enter, Backspace,
// печать фильтрует список, Esc закрывает.
Item {
    id: view
    property var sys
    // true — проводник открыт отдельным окном Hyprland: закрывать надо окно,
    // а пилюля живёт своей жизнью и трогать её нельзя
    property bool windowMode: false
    property int  windowId: 0

    function leave() {
        if (view.sys.wallpaperFolderPickMode)
            view.sys.cancelWallpaperFolderPick();
        if (view.sys.wallpaperPickMode)
            view.sys.wallpaperPickMode = false;
        if (view.windowMode) view.sys.closeFilesWindow(view.windowId);
        else                 view.sys.collapse();
    }

    implicitHeight: col.implicitHeight

    // ------------------------------------------------------------ состояние
    property string dir: ""
    property int current: 0
    property string filter: ""
    // Сортировка: "name" | "time" | "size" | "type". Порядок и «папки сверху»
    // отдельными переключателями — так же, как в любом привычном проводнике.
    property string sortBy: "name"
    property bool   sortDesc: false
    property bool   foldersFirst: true
    property string status: ""

    // Раскладка содержимого: "list" | "grid". Живёт в настройках, а не в самом
    // виде: проводник открывают и закрывают десятками раз за сеанс, и каждый
    // раз возвращаться к списку, когда работаешь с картинками, — маета.
    readonly property string mode: view.sys.cfg.filesMode === "grid" ? "grid" : "list"
    function setMode(m) {
        if (view.mode === m) return;
        view.sys.cfg.filesMode = m;
        view.sys.saveCfg();
    }
    // Сколько плиток помещается в ряд. Нужно не только сетке: по этому же
    // числу стрелки вверх и вниз ходят на строку, а не на соседний файл.
    readonly property int gridCell: 118
    readonly property int gridCols: Math.max(1, Math.floor(view.width > 0
                                                           ? view.width / view.gridCell : 1))

    // выбранный файл, для которого показываем «чем открыть»
    property string openWithFile: ""

    // буфер обмена проводника
    property var    clipPaths: []
    property string clipPath: clipPaths.length ? clipPaths[0] : ""
    property string clipMode: ""        // "copy" | "cut"

    // мультивыделение файлов
    property var    selectedPaths: []
    readonly property int selectedCount: selectedPaths.length
    property int    anchorIndex: -1

    // контекстное меню
    property bool   menuOpen: false
    property string menuPath: ""        // "" — меню пустого места
    property bool   menuIsDir: false
    property string menuKind: "folder"   // "file" | "folder" | "trash"
    property real   menuX: 0
    property real   menuY: 0
    // secções do menu — todas colapsadas por omissão
    property bool   menuSecOpen: false
    property bool   menuSecEdit: false
    property bool   menuSecCreate: false
    property bool   menuSecGit: false

    // диалог ввода имени
    property string dialogMode: ""      // "rename" | "mkdir"

    // Переход между папками: список уезжает и гаснет, новый приезжает
    // с той стороны, куда мы двинулись. Направление помним, чтобы «вверх»
    // и «внутрь» ощущались по-разному.
    property real listOpacity: 1
    property real listShift: 0
    Behavior on listShift { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    property int  navDir: 1             // 1 — внутрь, -1 — наверх

    // -------------------- FM 2.0: abas + histórico + path edit
    ListModel { id: fileTabs }
    ListModel { id: favPlaces }
    ListModel { id: recentPlaces }
    property int  nextTabId: 1
    property int  activeTabId: 0
    property var  closedTabs: []
    property var  histBack: ({})
    property var  histFwd: ({})
    property bool suppressHist: false
    property bool pathEditing: false
    property string pathEditText: ""
    property string pathError: ""
    property bool tabMenuOpen: false
    property int  tabMenuTid: -1
    property real tabMenuX: 0
    property real tabMenuY: 0
    property bool hasCode: false
    property string gitBrief: ""
    property bool confirmEmptyTrash: false
    property bool confirmPermDelete: false
    property var  permDeleteTargets: []

    // Fase 4–5: preview / git panel / trash
    property bool   previewOpen: false
    property string previewPath: ""
    property string previewKind: ""   // text | image | too_large | none | ""
    property string previewText: ""
    property string previewMeta: ""   // size · lines · mime
    property string previewError: ""
    property bool   gitPanelOpen: false
    ListModel { id: gitLines }
    property bool   trashConfirmOpen: false
    property string trashConfirmMode: ""  // empty | permanent
    property var    trashConfirmTargets: []
    property int    listTotal: 0
    property int    listShown: 0
    property string gitPanelTitle: "GIT STATUS"
    ListModel { id: pathSuggest }
    property int    pathSuggestIndex: 0
    property bool   watchArmed: false

    ListModel { id: entries }      // отфильтрованный список
    ListModel { id: rawEntries }   // всё, что вернул files.sh
    ListModel { id: places }
    // Смонтированные носители. Съёмные держим отдельной моделью: их раздел
    // должен появляться только когда что-то воткнули.
    ListModel { id: disks }
    ListModel { id: removables }
    ListModel { id: apps }

    readonly property string scripts: view.sys.scriptDir + "/files.sh"

    focus: true
    Component.onCompleted: {
        // Каталог, с которого попросили открыться (карусель живых обоев,
        // например). Одноразовый: дальше проводник ходит сам.
        if (!view.dir.length && view.sys.filesStartDir.length) {
            view.dir = view.sys.filesStartDir;
            view.sys.filesStartDir = "";
        }
        if (!view.dir.length) view.dir = view.sys.filesDir;
        if (fileTabs.count === 0) {
            var tid = view.nextTabId++;
            fileTabs.append({ tid: tid, path: view.dir, label: view.tabLabel(view.dir) });
            view.activeTabId = tid;
            view.histBack[tid] = [];
            view.histFwd[tid] = [];
        }
        forceActiveFocus();
        loadPlaces();
        loadFavorites();
        loadRecent();
        checkCode();
        reload();
        refreshGit();
    }

    // ---------------------------------------------------------------- чтение
    Process {
        id: pList
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim();
                if (t.indexOf("#meta|") === 0) {
                    var m = t.split("|");
                    view.listTotal = parseInt(m[1]) || 0;
                    view.listShown = parseInt(m[2]) || 0;
                    return;
                }
                var p = t.split("|");
                if (p.length < 5) return;
                rawEntries.append({
                    eType: p[0], eName: p[1],
                    eSize: parseInt(p[2]) || 0,
                    eTime: parseInt(p[3]) || 0,
                    eMime: p[4]
                });
            }
        }
        onRunningChanged: {
            if (!running) {
                view.applyFilter();
                view.armWatch();
            }
        }
    }

    // Watcher: inotify quando existir; senão mtime poll leve (2.5s)
    Process {
        id: pWatch
        stdout: SplitParser {
            onRead: line => {
                if (view.selfChange || pList.running || pAction.running) return;
                watchDebounce.restart();
            }
        }
    }
    Timer {
        id: watchDebounce
        interval: 480
        onTriggered: {
            if (view.selfChange || pList.running) return;
            view.reloadQuiet();
        }
    }
    Timer {
        id: watchPoll
        interval: 2500
        running: view.watchArmed && !pWatch.running
        repeat: true
        onTriggered: {
            if (view.selfChange || pList.running) return;
            pMtime.command = ["stat", "-c", "%Y", view.dir];
            pMtime.running = false;
            pMtime.running = true;
        }
    }
    property string dirMtime: ""
    Process {
        id: pMtime
        stdout: StdioCollector {
            onStreamFinished: {
                var m = text.trim();
                if (!m.length) return;
                if (view.dirMtime.length && view.dirMtime !== m)
                    watchDebounce.restart();
                view.dirMtime = m;
            }
        }
    }
    function armWatch() {
        view.watchArmed = true;
        view.dirMtime = "";
        pWatch.running = false;
        // inotifywait -m (monitor); se falhar, o poll assume
        pWatch.command = ["sh", "-c",
            "command -v inotifywait >/dev/null 2>&1 || exit 0; " +
            "inotifywait -m -q -e create,delete,move,moved_to,moved_from,close_write --format %e \"$1\" 2>/dev/null",
            "_", view.dir];
        pWatch.running = true;
        pMtime.command = ["stat", "-c", "%Y", view.dir];
        pMtime.running = false;
        pMtime.running = true;
    }
    function reloadQuiet() {
        // reload sem animação de navegação
        var prev = view.navDir;
        view.navDir = 0;
        rawEntries.clear();
        // manter selection se possível — clear entries só após
        pList.command = ["sh", "-c", view.scripts + " list \"$1\" \"$2\"", "_", view.dir,
                         view.sys.cfg.filesHidden ? "hidden" : ""];
        pList.running = false;
        pList.running = true;
        view.navDir = prev;
        view.refreshGit();
    }

    Process {
        id: pPlaces
        command: ["sh", "-c", view.scripts + " places"]
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split("|");
                if (p.length < 3) return;
                places.append({ pKey: p[0], pPath: p[1], pLabel: p[2] });
            }
        }
    }

    Process {
        id: pApps
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split("|");
                if (p.length < 3) return;
                apps.append({ aFile: p[0], aName: p[1], aIcon: p[2] });
            }
        }
    }

    // Очередь коротких операций. pAction здесь один на всех, и вторая
    // операция, начатая пока идёт первая, затирала её команду и молча
    // пропадала. Копирование и перенос сюда не попадают — они уходят в
    // пилюлю, к своей очереди: см. runLong().
    property var opQueue: []

    Process {
        id: pAction
        onRunningChanged: {
            if (running) return;
            // следующая из очереди — до перечитывания списка: перечитывать
            // между операциями значит дважды проиграть анимацию появления
            if (view.opQueue.length > 0) {
                var q = view.opQueue.slice();
                var next = q.shift();
                view.opQueue = q;
                view.startOp(next.args, next.note);
                return;
            }
            view.reload();
            view.countTrash();
            // Соседние окна проводника про наши правки не знают: после
            // переноса файл исчезает здесь, но у них в списке ещё висит.
            // Флаг — чтобы не перечитать список ещё раз у самих себя: две
            // перезагрузки подряд дёргают анимацию появления.
            view.selfChange = true;
            view.sys.filesChanged();
            view.selfChange = false;
        }
    }
    property bool selfChange: false
    // ...и наоборот: правку в соседнем окне подхватываем сами
    Connections {
        target: view.sys
        ignoreUnknownSignals: true
        function onFilesChanged() {
            if (view.selfChange || pAction.running) return;
            view.reload();
        }
    }

    // сколько файлов в корзине — показываем счётчиком у закладки
    property int trashCount: 0
    readonly property string trashDir:
        (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share"))
        + "/Trash/files"
    readonly property bool inTrash: {
        var t = view.trashDir;
        return view.dir === t || (t.length > 0 && view.dir.indexOf(t + "/") === 0);
    }

    Process {
        id: pTrashCount
        command: ["sh", "-c", view.scripts + " trashcount"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: view.trashCount = parseInt(text.trim()) || 0
        }
    }

    Process {
        id: pDisks
        command: ["sh", "-c", view.scripts + " disks"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n");
                var d = [], r = [];
                for (var i = 0; i < lines.length; i++) {
                    var p = lines[i].split("|");
                    if (p.length < 6) continue;
                    var row = {
                        dPath: p[1], dLabel: p[2],
                        dSize: parseFloat(p[3]) || 0,
                        dUsed: parseFloat(p[4]) || 0,
                        dDev: p[5]
                    };
                    if (p[0] === "removable") r.push(row); else d.push(row);
                }
                // Раньше модель очищалась и набивалась заново каждые 4 секунды:
                // делегаты пересоздавались, и полоса заполнения каждый раз
                // заново уезжала от нуля. Теперь правим строки на месте, а
                // список трогаем, только если носитель появился или пропал.
                view.syncDisks(disks, d);
                view.syncDisks(removables, r);
            }
        }
    }

    Process {
        id: pMount
        property string targetDev: ""
        command: ["sh", "-c", view.scripts + " mountdisk " + JSON.stringify(targetDev)]
        stdout: StdioCollector {
            onStreamFinished: {
                var mp = text.trim();
                view.reloadDisks();
                if (mp.length > 0) {
                    view.go(mp);
                }
            }
        }
    }
    function mountDisk(dev) {
        if (!dev || dev.length === 0) return;
        pMount.targetDev = dev;
        pMount.running = false;
        pMount.running = true;
    }

    Process {
        id: pEject
        property string targetItem: ""
        command: ["sh", "-c", view.scripts + " ejectdisk " + JSON.stringify(targetItem)]
        stdout: StdioCollector {
            onStreamFinished: {
                view.reloadDisks();
                if (pEject.targetItem.length > 0 && view.dir.startsWith(pEject.targetItem)) {
                    view.go(view.sys.home);
                }
            }
        }
    }
    function ejectDisk(dev, path) {
        pEject.targetItem = path && path.length > 0 ? path : dev;
        pEject.running = false;
        pEject.running = true;
    }

    function syncDisks(model, rows) {
        if (model.count !== rows.length) {
            model.clear();
            for (var i = 0; i < rows.length; i++) model.append(rows[i]);
            return;
        }
        for (var j = 0; j < rows.length; j++) {
            var cur = model.get(j);
            if (cur.dDev !== rows[j].dDev || cur.dPath !== rows[j].dPath || cur.dLabel !== rows[j].dLabel) {
                model.set(j, rows[j]);
                continue;
            }
            // меняем только цифры — делегат остаётся тем же
            if (cur.dUsed !== rows[j].dUsed) model.setProperty(j, "dUsed", rows[j].dUsed);
            if (cur.dSize !== rows[j].dSize) model.setProperty(j, "dSize", rows[j].dSize);
        }
    }
    function reloadDisks() { pDisks.running = false; pDisks.running = true; }
    // Воткнули флешку или подключили телефон — раздел появится сам.
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: view.reloadDisks()
    }

    function human(b) {
        if (!b || b <= 0) return "";
        var u = ["B", "KB", "MB", "GB", "TB"];
        var i = 0;
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
        return (b >= 100 || i < 2 ? Math.round(b) : b.toFixed(1)) + " " + u[i];
    }
    function countTrash() { pTrashCount.running = false; pTrashCount.running = true; }

    function emptyTrash() {
        closeMenu();
        view.trashConfirmMode = "empty";
        view.trashConfirmTargets = [];
        view.trashConfirmOpen = true;
    }
    function doRestore(path) {
        var targets = (view.selectedCount > 1 && (path === "" || view.isSelected(path)))
                    ? view.selectedPaths.slice()
                    : (path ? [path] : []);
        if (!targets.length) return;
        closeMenu();
        var cmd = ["bash", view.scripts, "restore"].concat(targets);
        run(cmd, "✓ RESTORED");
        view.clearSelection();
    }
    function askDeletePermanent(path) {
        var targets = (view.selectedCount > 1 && (path === "" || view.isSelected(path)))
                    ? view.selectedPaths.slice()
                    : (path ? [path] : []);
        if (!targets.length) return;
        closeMenu();
        view.trashConfirmMode = "permanent";
        view.trashConfirmTargets = targets;
        view.trashConfirmOpen = true;
    }
    function confirmTrashAction() {
        var mode = view.trashConfirmMode;
        var targets = view.trashConfirmTargets.slice();
        view.trashConfirmOpen = false;
        view.trashConfirmMode = "";
        view.trashConfirmTargets = [];
        if (mode === "empty") {
            run(["sh", "-c", view.scripts + " emptytrash"], view.sys.tr("Корзина очищена"));
            return;
        }
        if (mode === "permanent" && targets.length) {
            var cmd = ["bash", view.scripts, "delete-permanent"].concat(targets);
            var label = targets.length === 1 ? view.baseName(targets[0])
                                             : (targets.length + " " + view.sys.tr("файлов"));
            run(cmd, "✓ DELETED · " + label);
            view.clearSelection();
        }
    }
    function cancelTrashConfirm() {
        view.trashConfirmOpen = false;
        view.trashConfirmMode = "";
        view.trashConfirmTargets = [];
    }

    function loadPlaces() {
        places.clear();
        pPlaces.running = false;
        pPlaces.running = true;
    }

    function reload() {
        rawEntries.clear();
        entries.clear();
        view.listTotal = 0;
        view.listShown = 0;
        view.listOpacity = 0;
        view.listShift = 22 * view.navDir;
        pWatch.running = false;
        pList.command = ["sh", "-c", view.scripts + " list \"$1\" \"$2\"", "_", view.dir,
                         view.sys.cfg.filesHidden ? "hidden" : ""];
        pList.running = false;
        pList.running = true;
        view.sys.filesDir = view.dir;
    }

    function applyFilter() {
        entries.clear();
        // содержимое готово — вернуть на место
        view.listOpacity = 1;
        view.listShift = 0;
        var f = view.filter.toLowerCase();
        var rows = [];
        for (var i = 0; i < rawEntries.count; i++) {
            var e = rawEntries.get(i);
            if (f.length && e.eName.toLowerCase().indexOf(f) < 0) continue;
            rows.push({ eType: e.eType, eName: e.eName, eSize: e.eSize,
                        eTime: e.eTime, eMime: e.eMime });
        }
        rows.sort(view.compare);
        for (var j = 0; j < rows.length; j++) entries.append(rows[j]);
        view.current = 0;
    }

    // Сравнение двух строк списка. Каталоги держим отдельной группой, если
    // включено «папки сверху»: иначе при сортировке по размеру они, все
    // нулевые, сваливались в одну кучу посреди файлов.
    function compare(a, b) {
        if (view.foldersFirst && a.eType !== b.eType)
            return a.eType === "d" ? -1 : 1;

        var r = 0;
        if (view.sortBy === "time") r = a.eTime - b.eTime;
        else if (view.sortBy === "size") r = a.eSize - b.eSize;
        else if (view.sortBy === "type") {
            var ea = view.extOf(a), eb = view.extOf(b);
            r = ea < eb ? -1 : ea > eb ? 1 : 0;
        }
        if (r === 0) {
            var na = a.eName.toLowerCase(), nb = b.eName.toLowerCase();
            r = na < nb ? -1 : na > nb ? 1 : 0;
            // имя всегда по возрастанию, если сортируем не по нему
            if (view.sortBy !== "name") return r;
        }
        return view.sortDesc ? -r : r;
    }
    function extOf(e) {
        if (e.eType === "d") return "";
        var i = e.eName.lastIndexOf(".");
        return i > 0 ? e.eName.substring(i + 1).toLowerCase() : "";
    }
    function setSort(k) {
        if (view.sortBy === k) view.sortDesc = !view.sortDesc;
        else { view.sortBy = k; view.sortDesc = (k === "time" || k === "size"); }
        view.applyFilter();
    }

    // «12 авг, 14:32», а для прошлых лет — с годом
    function timeText(e) {
        if (!e.eTime) return "";
        var d = new Date(e.eTime * 1000);
        var now = new Date();
        var fmt = d.getFullYear() === now.getFullYear() ? "d MMM, hh:mm" : "d MMM yyyy";
        return Qt.formatDateTime(d, fmt);
    }

    function go(path) {
        if (!path || !path.length) return;
        if (path !== view.dir && !view.suppressHist && view.activeTabId) {
            var back = (view.histBack[view.activeTabId] || []).slice();
            back.push(view.dir);
            if (back.length > 48) back = back.slice(-48);
            view.histBack[view.activeTabId] = back;
            view.histFwd[view.activeTabId] = [];
            view.histBack = Object.assign({}, view.histBack);
            view.histFwd = Object.assign({}, view.histFwd);
        }
        view.navDir = path.length < view.dir.length ? -1 : 1;
        view.filter = "";
        view.dir = path;
        view.openWithFile = "";
        view.pathEditing = false;
        view.pathError = "";
        view.clearSelection();
        view.syncActiveTabPath(path);
        view.pushRecent(path);
        view.reload();
        view.refreshGit();
    }
    function up() {
        if (view.dir === "/") return;
        var p = view.dir.replace(/\/+$/, "");
        var i = p.lastIndexOf("/");
        go(i <= 0 ? "/" : p.slice(0, i));
    }

    function tabLabel(path) {
        var home = Quickshell.env("HOME");
        if (path === home || path === home + "/") return "HOME";
        var base = String(path).replace(/\/+$/, "").split("/").pop();
        return base && base.length ? base : "/";
    }
    function syncActiveTabPath(path) {
        for (var i = 0; i < fileTabs.count; i++) {
            if (fileTabs.get(i).tid === view.activeTabId) {
                fileTabs.setProperty(i, "path", path);
                fileTabs.setProperty(i, "label", view.tabLabel(path));
                return;
            }
        }
    }
    function newTab(path) {
        var p = path && path.length ? path : Quickshell.env("HOME");
        var tid = view.nextTabId++;
        fileTabs.append({ tid: tid, path: p, label: view.tabLabel(p) });
        view.histBack[tid] = [];
        view.histFwd[tid] = [];
        view.histBack = Object.assign({}, view.histBack);
        view.histFwd = Object.assign({}, view.histFwd);
        view.switchTab(tid);
    }
    function switchTab(tid) {
        if (tid === view.activeTabId) return;
        var path = "";
        for (var i = 0; i < fileTabs.count; i++) {
            if (fileTabs.get(i).tid === tid) { path = fileTabs.get(i).path; break; }
        }
        if (!path.length) return;
        view.activeTabId = tid;
        view.suppressHist = true;
        view.filter = "";
        view.clearSelection();
        view.openWithFile = "";
        view.dir = path;
        view.reload();
        view.refreshGit();
        view.suppressHist = false;
        view.forceActiveFocus();
    }
    function closeTab(tid) {
        view.closeTabMenu();
        if (fileTabs.count <= 1) { view.leave(); return; }
        var idx = -1;
        var closedPath = "";
        for (var i = 0; i < fileTabs.count; i++) {
            if (fileTabs.get(i).tid === tid) {
                idx = i;
                closedPath = fileTabs.get(i).path;
                break;
            }
        }
        if (idx < 0) return;
        var stack = (view.closedTabs || []).slice();
        stack.unshift(closedPath);
        if (stack.length > 12) stack = stack.slice(0, 12);
        view.closedTabs = stack;
        var wasActive = view.activeTabId === tid;
        fileTabs.remove(idx);
        var hb = Object.assign({}, view.histBack);
        var hf = Object.assign({}, view.histFwd);
        delete hb[tid];
        delete hf[tid];
        view.histBack = hb;
        view.histFwd = hf;
        if (wasActive) {
            var next = fileTabs.get(Math.min(idx, fileTabs.count - 1));
            view.switchTab(next.tid);
        }
    }
    function closeOtherTabs(tid) {
        view.closeTabMenu();
        for (var i = fileTabs.count - 1; i >= 0; i--) {
            if (fileTabs.get(i).tid !== tid) view.closeTab(fileTabs.get(i).tid);
        }
    }
    function closeTabsToRight(tid) {
        view.closeTabMenu();
        var seen = false;
        for (var i = 0; i < fileTabs.count; ) {
            if (fileTabs.get(i).tid === tid) { seen = true; i++; continue; }
            if (seen) view.closeTab(fileTabs.get(i).tid);
            else i++;
        }
    }
    function reopenClosedTab() {
        view.closeTabMenu();
        var stack = (view.closedTabs || []).slice();
        if (!stack.length) return;
        var p = stack.shift();
        view.closedTabs = stack;
        view.newTab(p);
    }
    function openTabMenu(tid, x, y) {
        view.tabMenuTid = tid;
        view.tabMenuX = Math.max(8, Math.min(x, view.width - 200));
        view.tabMenuY = Math.max(8, Math.min(y, view.height - 160));
        view.tabMenuOpen = true;
    }
    function closeTabMenu() { view.tabMenuOpen = false; view.tabMenuTid = -1; }
    function navBack() {
        var back = (view.histBack[view.activeTabId] || []).slice();
        if (!back.length) return;
        var prev = back.pop();
        view.histBack[view.activeTabId] = back;
        var fwd = (view.histFwd[view.activeTabId] || []).slice();
        fwd.push(view.dir);
        view.histFwd[view.activeTabId] = fwd;
        view.histBack = Object.assign({}, view.histBack);
        view.histFwd = Object.assign({}, view.histFwd);
        view.suppressHist = true;
        view.filter = "";
        view.dir = prev;
        view.syncActiveTabPath(prev);
        view.reload();
        view.refreshGit();
        view.suppressHist = false;
    }
    function navForward() {
        var fwd = (view.histFwd[view.activeTabId] || []).slice();
        if (!fwd.length) return;
        var next = fwd.pop();
        view.histFwd[view.activeTabId] = fwd;
        var back = (view.histBack[view.activeTabId] || []).slice();
        back.push(view.dir);
        view.histBack[view.activeTabId] = back;
        view.histBack = Object.assign({}, view.histBack);
        view.histFwd = Object.assign({}, view.histFwd);
        view.suppressHist = true;
        view.filter = "";
        view.dir = next;
        view.syncActiveTabPath(next);
        view.reload();
        view.refreshGit();
        view.suppressHist = false;
    }
    function pathSegments() {
        var d = view.dir === "/" ? "/" : view.dir.replace(/\/+$/, "");
        if (d === "/") return [{ name: "/", path: "/" }];
        var parts = d.split("/");
        var out = [];
        var acc = "";
        for (var i = 1; i < parts.length; i++) {
            if (!parts[i].length) continue;
            acc += "/" + parts[i];
            out.push({ name: parts[i], path: acc });
        }
        return out;
    }
    function startPathEdit() {
        view.pathEditing = true;
        view.pathEditText = view.dir;
        view.pathError = "";
        view.pathSuggestIndex = 0;
        pathSuggest.clear();
        Qt.callLater(function () { pathField.forceActiveFocus(); pathField.selectAll(); });
        pathCompleteDebounce.restart();
    }
    function cancelPathEdit() {
        view.pathEditing = false;
        view.pathError = "";
        pathSuggest.clear();
        view.forceActiveFocus();
    }
    function submitPathEdit() {
        // se há sugestão selecionada e Tab-like, aceitar dir
        if (pathSuggest.count > 0 && view.pathSuggestIndex >= 0
            && view.pathSuggestIndex < pathSuggest.count) {
            var s = pathSuggest.get(view.pathSuggestIndex);
            if (s && s.sKind === "dir") {
                view.pathEditText = s.sPath;
                pathField.text = s.sPath;
            }
        }
        pResolve.command = ["bash", view.scripts, "resolve", view.dir, view.pathEditText];
        pResolve.running = false;
        pResolve.running = true;
    }
    function acceptPathSuggest() {
        if (pathSuggest.count === 0) return false;
        var i = Math.max(0, Math.min(view.pathSuggestIndex, pathSuggest.count - 1));
        var s = pathSuggest.get(i);
        view.pathEditText = s.sPath;
        pathField.text = s.sPath;
        pathField.cursorPosition = pathField.text.length;
        pathCompleteDebounce.restart();
        return true;
    }
    Timer {
        id: pathCompleteDebounce
        interval: 120
        onTriggered: view.fetchPathSuggest()
    }
    function fetchPathSuggest() {
        if (!view.pathEditing) return;
        pathSuggest.clear();
        pPathComplete.command = ["bash", view.scripts, "path-complete", view.dir, view.pathEditText];
        pPathComplete.running = false;
        pPathComplete.running = true;
    }
    Process {
        id: pPathComplete
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split("|");
                if (p.length < 2) return;
                if (pathSuggest.count >= 12) return;
                pathSuggest.append({ sKind: p[0], sPath: p.slice(1).join("|") });
            }
        }
        onRunningChanged: {
            if (!running) view.pathSuggestIndex = 0;
        }
    }
    Process {
        id: pResolve
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim();
                if (!p.length) { view.pathError = "PATH NOT FOUND"; return; }
                pExists.command = ["bash", view.scripts, "exists", p];
                pExists.targetPath = p;
                pExists.running = false;
                pExists.running = true;
            }
        }
    }
    Process {
        id: pExists
        property string targetPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var k = text.trim();
                if (k === "dir") {
                    view.pathEditing = false;
                    view.pathError = "";
                    pathSuggest.clear();
                    view.go(pExists.targetPath);
                    view.forceActiveFocus();
                } else {
                    view.pathError = "PATH NOT FOUND";
                }
            }
        }
    }
    function copyCurrentPath() {
        var targets = view.selectedCount > 0 ? view.selectedPaths.slice() : [view.dir];
        var text = targets.join("\n");
        run(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", text],
            view.sys.tr("Путь скопирован"));
    }
    function openFolderInNewTab(path) {
        if (!path || !path.length) return;
        view.newTab(path);
    }
    function openTerminalHere(path) {
        var d = path && path.length ? path : view.dir;
        // se for ficheiro, usar o parent
        pTerm.command = ["bash", view.scripts, "terminal-here", d];
        pTerm.running = false;
        pTerm.running = true;
        view.closeMenu();
        view.say("TERMINAL");
    }
    Process { id: pTerm }
    function openInCode(path) {
        if (!view.hasCode) return;
        var p = path && path.length ? path : view.dir;
        pCode.command = ["bash", view.scripts, "open-code", p];
        pCode.running = false;
        pCode.running = true;
        view.closeMenu();
        view.say("VS CODE");
    }
    Process { id: pCode }
    function checkCode() {
        pWhichCode.command = ["bash", view.scripts, "which-code"];
        pWhichCode.running = false;
        pWhichCode.running = true;
    }
    Process {
        id: pWhichCode
        stdout: StdioCollector {
            onStreamFinished: { view.hasCode = text.trim().length > 0; }
        }
    }
    function refreshGit() {
        pGit.command = ["bash", view.scripts, "git-brief", view.dir];
        pGit.running = false;
        pGit.running = true;
    }
    Process {
        id: pGit
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim();
                view.gitBrief = (t === "NONE" || !t.length) ? "" : t;
            }
        }
    }
    readonly property bool gitRepo: view.gitBrief.length > 0
    function openGitPanel(mode) {
        view.gitPanelTitle = (mode === "log") ? "GIT LOG --oneline" : "GIT STATUS";
        gitLines.clear();
        view.gitPanelOpen = true;
        view.closeMenu();
        if (mode === "log") {
            if (!view.gitRepo) {
                gitLines.append({ gLine: "(not a git repository)" });
                return;
            }
            pGitList.command = ["bash", view.scripts, "git-log", view.dir];
        } else {
            if (!view.gitRepo) {
                gitLines.append({ gLine: "(not a git repository — use Git Init)" });
                return;
            }
            pGitList.command = ["bash", view.scripts, "git-status-list", view.dir];
        }
        pGitList.running = false;
        pGitList.running = true;
    }
    Process {
        id: pGitList
        stdout: SplitParser {
            onRead: line => {
                var t = line.trimEnd();
                if (!t.length) return;
                gitLines.append({ gLine: t });
            }
        }
    }
    function closeGitPanel() { view.gitPanelOpen = false; }
    function gitInitHere() {
        view.closeMenu();
        pGitInit.command = ["bash", view.scripts, "git-init", view.dir];
        pGitInit.running = false;
        pGitInit.running = true;
    }
    Process {
        id: pGitInit
        stdout: StdioCollector {
            onStreamFinished: {
                view.say("✓ GIT INIT");
                view.refreshGit();
                view.openGitPanel("status");
            }
        }
    }

    function canPreviewPath(path) {
        if (!path || !path.length) return false;
        var base = view.baseName(path);
        var i = base.lastIndexOf(".");
        if (i < 0) return false;
        var ext = base.substring(i + 1).toLowerCase();
        var ok = ["txt","md","json","yaml","yml","toml","py","js","ts","tsx","jsx","sh","bash","zsh",
                  "css","html","htm","xml","ini","conf","cfg","rs","go","c","h","cpp","hpp","java",
                  "qml","lua","rb","php","sql","env","log","csv",
                  "png","jpg","jpeg","gif","webp","bmp","svg"];
        return ok.indexOf(ext) >= 0;
    }
    function togglePreview(path) {
        var p = path && path.length ? path : view.currentPath();
        if (!p.length) return;
        if (view.previewOpen && view.previewPath === p) {
            view.closePreview();
            return;
        }
        view.openPreview(p);
    }
    function openPreview(path) {
        if (!path || !path.length) return;
        view.previewPath = path;
        view.previewKind = "";
        view.previewText = "";
        view.previewMeta = "READING…";
        view.previewError = "";
        view.previewOpen = true;
        pPreview.command = ["bash", view.scripts, "preview", path];
        pPreview.running = false;
        pPreview.running = true;
    }
    function closePreview() {
        view.previewOpen = false;
        view.previewPath = "";
        view.previewKind = "";
        view.previewText = "";
        view.previewMeta = "";
        view.previewError = "";
    }
    Process {
        id: pPreview
        stdout: StdioCollector {
            onStreamFinished: {
                var kind = "";
                var meta = [];
                var err = "";
                var content = "";
                var inContent = false;
                var lines = text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i];
                    if (inContent) {
                        if (line.indexOf("content_end\t") === 0) { inContent = false; continue; }
                        content += (content.length ? "\n" : "") + line;
                        continue;
                    }
                    var t = line.split("\t");
                    if (t.length < 2) continue;
                    var k = t[0];
                    var v = t.slice(1).join("\t");
                    if (k === "content_begin") { inContent = true; continue; }
                    if (k === "preview_kind") kind = v;
                    else if (k === "error") err = v;
                    else if (k === "kind") meta.push(v);
                    else if (k === "size_human") meta.push(v);
                    else if (k === "lines") meta.push(v + " lines");
                    else if (k === "resolution") meta.push(v);
                }
                view.previewKind = kind;
                view.previewMeta = meta.join(" · ");
                view.previewError = err;
                view.previewText = content;
            }
        }
    }

    function loadFavorites() {
        favPlaces.clear();
        pFav.command = ["bash", view.scripts, "favorites-list"];
        pFav.running = false;
        pFav.running = true;
    }
    Process {
        id: pFav
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim().split("|");
                if (p.length < 2) return;
                favPlaces.append({ fPath: p[0], fName: p.slice(1).join("|") });
            }
        }
    }
    function loadRecent() {
        recentPlaces.clear();
        pRecent.command = ["bash", view.scripts, "recent-list"];
        pRecent.running = false;
        pRecent.running = true;
    }
    Process {
        id: pRecent
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim();
                if (!p.length) return;
                recentPlaces.append({ rPath: p, rName: view.tabLabel(p) });
            }
        }
    }
    function pushRecent(path) {
        pRecentPush.command = ["bash", view.scripts, "recent-push", path];
        pRecentPush.running = false;
        pRecentPush.running = true;
    }
    Process {
        id: pRecentPush
        onExited: view.loadRecent()
    }
    function addFavorite(path) {
        if (!path || !path.length) path = view.dir;
        run(["bash", view.scripts, "favorites-add", path, view.tabLabel(path)], "★");
        view.closeMenu();
        Qt.callLater(view.loadFavorites);
    }
    function removeFavorite(path) {
        run(["bash", view.scripts, "favorites-remove", path], "✓");
        Qt.callLater(view.loadFavorites);
    }
    function isCutPath(path) {
        return view.clipMode === "cut" && view.clipPaths.indexOf(path) >= 0;
    }
    function isCopiedPath(path) {
        return view.clipMode === "copy" && view.clipPaths.indexOf(path) >= 0;
    }

    // что умеет показать наш плеер — открываем сразу, без вопроса «чем»
    function isMedia(e) {
        var m = String(e.eMime);
        return m.indexOf("image/") === 0 || m.indexOf("video/") === 0;
    }

    function activate(i) {
        if (i < 0 || i >= entries.count) return;
        var e = entries.get(i);
        var full = (view.dir === "/" ? "" : view.dir) + "/" + e.eName;
        if (e.eType === "d") { go(full); return; }
        // режим выбора обоев: картинку не открываем в плеере, а отдаём
        // странице обоев для сохранения
        if (view.sys.wallpaperPickMode) {
            var m = String(e.eMime);
            if (m.indexOf("image/") === 0) { view.sys.finishWallpaperPick(full); return; }
        }
        if (view.isMedia(e)) { view.sys.openMedia(full); return; }
        // остальное — сначала спрашиваем, чем открывать
        view.openWithFile = full;
        apps.clear();
        pApps.command = ["sh", "-c", view.scripts + " apps \"$1\"", "_", full];
        pApps.running = false;
        pApps.running = true;
    }

    function openWith(desktopFile) {
        if (!view.openWithFile.length) return;
        // Запускаем НЕ отсюда: следующей строкой панель закрывается, а вместе
        // с ней уничтожается вид и всё, что в нём объявлено, — включая
        // Process. Он умирал раньше, чем успевал запустить программу, и
        // проводник просто закрывался, ничего не открыв.
        view.sys.openFileWith(view.openWithFile, desktopFile || "");
        view.openWithFile = "";
        view.leave();
    }

    function trashCurrent() {
        if (view.current < 0 || view.current >= entries.count) return;
        var e = entries.get(view.current);
        var full = (view.dir === "/" ? "" : view.dir) + "/" + e.eName;
        view.status = view.sys.tr("В корзину: ") + e.eName;
        statusClear.restart();
        pAction.command = ["sh", "-c", view.scripts + " trash \"$1\"", "_", full];
        pAction.running = true;
    }
    Timer { id: statusClear; interval: 2600; onTriggered: view.status = "" }

    function say(msg) { view.status = msg; statusClear.restart(); }

    function fullPath(name) {
        return (view.dir === "/" ? "" : view.dir) + "/" + name;
    }
    function currentPath() {
        if (view.current < 0 || view.current >= entries.count) return "";
        return view.fullPath(entries.get(view.current).eName);
    }
    function baseName(p) { return String(p).split("/").pop(); }

    // Подписи закладок переводим здесь: скрипт про язык интерфейса не знает.
    function placeLabel(key, fallback) {
        switch (key) {
            case "home":      return view.sys.tr("Домашняя");
            case "downloads": return view.sys.tr("Загрузки");
            case "documents": return view.sys.tr("Документы");
            case "pictures":  return view.sys.tr("Изображения");
            case "videos":    return view.sys.tr("Видео");
            case "music":     return view.sys.tr("Музыка");
            case "desktop":   return view.sys.tr("Рабочий стол");
            case "trash":     return view.sys.tr("Корзина");
            case "root":      return view.sys.tr("Система");
        }
        return fallback;
    }

    function startOp(args, note) {
        pAction.command = args;
        pAction.running = true;
        if (note !== undefined) view.say(note);
    }
    function run(args, note) {
        if (pAction.running) {
            var q = view.opQueue.slice();
            q.push({ args: args, note: note });
            view.opQueue = q;
            if (note !== undefined) view.say(note);
            return;
        }
        view.startOp(args, note);
    }

    // Копирование и перенос уходят в пилюлю: они длятся минутами, а панель
    // закрывают сразу после того, как перетащили файлы. Здесь их процесс
    // умер бы вместе с Loader'ом, на середине.
    function runLong(args, note, label) {
        view.sys.runFileOp(args, label);
        if (note !== undefined) view.say(note);
    }

    // --------------------------------------------------------- меню действий
    function openMenu(path, isDir, x, y, kind) {
        view.menuPath = path;
        view.menuIsDir = isDir;
        view.menuKind = kind !== undefined ? kind : (path.length ? "file" : "folder");
        // por omissão: secções fechadas (menu curto)
        view.menuSecOpen = false;
        view.menuSecEdit = false;
        view.menuSecCreate = false;
        view.menuSecGit = false;
        view.menuX = Math.max(0, Math.min(x, view.width - 248));
        view.menuY = Math.max(0, Math.min(y, Math.max(0, view.height - 280)));
        view.menuOpen = true;
    }
    function closeMenu() { view.menuOpen = false; }
    function toggleMenuSec(name) {
        if (name === "open") view.menuSecOpen = !view.menuSecOpen;
        else if (name === "edit") view.menuSecEdit = !view.menuSecEdit;
        else if (name === "create") view.menuSecCreate = !view.menuSecCreate;
        else if (name === "git") view.menuSecGit = !view.menuSecGit;
    }

    function doOpen(path) {
        if (!path.length) return;
        closeMenu();
        for (var i = 0; i < entries.count; i++) {
            if (view.fullPath(entries.get(i).eName) === path) { view.activate(i); return; }
        }
    }
    // явный выбор программы — минуя автозапуск медиа в своём плеере
    function doOpenWith(path) {
        if (!path.length) return;
        closeMenu();
        view.openWithFile = path;
        apps.clear();
        pApps.command = ["sh", "-c", view.scripts + " apps \"$1\"", "_", path];
        pApps.running = false;
        pApps.running = true;
    }
    // ---------------------------------------------------- мультивыделение
    function isSelected(path) {
        return view.selectedPaths.indexOf(path) !== -1;
    }
    function toggleSelection(path, idx) {
        var copy = view.selectedPaths.slice();
        var i = copy.indexOf(path);
        if (i !== -1) copy.splice(i, 1);
        else copy.push(path);
        view.selectedPaths = copy;
        if (idx !== undefined) view.anchorIndex = idx;
    }
    function selectSingle(path, idx) {
        view.selectedPaths = [path];
        if (idx !== undefined) view.anchorIndex = idx;
    }
    function selectRange(targetIdx) {
        if (view.anchorIndex < 0) view.anchorIndex = view.current;
        var start = Math.min(view.anchorIndex, targetIdx);
        var end = Math.max(view.anchorIndex, targetIdx);
        var res = [];
        for (var i = start; i <= end; i++) {
            if (i >= 0 && i < entries.count) {
                res.push(view.fullPath(entries.get(i).eName));
            }
        }
        view.selectedPaths = res;
    }
    function selectAll() {
        var res = [];
        for (var i = 0; i < entries.count; i++) {
            res.push(view.fullPath(entries.get(i).eName));
        }
        view.selectedPaths = res;
    }
    function clearSelection() {
        view.selectedPaths = [];
        view.anchorIndex = -1;
    }
    function updateSelectionByRect(rx, ry, rw, rh) {
        var rectX2 = rx + rw;
        var rectY2 = ry + rh;
        var matched = [];

        if (view.mode === "list") {
            var rowH = 42;
            var scrollY = list.contentY;
            for (var i = 0; i < entries.count; i++) {
                var itemY = i * rowH - scrollY;
                var itemY2 = itemY + rowH;
                if (itemY2 >= ry && itemY <= rectY2) {
                    matched.push(view.fullPath(entries.get(i).eName));
                }
            }
        } else {
            var cols = view.gridCols;
            var cellW = grid.cellWidth;
            var cellH = grid.cellHeight;
            var scrollY = grid.contentY;
            for (var j = 0; j < entries.count; j++) {
                var colIdx = j % cols;
                var rowIdx = Math.floor(j / cols);
                var itemX = colIdx * cellW;
                var itemX2 = itemX + cellW;
                var itemY = rowIdx * cellH - scrollY;
                var itemY2 = itemY + cellH;

                if (itemX2 >= rx && itemX <= rectX2 && itemY2 >= ry && itemY <= rectY2) {
                    matched.push(view.fullPath(entries.get(j).eName));
                }
            }
        }
        view.selectedPaths = matched;
    }

    // ----------------------------------------------------------- архивы
    function isArchive(path) {
        if (!path) return false;
        var l = String(path).toLowerCase();
        return l.endsWith(".zip") || l.endsWith(".tar.gz") || l.endsWith(".tgz")
            || l.endsWith(".tar.xz") || l.endsWith(".txz") || l.endsWith(".tar.bz2")
            || l.endsWith(".tbz2") || l.endsWith(".tar.zst") || l.endsWith(".tar")
            || l.endsWith(".7z") || l.endsWith(".rar") || l.endsWith(".gz")
            || l.endsWith(".xz") || l.endsWith(".zst") || l.endsWith(".bz2")
            || l.endsWith(".iso");
    }
    function archiveFolderName(path) {
        var name = view.baseName(path);
        name = name.replace(/\.(tar\.(gz|xz|bz2|zst)|tgz|txz|tbz2|zip|7z|rar|iso|gz|xz|zst|bz2)$/i, "");
        return name || "extracted";
    }
    function hasArchiveSelected() {
        for (var i = 0; i < view.selectedPaths.length; i++) {
            if (view.isArchive(view.selectedPaths[i])) return true;
        }
        return false;
    }
    function doExtractHere(path) {
        closeMenu();
        runLong(["sh", "-c", view.scripts + " extract \"$1\" \"$2\"", "_", path, view.dir],
                view.sys.tr("Распаковано: ") + view.baseName(path),
                view.baseName(path));
    }
    function doExtractToFolder(path) {
        closeMenu();
        var folder = view.dir + "/" + view.archiveFolderName(path);
        runLong(["sh", "-c", view.scripts + " extract \"$1\" \"$2\"", "_", path, folder],
                view.sys.tr("Распаковано в ") + view.archiveFolderName(path) + "/",
                view.baseName(path));
    }
    function doExtractAllSelected(toSubfolders) {
        closeMenu();
        var paths = view.selectedPaths.filter(view.isArchive);
        if (!paths.length && view.isArchive(view.menuPath)) paths = [view.menuPath];
        if (!paths.length) return;
        for (var i = 0; i < paths.length; i++) {
            var p = paths[i];
            var dst = toSubfolders ? (view.dir + "/" + view.archiveFolderName(p)) : view.dir;
            view.runLong(["sh", "-c", view.scripts + " extract \"$1\" \"$2\"", "_", p, dst],
                         view.sys.tr("Распаковано: ") + view.baseName(p),
                         view.baseName(p));
        }
    }

    function doCopy(path) {
        var targets = (view.selectedCount > 1 && (path === "" || view.isSelected(path)))
                    ? view.selectedPaths.slice()
                    : (path ? [path] : []);
        if (!targets.length) return;
        view.clipPaths = targets;
        view.clipMode = "copy";
        closeMenu();
        if (targets.length === 1) {
            view.say(view.sys.tr("Скопировано: ") + view.baseName(targets[0]));
        } else {
            view.say(view.sys.tr("Скопировано файлов: ") + targets.length);
        }
    }
    function doCut(path) {
        var targets = (view.selectedCount > 1 && (path === "" || view.isSelected(path)))
                    ? view.selectedPaths.slice()
                    : (path ? [path] : []);
        if (!targets.length) return;
        view.clipPaths = targets;
        view.clipMode = "cut";
        closeMenu();
        if (targets.length === 1) {
            view.say(view.sys.tr("Вырезано: ") + view.baseName(targets[0]));
        } else {
            view.say(view.sys.tr("Вырезано файлов: ") + targets.length);
        }
    }
    function doPaste() {
        if (!view.clipPaths.length) return;
        var op = view.clipMode === "cut" ? "move" : "copy";
        closeMenu();
        var dest = view.dir;
        if (view.selectedCount === 1) {
            var sp = view.selectedPaths[0];
            for (var i = 0; i < entries.count; i++) {
                if (view.fullPath(entries.get(i).eName) === sp && entries.get(i).eType === "d") {
                    dest = sp;
                    break;
                }
            }
        } else if (view.menuPath.length && view.menuIsDir) {
            dest = view.menuPath;
        }
        var label = view.clipPaths.length === 1 ? view.baseName(view.clipPaths[0])
                                               : (view.clipPaths.length + " " + view.sys.tr("файлов"));
        var note = (view.clipMode === "cut" ? view.sys.tr("Перемещено: ")
                                            : view.sys.tr("Вставлено: ")) + label;
        var cmd = ["sh", "-c", view.scripts + " " + op + " \"$1\" \"keepboth\" \"${@:2}\"", "_", dest];
        cmd = cmd.concat(view.clipPaths);
        runLong(cmd, note, label);
        if (view.clipMode === "cut") { view.clipPaths = []; view.clipMode = ""; }
    }
    function doCopyPath(path) {
        var targets = (view.selectedCount > 1 && (path === "" || view.isSelected(path)))
                    ? view.selectedPaths.slice()
                    : (path ? [path] : (view.selectedCount > 0 ? view.selectedPaths.slice() : [view.dir]));
        if (!targets.length) targets = [view.dir];
        closeMenu();
        var text = targets.join("\n");
        run(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", text],
            view.sys.tr("Путь скопирован"));
    }
    function doTrash(path) {
        var targets = (view.selectedCount > 1 && (path === "" || view.isSelected(path)))
                    ? view.selectedPaths.slice()
                    : (path ? [path] : []);
        if (!targets.length) return;
        closeMenu();
        var cmd = ["sh", "-c", view.scripts + " trash \"$@\"", "_"].concat(targets);
        var label = targets.length === 1 ? view.baseName(targets[0])
                                         : (targets.length + " " + view.sys.tr("файлов"));
        run(cmd, view.sys.tr("В корзину: ") + label);
        view.clearSelection();
    }

    // ---------------------------------------------------------- свойства
    property bool  propsOpen: false
    property var   propsData: ({})
    property string propsPath: ""
    function showProps(path) {
        closeMenu();
        view.propsPath = path;
        view.propsData = ({});
        pProps.command = ["sh", "-c", view.sys.scriptDir + "/props.sh \"$1\"", "_", path];
        pProps.running = true;
        view.propsOpen = true;
    }
    Process {
        id: pProps
        stdout: StdioCollector {
            onStreamFinished: {
                var o = {};
                var lines = text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var t = lines[i].split("\t");
                    if (t.length >= 2) o[t[0]] = t.slice(1).join("\t");
                }
                view.propsData = o;
            }
        }
    }
    function fmtDuration(sec) {
        var s = Math.floor(parseFloat(sec) || 0);
        var h = Math.floor(s / 3600); s -= h * 3600;
        var m = Math.floor(s / 60); s -= m * 60;
        var p2 = function (n) { return n < 10 ? "0" + n : "" + n; };
        return (h > 0 ? h + ":" + p2(m) : m) + ":" + p2(s);
    }
    function startRename(path) {
        closeMenu();
        view.menuPath = path;
        view.dialogMode = "rename";
        dialogField.text = view.baseName(path);
        dialogField.selectAll();
        dialogFocus.restart();
    }
    function startMkdir() {
        closeMenu();
        view.dialogMode = "mkdir";
        dialogField.text = view.sys.tr("Новая папка");
        dialogField.selectAll();
        dialogFocus.restart();
    }
    function startNewFile() {
        closeMenu();
        view.dialogMode = "newfile";
        dialogField.text = "untitled.txt";
        dialogField.selectAll();
        dialogFocus.restart();
    }
    function confirmDialog() {
        var name = dialogField.text.trim();
        var mode = view.dialogMode;
        view.dialogMode = "";
        view.forceActiveFocus();
        if (!name.length) return;
        if (mode === "rename")
            run(["sh", "-c", view.scripts + " rename \"$1\" \"$2\"", "_", view.menuPath, name],
                view.sys.tr("Переименовано"));
        else if (mode === "mkdir")
            run(["sh", "-c", view.scripts + " mkdir \"$1\" \"$2\"", "_", view.dir, name],
                view.sys.tr("Папка создана"));
        else if (mode === "newfile")
            run(["sh", "-c", view.scripts + " touch \"$1\" \"$2\"", "_", view.dir, name],
                "✓ CREATED");
    }
    function cancelDialog() {
        view.dialogMode = "";
        view.forceActiveFocus();
    }
    Timer { id: dialogFocus; interval: 40; onTriggered: dialogField.forceActiveFocus() }

    // -------------------------------------------------------------- клавиши
    Keys.onEscapePressed: {
        if (view.trashConfirmOpen) { view.cancelTrashConfirm(); return; }
        if (view.gitPanelOpen) { view.closeGitPanel(); return; }
        if (view.previewOpen) { view.closePreview(); return; }
        if (view.tabMenuOpen) { view.closeTabMenu(); return; }
        if (view.pathEditing) { view.cancelPathEdit(); return; }
        if (view.dialogMode.length) { view.cancelDialog(); return; }
        if (view.propsOpen) { view.propsOpen = false; return; }
        if (view.menuOpen) { view.closeMenu(); return; }
        if (view.selectedCount > 0) { view.clearSelection(); return; }
        if (view.openWithFile.length) { view.openWithFile = ""; return; }
        if (view.filter.length) { view.filter = ""; applyFilter(); return; }
        view.leave();
    }
    // В сетке вверх и вниз ходят на строку, а не на соседний файл: иначе
    // стрелка вниз ползла бы вдоль ряда, а глаз ждёт, что она опустится под
    // курсор. В списке строка и есть один файл, поэтому шаг там прежний.
    function step(delta) {
        var n = entries.count;
        if (n === 0) return;
        view.current = Math.max(0, Math.min(n - 1, view.current + delta));
    }
    // Пока открыт список «чем открыть», стрелки ходят по нему: он и есть то,
    // с чем сейчас работают. Ходить в это время по спрятанному списку файлов
    // бессмысленно — его не видно.
    Keys.onUpPressed:    view.openWithFile.length ? appList.step(-1)
                       : view.step(view.mode === "grid" ? -view.gridCols : -1)
    Keys.onDownPressed:  view.openWithFile.length ? appList.step(1)
                       : view.step(view.mode === "grid" ?  view.gridCols :  1)
    Keys.onLeftPressed:  if (view.mode === "grid") view.step(-1)
    Keys.onRightPressed: if (view.mode === "grid") view.step(1)
    Keys.onReturnPressed: view.openWithFile.length ? view.openWith(appList.currentFile())
                                                   : view.activate(view.current)
    Keys.onEnterPressed:  view.openWithFile.length ? view.openWith(appList.currentFile())
                                                   : view.activate(view.current)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Backspace) {
            if (view.filter.length) {
                view.filter = view.filter.slice(0, -1);
                applyFilter();
            } else {
                view.up();
            }
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Delete) {
            if (event.modifiers & Qt.ShiftModifier) {
                if (view.selectedCount > 0) view.askDeletePermanent("");
                else if (view.currentPath().length) view.askDeletePermanent(view.currentPath());
                event.accepted = true;
                return;
            }
            if (view.selectedCount > 0) {
                view.doTrash("");
            } else {
                view.trashCurrent();
            }
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Space) {
            var sp = view.currentPath();
            if (sp.length && view.canPreviewPath(sp)) {
                view.togglePreview(sp);
                event.accepted = true;
                return;
            }
        }
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_A) { view.selectAll(); event.accepted = true; return; }
            var p = view.currentPath();
            if (event.key === Qt.Key_C) {
                if (event.modifiers & Qt.ShiftModifier) {
                    view.copyCurrentPath();
                    event.accepted = true;
                    return;
                }
                view.doCopy(p); event.accepted = true; return;
            }
            if (event.key === Qt.Key_X) { view.doCut(p); event.accepted = true; return; }
            if (event.key === Qt.Key_V) { view.doPaste(); event.accepted = true; return; }
            if (event.key === Qt.Key_N) { view.startMkdir(); event.accepted = true; return; }
            if (event.key === Qt.Key_T) {
                if (event.modifiers & Qt.ShiftModifier) view.reopenClosedTab();
                else view.newTab(Quickshell.env("HOME"));
                event.accepted = true; return;
            }
            if (event.key === Qt.Key_W) { view.closeTab(view.activeTabId); event.accepted = true; return; }
            if (event.key === Qt.Key_L) { view.startPathEdit(); event.accepted = true; return; }
            if (event.key === Qt.Key_G) {
                if (event.modifiers & Qt.ShiftModifier) view.openGitPanel("log");
                else view.openGitPanel("status");
                event.accepted = true;
                return;
            }
            return;
        }
        if (event.modifiers & Qt.AltModifier) {
            if (event.key === Qt.Key_Left) { view.navBack(); event.accepted = true; return; }
            if (event.key === Qt.Key_Right) { view.navForward(); event.accepted = true; return; }
        }
        if (event.key === Qt.Key_F5) {
            view.reload();
            view.say("READY");
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_F2) {
            var r = view.currentPath();
            if (r.length) view.startRename(r);
            event.accepted = true;
            return;
        }
        if (view.pathEditing) return;
        if (event.text.length === 1 && event.text >= " ") {
            view.filter += event.text;
            applyFilter();
            event.accepted = true;
        }
    }

    // ------------------------------------------------------------- иконки
    function iconFor(e) {
        if (e.eType === "d") return String.fromCodePoint(0xF024B);   // folder
        var m = String(e.eMime);
        if (m.indexOf("image/") === 0) return String.fromCodePoint(0xF021F);
        if (m.indexOf("video/") === 0) return String.fromCodePoint(0xF022B);
        if (m.indexOf("audio/") === 0) return String.fromCodePoint(0xF0388);
        if (m === "application/pdf") return String.fromCodePoint(0xF0226);
        if (m.indexOf("text/") === 0) return String.fromCodePoint(0xF0219);
        if (m.indexOf("zip") >= 0 || m.indexOf("tar") >= 0 || m.indexOf("compress") >= 0)
            return String.fromCodePoint(0xF05C0);
        return String.fromCodePoint(0xF0224);                        // generic file
    }

    function sizeText(e) {
        if (e.eType === "d") return "";
        var s = e.eSize;
        if (s < 1024) return s + " B";
        if (s < 1024 * 1024) return (s / 1024).toFixed(0) + " KB";
        if (s < 1024 * 1024 * 1024) return (s / 1048576).toFixed(1) + " MB";
        return (s / 1073741824).toFixed(2) + " GB";
    }

    // ------------------------------------------------------ контекстное меню
    component MenuItem: Rectangle {
        property string glyph: ""
        property string label: ""
        property bool danger: false
        property bool enabledItem: true
        signal chosen()

        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 34 : 0
        Layout.maximumHeight: visible ? 34 : 0
        implicitHeight: 34
        radius: 9
        color: itemMa.containsMouse && enabledItem
               ? (danger ? Qt.rgba(0.94, 0.27, 0.27, 0.18) : view.sys.colHover)
               : "transparent"
        opacity: enabledItem ? 1 : 0.35
        Behavior on color { ColorAnimation { duration: 110 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 11
            spacing: 10

            Text {
                text: glyph
                color: danger ? view.sys.colCrit : view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: 14 }
            }
            Text {
                Layout.fillWidth: true
                text: label
                elide: Text.ElideRight
                color: danger ? view.sys.colCrit : view.sys.colFg
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
            }
        }

        MouseArea {
            id: itemMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.enabledItem
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.chosen()
        }
    }

    component MenuSectionHead: Rectangle {
        property string title: ""
        property bool expanded: false
        property bool sectionVisible: true
        signal toggled()

        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 28 : 0
        Layout.maximumHeight: visible ? 28 : 0
        visible: sectionVisible
        implicitHeight: 28
        radius: 8
        color: headMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6
            Text {
                text: expanded ? "▾" : "▸"
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: 11 }
            }
            Text {
                Layout.fillWidth: true
                text: title
                color: view.sys.colMuted
                font {
                    family: view.sys.fontFam
                    pixelSize: 10
                    letterSpacing: 1.2
                    bold: true
                }
            }
        }
        MouseArea {
            id: headMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.toggled()
        }
    }

    // ---------------------------------------------------------------- вид
    // Раздел «Диски» / «Съёмные»: подпись, занятое место и полоска заполнения.
    // Пустой раздел не рисуется вовсе — флешки нет, и заголовка быть не должно.
    component DiskSection: ColumnLayout {
        id: sec
        property string title: ""
        property var items: null
        property bool removable: false

        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 3
        visible: items && items.count > 0

        Text {
            Layout.leftMargin: 10
            Layout.bottomMargin: 2
            text: sec.title
            color: Qt.rgba(1, 1, 1, 0.32)
            font {
                family: view.sys.fontFam; pixelSize: view.sys.fontSize - 5
                bold: true; capitalization: Font.AllUppercase; letterSpacing: 1
            }
        }

        Repeater {
            model: sec.items

            Rectangle {
                id: disk
                required property var model
                readonly property bool mounted: disk.model.dPath && disk.model.dPath.length > 0
                readonly property bool active: mounted && view.dir === disk.model.dPath
                readonly property real frac: (mounted && disk.model.dSize > 0)
                                             ? disk.model.dUsed / disk.model.dSize : 0

                Layout.fillWidth: true
                Layout.preferredHeight: disk.model.dSize > 0 ? 58 : 34
                radius: 12
                color: diskMa.containsMouse ? view.sys.colHover
                     : (disk.active ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                Behavior on color { ColorAnimation { duration: 130 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 5
                    anchors.bottomMargin: 5
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: String.fromCodePoint(
                                      disk.model.dDev === "mtp" ? 0xF011C
                                    : sec.removable ? 0xF129B
                                                    : 0xF02CA)
                            color: disk.active ? view.sys.colOn : (disk.mounted ? view.sys.colMuted : Qt.rgba(1, 1, 1, 0.35))
                            font { family: view.sys.fontFam; pixelSize: 15 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: disk.model.dLabel
                            color: disk.active ? view.sys.colFg : (disk.mounted ? view.sys.colFg : Qt.rgba(1, 1, 1, 0.65))
                            elide: Text.ElideRight
                            font {
                                family: view.sys.fontFam
                                pixelSize: view.sys.fontSize - 2
                                bold: disk.active
                            }
                        }
                        // Кнопка безопасного извлечения
                        Rectangle {
                            visible: sec.removable && disk.mounted && (diskMa.containsMouse || ejectMa.containsMouse)
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            radius: 5
                            color: ejectMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: "⏏"
                                color: ejectMa.containsMouse ? view.sys.colCrit : Qt.rgba(1, 1, 1, 0.65)
                                font { family: view.sys.fontFam; pixelSize: 12; bold: true }
                            }
                            MouseArea {
                                id: ejectMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.ejectDisk(disk.model.dDev, disk.model.dPath)
                            }
                        }
                        Text {
                            visible: disk.mounted && disk.model.dSize > 0 && !(sec.removable && diskMa.containsMouse)
                            text: Math.round(disk.frac * 100) + "%"
                            color: disk.frac > 0.9 ? view.sys.colCrit
                                                   : Qt.rgba(1, 1, 1, 0.42)
                            font {
                                family: view.sys.fontFam
                                pixelSize: view.sys.fontSize - 6
                                bold: true
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: disk.model.dSize > 0
                        text: disk.mounted
                              ? (view.human(disk.model.dUsed) + " / " + view.human(disk.model.dSize))
                              : (view.human(disk.model.dSize) + " • " + view.sys.tr("Подключить"))
                        color: disk.mounted ? Qt.rgba(1, 1, 1, 0.28) : view.sys.colOn
                        elide: Text.ElideRight
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 7 }
                    }

                    // полоска заполнения; у телефонов размера нет — и полосы тоже
                    Rectangle {
                        visible: disk.mounted && disk.model.dSize > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 3
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.10)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, disk.frac))
                            height: parent.height
                            radius: 2
                            color: disk.frac > 0.9 ? view.sys.colCrit : view.sys.colOn
                            Behavior on width { NumberAnimation { duration: 240 } }
                        }
                    }
                }

                MouseArea {
                    id: diskMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (disk.mounted) {
                            view.go(disk.model.dPath);
                        } else {
                            view.mountDisk(disk.model.dDev);
                        }
                    }
                }
            }
        }
    }

    // Колонка закладок и список лежат на одном фоне, без черты граница не
    // читалась. В раскладке она обрывалась вместе со строкой, поэтому рисуем
    // её слоем: от шапки и до самого низа окна.
    Rectangle {
        z: 1
        width: 1
        x: 190 + 7
        // Не anchors: headSep лежит внутри col, а не рядом, и привязка к
        // не-родителю и не-соседу молча не срабатывает — черта просто
        // не имела высоты. Считаем координату через положение в раскладке.
        y: col.y + headSep.y + headSep.height
        height: Math.max(0, view.height - y)
        color: Qt.rgba(1, 1, 1, 0.14)
        visible: !view.openWithFile.length && height > 0
    }

    ColumnLayout {
        id: col
        width: parent.width
        // В отдельном окне колонка обязана занять его целиком: список внутри
        // тянется на всю оставшуюся высоту. Без этого окно любого размера
        // показывало список одной и той же высоты, а под ним оставалась
        // чёрная полоса в треть экрана — файлы приходилось прокручивать в
        // окне, где на них хватало места с запасом.
        height: view.windowMode ? view.height : col.implicitHeight
        spacing: 12

        // ------------------------------------------------------- abas FM 2.0
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: !view.openWithFile.length

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                contentWidth: tabsRow.implicitWidth
                clip: true
                interactive: contentWidth > width
                Row {
                    id: tabsRow
                    spacing: 4
                    Repeater {
                        model: fileTabs
                        delegate: Rectangle {
                            id: tabChip
                            required property var model
                            readonly property int tid: model.tid
                            readonly property string path: model.path
                            readonly property string label: model.label
                            readonly property bool on: tid === view.activeTabId
                            width: Math.min(140, tabLbl.implicitWidth + 36)
                            height: 28
                            radius: 9
                            color: on ? Qt.rgba(1, 1, 1, 0.10)
                                 : (tabMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                            border.color: on ? view.sys.colLine : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 4
                                spacing: 2
                                Text {
                                    id: tabLbl
                                    Layout.fillWidth: true
                                    text: tabChip.label
                                    elide: Text.ElideRight
                                    color: tabChip.on ? view.sys.colFg : view.sys.colMuted
                                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                                }
                                Text {
                                    visible: fileTabs.count > 1
                                    text: "×"
                                    color: closeMa.containsMouse ? view.sys.colFg : Qt.rgba(1, 1, 1, 0.35)
                                    font { family: view.sys.fontFam; pixelSize: 14 }
                                    MouseArea {
                                        id: closeMa
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: view.closeTab(tabChip.tid)
                                    }
                                }
                            }
                            ToolTip.visible: tabMa.containsMouse
                            ToolTip.delay: 400
                            ToolTip.text: tabChip.path
                            MouseArea {
                                id: tabMa
                                anchors.fill: parent
                                anchors.rightMargin: fileTabs.count > 1 ? 18 : 0
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.MiddleButton) {
                                        view.closeTab(tabChip.tid);
                                        return;
                                    }
                                    if (mouse.button === Qt.RightButton) {
                                        var pos = mapToItem(view, mouse.x, mouse.y);
                                        view.openTabMenu(tabChip.tid, pos.x, pos.y);
                                        return;
                                    }
                                    view.switchTab(tabChip.tid);
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 9
                color: plusMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                border.color: view.sys.colLine
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 16 }
                }
                MouseArea {
                    id: plusMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.newTab(Quickshell.env("HOME"))
                }
            }

            Text {
                text: view.gitBrief.length > 0 ? ("GIT · " + view.gitBrief) : "GIT"
                color: gitBadgeMa.containsMouse ? view.sys.colOn : view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                MouseArea {
                    id: gitBadgeMa
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.openGitPanel("status")
                }
            }
        }

        // ------------------------------------------------------- шапка
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                radius: 13
                color: upMa.containsMouse ? view.sys.colHover : Qt.rgba(1, 1, 1, 0.05)
                border.color: view.sys.colLine
                border.width: 1
                Behavior on color { ColorAnimation { duration: 140 } }

                Glyph {
                    anchors.fill: parent
                    glyph: String.fromCodePoint(0xF0143)   // chevron-up
                    color: view.sys.colFg
                    fontFam: view.sys.fontFam
                    size: view.sys.iconSize - 2
                }
                MouseArea {
                    id: upMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.up()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: !view.pathEditing

                // breadcrumb clicável
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    contentWidth: crumbRow.implicitWidth
                    clip: true
                    interactive: contentWidth > width
                    Row {
                        id: crumbRow
                        spacing: 2
                        Text {
                            text: "/"
                            color: rootCrumbMa.containsMouse ? view.sys.colOn : view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; bold: true }
                            MouseArea {
                                id: rootCrumbMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.go("/")
                            }
                        }
                        Repeater {
                            model: view.pathSegments()
                            delegate: Row {
                                required property var modelData
                                spacing: 2
                                Text {
                                    text: "›"
                                    color: Qt.rgba(1, 1, 1, 0.25)
                                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                                }
                                Text {
                                    text: modelData.name
                                    color: segMa.containsMouse ? view.sys.colOn : view.sys.colFg
                                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 1; bold: true }
                                    MouseArea {
                                        id: segMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: view.go(modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: view.sys.wallpaperFolderPickMode
                          ? view.sys.tr("Выберите папку с обоями")
                          : (view.status.length ? view.status
                             : (view.pathError.length ? view.pathError : view.dir))
                    color: view.sys.wallpaperFolderPickMode || view.status.length
                           ? view.sys.colOn
                           : (view.pathError.length ? view.sys.colWarn : view.sys.colMuted)
                    elide: Text.ElideMiddle
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onDoubleClicked: view.startPathEdit()
                    }
                }
            }

            // path edit (Ctrl+L)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: 13
                visible: view.pathEditing
                color: Qt.rgba(1, 1, 1, 0.06)
                border.color: view.pathError.length ? view.sys.colWarn : view.sys.colOn
                border.width: 1
                TextField {
                    id: pathField
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    text: view.pathEditText
                    onTextChanged: {
                        view.pathEditText = text;
                        if (view.pathEditing) pathCompleteDebounce.restart();
                    }
                    color: view.sys.colFg
                    selectedTextColor: view.sys.colBg
                    selectionColor: view.sys.colOn
                    background: Item {}
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 1 }
                    Keys.onEscapePressed: view.cancelPathEdit()
                    Keys.onReturnPressed: view.submitPathEdit()
                    Keys.onEnterPressed: view.submitPathEdit()
                    Keys.onDownPressed: {
                        if (pathSuggest.count > 0)
                            view.pathSuggestIndex = Math.min(pathSuggest.count - 1, view.pathSuggestIndex + 1);
                    }
                    Keys.onUpPressed: {
                        if (pathSuggest.count > 0)
                            view.pathSuggestIndex = Math.max(0, view.pathSuggestIndex - 1);
                    }
                    Keys.onTabPressed: {
                        if (view.acceptPathSuggest()) event.accepted = true;
                    }
                }

                // autocomplete dropdown
                Rectangle {
                    visible: view.pathEditing && pathSuggest.count > 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.bottom
                    anchors.topMargin: 4
                    z: 50
                    height: Math.min(180, pathSuggestCol.implicitHeight + 8)
                    radius: 12
                    color: Qt.rgba(0.05, 0.05, 0.06, 0.98)
                    border.color: view.sys.colLine
                    border.width: 1
                    clip: true
                    Column {
                        id: pathSuggestCol
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 1
                        Repeater {
                            model: pathSuggest
                            delegate: Rectangle {
                                required property var model
                                required property int index
                                width: pathSuggestCol.width
                                height: 26
                                radius: 8
                                color: index === view.pathSuggestIndex
                                       ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    text: (model.sKind === "dir" ? "▸ " : "  ") + model.sPath
                                    elide: Text.ElideMiddle
                                    color: index === view.pathSuggestIndex
                                           ? view.sys.colFg : view.sys.colMuted
                                    font { family: view.sys.fontFam; pixelSize: 11 }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: view.pathSuggestIndex = index
                                    onClicked: {
                                        view.pathSuggestIndex = index;
                                        view.acceptPathSuggest();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // copy path
            Rectangle {
                visible: !view.pathEditing && !view.sys.wallpaperFolderPickMode
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 13
                color: copyPathMa.containsMouse ? view.sys.colHover : Qt.rgba(1, 1, 1, 0.05)
                border.color: view.sys.colLine
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF018F)
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 15 }
                }
                ToolTip.visible: copyPathMa.containsMouse
                ToolTip.text: "COPY PATH"
                ToolTip.delay: 350
                MouseArea {
                    id: copyPathMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.copyCurrentPath()
                }
            }

            // Режим связи папки обоев: подтверждаем текущий каталог.
            Rectangle {
                visible: view.sys.wallpaperFolderPickMode
                Layout.preferredWidth: Math.max(148, useFolderRow.implicitWidth + 24)
                Layout.preferredHeight: 38
                radius: 13
                color: useFolderMa.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                border.color: useFolderMa.containsMouse ? view.sys.colOn : view.sys.colLine
                border.width: 1
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on border.color { ColorAnimation { duration: 140 } }

                RowLayout {
                    id: useFolderRow
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: String.fromCodePoint(0xF012C)
                        color: useFolderMa.containsMouse ? view.sys.colOn : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 15 }
                    }
                    Text {
                        text: view.sys.tr("Использовать эту папку")
                        color: useFolderMa.containsMouse ? view.sys.colFg : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                    }
                }
                MouseArea {
                    id: useFolderMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.sys.finishWallpaperFolderPick(view.dir)
                }
            }

            // строка фильтра
            Rectangle {
                Layout.preferredWidth: 260
                Layout.preferredHeight: 38
                radius: 19
                color: Qt.rgba(1, 1, 1, 0.06)
                border.color: view.filter.length ? view.sys.colOn : view.sys.colLine
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    spacing: 7
                    Text {
                        text: String.fromCodePoint(0xF0349)   // magnify
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 13 }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: view.filter.length ? view.filter : view.sys.tr("Просто печатайте")
                        color: view.filter.length ? view.sys.colFg : Qt.rgba(1, 1, 1, 0.30)
                        elide: Text.ElideRight
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 1 }
                    }
                }
            }

            // ------------------------------------------- список или сетка
            // Две кнопки, а не выпадающий список: режимов ровно два, и между
            // ними переключаются часто. Выбор запоминается в настройках, иначе
            // проводник каждый раз открывался бы не тем, чем его закрыли.
            Rectangle {
                Layout.preferredWidth: 76
                Layout.preferredHeight: 38
                radius: 19
                color: Qt.rgba(1, 1, 1, 0.06)
                border.color: view.sys.colLine
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 2

                    Repeater {
                        model: [
                            { id: "list", g: 0xF0279 },   // md-format_list_bulleted
                            { id: "grid", g: 0xF0A0E }    // md-view_grid_outline
                        ]

                        Rectangle {
                            required property var modelData
                            readonly property bool on: view.mode === modelData.id

                            width: 34; height: 30
                            radius: 15
                            color: on ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g,
                                                view.sys.colOn.b, 0.25)
                                 : (modeMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08)
                                                         : "transparent")
                            Behavior on color { ColorAnimation { duration: 130 } }

                            Glyph {
                                anchors.centerIn: parent
                                glyph: String.fromCodePoint(parent.modelData.g)
                                color: parent.on ? view.sys.colOn : view.sys.colMuted
                                fontFam: view.sys.fontFam
                                size: 15
                            }

                            MouseArea {
                                id: modeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.setMode(parent.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: headSep
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: view.sys.colLine
        }

        // ---------------------------------------------- закладки + список
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            visible: !view.openWithFile.length

            // закладки: узкая колонка фиксированной ширины, остальное — списку
            ColumnLayout {
                Layout.preferredWidth: 190
                Layout.maximumWidth: 190
                Layout.minimumWidth: 190
                Layout.alignment: Qt.AlignTop
                spacing: 3

                Repeater {
                    model: places
                    Rectangle {
                        id: place
                        required property var model
                        readonly property bool active: view.dir === place.model.pPath

                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 12
                        color: placeMa.containsMouse ? view.sys.colHover
                             : (place.active ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                        Behavior on color { ColorAnimation { duration: 130 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            spacing: 9
                            Text {
                                text: String.fromCodePoint(
                                          place.model.pKey === "home" ? 0xF02DC
                                        : place.model.pKey === "downloads" ? 0xF0179
                                        : place.model.pKey === "pictures" ? 0xF021F
                                        : place.model.pKey === "videos" ? 0xF022B
                                        : place.model.pKey === "music" ? 0xF0388
                                        : place.model.pKey === "documents" ? 0xF0219
                                        : place.model.pKey === "trash" ? 0xF0A79
                                        : place.model.pKey === "root" ? 0xF02CA
                                                                      : 0xF024B)
                                color: place.active ? view.sys.colOn : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: 16 }
                            }
                            Text {
                                visible: place.model.pKey === "trash" && view.trashCount > 0
                                text: String(view.trashCount)
                                color: view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: view.placeLabel(place.model.pKey, place.model.pLabel)
                                color: place.active ? view.sys.colFg : view.sys.colMuted
                                elide: Text.ElideRight
                                font {
                                    family: view.sys.fontFam
                                    pixelSize: view.sys.fontSize - 1
                                    bold: place.active
                                }
                            }
                        }
                        MouseArea {
                            id: placeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                // у корзины своё короткое меню: только очистка
                                if (mouse.button === Qt.RightButton) {
                                    if (place.model.pKey !== "trash") return;
                                    var p = mapToItem(view, mouse.x, mouse.y);
                                    view.openMenu("", true, p.x, p.y, "trash");
                                    return;
                                }
                                view.go(place.model.pPath);
                            }
                        }
                    }
                }

                // Favorites
                Text {
                    visible: favPlaces.count > 0
                    Layout.topMargin: 8
                    Layout.leftMargin: 10
                    text: "FAVORITES"
                    color: Qt.rgba(1, 1, 1, 0.28)
                    font { family: view.sys.fontFam; pixelSize: 10; letterSpacing: 1 }
                }
                Repeater {
                    model: favPlaces
                    Rectangle {
                        id: fav
                        required property var model
                        readonly property bool active: view.dir === fav.model.fPath
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 10
                        color: favMa.containsMouse ? view.sys.colHover
                             : (fav.active ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            spacing: 8
                            Text {
                                text: "★"
                                color: fav.active ? view.sys.colOn : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: 12 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: fav.model.fName
                                elide: Text.ElideRight
                                color: fav.active ? view.sys.colFg : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
                            }
                        }
                        MouseArea {
                            id: favMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton) {
                                    view.openFolderInNewTab(fav.model.fPath);
                                    return;
                                }
                                if (mouse.button === Qt.RightButton) {
                                    view.removeFavorite(fav.model.fPath);
                                    return;
                                }
                                view.go(fav.model.fPath);
                            }
                        }
                    }
                }

                // Recent
                Text {
                    visible: recentPlaces.count > 0
                    Layout.topMargin: 8
                    Layout.leftMargin: 10
                    text: "RECENT"
                    color: Qt.rgba(1, 1, 1, 0.28)
                    font { family: view.sys.fontFam; pixelSize: 10; letterSpacing: 1 }
                }
                Repeater {
                    model: recentPlaces
                    Rectangle {
                        id: rec
                        required property var model
                        readonly property bool active: view.dir === rec.model.rPath
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 10
                        color: recMa.containsMouse ? view.sys.colHover : "transparent"
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            text: rec.model.rName
                            elide: Text.ElideMiddle
                            color: rec.active ? view.sys.colFg : view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                        }
                        MouseArea {
                            id: recMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton)
                                    view.openFolderInNewTab(rec.model.rPath);
                                else
                                    view.go(rec.model.rPath);
                            }
                        }
                    }
                }

                // ------------------------------------------- носители
                DiskSection {
                    title: view.sys.tr("Диски")
                    items: disks
                }
                DiskSection {
                    title: view.sys.tr("Съёмные")
                    items: removables
                    removable: true
                }
            }

            // место под вертикальную черту: сама она нарисована отдельно,
            // чтобы идти до самого низа окна, а не до конца строки
            Item { Layout.preferredWidth: 1 }

            // список файлов — занимает всё оставшееся место
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 380
                spacing: 1

                // ---------------------------------------------- сортировка
                Text {
                    Layout.fillWidth: true
                    visible: view.listTotal > view.listShown && view.listShown > 0
                    text: "SHOWING " + view.listShown + " / " + view.listTotal
                          + " · type to filter"
                    color: view.sys.colWarn
                    font { family: view.sys.fontFam; pixelSize: 10 }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 4
                    spacing: 6

                    component SortBtn: Rectangle {
                        property string key: ""
                        property string label: ""
                        readonly property bool on: view.sortBy === key

                        Layout.preferredHeight: 26
                        Layout.preferredWidth: sortTxt.implicitWidth + (on ? 30 : 18)
                        radius: 9
                        color: on ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g,
                                            view.sys.colOn.b, 0.20)
                             : (sortMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 140 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                id: sortTxt
                                text: parent.parent.label
                                color: parent.parent.on ? view.sys.colFg : view.sys.colMuted
                                font {
                                    family: view.sys.fontFam
                                    pixelSize: view.sys.fontSize - 4
                                    bold: parent.parent.on
                                }
                            }
                            // стрелка показывает направление и переключает его
                            Text {
                                visible: parent.parent.on
                                text: view.sortDesc ? "󰄼" : "󰄿"
                                color: view.sys.colOn
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                            }
                        }
                        MouseArea {
                            id: sortMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.setSort(parent.key)
                        }
                    }

                    Text {
                        text: view.sys.tr("Сортировка")
                        color: Qt.rgba(1, 1, 1, 0.30)
                        font {
                            family: view.sys.fontFam; pixelSize: view.sys.fontSize - 5
                            bold: true; capitalization: Font.AllUppercase; letterSpacing: 1
                        }
                    }
                    SortBtn { key: "name"; label: view.sys.tr("Имя") }
                    SortBtn { key: "time"; label: view.sys.tr("Дата") }
                    SortBtn { key: "size"; label: view.sys.tr("Размер") }
                    SortBtn { key: "type"; label: view.sys.tr("Тип") }

                    Item { Layout.fillWidth: true }

                    // Скрытые файлы. Выбор запоминается в настройках, а не
                    // живёт до закрытия окна: человек решает это один раз и
                    // не любит возвращаться к решению каждое утро.
                    Rectangle {
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: hidTxt.implicitWidth + 26
                        radius: 9
                        color: view.sys.cfg.filesHidden
                               ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g,
                                         view.sys.colOn.b, 0.18)
                             : (hidMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
                        Behavior on color { ColorAnimation { duration: 140 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: String.fromCodePoint(
                                          view.sys.cfg.filesHidden ? 0xF06D0 : 0xF06D1)
                                color: view.sys.cfg.filesHidden ? view.sys.colOn : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                            }
                            Text {
                                id: hidTxt
                                text: view.sys.tr("Скрытые")
                                color: view.sys.cfg.filesHidden ? view.sys.colFg : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                            }
                        }
                        MouseArea {
                            id: hidMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                view.sys.cfg.filesHidden = !view.sys.cfg.filesHidden;
                                view.sys.saveCfg();
                                view.reload();
                            }
                        }
                    }

                    // папки сверху — отдельным переключателем, а не частью
                    // порядка: он нужен при любой сортировке
                    Rectangle {
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: ffTxt.implicitWidth + 26
                        radius: 9
                        color: view.foldersFirst
                               ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g,
                                         view.sys.colOn.b, 0.18)
                             : (ffMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
                        Behavior on color { ColorAnimation { duration: 140 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: String.fromCodePoint(0xF024B)
                                color: view.foldersFirst ? view.sys.colOn : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                            }
                            Text {
                                id: ffTxt
                                text: view.sys.tr("Папки сверху")
                                color: view.foldersFirst ? view.sys.colFg : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                            }
                        }
                        MouseArea {
                            id: ffMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                view.foldersFirst = !view.foldersFirst;
                                view.applyFilter();
                            }
                        }
                    }
                }

                // Сдвиг делаем трансформом, а не x: координатами элементов
                // внутри Layout распоряжается сам Layout, и присвоение x
                // разъезжалось с раскладкой — колонки налезали друг на друга.
                opacity: view.listOpacity
                transform: Translate { x: view.listShift }
                Behavior on opacity { NumberAnimation { duration: 150 } }

                ListView {
                    id: list
                    visible: view.mode === "list"
                    Layout.fillWidth: true
                    // В пилюле высоту держим постоянной: список не должен
                    // «дышать» при переходе между папками с разным числом
                    // файлов. В отдельном окне наоборот — он занимает всё,
                    // что окно даёт, иначе часть окна пропадает впустую.
                    Layout.fillHeight: view.windowMode
                    Layout.preferredHeight: view.windowMode ? 0 : view.sys.filesListH
                    Layout.minimumHeight: view.windowMode ? 120 : 0
                    clip: true
                    model: entries
                    currentIndex: view.current
                    highlightMoveDuration: 130
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    // Рамка выделения внутри ListView
                    Rectangle {
                        id: listRubberBand
                        z: 90
                        visible: false
                        color: Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.18)
                        border.color: view.sys.colOn
                        border.width: 1
                        radius: 4
                    }

                    // Мышью список не таскается. ListView — это Flickable, а он
                    // по умолчанию понимает зажатую кнопку как прокрутку: то
                    // есть ровно тем же движением, которым файл берут, чтобы
                    // перетащить. Список уезжал из-под курсора на первых же
                    // пикселях, и перетаскивание превращалось в лотерею.
                    //
                    // Это поведение с сенсорного экрана, где другого способа
                    // прокрутить нет. Здесь есть колесо, и оно однозначно.
                    interactive: false

                    // interactive: false выключает у Flickable и колесо тоже,
                    // поэтому крутим сами. У мыши шаг приходит в angleDelta
                    // (одна «ступенька» — 120), у тачпада в pixelDelta и
                    // мелкими порциями; берём то, что пришло.
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function (ev) {
                            var step = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y
                                     : ev.angleDelta.y;
                            if (step === 0) return;
                            var max = Math.max(0, list.contentHeight - list.height);
                            list.contentY = Math.max(0, Math.min(max, list.contentY - step));
                        }
                    }

                    // Подложка под делегатами: правый клик по пустому месту
                    // даёт меню самой папки. Живёт внутри ListView, иначе
                    // anchors ругались бы на управление со стороны Layout.
                    MouseArea {
                        id: listBgMa
                        anchors.fill: parent
                        z: -1
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        hoverEnabled: true

                        property real startX: 0
                        property real startY: 0
                        property bool selecting: false

                        onPressed: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                startX = mouse.x;
                                startY = mouse.y;
                                selecting = true;
                                if (!(mouse.modifiers & Qt.ControlModifier)) {
                                    view.clearSelection();
                                }
                            }
                        }

                        onPositionChanged: mouse => {
                            if (!selecting || mouse.buttons !== Qt.LeftButton) return;
                            var rx = Math.min(startX, mouse.x);
                            var ry = Math.min(startY, mouse.y);
                            var rw = Math.abs(mouse.x - startX);
                            var rh = Math.abs(mouse.y - startY);

                            if (rw > 5 || rh > 5) {
                                listRubberBand.x = rx;
                                listRubberBand.y = ry;
                                listRubberBand.width = rw;
                                listRubberBand.height = rh;
                                listRubberBand.visible = true;

                                view.updateSelectionByRect(rx, ry, rw, rh);
                            }
                        }

                        onReleased: mouse => {
                            if (selecting) {
                                selecting = false;
                                listRubberBand.visible = false;
                            }
                        }

                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                var p = mapToItem(view, mouse.x, mouse.y);
                                view.openMenu("", true, p.x, p.y);
                            } else if (mouse.button === Qt.LeftButton) {
                                if (listRubberBand.width <= 5 && listRubberBand.height <= 5) {
                                    view.clearSelection();
                                }
                            }
                        }
                    }

                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property var model

                        width: ListView.view.width
                        height: 42
                        radius: 12
                        readonly property bool dropTarget:
                            row.model.eType === "d" && rowDrop.containsDrag
                        readonly property bool isSelected:
                            view.isSelected(view.fullPath(row.model.eName))

                        color: row.dropTarget
                               ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g,
                                         view.sys.colOn.b, 0.28)
                             : row.isSelected
                               ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g,
                                         view.sys.colOn.b, 0.20)
                             : index === view.current ? Qt.rgba(1, 1, 1, 0.09)
                             : (rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }
                        border.color: row.dropTarget ? view.sys.colOn
                                    : row.isSelected ? view.sys.colOn
                                    : "transparent"
                        border.width: (row.dropTarget || row.isSelected) ? 1 : 0
                        opacity: view.isCutPath(view.fullPath(row.model.eName)) ? 0.42
                               : (view.isCopiedPath(view.fullPath(row.model.eName)) ? 0.78 : 1)
                        Behavior on opacity { NumberAnimation { duration: 140 } }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.dropTarget
                            z: 5
                            text: "DROP HERE"
                            color: view.sys.colOn
                            font { family: view.sys.fontFam; pixelSize: 10; letterSpacing: 1 }
                        }

                        // Папку можно выбрать курсором: бросили на строку —
                        // кладём внутрь неё, а не в открытый каталог.
                        DropArea {
                            id: rowDrop
                            anchors.fill: parent
                            keys: ["text/uri-list"]
                            enabled: row.model.eType === "d"
                            onDropped: drop => {
                                var p = view.mapFromItem(row, drop.x, drop.y);
                                view.takeDrop(drop, view.fullPath(row.model.eName), p.x, p.y);
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 11
                            spacing: 10

                            Text {
                                text: view.iconFor(row.model)
                                color: row.model.eType === "d" ? view.sys.colOn : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: 19 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.model.eName
                                color: view.sys.colFg
                                elide: Text.ElideMiddle
                                font {
                                    family: view.sys.fontFam
                                    pixelSize: view.sys.fontSize
                                    bold: row.index === view.current || row.isSelected
                                }
                            }
                            // дата изменения — у всех, включая папки
                            Text {
                                text: view.timeText(row.model)
                                color: Qt.rgba(1, 1, 1, 0.26)
                                horizontalAlignment: Text.AlignRight
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                            }
                            Text {
                                Layout.preferredWidth: 62
                                text: view.sizeText(row.model)
                                color: Qt.rgba(1, 1, 1, 0.32)
                                horizontalAlignment: Text.AlignRight
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                            property bool dragging: false
                            property real pressX: 0
                            property real pressY: 0

                            onPressed: mouse => { pressX = mouse.x; pressY = mouse.y; }
                            onReleased: dragging = false
                            onPositionChanged: mouse => {
                                if (dragging || !pressed || mouse.buttons !== Qt.LeftButton) return;
                                // порог, чтобы обычный клик не превращался в перетаскивание
                                if (Math.abs(mouse.x - pressX) < 12
                                    && Math.abs(mouse.y - pressY) < 12) return;
                                view.current = row.index;
                                dragging = true;
                                var p = view.fullPath(row.model.eName);
                                if (!view.isSelected(p)) view.selectSingle(p, row.index);
                                // панель сворачивается, файл остаётся на курсоре
                                view.sys.startFileDrag(p, view.windowMode);
                            }

                            onClicked: mouse => {
                                if (rowMa.dragging) return;
                                var p = view.fullPath(row.model.eName);
                                view.current = row.index;
                                view.forceActiveFocus();
                                if (mouse.button === Qt.MiddleButton) {
                                    if (row.model.eType === "d") view.openFolderInNewTab(p);
                                    return;
                                }
                                if (mouse.button === Qt.RightButton) {
                                    if (!view.isSelected(p)) {
                                        view.selectSingle(p, row.index);
                                    }
                                    var pos = mapToItem(view, mouse.x, mouse.y);
                                    view.openMenu(p, row.model.eType === "d", pos.x, pos.y);
                                    return;
                                }
                                if (mouse.modifiers & Qt.ControlModifier) {
                                    view.toggleSelection(p, row.index);
                                } else if (mouse.modifiers & Qt.ShiftModifier) {
                                    view.selectRange(row.index);
                                } else {
                                    view.selectSingle(p, row.index);
                                }
                            }
                            onDoubleClicked: view.activate(row.index)
                        }
                    }
                }

                // ------------------------------------------------- сетка
                // Тот же список, разложенный плитками: значок крупно, имя под
                // ним в две строки. Пригождается там, где по имени файл не
                // узнать, — снимки, обои, загрузки.
                //
                // Модель, выделение, перетаскивание и меню — те же, что у
                // списка: это одна и та же папка, показанная иначе, и вести
                // себя она обязана одинаково.
                GridView {
                    id: grid
                    visible: view.mode === "grid"
                    Layout.fillWidth: true
                    Layout.fillHeight: view.windowMode
                    Layout.preferredHeight: view.windowMode ? 0 : view.sys.filesListH
                    Layout.minimumHeight: view.windowMode ? 120 : 0
                    clip: true
                    model: entries
                    currentIndex: view.current
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                    cellWidth: Math.floor(width / view.gridCols)
                    cellHeight: 104

                    // Мышью не таскается — по той же причине, что и список:
                    // зажатая кнопка здесь берёт файл, а не крутит содержимое.
                    interactive: false
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function (ev) {
                            var step = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y
                                     : ev.angleDelta.y;
                            if (step === 0) return;
                            var max = Math.max(0, grid.contentHeight - grid.height);
                            grid.contentY = Math.max(0, Math.min(max, grid.contentY - step));
                        }
                    }

                    // Рамка выделения внутри GridView
                    Rectangle {
                        id: gridRubberBand
                        z: 90
                        visible: false
                        color: Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.18)
                        border.color: view.sys.colOn
                        border.width: 1
                        radius: 4
                    }

                    MouseArea {
                        id: gridBgMa
                        anchors.fill: parent
                        z: -1
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        hoverEnabled: true

                        property real startX: 0
                        property real startY: 0
                        property bool selecting: false

                        onPressed: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                startX = mouse.x;
                                startY = mouse.y;
                                selecting = true;
                                if (!(mouse.modifiers & Qt.ControlModifier)) {
                                    view.clearSelection();
                                }
                            }
                        }

                        onPositionChanged: mouse => {
                            if (!selecting || mouse.buttons !== Qt.LeftButton) return;
                            var rx = Math.min(startX, mouse.x);
                            var ry = Math.min(startY, mouse.y);
                            var rw = Math.abs(mouse.x - startX);
                            var rh = Math.abs(mouse.y - startY);

                            if (rw > 5 || rh > 5) {
                                gridRubberBand.x = rx;
                                gridRubberBand.y = ry;
                                gridRubberBand.width = rw;
                                gridRubberBand.height = rh;
                                gridRubberBand.visible = true;

                                view.updateSelectionByRect(rx, ry, rw, rh);
                            }
                        }

                        onReleased: mouse => {
                            if (selecting) {
                                selecting = false;
                                gridRubberBand.visible = false;
                            }
                        }

                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                var p = mapToItem(view, mouse.x, mouse.y);
                                view.openMenu(view.dir, true, p.x, p.y);
                            } else if (mouse.button === Qt.LeftButton) {
                                if (gridRubberBand.width <= 5 && gridRubberBand.height <= 5) {
                                    view.clearSelection();
                                }
                            }
                        }
                    }

                    delegate: Rectangle {
                        id: tile
                        required property int index
                        required property var model

                        width: grid.cellWidth - 6
                        height: grid.cellHeight - 6
                        radius: 14
                        readonly property bool dropTarget:
                            tile.model.eType === "d" && tileDrop.containsDrag
                        readonly property bool isSelected:
                            view.isSelected(view.fullPath(tile.model.eName))

                        color: tile.dropTarget
                               ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g,
                                         view.sys.colOn.b, 0.28)
                             : tile.isSelected
                               ? Qt.rgba(view.sys.colOn.r, view.sys.colOn.g,
                                         view.sys.colOn.b, 0.20)
                             : index === view.current ? Qt.rgba(1, 1, 1, 0.09)
                             : (tileMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }
                        border.color: tile.dropTarget ? view.sys.colOn
                                    : tile.isSelected ? view.sys.colOn
                                    : "transparent"
                        border.width: (tile.dropTarget || tile.isSelected) ? 1 : 0
                        opacity: view.isCutPath(view.fullPath(tile.model.eName)) ? 0.42
                               : (view.isCopiedPath(view.fullPath(tile.model.eName)) ? 0.78 : 1)
                        Behavior on opacity { NumberAnimation { duration: 140 } }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            visible: tile.dropTarget
                            z: 5
                            text: "DROP HERE"
                            color: view.sys.colOn
                            font { family: view.sys.fontFam; pixelSize: 9; letterSpacing: 1 }
                        }

                        DropArea {
                            id: tileDrop
                            anchors.fill: parent
                            keys: ["text/uri-list"]
                            enabled: tile.model.eType === "d"
                            onDropped: drop => {
                                var p = view.mapFromItem(tile, drop.x, drop.y);
                                view.takeDrop(drop, view.fullPath(tile.model.eName), p.x, p.y);
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.topMargin: 12
                            anchors.bottomMargin: 8
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 6

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: view.iconFor(tile.model)
                                color: tile.model.eType === "d" ? view.sys.colOn
                                                                : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: 34 }
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: tile.model.eName
                                color: view.sys.colFg
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font {
                                    family: view.sys.fontFam
                                    pixelSize: view.sys.fontSize - 4
                                    bold: tile.index === view.current || tile.isSelected
                                }
                            }
                        }

                        MouseArea {
                            id: tileMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                            property bool dragging: false
                            property real pressX: 0
                            property real pressY: 0

                            onPressed: mouse => { pressX = mouse.x; pressY = mouse.y; }
                            onReleased: dragging = false
                            onPositionChanged: mouse => {
                                if (dragging || !pressed || mouse.buttons !== Qt.LeftButton) return;
                                if (Math.abs(mouse.x - pressX) < 12
                                    && Math.abs(mouse.y - pressY) < 12) return;
                                view.current = tile.index;
                                dragging = true;
                                var p = view.fullPath(tile.model.eName);
                                if (!view.isSelected(p)) view.selectSingle(p, tile.index);
                                view.sys.startFileDrag(p, view.windowMode);
                            }

                            onClicked: mouse => {
                                if (tileMa.dragging) return;
                                var p = view.fullPath(tile.model.eName);
                                view.current = tile.index;
                                view.forceActiveFocus();
                                if (mouse.button === Qt.MiddleButton) {
                                    if (tile.model.eType === "d") view.openFolderInNewTab(p);
                                    return;
                                }
                                if (mouse.button === Qt.RightButton) {
                                    if (!view.isSelected(p)) {
                                        view.selectSingle(p, tile.index);
                                    }
                                    var pos = mapToItem(view, mouse.x, mouse.y);
                                    view.openMenu(p, tile.model.eType === "d", pos.x, pos.y);
                                    return;
                                }
                                if (mouse.modifiers & Qt.ControlModifier) {
                                    view.toggleSelection(p, tile.index);
                                } else if (mouse.modifiers & Qt.ShiftModifier) {
                                    view.selectRange(tile.index);
                                } else {
                                    view.selectSingle(p, tile.index);
                                }
                            }
                            onDoubleClicked: view.activate(tile.index)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: entries.count === 0
                    text: view.filter.length ? view.sys.tr("Ничего не найдено")
                                             : view.sys.tr("Пусто")
                    color: view.sys.colMuted
                    horizontalAlignment: Text.AlignHCenter
                    font { family: view.sys.fontFam; pixelSize: 11 }
                }
            }
        }

        // -------------------------------------------------- чем открыть
        ColumnLayout {
            id: appList
            // Не во всю ширину: проводник занимает 78% экрана, и список из
            // пяти программ, растянутый на всю эту ширину, читался как
            // случайно раскрытая таблица. Список выбора должен быть узким и по
            // центру — глаз идёт по именам сверху вниз, а не слева направо.
            Layout.fillWidth: true
            Layout.maximumWidth: 520
            Layout.alignment: Qt.AlignHCenter
            spacing: 3
            visible: view.openWithFile.length > 0

            // Какая программа сейчас выбрана. Раньше Enter всегда запускал
            // ПЕРВУЮ: выбранной строки не существовало, а currentFile()
            // возвращал apps.get(0). Стрелками выбрать было нечего.
            property int index: 0
            onVisibleChanged: if (visible) appList.index = 0

            function currentFile() {
                if (apps.count === 0) return "";
                var i = Math.max(0, Math.min(apps.count - 1, appList.index));
                return apps.get(i).aFile;
            }
            function step(d) {
                if (apps.count === 0) return;
                appList.index = Math.max(0, Math.min(apps.count - 1, appList.index + d));
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 9
                Text {
                    text: String.fromCodePoint(0xF0770)
                    color: view.sys.colOn
                    font { family: view.sys.fontFam; pixelSize: 15 }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: view.sys.tr("Чем открыть")
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 1; bold: true }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: view.openWithFile.split("/").pop()
                        color: view.sys.colMuted
                        elide: Text.ElideMiddle
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 5 }
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 28; Layout.preferredHeight: 28
                    radius: 14
                    color: backMa.containsMouse ? view.sys.colHover : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: 16 }
                    }
                    MouseArea {
                        id: backMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.openWithFile = ""
                    }
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(apps.count * 44, 520)
                clip: true
                model: apps

                delegate: Rectangle {
                    id: appRow
                    required property int index
                    required property var model

                    width: ListView.view.width
                    height: 44
                    radius: 12
                    // Выделена выбранная строка, а не первая: раньше подсветка
                    // стояла на программе по умолчанию и не двигалась, из-за
                    // чего было не видно, что именно запустит Enter.
                    color: appRow.index === appList.index ? Qt.rgba(1, 1, 1, 0.11)
                         : (appMa.containsMouse ? view.sys.colHover : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 11
                        spacing: 10

                        Image {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            source: appRow.model.aIcon.length
                                    ? Quickshell.iconPath(appRow.model.aIcon, true) : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            visible: status === Image.Ready
                        }
                        Text {
                            Layout.fillWidth: true
                            text: appRow.model.aName
                            color: view.sys.colFg
                            elide: Text.ElideRight
                            font {
                                family: view.sys.fontFam
                                pixelSize: view.sys.fontSize
                                bold: appRow.index === appList.index
                            }
                        }
                        Text {
                            visible: appRow.index === 0
                            text: view.sys.tr("по умолчанию")
                            color: view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 6 }
                        }
                    }

                    MouseArea {
                        id: appMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: appList.index = appRow.index
                        onClicked: view.openWith(appRow.model.aFile)
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: apps.count === 0
                text: view.sys.tr("Подходящих программ не нашлось")
                color: view.sys.colMuted
                horizontalAlignment: Text.AlignHCenter
                font { family: view.sys.fontFam; pixelSize: 11 }
            }
        }

        // Строки-подсказки внизу больше нет: длинный список наезжал на неё,
        // и получалась каша из имён файлов и справки.
    }

    // ------------------------------------------------------ приём файлов
    // Перетаскивание идёт через системный drag (Drag.Automatic), поэтому
    // работает и между двумя окнами проводника, а не только внутри одного.
    property var dropUrls: []
    property real dropX: 0
    property real dropY: 0
    property bool dropMenu: false
    // Куда именно кладём: пусто — в открытую папку, иначе в ту, над которой
    // отпустили. Так можно бросить прямо на строку каталога.
    property string dropDir: ""
    property string dropHover: ""

    function pathsOf(urls) {
        var out = [];
        for (var i = 0; i < urls.length; i++) {
            var u = String(urls[i]);
            if (u.indexOf("file://") === 0) u = u.substring(7);
            out.push(decodeURIComponent(u));
        }
        return out;
    }
    // Что выбрали в первом меню, и что уже лежит в каталоге назначения.
    property bool dropMove: false
    property var  dropConflicts: []
    property bool dropAsk: false

    function dirOf(p) {
        var s = String(p).replace(/\/+$/, "");
        var i = s.lastIndexOf("/");
        return i <= 0 ? "/" : s.substring(0, i);
    }
    function dropTargetDir() {
        return view.dropDir.length ? view.dropDir : view.dir;
    }

    // То из перетаскиваемого, что действительно куда-то поедет.
    //
    // Файл, отпущенный там же, где он и лежал, никуда не переносится: копия
    // рядом с оригиналом — это не то, что человек имел в виду, отпустив кнопку
    // в паре сантиметров от места, где нажал. И папку внутрь себя самой класть
    // тоже незачем.
    function movablePaths() {
        var dest = view.dropTargetDir();
        var all = view.pathsOf(view.dropUrls), out = [];
        for (var i = 0; i < all.length; i++) {
            var p = String(all[i]).replace(/\/+$/, "");
            if (p === dest) continue;               // папка сама в себя
            if (view.dirOf(p) === dest) continue;   // уже здесь
            out.push(all[i]);
        }
        return out;
    }

    function dropCancel() {
        view.dropMenu = false;
        view.dropAsk = false;
        view.dropUrls = [];
        view.dropDir = "";
        view.dropConflicts = [];
    }

    // Первый вопрос: переместить или скопировать. Второй — что делать с
    // совпавшими именами — задаём только если совпадения есть, и только
    // после того, как выбран сам способ.
    Process {
        id: pConflicts
        stdout: StdioCollector {
            onStreamFinished: {
                var names = String(text).trim().split("\n").filter(function (x) {
                    return x.length > 0;
                });
                if (names.length === 0) { view.dropRun("keepboth"); return; }
                view.dropConflicts = names;
                view.dropAsk = true;
            }
        }
    }

    function dropPick(move) {
        var paths = view.movablePaths();
        if (paths.length === 0) { view.dropCancel(); return; }
        view.dropMove = move;
        view.dropMenu = false;
        pConflicts.running = false;
        pConflicts.command = ["sh", "-c", view.scripts + ' conflicts "$@"',
                              "_", view.dropTargetDir()].concat(paths);
        pConflicts.running = true;
    }

    function dropRun(mode) {
        var paths = view.movablePaths();
        if (paths.length === 0) { view.dropCancel(); return; }
        // Все файлы одним вызовом: скрипт сам обходит список и считает по
        // нему общий прогресс. Имена уходят отдельными аргументами, поэтому
        // пробелы и кавычки внутри них ничего не ломают.
        var op = view.dropMove ? "move" : "copy";
        var dest = view.dropTargetDir();
        var args = ["sh", "-c", view.scripts + " " + op + ' "$@"',
                    "_", dest, mode].concat(paths);
        view.runLong(args, undefined,
                     paths.length === 1 ? view.baseName(paths[0])
                                        : view.sys.tr("Файлов: ") + paths.length);
        view.dropCancel();
        // перечитывать список тут не надо: pAction сделает это сам, когда
        // закончит. Две перезагрузки подряд запускали анимацию списка дважды,
        // и появление файла дёргалось.
    }

    // Общий приём: если отпустили не над папкой — кладём в открытый каталог.
    // Лежит под строками списка, поэтому их собственные области получают
    // событие первыми.
    function takeDrop(drop, targetDir, px, py) {
        if (!drop.hasUrls || drop.urls.length === 0) return;
        drop.accept(Qt.CopyAction);
        view.dropUrls = drop.urls;
        view.dropDir = targetDir;

        // Отпустили там же, откуда взяли, — переносить нечего, и спрашивать не
        // о чем: любой ответ ничего бы не изменил. Меню в этом случае было
        // чистой помехой — оно появлялось на каждый промах мимо цели и его
        // приходилось закрывать.
        if (view.movablePaths().length === 0) {
            view.dropCancel();
            return;
        }

        view.dropX = Math.max(6, Math.min(px, view.width - 192));
        view.dropY = Math.max(6, Math.min(py, view.height - 84));
        view.dropMenu = true;
    }

    DropArea {
        id: dropZone
        // Ниже всего: событие перетаскивания достаётся самой ВЕРХНЕЙ области
        // под курсором и дальше не идёт. Пока эта висела сверху, строки папок
        // до неё не доживали, и бросить файл в папку было нельзя.
        z: -1
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            var p = view.mapFromItem(dropZone, drop.x, drop.y);
            view.takeDrop(drop, "", p.x, p.y);
        }
    }

    // тонкая рамка, пока над окном что-то тащат: заливка во весь экран
    // мешала целиться в конкретную папку
    Rectangle {
        z: 6
        anchors.fill: parent
        visible: dropZone.containsDrag
        color: "transparent"
        border.color: Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.55)
        border.width: 2
        radius: 14
    }

    // что делать с перенесённым — спрашиваем, а не угадываем по модификатору
    MouseArea {
        z: 92
        anchors.fill: parent
        visible: view.dropMenu
        onClicked: view.dropCancel()
    }
    Rectangle {
        z: 93
        visible: view.dropMenu
        x: view.dropX
        y: view.dropY
        width: 186
        height: dropCol.implicitHeight + 12
        radius: 12
        color: Qt.rgba(0.06, 0.06, 0.07, 0.99)
        border.color: view.sys.colLine
        border.width: 1

        ColumnLayout {
            id: dropCol
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            Repeater {
                model: [
                    { t: view.sys.tr("Скопировать сюда"), g: 0xF018F, mv: false },
                    { t: view.sys.tr("Переместить сюда"), g: 0xF0552, mv: true }
                ]
                Rectangle {
                    id: dropItem
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 9
                    color: dropItemMa.containsMouse ? view.sys.colHover : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        spacing: 9
                        Text {
                            text: String.fromCodePoint(dropItem.modelData.g)
                            color: view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: 14 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: dropItem.modelData.t
                            color: view.sys.colFg
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                        }
                    }
                    MouseArea {
                        id: dropItemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.dropPick(dropItem.modelData.mv)
                    }
                }
            }
        }
    }

    // ------------------------------- совпавшие имена: что с ними делать
    // Второй вопрос задаётся только когда есть о чём спрашивать, и уже после
    // того, как выбран способ переноса. Раньше совпадения разбирались молча:
    // рядом появлялся «файл-2», и человек узнавал об этом, когда искал глазами
    // тот, что клал.
    MouseArea {
        z: 94
        anchors.fill: parent
        visible: view.dropAsk
        onClicked: view.dropCancel()
    }
    Rectangle {
        z: 95
        visible: view.dropAsk
        x: view.dropX
        y: view.dropY
        width: 236
        height: askCol.implicitHeight + 12
        radius: 12
        color: Qt.rgba(0.06, 0.06, 0.07, 0.99)
        border.color: view.sys.colLine
        border.width: 1

        ColumnLayout {
            id: askCol
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.topMargin: 6
                Layout.bottomMargin: 2
                text: view.dropConflicts.length === 1
                      ? view.sys.tr("Уже есть: ") + view.dropConflicts[0]
                      : view.sys.tr("Совпало имён: ") + view.dropConflicts.length
                color: view.sys.colMuted
                elide: Text.ElideMiddle
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
            }

            Repeater {
                model: [
                    { t: view.sys.tr("Заменить"),     g: 0xF0450, m: "overwrite" },
                    { t: view.sys.tr("Оставить оба"), g: 0xF018F, m: "keepboth" },
                    { t: view.sys.tr("Пропустить"),   g: 0xF0156, m: "skip" }
                ]
                Rectangle {
                    id: askItem
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 9
                    color: askItemMa.containsMouse ? view.sys.colHover : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        spacing: 9
                        Text {
                            text: String.fromCodePoint(askItem.modelData.g)
                            color: askItem.modelData.m === "overwrite"
                                   ? view.sys.colCrit : view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: 14 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: askItem.modelData.t
                            color: view.sys.colFg
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
                        }
                    }
                    MouseArea {
                        id: askItemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.dropRun(askItem.modelData.m)
                    }
                }
            }
        }
    }

    // ------------------------------------------------ слой контекстного меню
    MouseArea {
        anchors.fill: parent
        z: 90
        visible: view.menuOpen || view.tabMenuOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
            view.closeMenu();
            view.closeTabMenu();
        }
    }

    // menu de abas
    Rectangle {
        z: 92
        visible: view.tabMenuOpen
        x: view.tabMenuX
        y: view.tabMenuY
        width: 200
        height: tabMenuCol.implicitHeight + 12
        radius: 14
        color: Qt.rgba(0.04, 0.04, 0.05, 0.98)
        border.color: view.sys.colLine
        border.width: 1
        ColumnLayout {
            id: tabMenuCol
            anchors.fill: parent
            anchors.margins: 6
            spacing: 1
            MenuItem {
                glyph: ""
                label: "Close"
                onChosen: view.closeTab(view.tabMenuTid)
            }
            MenuItem {
                glyph: ""
                label: "Close Others"
                onChosen: view.closeOtherTabs(view.tabMenuTid)
            }
            MenuItem {
                glyph: ""
                label: "Close to Right"
                onChosen: view.closeTabsToRight(view.tabMenuTid)
            }
            MenuItem {
                glyph: ""
                label: "Reopen Closed Tab"
                enabledItem: view.closedTabs.length > 0
                onChosen: view.reopenClosedTab()
            }
        }
    }

    Rectangle {
        id: menu
        z: 91
        visible: view.menuOpen
        x: view.menuX
        y: view.menuY
        width: 248
        height: menuCol.implicitHeight + 12
        radius: 14
        color: Qt.rgba(0.04, 0.04, 0.05, 0.98)
        border.color: view.sys.colLine
        border.width: 1

        opacity: view.menuOpen ? 1 : 0
        scale: view.menuOpen ? 1 : 0.94
        transformOrigin: Item.TopLeft
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

        ColumnLayout {
            id: menuCol
            anchors.fill: parent
            anchors.margins: 6
            spacing: 1

            // ========== OPEN ==========
            MenuSectionHead {
                visible: view.menuKind !== "trash"
                title: "OPEN"
                expanded: view.menuSecOpen
                onToggled: view.toggleMenuSec("open")
            }
            MenuItem {
                visible: view.menuSecOpen && view.menuKind !== "trash"
                         && view.menuPath.length > 0 && view.selectedCount <= 1
                glyph: String.fromCodePoint(0xF0770)
                label: view.menuIsDir ? view.sys.tr("Открыть папку") : view.sys.tr("Открыть")
                onChosen: view.doOpen(view.menuPath)
            }
            MenuItem {
                visible: view.menuSecOpen && view.menuKind !== "trash"
                         && view.menuPath.length > 0 && view.menuIsDir && view.selectedCount <= 1
                glyph: String.fromCodePoint(0xF0334)
                label: "Open in New Tab"
                onChosen: { view.closeMenu(); view.openFolderInNewTab(view.menuPath); }
            }
            MenuItem {
                visible: view.menuSecOpen && view.menuKind !== "trash"
                         && view.menuPath.length > 0 && view.selectedCount <= 1 && view.canPreviewPath(view.menuPath)
                glyph: String.fromCodePoint(0xF033A)
                label: "Preview"
                onChosen: { view.closeMenu(); view.openPreview(view.menuPath); }
            }
            MenuItem {
                visible: view.menuSecOpen && view.menuKind !== "trash"
                         && view.menuPath.length > 0 && !view.menuIsDir && view.selectedCount <= 1
                glyph: String.fromCodePoint(0xF03CB)
                label: view.sys.tr("Открыть с помощью…")
                onChosen: view.doOpenWith(view.menuPath)
            }
            MenuItem {
                visible: view.menuSecOpen && view.menuKind !== "trash"
                glyph: String.fromCodePoint(0xF07B7)
                label: "Open Terminal Here"
                onChosen: view.openTerminalHere(view.menuIsDir && view.menuPath.length ? view.menuPath : view.dir)
            }
            MenuItem {
                visible: view.menuSecOpen && view.menuKind !== "trash" && view.hasCode
                glyph: String.fromCodePoint(0xF05A2)
                label: "Open in VS Code"
                onChosen: view.openInCode(view.menuPath.length ? view.menuPath : view.dir)
            }
            MenuItem {
                visible: view.menuSecOpen && view.menuKind !== "trash"
                         && view.menuPath.length > 0 && !view.menuIsDir && view.isArchive(view.menuPath) && view.selectedCount <= 1
                glyph: String.fromCodePoint(0xF05C0)
                label: view.sys.tr("Распаковать сюда")
                onChosen: view.doExtractHere(view.menuPath)
            }
            MenuItem {
                visible: view.menuSecOpen && view.menuKind !== "trash"
                         && view.menuPath.length > 0 && !view.menuIsDir && view.isArchive(view.menuPath) && view.selectedCount <= 1
                glyph: String.fromCodePoint(0xF024B)
                label: view.sys.tr("Распаковать в ") + view.archiveFolderName(view.menuPath) + "/"
                onChosen: view.doExtractToFolder(view.menuPath)
            }
            MenuItem {
                visible: view.menuSecOpen && view.menuKind !== "trash"
                         && view.selectedCount > 1 && view.hasArchiveSelected()
                glyph: String.fromCodePoint(0xF05C0)
                label: view.sys.tr("Распаковать архивы в папки")
                onChosen: view.doExtractAllSelected(true)
            }

            // ========== EDIT ==========
            MenuSectionHead {
                visible: view.menuKind !== "trash"
                title: "EDIT"
                expanded: view.menuSecEdit
                onToggled: view.toggleMenuSec("edit")
            }
            MenuItem {
                visible: view.menuSecEdit && view.menuKind !== "trash"
                         && (view.menuPath.length > 0 || view.selectedCount > 0)
                glyph: String.fromCodePoint(0xF018F)
                label: view.selectedCount > 1 ? (view.sys.tr("Копировать (") + view.selectedCount + ")")
                                             : view.sys.tr("Копировать")
                onChosen: view.doCopy(view.menuPath)
            }
            MenuItem {
                visible: view.menuSecEdit && view.menuKind !== "trash"
                         && (view.menuPath.length > 0 || view.selectedCount > 0)
                glyph: String.fromCodePoint(0xF0190)
                label: view.selectedCount > 1 ? (view.sys.tr("Вырезать (") + view.selectedCount + ")")
                                             : view.sys.tr("Вырезать")
                onChosen: view.doCut(view.menuPath)
            }
            MenuItem {
                visible: view.menuSecEdit && view.menuKind !== "trash"
                glyph: String.fromCodePoint(0xF0192)
                label: view.clipPaths.length > 1 ? (view.sys.tr("Вставить (") + view.clipPaths.length + ")")
                                                : view.sys.tr("Вставить")
                enabledItem: view.clipPaths.length > 0
                onChosen: view.doPaste()
            }
            MenuItem {
                visible: view.menuSecEdit && view.menuKind !== "trash"
                         && view.menuPath.length > 0 && view.selectedCount <= 1
                glyph: String.fromCodePoint(0xF03EB)
                label: view.sys.tr("Переименовать")
                onChosen: view.startRename(view.menuPath)
            }
            MenuItem {
                visible: view.menuSecEdit && view.menuKind !== "trash"
                glyph: String.fromCodePoint(0xF0219)
                label: view.sys.tr("Копировать путь")
                onChosen: view.doCopyPath(view.menuPath)
            }
            MenuItem {
                visible: view.menuSecEdit && view.menuKind !== "trash"
                         && (view.menuIsDir || view.menuPath.length === 0)
                glyph: String.fromCodePoint(0xF04CE)
                label: "Add to Favorites"
                onChosen: view.addFavorite(view.menuPath.length ? view.menuPath : view.dir)
            }
            MenuItem {
                visible: view.menuSecEdit && view.menuKind !== "trash"
                         && view.menuPath.length > 0 && view.selectedCount <= 1
                glyph: String.fromCodePoint(0xF02FD)
                label: view.sys.tr("Свойства")
                onChosen: view.showProps(view.menuPath)
            }

            // ========== CREATE ==========
            MenuSectionHead {
                visible: view.menuKind !== "trash"
                title: "CREATE"
                expanded: view.menuSecCreate
                onToggled: view.toggleMenuSec("create")
            }
            MenuItem {
                visible: view.menuSecCreate && view.menuKind !== "trash"
                glyph: String.fromCodePoint(0xF0257)
                label: view.sys.tr("Создать папку")
                onChosen: view.startMkdir()
            }
            MenuItem {
                visible: view.menuSecCreate && view.menuKind !== "trash"
                glyph: String.fromCodePoint(0xF0219)
                label: "New File"
                onChosen: view.startNewFile()
            }
            MenuItem {
                visible: view.menuSecCreate && view.menuKind !== "trash"
                glyph: String.fromCodePoint(0xF0450)
                label: view.sys.tr("Обновить")
                onChosen: { view.closeMenu(); view.reload(); }
            }

            // ========== GIT ==========
            MenuSectionHead {
                visible: view.menuKind !== "trash"
                title: "GIT"
                expanded: view.menuSecGit
                onToggled: view.toggleMenuSec("git")
            }
            MenuItem {
                visible: view.menuSecGit && view.menuKind !== "trash"
                glyph: String.fromCodePoint(0xF02A2)
                label: "Git Status"
                onChosen: view.openGitPanel("status")
            }
            MenuItem {
                visible: view.menuSecGit && view.menuKind !== "trash"
                glyph: String.fromCodePoint(0xF0318)
                label: "Git Log --oneline"
                onChosen: view.openGitPanel("log")
            }
            MenuItem {
                visible: view.menuSecGit && view.menuKind !== "trash" && !view.gitRepo
                glyph: String.fromCodePoint(0xF02A2)
                label: "Git Init"
                onChosen: view.gitInitHere()
            }

            // ========== DANGER (sempre visível) ==========
            Rectangle {
                visible: view.menuKind !== "trash"
                         && (view.menuPath.length > 0 || view.selectedCount > 0)
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                color: view.sys.colLine
            }

            MenuItem {
                visible: view.menuKind === "trash"
                glyph: String.fromCodePoint(0xF0A79)
                label: view.sys.tr("Очистить корзину")
                danger: true
                enabledItem: view.trashCount > 0
                onChosen: view.emptyTrash()
            }
            MenuItem {
                visible: view.inTrash && view.menuPath.length > 0
                glyph: String.fromCodePoint(0xF0450)
                label: "Restore"
                onChosen: view.doRestore(view.menuPath)
            }
            MenuItem {
                visible: view.menuPath.length > 0 || view.selectedCount > 0
                glyph: String.fromCodePoint(0xF0A79)
                label: view.selectedCount > 1 ? (view.sys.tr("В корзину (") + view.selectedCount + ")")
                                             : view.sys.tr("В корзину")
                danger: true
                onChosen: view.doTrash(view.menuPath)
            }
            MenuItem {
                visible: (view.menuPath.length > 0 || view.selectedCount > 0) && view.menuKind !== "trash"
                glyph: String.fromCodePoint(0xF01B4)
                label: "Delete Permanently"
                danger: true
                onChosen: view.askDeletePermanent(view.menuPath)
            }
            MenuItem {
                visible: view.inTrash && (view.menuPath.length > 0 || view.selectedCount > 0)
                glyph: String.fromCodePoint(0xF01B4)
                label: "Delete Permanently"
                danger: true
                onChosen: view.askDeletePermanent(view.menuPath)
            }
        }
    }

    // ------------------------------------------------ плашка мультивыделения
    Rectangle {
        id: multiActionBar
        z: 88
        visible: view.selectedCount > 1
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(view.width - 24, multiRow.implicitWidth + 32)
        height: 42
        radius: 21
        color: Qt.rgba(0.06, 0.06, 0.08, 0.96)
        border.color: view.sys.colLine
        border.width: 1

        RowLayout {
            id: multiRow
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 10
            spacing: 8

            Text {
                text: view.selectedCount + " " + view.sys.tr("выбрано")
                color: view.sys.colFg
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; bold: true }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                color: view.sys.colLine
            }

            // Копировать
            Rectangle {
                width: 30; height: 30; radius: 15
                color: btnCopyMa.containsMouse ? view.sys.colHover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF018F)
                    color: view.sys.colFg
                    font { family: view.sys.fontFam; pixelSize: 15 }
                }
                MouseArea {
                    id: btnCopyMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.doCopy(view.selectedPaths[0])
                }
            }

            // Вырезать
            Rectangle {
                width: 30; height: 30; radius: 15
                color: btnCutMa.containsMouse ? view.sys.colHover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF0190)
                    color: view.sys.colFg
                    font { family: view.sys.fontFam; pixelSize: 15 }
                }
                MouseArea {
                    id: btnCutMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.doCut(view.selectedPaths[0])
                }
            }

            // Распаковать
            Rectangle {
                visible: view.hasArchiveSelected()
                width: 30; height: 30; radius: 15
                color: btnExtMa.containsMouse ? view.sys.colHover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF05C0)
                    color: view.sys.colOn
                    font { family: view.sys.fontFam; pixelSize: 15 }
                }
                MouseArea {
                    id: btnExtMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.doExtractAllSelected(true)
                }
            }

            // В корзину
            Rectangle {
                width: 30; height: 30; radius: 15
                color: btnTrashMa.containsMouse ? Qt.rgba(0.94, 0.27, 0.27, 0.18) : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF0A79)
                    color: view.sys.colCrit
                    font { family: view.sys.fontFam; pixelSize: 15 }
                }
                MouseArea {
                    id: btnTrashMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.doTrash("")
                }
            }

            // Снять выделение
            Rectangle {
                width: 26; height: 26; radius: 13
                color: btnCloseMa.containsMouse ? view.sys.colHover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 12 }
                }
                MouseArea {
                    id: btnCloseMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.clearSelection()
                }
            }
        }
    }

    // ---------------------------------------------- диалог ввода имени
    MouseArea {
        anchors.fill: parent
        z: 95
        visible: view.dialogMode.length > 0
        onClicked: view.cancelDialog()
    }

    Rectangle {
        z: 96
        visible: view.dialogMode.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(20, view.height / 2 - height)
        width: 420
        height: 64
        radius: 32
        color: Qt.rgba(0.04, 0.04, 0.05, 0.98)
        border.color: view.sys.colOn
        border.width: 1

        scale: view.dialogMode.length > 0 ? 1 : 0.94
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 14
            spacing: 12

            Text {
                text: String.fromCodePoint(view.dialogMode === "mkdir" ? 0xF0257 : 0xF03EB)
                color: view.sys.colOn
                font { family: view.sys.fontFam; pixelSize: 18 }
            }
            TextField {
                id: dialogField
                Layout.fillWidth: true
                color: view.sys.colFg
                placeholderTextColor: view.sys.colMuted
                placeholderText: view.sys.tr("Имя")
                background: null
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize }
                onAccepted: view.confirmDialog()
                Keys.onEscapePressed: view.cancelDialog()
            }
            Rectangle {
                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                radius: 20
                color: dialogField.text.trim().length ? view.sys.colOn : Qt.rgba(1, 1, 1, 0.10)
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF012C)
                    color: "#ffffff"
                    font { family: view.sys.fontFam; pixelSize: 15 }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.confirmDialog()
                }
            }
        }
    }

    // ------------------------------------------------------ trash confirm
    MouseArea {
        anchors.fill: parent
        z: 99
        visible: view.trashConfirmOpen
        onClicked: view.cancelTrashConfirm()
    }
    Rectangle {
        z: 100
        visible: view.trashConfirmOpen
        anchors.centerIn: parent
        width: 360
        implicitHeight: trashConfCol.implicitHeight + 28
        radius: 18
        color: Qt.rgba(0.04, 0.04, 0.05, 0.98)
        border.color: view.sys.colLine
        border.width: 1
        ColumnLayout {
            id: trashConfCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            Text {
                text: view.trashConfirmMode === "empty" ? "EMPTY TRASH?" : "DELETE PERMANENTLY?"
                color: view.sys.colFg
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize; bold: true }
            }
            Text {
                Layout.fillWidth: true
                text: view.trashConfirmMode === "empty"
                      ? "This cannot be undone."
                      : (view.trashConfirmTargets.length === 1
                         ? view.baseName(view.trashConfirmTargets[0])
                         : (view.trashConfirmTargets.length + " items"))
                color: view.sys.colMuted
                wrapMode: Text.Wrap
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2 }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredWidth: cancelTrashLbl.implicitWidth + 20
                    Layout.preferredHeight: 34
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: view.sys.colLine; border.width: 1
                    Text {
                        id: cancelTrashLbl
                        anchors.centerIn: parent
                        text: "CANCEL"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 12 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.cancelTrashConfirm()
                    }
                }
                Rectangle {
                    Layout.preferredWidth: okTrashLbl.implicitWidth + 20
                    Layout.preferredHeight: 34
                    radius: 10
                    color: Qt.rgba(view.sys.colCrit.r, view.sys.colCrit.g, view.sys.colCrit.b, 0.85)
                    Text {
                        id: okTrashLbl
                        anchors.centerIn: parent
                        text: view.trashConfirmMode === "empty" ? "EMPTY" : "DELETE"
                        color: "#fff"
                        font { family: view.sys.fontFam; pixelSize: 12; bold: true }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.confirmTrashAction()
                    }
                }
            }
        }
    }

    // ------------------------------------------------------ git status panel
    MouseArea {
        anchors.fill: parent
        z: 95
        visible: view.gitPanelOpen
        onClicked: view.closeGitPanel()
    }
    Rectangle {
        z: 96
        visible: view.gitPanelOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        width: 320
        height: Math.min(parent.height - 32, gitPanelCol.implicitHeight + 24)
        radius: 16
        color: Qt.rgba(0.04, 0.04, 0.05, 0.98)
        border.color: view.sys.colLine
        border.width: 1
        ColumnLayout {
            id: gitPanelCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: view.gitPanelTitle + (view.gitBrief.length ? (" · " + view.gitBrief) : "")
                    color: view.sys.colFg
                    font { family: view.sys.fontFam; pixelSize: 12; bold: true }
                }
                Text {
                    text: "×"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 16 }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.closeGitPanel()
                    }
                }
            }
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(280, gitLinesCol.implicitHeight)
                contentHeight: gitLinesCol.implicitHeight
                clip: true
                Column {
                    id: gitLinesCol
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: gitLines
                        Text {
                            required property var model
                            width: gitLinesCol.width
                            text: model.gLine
                            elide: Text.ElideRight
                            color: view.sys.colMuted
                            font { family: view.sys.fontFam; pixelSize: 11 }
                        }
                    }
                    Text {
                        visible: gitLines.count === 0
                        text: "CLEAN"
                        color: view.sys.colOk
                        font { family: view.sys.fontFam; pixelSize: 11 }
                    }
                }
            }
            RowLayout {
                spacing: 8
                Rectangle {
                    Layout.preferredWidth: termGitLbl.implicitWidth + 16
                    Layout.preferredHeight: 28
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.06)
                    Text {
                        id: termGitLbl
                        anchors.centerIn: parent
                        text: "TERMINAL"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 10 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { view.closeGitPanel(); view.openTerminalHere(view.dir); }
                    }
                }
                Rectangle {
                    visible: view.hasCode
                    Layout.preferredWidth: codeGitLbl.implicitWidth + 16
                    Layout.preferredHeight: 28
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.06)
                    Text {
                        id: codeGitLbl
                        anchors.centerIn: parent
                        text: "VS CODE"
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 10 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { view.closeGitPanel(); view.openInCode(view.dir); }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------ preview panel
    MouseArea {
        anchors.fill: parent
        z: 93
        visible: view.previewOpen
        onClicked: view.closePreview()
    }
    Rectangle {
        z: 94
        visible: view.previewOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 12
        width: Math.min(420, parent.width * 0.42)
        radius: 16
        color: Qt.rgba(0.04, 0.04, 0.05, 0.98)
        border.color: view.sys.colLine
        border.width: 1
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: view.baseName(view.previewPath)
                    elide: Text.ElideMiddle
                    color: view.sys.colFg
                    font { family: view.sys.fontFam; pixelSize: 13; bold: true }
                }
                Text {
                    text: "×"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 16 }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.closePreview()
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: view.previewMeta.length ? view.previewMeta : "READING…"
                color: view.sys.colMuted
                elide: Text.ElideRight
                font { family: view.sys.fontFam; pixelSize: 10 }
            }
            Text {
                visible: view.previewError.length > 0
                Layout.fillWidth: true
                text: view.previewError
                color: view.sys.colWarn
                wrapMode: Text.Wrap
                font { family: view.sys.fontFam; pixelSize: 11 }
            }
            Image {
                visible: view.previewKind === "image"
                Layout.fillWidth: true
                Layout.fillHeight: true
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: view.previewKind === "image" && view.previewPath.length
                        ? ("file://" + view.previewPath) : ""
            }
            Flickable {
                visible: view.previewKind === "text"
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: previewBody.implicitHeight
                clip: true
                Text {
                    id: previewBody
                    width: parent.width
                    text: view.previewText
                    color: view.sys.colFg
                    wrapMode: Text.WrapAnywhere
                    font { family: view.sys.fontFam; pixelSize: 11 }
                }
            }
            Text {
                visible: view.previewKind === "too_large" || view.previewKind === "none"
                Layout.fillWidth: true
                text: view.previewKind === "too_large" ? "TOO LARGE" : "NO PREVIEW"
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: 12 }
            }
            Text {
                Layout.fillWidth: true
                text: "Space · toggle preview"
                color: Qt.rgba(1, 1, 1, 0.22)
                font { family: view.sys.fontFam; pixelSize: 9 }
            }
        }
    }

    // ------------------------------------------------------ панель «Свойства»
    MouseArea {
        anchors.fill: parent
        z: 97
        visible: view.propsOpen
        onClicked: view.propsOpen = false
    }
    Rectangle {
        id: propsPanel
        z: 98
        visible: view.propsOpen
        anchors.centerIn: parent
        width: 440
        implicitHeight: propsCol.implicitHeight + 36
        radius: 20
        color: Qt.rgba(0.04, 0.04, 0.05, 0.98)
        border.color: view.sys.colLine
        border.width: 1
        scale: view.propsOpen ? 1 : 0.94
        opacity: view.propsOpen ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 150 } }

        readonly property bool isDir: String(view.propsData.kind || "") === "inode/directory"

        component PropRow: RowLayout {
            property string k: ""
            property string v: ""
            visible: v.length > 0
            Layout.fillWidth: true
            spacing: 12
            Text {
                Layout.preferredWidth: 130
                text: k
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
            }
            Text {
                Layout.fillWidth: true
                text: v
                color: view.sys.colFg
                wrapMode: Text.WrapAnywhere
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 3 }
            }
        }

        ColumnLayout {
            id: propsCol
            anchors.fill: parent
            anchors.margins: 18
            spacing: 7

            RowLayout {
                Layout.fillWidth: true
                spacing: 11
                Rectangle {
                    Layout.preferredWidth: 40; Layout.preferredHeight: 40
                    radius: 11
                    color: Qt.rgba(1, 1, 1, 0.08)
                    Glyph {
                        anchors.fill: parent
                        glyph: String.fromCodePoint(propsPanel.isDir ? 0xF024B : 0xF0224)
                        color: view.sys.colOn
                        fontFam: view.sys.fontFam
                        size: view.sys.iconSize
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: String(view.propsData.name || "")
                    color: view.sys.colFg
                    elide: Text.ElideMiddle
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize; bold: true }
                }
                Text {
                    text: "×"
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize + 6 }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.propsOpen = false
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 1
                Layout.topMargin: 4; Layout.bottomMargin: 4
                color: view.sys.colLine
            }

            PropRow { k: view.sys.tr("Тип");        v: String(view.propsData.kind || "") }
            PropRow { k: view.sys.tr("Внутри");     v: propsPanel.isDir ? (String(view.propsData.items || "") + " " + view.sys.tr("элементов")) : "" }
            PropRow { k: view.sys.tr("Размер");     v: String(view.propsData.size_human || "")
                                                       + (view.propsData.size_bytes ? "  (" + view.propsData.size_bytes + " " + view.sys.tr("байт") + ")" : "") }
            PropRow { k: view.sys.tr("Разрешение"); v: String(view.propsData.resolution || "") }
            PropRow { k: view.sys.tr("Длительность"); v: view.propsData.duration ? view.fmtDuration(view.propsData.duration) : "" }
            PropRow { k: view.sys.tr("Изменён");    v: String(view.propsData.modified || "") }
            PropRow { k: view.sys.tr("Создан");     v: String(view.propsData.created || "") }
            PropRow { k: view.sys.tr("Права");      v: String(view.propsData.perms || "") }
            PropRow { k: view.sys.tr("Владелец");   v: String(view.propsData.owner || "") }
            PropRow { k: view.sys.tr("Путь");       v: String(view.propsData.path || "") }
        }
    }
}
