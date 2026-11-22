import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons as Commons
import Quickshell.Io
import Quickshell.Wayland
import "Core.js" as Core
import "Settings.js" as Settings
import "Gate.js" as Gate

// Servicio del plugin: vive mientras el shell corre (keepLoaded). Lleva el estado
// (Core.js), sigue el workspace activo de Hyprland y muestra la capa de bloqueo.
Item {
  id: root

  // Los inyecta el shell si existen.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "leninzapata.super-workspace-lock"
  // Se actualizan solo en syncFocus()/setLockState(): con bindings, el cambio de
  // workspace reescribía lockState dentro de su propio recálculo (binding loop).
  property int activeWorkspaceId: -1
  property bool activeLocked: false

  // ---------------------------------------------------------------- ajustes
  // ~/.config/omarchy/super-workspace-lock/settings.json (DATOS.md). Carpeta 700 y
  // archivo 600, impuestos al arrancar también a lo que ya existía. Ningún
  // FileView tiene ruta hasta storageReady.
  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy/super-workspace-lock"
  property bool storageReady: false
  property bool settingsLoaded: false
  property bool settingsBroken: false
  property var settings: Settings.defaults()

  // Estado de Core.js. Arranca de verdad con la primera lectura de settings.json:
  // todo privado empieza bloqueado.
  property var lockState: Core.start([])
  // Clave de texto del último error de clave (auth.wrong / auth.locked); nunca la clave.
  property string authError: ""

  function applySettingsText(raw) {
    var parsed = null
    try { parsed = JSON.parse(raw && raw.trim().length > 0 ? raw : "{}") } catch (e) { parsed = null }
    // Archivo roto: valores por defecto y el archivo NO se pisa hasta el próximo cambio.
    settingsBroken = parsed === null
    settings = Settings.normalize(parsed)
    var ids = Settings.privateIds(settings)
    if (!settingsLoaded) {
      settingsLoaded = true
      applyShortcut()
      var started = Core.start(ids)
      // Al arrancar: ocultar los bloqueados y devolver lo que quedó oculto de antes
      // (un workspace que dejó de ser privado con el shell apagado).
      Quickshell.execDetached(["python3", "-I", visScript, "sync"].concat(started.lockedIds.map(String)))
      lockState = started
      setLockState(Core.focusChanged(started, -1, activeWorkspaceId > 0 ? activeWorkspaceId : -1, Date.now(), {}))
    } else {
      setLockState(Core.syncPrivate(lockState, ids))
    }
  }

  function savePrivate(id, value) {
    settings = Settings.withPrivate(settings, id, value)
    settingsBroken = false
    settingsFile.setText(JSON.stringify(settings, null, 2) + "\n")
    setLockState(Core.syncPrivate(lockState, Settings.privateIds(settings)))
  }

  // ------------------------------------------------------------- retardo (B)
  // Privados en modo delay que se dejaron: se bloquean al vencer su plazo.
  Timer {
    id: delayTick
    interval: 1000
    repeat: true
    running: Core.hasPending(root.lockState)
    onTriggered: {
      var next = Core.tick(root.lockState, Date.now())
      if (next !== root.lockState) root.setLockState(next)
    }
  }

  // ------------------------------------------------------- lock de sesión (H1)
  // Hyprland no avisa cuando se bloquea la sesión. omarchy.lock y LockSigil
  // responden ambos a `omarchy-shell lock isLocked`: se pregunta cada 2 s, y solo
  // mientras haya algún privado abierto (si no, no hay nada que volver a bloquear).
  readonly property bool sessionWatch: settingsLoaded && Core.hasUnlockedPrivate(lockState)

  Timer {
    id: sessionPoll
    interval: 2000
    repeat: true
    running: root.sessionWatch
    onTriggered: if (!sessionProc.running) sessionProc.exec(["omarchy-shell", "lock", "isLocked"])
  }

  Process {
    id: sessionProc
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() === "true") root.setLockState(Core.sessionLocked(root.lockState))
    }
  }

  // ------------------------------------------------------------ inactividad (0.4.0)
  // Sin teclado ni ratón durante el plazo de un privado ABIERTO, se bloquea aunque estés
  // dentro. IdleMonitor (ext-idle-notify de Wayland) avisa al primer minuto quieto; desde
  // ahí se cuenta el resto. Ignora los inhibidores (un vídeo no lo frena): el audio se
  // decide aparte, por workspace, con idleAudio "wait". Independiente del bloqueo por
  // inactividad de Omarchy: vale también con «Stay awake» puesto.
  readonly property int idleGraceSec: 60          // = Settings.IDLE_MIN
  readonly property var idleTargets: Settings.idleTargets(settings)
  readonly property bool idleWatch: settingsLoaded && Core.hasUnlockedPrivate(lockState)
                                    && Object.keys(idleTargets).length > 0
  property double idleSince: 0                     // ms; 0 = hay actividad

  IdleMonitor {
    id: idleMon
    enabled: root.idleWatch
    timeout: root.idleGraceSec
    respectInhibitors: false
    onIsIdleChanged: root.idleSince = isIdle ? Date.now() - root.idleGraceSec * 1000 : 0
  }

  Timer {
    id: idleTick
    interval: 10000
    repeat: true
    triggeredOnStart: true
    running: root.idleWatch && root.idleSince > 0
    onTriggered: root.checkIdle()
  }

  property var idleWaitIds: []
  function checkIdle() {
    if (!(idleSince > 0)) return
    var due = Core.idleDue(lockState, idleTargets, Date.now() - idleSince)
    if (due.lock.length > 0) setLockState(Core.lockMany(lockState, due.lock))
    if (due.wait.length > 0 && !audioProc.running) {
      idleWaitIds = due.wait
      audioProc.exec(["pactl", "list", "sinks", "short"])
    }
  }

  // ¿Suena algo? Una salida en RUNNING = hay audio en curso. Si pactl falla, no se sabe:
  // se bloquea (la privacidad manda sobre la comodidad).
  Process {
    id: audioProc
    stdout: StdioCollector {
      onStreamFinished: {
        var playing = /\tRUNNING\s*$/m.test(text)
        if (!playing && root.idleSince > 0) root.setLockState(Core.lockMany(root.lockState, root.idleWaitIds))
        root.idleWaitIds = []
      }
    }
  }

  // ------------------------------------------------------------ atajo global
  // lockShortcut se registra en caliente (hyprctl eval): al arrancar, al cambiar el
  // ajuste y tras cada recarga de Hyprland. Antes se leen los atajos de Hyprland: una
  // tecla que ya usa otra cosa no se pisa (queda en shortcutConflict y se avisa en los
  // ajustes), y de los anteriores solo se suelta lo que es nuestro.
  property var appliedShortcuts: []
  property string shortcutConflict: ""

  function applyShortcut() { bindsProc.exec(["hyprctl", "binds", "-j"]) }

  Process {
    id: bindsProc
    stdout: StdioCollector {
      onStreamFinished: {
        var s = Gate.shortcutLua(root.settings.lockShortcut, root.appliedShortcuts, Gate.bindOwners(text))
        root.appliedShortcuts = s.applied
        root.shortcutConflict = s.conflict
        if (s.lua.length > 0) Quickshell.execDetached(["hyprctl", "eval", s.lua])
        if (s.retry) shortcutRetry.restart()
      }
    }
  }
  // No se pudo leer la lista de atajos: no se tocó nada; se reintenta.
  Timer { id: shortcutRetry; interval: 3000; onTriggered: if (root.settingsLoaded) root.applyShortcut() }

  onSettingsChanged: if (settingsLoaded && Gate.normChord(settings.lockShortcut) !== (appliedShortcuts[0] || null)) applyShortcut()

  // Bloquear ya un workspace concreto (botón del panel). Si es el activo, sale la capa.
  function lockWorkspace(id) {
    if (id > 0) setLockState(Core.lockNow(lockState, id))
  }

  // Bloquear ya el workspace activo (atajo / IPC). En uno público: bloqueo puntual.
  function lockCurrent() {
    if (activeWorkspaceId > 0) setLockState(Core.lockNow(lockState, activeWorkspaceId))
  }

  // ------------------------------------------------------------ ventana de ajustes (B)
  property bool settingsOpen: false
  function openSettings() { settingsOpen = true; settingsFocusTimer.restart() }
  Timer { id: settingsFocusTimer; interval: 250; onTriggered: Quickshell.execDetached(["hyprctl", "eval", Gate.focusSettingsLua()]) }
  function closeSettings() { settingsOpen = false }

  // Guarda unos ajustes completos (la ventana de ajustes). Normaliza, escribe y
  // aplica: privados, atajo (onSettingsChanged) y retardos en el próximo cambio.
  function saveSettings(next) {
    if (!settingsLoaded) return "error: settings not loaded"
    settings = Settings.normalize(next)
    settingsBroken = false
    settingsFile.setText(JSON.stringify(settings, null, 2) + "\n")
    setLockState(Core.syncPrivate(lockState, Settings.privateIds(settings)))
    return "ok"
  }

  // Clave propia (B5). La clave va a hash.py por stdin y se borra en cuanto se
  // escribe; de passwords.json el servicio solo mira QUÉ workspaces tienen entrada.
  property var ownPasswordIds: []
  property string ownStatus: ""      // "", "busy", "saved", "removed", "error"

  function setOwnPassword(id, password) {
    if (ownProc.running || !(id > 0) || !password) return
    ownStatus = "busy"
    ownProc.secret = password
    ownProc.mode = "set"
    ownProc.exec(["python3", "-I", String(Qt.resolvedUrl("hash.py")).replace(/^file:\/\//, ""), "set", String(id)])
  }

  function removeOwnPassword(id) {
    if (ownProc.running || !(id > 0)) return
    ownStatus = "busy"
    ownProc.secret = ""
    ownProc.mode = "remove"
    ownProc.exec(["python3", "-I", String(Qt.resolvedUrl("hash.py")).replace(/^file:\/\//, ""), "remove", String(id)])
  }

  Process {
    id: ownProc
    property string secret: ""
    property string mode: ""
    stdinEnabled: true
    onStarted: {
      if (secret.length > 0) write(secret + "\n")
      secret = ""
    }
    onExited: function(exitCode) {
      root.ownStatus = exitCode === 0 ? (mode === "set" ? "saved" : "removed") : "error"
      passwordsFile.reload()
    }
  }

  FileView {
    id: passwordsFile
    path: root.storageReady ? root.configDir + "/passwords.json" : ""
    watchChanges: true
    printErrors: false
    onLoaded: {
      var ids = []
      try {
        var d = JSON.parse(text())
        for (var k in (d.entries || {})) if (parseInt(k, 10) > 0) ids.push(parseInt(k, 10))
      } catch (e) {}
      root.ownPasswordIds = ids
    }
    onLoadFailed: root.ownPasswordIds = []
    onFileChanged: reload()
  }

  SettingsWindow {
    service: root
    strings: strings
    visible: root.settingsOpen
    onVisibleChanged: if (!visible) root.settingsOpen = false
  }

  // Lo llama el panel de la barra (BarWidget.qml). Devuelve "ok" o "error: …".
  function requestPrivate(id, on) {
    if (!settingsLoaded) return "error: settings not loaded"
    if (!Core.canSetPrivate(lockState, id, on)) return "error: locked"
    savePrivate(id, on)
    return "ok"
  }

  Process {
    id: initProc
    command: ["sh", "-c", 'umask 077\n'
              + 'mkdir -p "$1"\n'
              + 'chmod 700 "$1"\n'
              + '[ -e "$1/settings.json" ] || [ -L "$1/settings.json" ] || : > "$1/settings.json"\n'
              + 'find "$1" -maxdepth 1 -type f ! -perm 600 -exec chmod 600 {} +',
              "init", root.configDir]
    onExited: root.storageReady = true
  }

  FileView {
    id: settingsFile
    path: root.storageReady ? root.configDir + "/settings.json" : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applySettingsText(text())
    onLoadFailed: if (root.storageReady) root.applySettingsText("{}")
    onFileChanged: reload()
  }

  function setLockState(next) {
    var before = lockState ? lockState.lockedIds : []
    lockState = next
    activeLocked = Core.isLocked(next, activeWorkspaceId)
    syncVisibility(before, next.lockedIds)
    syncCovers()
  }

  // ------------------------------------------------------- ventanas invisibles
  // Las ventanas de un workspace bloqueado van a opacidad 0 (vis.py guarda y devuelve
  // la original). Hyprland anima el cambio de workspace antes de que el plugin se
  // entere: sin esto, esa transición enseñaba un instante lo que había detrás.
  readonly property string visScript: String(Qt.resolvedUrl("vis.py")).replace(/^file:\/\//, "")

  function vis(cmd, ids) {
    if (ids.length === 0) return
    Quickshell.execDetached(["python3", "-I", visScript, cmd].concat(ids.map(String)))
  }

  function syncVisibility(before, after) {
    vis("hide", after.filter(function(id) { return before.indexOf(id) === -1 }))
    vis("show", before.filter(function(id) { return after.indexOf(id) === -1 }))
  }

  // ------------------------------------------------------------ tapas (0.3.3)
  // Una ventana tapa por workspace bloqueado (CoverWindow.qml). Primero se registra su
  // regla (que nazca en su workspace, «silent»); solo entonces entra en coverIds y se crea.
  property var coverIds: []
  property var coverReadyIds: []
  readonly property bool activeCoverReady: coverReadyIds.indexOf(activeWorkspaceId) !== -1

  function syncCovers() {
    var want = lockState.lockedIds
    var keep = coverIds.filter(function(id) { return want.indexOf(id) !== -1 })
    coverReadyIds = coverReadyIds.filter(function(id) { return want.indexOf(id) !== -1 })
    var add = want.filter(function(id) { return coverIds.indexOf(id) === -1 })
    coverIds = keep
    if (add.length === 0) return
    coverRuleProc.pending = add
    coverRuleProc.exec(["hyprctl", "eval", add.map(Gate.coverRuleLua).join("; ")])
  }

  Process {
    id: coverRuleProc
    property var pending: []
    onExited: {
      var next = root.coverIds.slice()
      for (var i = 0; i < pending.length; i++)
        if (root.lockState.lockedIds.indexOf(pending[i]) !== -1 && next.indexOf(pending[i]) === -1) next.push(pending[i])
      root.coverIds = next
      coverFsTimer.restart()
    }
  }

  // Ya mapeadas: a pantalla completa (por dirección; no cambia el workspace activo).
  Timer {
    id: coverFsTimer
    interval: 350
    onTriggered: {
      var ids = root.coverIds.slice()
      Quickshell.execDetached(["hyprctl", "eval", ids.map(Gate.coverFullscreenLua).join("; ")])
      coverReadyTimer.pending = ids
      coverReadyTimer.restart()
    }
  }
  Timer {
    id: coverReadyTimer
    property var pending: []
    interval: 250
    onTriggered: root.coverReadyIds = pending.filter(function(id) { return root.coverIds.indexOf(id) !== -1 })
  }

  Variants {
    model: root.coverIds
    delegate: CoverWindow {
      required property var modelData
      workspaceId: modelData
      strings: root.translations
      useOwnPassword: Settings.effective(root.settings, modelData).passwordMode === "own"
      visible: true
    }
  }

  // Una ventana que se abre o llega a un workspace bloqueado también se oculta.
  Timer {
    id: rehideTimer
    interval: 150
    onTriggered: root.vis("hide", root.lockState.lockedIds)
  }

  // El workspace activo cambió: el que se deja, si es privado, se bloquea.
  function syncFocus() {
    var id = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    if (id <= 0 || id === activeWorkspaceId) return
    var next = Core.focusChanged(lockState, activeWorkspaceId, id, Date.now(), Settings.delays(settings))
    activeWorkspaceId = id
    setLockState(next)
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.syncFocus() }
  }

  // ---------------------------------------------------------------- Hyprland
  // Mientras se ve la capa: blur fuerte + submap con solo los atajos permitidos
  // (Gate.js). Antes de entrar hacen falta el caché de atajos de Omarchy y el blur
  // que tenía Lenin, para devolverlo igual al salir.
  property var records: ({})
  property var prevBlur: null
  property bool recordsReady: false
  property bool gateOn: false        // submap + blur pedidos a Hyprland
  property bool blurActive: false    // Hyprland confirmó: la capa ya puede ser translúcida
  property var missingAllowed: []
  readonly property bool hyprReady: recordsReady && prevBlur !== null

  onActiveLockedChanged: applyGate()
  onHyprReadyChanged: applyGate()

  function applyGate() {
    if (activeLocked && hyprReady && !gateOn) {
      var g = Gate.enterLua(settings.lockedAllowedShortcuts, records)
      missingAllowed = g.missing
      gateOn = true
      gateProc.exec(["hyprctl", "eval", g.lua])
      var wd = Gate.watchdogCmd(shellPid)
      if (wd) Quickshell.execDetached(wd)
    } else if (!activeLocked && gateOn) {
      gateOn = false
      blurActive = false
      Quickshell.execDetached(["hyprctl", "eval", Gate.exitLua(prevBlur)])
    }
  }

  // PID del proceso del shell (el padre de un sh lanzado con Process), para el vigía.
  property int shellPid: 0
  Process {
    id: pidProc
    command: ["sh", "-c", "echo $PPID; hyprctl submap"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        root.shellPid = parseInt(lines[0], 10) || 0
        // Un shell anterior murió con la capa puesta: devolver la config de Lenin.
        if ((lines[1] || "").trim() === Gate.SUBMAP) Quickshell.execDetached(Gate.recoverCmd())
      }
    }
  }

  function refreshHyprland() {
    blurActive = false
    gateOn = false
    recordsReady = false
    prevBlur = null
    Quickshell.execDetached(["hyprctl", "eval", Gate.layerRuleLua()])
    if (settingsLoaded) { appliedShortcuts = []; applyShortcut() }
    recordsProc.exec(["sh", "-c", "omarchy-menu-keybindings --print >/dev/null 2>&1; "
      + "f=$(ls -t \"$HOME\"/.cache/omarchy/keybindings-*.records 2>/dev/null | head -1); "
      + "[ -n \"$f\" ] && cat \"$f\""])
    blurProc.exec(["sh", "-c", "for o in enabled size passes; do hyprctl getoption decoration:blur:$o -j; done"])
    animProc.exec(["hyprctl", "animations", "-j"])
  }

  Process {
    id: recordsProc
    stdout: StdioCollector {
      onStreamFinished: { root.records = Gate.parseRecords(text); root.recordsReady = true }
    }
  }

  property int workspaceAnimMs: 300
  Process {
    id: animProc
    stdout: StdioCollector { onStreamFinished: root.workspaceAnimMs = Gate.workspaceAnimMs(text) }
  }

  Process {
    id: blurProc
    stdout: StdioCollector {
      onStreamFinished: root.prevBlur = Gate.parseBlurOptions(text)
    }
  }

  // Cuando hyprctl eval terminó, el blur ya está activo: la capa puede aclararse.
  Process {
    id: gateProc
    onExited: if (root.gateOn) root.blurActive = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // Una recarga de Hyprland borra reglas, submap y blur pedidos en caliente.
      if (event && event.name === "configreloaded") reloadTimer.restart()
      if (event && (event.name === "openwindow" || event.name === "movewindowv2")
          && root.lockState.lockedIds.length > 0) rehideTimer.restart()
    }
  }
  Timer { id: reloadTimer; interval: 300; onTriggered: root.refreshHyprland() }

  Component.onDestruction: {
    if (gateOn) Quickshell.execDetached(["hyprctl", "eval", Gate.exitLua(prevBlur)])
    var off = Gate.releaseCmd(String(Qt.resolvedUrl("binds.py")).replace(/^file:\/\//, ""), appliedShortcuts)
    if (off) Quickshell.execDetached(off)
  }

  Component.onCompleted: {
    syncFocus()
    pidProc.running = true
    refreshHyprland()
    initProc.running = true
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  // Con nombre propio: dentro de un delegado, `strings: strings` se apunta a sí mismo.
  readonly property var translations: strings

  LockLayer {
    shown: root.activeLocked
    workspaceId: root.activeWorkspaceId
    strings: strings
    blurActive: root.blurActive
    useOwnPassword: Settings.effective(root.settings, root.activeWorkspaceId).passwordMode === "own"
    coverReady: root.activeCoverReady
    revealDelay: root.workspaceAnimMs + 60
    onUnlocked: function(id) { root.authError = ""; root.setLockState(Core.unlockOk(root.lockState, id)) }
    onErrorReported: function(key) { root.authError = key }
  }

  // IPC: omarchy-shell leninzapata.super-workspace-lock <fn> [args]
  // Es también la puerta de las autopruebas (PLAN.md §1 Accesos).
  Commons.ShellIpc {
    target: root.pluginId

    function state(): string {
      return JSON.stringify({
        version: root.manifest && root.manifest.version ? root.manifest.version : "",
        activeWorkspaceId: root.activeWorkspaceId,
        private: root.lockState.privateIds,
        settingsLoaded: root.settingsLoaded,
        settingsBroken: root.settingsBroken,
        locked: root.lockState.lockedIds,
        pending: root.lockState.pending,
        gateOn: root.gateOn,
        blurActive: root.blurActive,
        allowedMissing: root.missingAllowed,
        authError: root.authError,
        shortcut: root.appliedShortcuts,
        shortcutConflict: root.shortcutConflict,
        shellPid: root.shellPid,
        sessionWatch: root.sessionWatch,
        idleWatch: root.idleWatch,
        idleSince: root.idleSince,
        idleTargets: root.idleTargets,
        settingsOpen: root.settingsOpen,
        language: Commons.I18n.language,
        name: strings.t("plugin.name")
      })
    }

    function openSettings(): string { root.openSettings(); return "ok" }
    function closeSettings(): string { root.closeSettings(); return "ok" }

    function lockCurrent(): string {
      root.lockCurrent()
      return "ok"
    }

    function setPrivate(id: string, value: string): string {
      var n = parseInt(id, 10)
      if (!(n > 0)) return "error: id"
      return root.requestPrivate(n, value === "true")
    }
  }
}
