import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons as Commons
import Quickshell.Io
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

  // ------------------------------------------------------------ atajo global
  // lockShortcut se registra en caliente (hyprctl eval): al arrancar, al cambiar el
  // ajuste y tras cada recarga de Hyprland. El anterior se suelta siempre.
  property var appliedShortcuts: []

  function applyShortcut() {
    var s = Gate.shortcutLua(settings.lockShortcut, appliedShortcuts)
    appliedShortcuts = s.applied
    if (s.lua.length > 0) Quickshell.execDetached(["hyprctl", "eval", s.lua])
  }

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
    lockState = next
    activeLocked = Core.isLocked(next, activeWorkspaceId)
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
  }

  Process {
    id: recordsProc
    stdout: StdioCollector {
      onStreamFinished: { root.records = Gate.parseRecords(text); root.recordsReady = true }
    }
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
    }
  }
  Timer { id: reloadTimer; interval: 300; onTriggered: root.refreshHyprland() }

  Component.onDestruction: {
    if (gateOn) Quickshell.execDetached(["hyprctl", "eval", Gate.exitLua(prevBlur)])
    var off = Gate.shortcutLua("", appliedShortcuts)
    if (off.lua.length > 0) Quickshell.execDetached(["hyprctl", "eval", off.lua])
  }

  Component.onCompleted: {
    syncFocus()
    pidProc.running = true
    refreshHyprland()
    initProc.running = true
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  LockLayer {
    shown: root.activeLocked
    workspaceId: root.activeWorkspaceId
    strings: strings
    blurActive: root.blurActive
    useOwnPassword: Settings.effective(root.settings, root.activeWorkspaceId).passwordMode === "own"
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
        shellPid: root.shellPid,
        sessionWatch: root.sessionWatch,
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
