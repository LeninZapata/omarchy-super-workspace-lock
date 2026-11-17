import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons as Commons
import "Core.js" as Core

// Servicio del plugin: vive mientras el shell corre (keepLoaded). Lleva el estado
// (Core.js), sigue el workspace activo de Hyprland y muestra la capa de bloqueo.
Item {
  id: root

  // Los inyecta el shell si existen.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "leninzapata.super-workspace-lock"
  readonly property int activeWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

  // Estado de Core.js; los privados aún no se guardan (llega en A3).
  property var lockState: Core.start([])
  readonly property bool activeLocked: Core.isLocked(lockState, activeWorkspaceId)

  onActiveWorkspaceIdChanged: {
    if (activeWorkspaceId > 0)
      lockState = Core.focusChanged(lockState, lockState.previousWorkspaceId, activeWorkspaceId)
  }
  Component.onCompleted: lockState = Core.focusChanged(lockState, -1, activeWorkspaceId)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  LockLayer {
    shown: root.activeLocked
    workspaceId: root.activeWorkspaceId
    strings: strings
    onUnlocked: function(id) { root.lockState = Core.unlockOk(root.lockState, id) }
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
        locked: root.lockState.lockedIds,
        language: Commons.I18n.language,
        name: strings.t("plugin.name")
      })
    }

    function setPrivate(id: string, value: string): string {
      var n = parseInt(id, 10)
      if (!(n > 0)) return "error: id"
      root.lockState = Core.setPrivate(root.lockState, n, value === "true")
      return "ok"
    }
  }
}
