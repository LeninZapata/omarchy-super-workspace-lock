import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
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

  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  property string pendingPassword: ""
  property bool busy: false

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
    if (busy || password.length === 0) return
    pendingPassword = password
    busy = true
    errorKey = ""
    if (!pam.start()) fail()
    else Qt.callLater(respond)
  }

  function respond() {
    if (!busy || !pam.active || !pam.responseRequired) return
    pam.respond(pendingPassword)
    pendingPassword = ""
  }

  function fail() {
    busy = false
    pendingPassword = ""
    errorKey = "auth.wrong"
    field.clear()
    field.forceActiveFocus()
  }

  PamContext {
    id: pam
    config: "omarchy-lock-password"
    user: layer.userName

    onResponseRequiredChanged: layer.respond()
    onPamMessage: layer.respond()
    onCompleted: function(result) {
      layer.pendingPassword = ""
      if (result === PamResult.Success) {
        layer.busy = false
        layer.unlocked(layer.workspaceId)
      } else layer.fail()
    }
    onError: function(error) { layer.fail() }
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
        text: layer.busy ? layer.t("auth.busy") : (layer.errorKey ? layer.t(layer.errorKey) : "")
      }
    }
  }
}
