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
    if (errorKey === "auth.wrong") card.shake()
  }

  visible: shown
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "super-workspace-lock"
  WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onShownChanged: {
    cardRevealed = false
    if (shown) revealTimer.restart()
    errorKey = ""
    field.clear()
    if (shown) field.forceActiveFocus()
  }
  onWorkspaceIdChanged: { errorKey = ""; field.clear(); cardRevealed = false; if (shown) revealTimer.restart() }

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
  // Con la tapa del workspace ya puesta (CoverWindow.qml: fondo con blur y la misma
  // tarjeta), la capa no pinta fondo: solo pone la tarjeta interactiva encima, en el
  // mismo sitio. Sin tapa, el fondo de siempre (opaco hasta que Hyprland confirma el blur).
  property bool coverReady: false
  // Con tapa: la tarjeta de la capa aparece al acabar la animación de workspace, alineada
  // encima de la de la tapa (antes se veían dos tarjetas mientras el workspace entraba).
  property int revealDelay: 360
  property bool cardRevealed: false
  Timer { id: revealTimer; interval: lockWin.revealDelay; onTriggered: lockWin.cardRevealed = true }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b,
                   lockWin.coverReady ? 0.0 : (lockWin.blurActive ? 0.35 : 1.0))

    // El ratón no llega a las ventanas de detrás.
    MouseArea { anchors.fill: parent; onClicked: field.forceActiveFocus() }

    LockCard {
      id: card
      anchors.centerIn: parent
      opacity: !lockWin.coverReady || lockWin.cardRevealed ? 1 : 0
      workspaceId: lockWin.workspaceId
      strings: lockWin.strings
      useOwnPassword: lockWin.useOwnPassword
      busy: lockWin.busy
      statusText: lockWin.busy ? lockWin.t("auth.busy")
        : lockWin.errorKey === "auth.locked" ? lockWin.t("auth.locked").arg(lockWin.waitSeconds)
        : (lockWin.errorKey ? lockWin.t(lockWin.errorKey) : "")
      onSubmitted: function(password) { lockWin.submit(password) }
    }
  }

  readonly property var field: card.field
}
