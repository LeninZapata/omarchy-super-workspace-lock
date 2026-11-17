import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Capa que tapa un workspace bloqueado (layer-shell Overlay, pantalla completa).
// Se queda con el teclado mientras se ve. El blur lo hace Hyprland (regla de capa
// + blur fuerte que activa Gate.js); hasta que Service.qml confirma que el blur
// está puesto, el fondo es opaco: nunca se ve un fotograma sin blur.
PanelWindow {
  id: lockWin

  property bool shown: false
  property int workspaceId: -1
  property var strings: null
  property string errorKey: ""
  property bool blurActive: false
  // passwordMode efectivo "own": se prueba primero la clave propia del workspace.
  property bool useOwnPassword: false

  signal unlocked(int workspaceId)

  readonly property bool busy: auth.busy
  property int waitSeconds: 0

  signal errorReported(string key)
  onErrorKeyChanged: {
    errorReported(errorKey)
    // Clave incorrecta: la tarjeta tiembla un instante.
    if (errorKey === "auth.wrong") shake.restart()
  }

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
    auth.submit(password, workspaceId, useOwnPassword)
  }

  Auth {
    id: auth
    onSucceeded: { lockWin.errorKey = ""; lockWin.unlocked(lockWin.workspaceId) }
    onFailed: function(wait) {
      lockWin.waitSeconds = wait
      lockWin.errorKey = wait > 0 ? "auth.locked" : "auth.wrong"
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
      lockWin.waitSeconds = Math.max(0, lockWin.waitSeconds - 1)
      if (lockWin.waitSeconds === 0) { stop(); lockWin.errorKey = "" }
    }
  }

  // ------------------------------------------------------------------ vista
  readonly property color fg: Commons.Color.menu.text
  readonly property color mutedFg: Util.alpha(fg, 0.55)
  readonly property color lockedColor: "#e06c75"   // rojo fijo: Color.urgent es gris en algunos temas
  readonly property string fontFamily: Style.font.menuFamily

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b,
                   lockWin.blurActive ? 0.35 : 1.0)

    // El ratón no llega a las ventanas de detrás.
    MouseArea { anchors.fill: parent; onClicked: field.forceActiveFocus() }

    Rectangle {
      id: card
      width: Style.space(420)
      height: cardCol.implicitHeight + 2 * Style.space(28)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Util.alpha(Commons.Color.menu.background, 0.92)
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(lockWin.fg, 0.14)

      transform: Translate { id: shakeX; x: 0 }
      SequentialAnimation {
        id: shake
        NumberAnimation { target: shakeX; property: "x"; to: -10; duration: 45 }
        NumberAnimation { target: shakeX; property: "x"; to: 10; duration: 70 }
        NumberAnimation { target: shakeX; property: "x"; to: -6; duration: 60 }
        NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 50 }
      }

      Column {
        id: cardCol
        anchors.centerIn: parent
        width: parent.width - 2 * Style.space(28)
        spacing: Style.space(12)

        WorkspaceIcon {
          anchors.horizontalCenter: parent.horizontalCenter
          size: 2.4
          number: lockWin.workspaceId
          status: "locked"
          foreground: lockWin.fg
          lockedColor: lockWin.lockedColor
          fontFamily: lockWin.fontFamily
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: lockWin.strings ? lockWin.strings.t("lock.title").arg(lockWin.workspaceId) : ""
          color: lockWin.fg
          font.family: lockWin.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: lockWin.t(lockWin.useOwnPassword ? "lock.hintOwn" : "lock.hintSystem")
          color: lockWin.mutedFg
          font.family: lockWin.fontFamily
          font.pixelSize: Style.font.caption
          bottomPadding: Style.space(4)
        }

        PasswordField {
          id: field
          width: parent.width
          implicitHeight: Style.space(44)
          busy: lockWin.busy
          placeholder: lockWin.t("lock.placeholder")
          onSubmitted: function(password) { lockWin.submit(password) }
        }

        // estado: altura fija para que la tarjeta no salte al aparecer un error
        Text {
          width: parent.width
          height: Style.space(18)
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          font.family: lockWin.fontFamily
          font.pixelSize: Style.font.caption
          color: lockWin.busy ? lockWin.mutedFg : lockWin.lockedColor
          text: lockWin.busy ? lockWin.t("auth.busy")
            : lockWin.errorKey === "auth.locked" ? lockWin.t("auth.locked").arg(lockWin.waitSeconds)
            : (lockWin.errorKey ? lockWin.t(lockWin.errorKey) : "")
          elide: Text.ElideRight
        }

        // pie de teclas
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)
          Repeater {
            model: [{ keys: "enter", hint: "hint.unlock" }, { keys: "esc", hint: "hint.clear" }, { keys: "super+1…0", hint: "hint.leave" }]
            delegate: Row {
              required property var modelData
              spacing: Style.space(4)
              Rectangle {
                radius: Style.space(3)
                color: Util.alpha(lockWin.fg, 0.07)
                width: keyText.implicitWidth + Style.space(10)
                height: Style.space(18)
                anchors.verticalCenter: parent.verticalCenter
                Text { id: keyText; anchors.centerIn: parent; textFormat: Text.PlainText; text: modelData.keys; color: lockWin.mutedFg; font.family: lockWin.fontFamily; font.pixelSize: Style.font.caption }
              }
              Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: lockWin.t(modelData.hint); color: lockWin.mutedFg; font.family: lockWin.fontFamily; font.pixelSize: Style.font.caption }
            }
          }
        }
      }
    }
  }
}
