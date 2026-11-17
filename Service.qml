import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons as Commons

// Servicio del plugin: vive mientras el shell corre (keepLoaded). Por ahora solo
// expone el estado por IPC; el núcleo (Core.js) y la capa llegan en los cortes A1+.
Item {
  id: root

  // Los inyecta el shell si existen.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "leninzapata.super-workspace-lock"
  readonly property int activeWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // IPC: omarchy-shell leninzapata.super-workspace-lock state
  // Es también la puerta de las autopruebas (PLAN.md §1 Accesos).
  Commons.ShellIpc {
    target: root.pluginId

    function state(): string {
      return JSON.stringify({
        version: root.manifest && root.manifest.version ? root.manifest.version : "",
        activeWorkspaceId: root.activeWorkspaceId,
        private: [],
        locked: [],
        language: Commons.I18n.language,
        name: strings.t("plugin.name")
      })
    }
  }
}
