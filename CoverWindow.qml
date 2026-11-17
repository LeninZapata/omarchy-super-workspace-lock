import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons as Commons

// La tapa de un workspace bloqueado: una ventana propia DENTRO de ese workspace, a
// pantalla completa, con el fondo de pantalla desenfocado y la tarjeta de bloqueo.
// Como pertenece al workspace, entra con él en la animación de Hyprland: llega ya
// bloqueado. Nace en su workspace con una regla «silent» (Gate.coverRuleLua) y se
// pone a pantalla completa por su dirección (Gate.coverFullscreenLua).
FloatingWindow {
  id: cover

  property int workspaceId: -1
  property var strings: null
  property bool useOwnPassword: false
  readonly property string backgroundPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"

  title: "Super Workspace Lock · cover " + workspaceId
  color: Commons.Color.background
  implicitWidth: 800
  implicitHeight: 600

  Image {
    id: wallpaper
    anchors.fill: parent
    source: "file://" + cover.backgroundPath
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    visible: false
  }
  MultiEffect {
    anchors.fill: parent
    source: wallpaper
    visible: wallpaper.status === Image.Ready
    blurEnabled: true
    blurMax: 64
    blur: 1.0
  }
  // el mismo oscurecido que la capa con blur
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b,
                   wallpaper.status === Image.Ready ? 0.35 : 1.0)
  }

  LockCard {
    anchors.centerIn: parent
    workspaceId: cover.workspaceId
    strings: cover.strings
    useOwnPassword: cover.useOwnPassword
    interactive: false
  }
}
