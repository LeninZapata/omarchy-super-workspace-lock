import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Core.js" as Core

// Candado en la barra (cajón de la bandeja) y su panel: los workspaces con su
// estado y un interruptor «privado» por cada uno. El estado y los cambios van al
// servicio del plugin (Service.qml); aquí no se guarda nada.
Panel {
  id: root
  moduleName: "leninzapata.super-workspace-lock"
  // IPC propio del panel (open/close/toggle): sirve para probarlo sin ratón.
  ipcTarget: "leninzapata.super-workspace-lock.panel"

  readonly property var service: bar && bar.shell ? bar.shell.firstPartyServiceFor("leninzapata.super-workspace-lock") : null
  readonly property var lockState: service ? service.lockState : null
  readonly property var privateIds: lockState ? lockState.privateIds : []
  readonly property var lockedIds: lockState ? lockState.lockedIds : []
  readonly property var workspaceIds: {
    var existing = []
    var list = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].id > 0) existing.push(list[i].id)
    return Core.panelIds(existing, privateIds, 5)
  }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property int cursor: 0
  property bool cursorActive: false
  property string message: ""

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function isPrivate(id) { return privateIds.indexOf(id) !== -1 }
  function isLocked(id) { return lockedIds.indexOf(id) !== -1 }
  function stateKey(id) { return isLocked(id) ? "state.locked" : (isPrivate(id) ? "state.private" : "state.public") }

  function toggleRow(id) {
    if (!service) return
    if (isLocked(id)) { message = strings.t("panel.lockedHint"); return }
    message = ""
    service.requestPrivate(id, !isPrivate(id))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    message = ""
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font: candado cerrado si hay algo bloqueado, abierto si no.
    text: root.lockedIds.length > 0 ? "󰌾" : "󰿆"
    opacity: root.privateIds.length > 0 ? 1.0 : 0.55
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(520))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.cursor = Math.max(0, Math.min(root.workspaceIds.length - 1, root.cursor + dy))
      }
      onActivateRequested: if (root.cursorActive) root.toggleRow(root.workspaceIds[root.cursor])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: strings.t("plugin.name")
          meta: root.privateIds.length > 0
            ? strings.t("panel.summary").arg(Commons.I18n.formatNumber(root.privateIds.length)).arg(Commons.I18n.formatNumber(root.lockedIds.length))
            : strings.t("panel.none")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.lockedIds.length > 0 ? "󰌾" : "󰿆"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Repeater {
          model: root.workspaceIds

          Item {
            id: row
            required property int modelData
            required property int index
            readonly property bool locked: root.isLocked(modelData)
            width: column.width
            implicitHeight: Math.max(label.implicitHeight + stateText.implicitHeight, toggle.implicitHeight)

            Column {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              Text {
                id: label
                textFormat: Text.PlainText
                text: strings.t("panel.workspace").arg(row.modelData)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                id: stateText
                textFormat: Text.PlainText
                text: strings.t(root.stateKey(row.modelData))
                color: row.locked ? Commons.Color.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            ToggleSwitch {
              id: toggle
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.isPrivate(row.modelData)
              interactive: !row.locked
              opacity: row.locked ? 0.45 : 1.0
              hasCursor: root.cursorActive && root.cursor === row.index
              foreground: root.foreground
              onToggled: root.toggleRow(row.modelData)
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.message !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.message
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
