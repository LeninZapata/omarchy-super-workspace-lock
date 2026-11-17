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

  function applySettingsText(raw) {
    var parsed = null
    try { parsed = JSON.parse(raw && raw.trim().length > 0 ? raw : "{}") } catch (e) { parsed = null }
    // Archivo roto: valores por defecto y el archivo NO se pisa hasta el próximo cambio.
    settingsBroken = parsed === null
    settings = Settings.normalize(parsed)
    var ids = Settings.privateIds(settings)
    if (!settingsLoaded) {
      settingsLoaded = true
      var started = Core.start(ids)
      setLockState(Core.focusChanged(started, -1, activeWorkspaceId > 0 ? activeWorkspaceId : -1))
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
    var next = Core.focusChanged(lockState, activeWorkspaceId, id)
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
    } else if (!activeLocked && gateOn) {
      gateOn = false
      blurActive = false
      Quickshell.execDetached(["hyprctl", "eval", Gate.exitLua(prevBlur)])
    }
  }

  function refreshHyprland() {
    blurActive = false
    gateOn = false
    recordsReady = false
    prevBlur = null
    Quickshell.execDetached(["hyprctl", "eval", Gate.layerRuleLua()])
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

  Component.onDestruction: if (gateOn) Quickshell.execDetached(["hyprctl", "eval", Gate.exitLua(prevBlur)])

  Component.onCompleted: {
    syncFocus()
    refreshHyprland()
    initProc.running = true
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  LockLayer {
    shown: root.activeLocked
    workspaceId: root.activeWorkspaceId
    strings: strings
    blurActive: root.blurActive
    onUnlocked: function(id) { root.setLockState(Core.unlockOk(root.lockState, id)) }
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
        gateOn: root.gateOn,
        blurActive: root.blurActive,
        allowedMissing: root.missingAllowed,
        language: Commons.I18n.language,
        name: strings.t("plugin.name")
      })
    }

    function setPrivate(id: string, value: string): string {
      var n = parseInt(id, 10)
      if (!(n > 0)) return "error: id"
      var on = value === "true"
      if (!root.settingsLoaded) return "error: settings not loaded"
      if (!Core.canSetPrivate(root.lockState, n, on)) return "error: locked"
      root.savePrivate(n, on)
      return "ok"
    }
  }
}
