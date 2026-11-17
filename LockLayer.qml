import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons

// Capa que tapa un workspace bloqueado (layer-shell Overlay, pantalla completa).
// Se queda con el teclado mientras se ve. El blur lo hace Hyprland (regla de capa
// + blur fuerte que activa Gate.js); hasta que Service.qml confirma que el blur
// está puesto, el fondo es opaco: nunca se ve un fotograma sin blur.
PanelWindow {
  id: layer

  property bool shown: false
  property int workspaceId: -1
  property var strings: null
  property string errorKey: ""
  property bool blurActive: false

  signal unlocked(int workspaceId)

  readonly property bool busy: auth.busy
  property int waitSeconds: 0

  signal errorReported(string key)
  onErrorKeyChanged: errorReported(errorKey)

  visible: shown
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "super-workspace-lock"
  WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onShownChanged: {
    errorKey = ""
    field.clear()
    if (shown) field.forceActiveFocus()
  }
  onWorkspaceIdChanged: { errorKey = ""; field.clear() }

  function t(key) { return strings ? strings.t(key) : key }

  function submit(password) {
    if (busy || waitSeconds > 0 || password.length === 0) return
    errorKey = ""
    auth.submit(password)
  }

  Auth {
    id: auth
    onSucceeded: { layer.errorKey = ""; layer.unlocked(layer.workspaceId) }
    onFailed: function(wait) {
      layer.waitSeconds = wait
      layer.errorKey = wait > 0 ? "auth.locked" : "auth.wrong"
      if (wait > 0) waitTimer.restart()
      field.clear()
      field.forceActiveFocus()
    }
  }

  // Cuenta atrás del faillock; al llegar a 0 se puede volver a intentar.
  Timer {
    id: waitTimer
    interval: 1000
    repeat: true
    onTriggered: {
      layer.waitSeconds = Math.max(0, layer.waitSeconds - 1)
      if (layer.waitSeconds === 0) { stop(); layer.errorKey = "" }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b,
                   layer.blurActive ? 0.35 : 1.0)

    // El ratón no llega a las ventanas de detrás.
    MouseArea { anchors.fill: parent; onClicked: field.forceActiveFocus() }

    Column {
      anchors.centerIn: parent
      spacing: 16

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        font.family: Commons.Style.fontFamily
        font.pixelSize: 22
        color: Commons.Color.foreground
        text: layer.strings ? layer.strings.t("lock.title").arg(layer.workspaceId) : ""
      }

      PasswordField {
        id: field
        anchors.horizontalCenter: parent.horizontalCenter
        busy: layer.busy
        placeholder: layer.t("lock.placeholder")
        onSubmitted: function(password) { layer.submit(password) }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        font.family: Commons.Style.fontFamily
        font.pixelSize: 14
        color: layer.busy ? Commons.Color.muted : Commons.Color.urgent
        text: layer.busy ? layer.t("auth.busy")
          : layer.errorKey === "auth.locked" ? layer.t("auth.locked").arg(layer.waitSeconds)
          : (layer.errorKey ? layer.t(layer.errorKey) : "")
      }
    }
  }
}
