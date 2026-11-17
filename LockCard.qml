import QtQuick
import qs.Commons
import qs.Commons as Commons

// La tarjeta de bloqueo: monitor bloqueado, título, qué clave pide, campo, estado y
// pie de teclas. La usan la capa (interactiva) y la tapa de cada workspace bloqueado
// (solo dibujo), en el mismo sitio, para que el paso de una a otra no se note.
Rectangle {
  id: card

  property int workspaceId: -1
  property var strings: null
  property bool useOwnPassword: false
  property bool interactive: true
  property bool busy: false
  property string statusText: ""
  readonly property alias field: field

  signal submitted(string password)

  readonly property color fg: Commons.Color.menu.text
  readonly property color mutedFg: Util.alpha(fg, 0.55)
  readonly property color lockedColor: "#e06c75"   // rojo fijo: Color.urgent es gris en algunos temas
  readonly property string fontFamily: Style.font.menuFamily

  function t(key) { return strings ? strings.t(key) : key }
  function shake() { shakeAnim.restart() }

  width: Style.space(420)
  height: cardCol.implicitHeight + 2 * Style.space(28)
  radius: Style.cornerRadius
  color: Util.alpha(Commons.Color.menu.background, 0.92)
  border.width: Style.normalBorderWidth
  border.color: Util.alpha(fg, 0.14)

  transform: Translate { id: shakeX; x: 0 }
  SequentialAnimation {
    id: shakeAnim
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
      number: card.workspaceId
      status: "locked"
      foreground: card.fg
      lockedColor: card.lockedColor
      fontFamily: card.fontFamily
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: card.strings ? card.strings.t("lock.title").arg(card.workspaceId) : ""
      color: card.fg
      font.family: card.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: card.t(card.useOwnPassword ? "lock.hintOwn" : "lock.hintSystem")
      color: card.mutedFg
      font.family: card.fontFamily
      font.pixelSize: Style.font.caption
      bottomPadding: Style.space(4)
    }

    PasswordField {
      id: field
      width: parent.width
      implicitHeight: Style.space(44)
      enabled: card.interactive
      busy: card.busy
      placeholder: card.t("lock.placeholder")
      onSubmitted: function(password) { card.submitted(password) }
    }

    // estado: altura fija para que la tarjeta no salte al aparecer un error
    Text {
      width: parent.width
      height: Style.space(18)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      font.family: card.fontFamily
      font.pixelSize: Style.font.caption
      color: card.busy ? card.mutedFg : card.lockedColor
      text: card.statusText
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
            color: Util.alpha(card.fg, 0.07)
            width: keyText.implicitWidth + Style.space(10)
            height: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            Text { id: keyText; anchors.centerIn: parent; textFormat: Text.PlainText; text: modelData.keys; color: card.mutedFg; font.family: card.fontFamily; font.pixelSize: Style.font.caption }
          }
          Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: card.t(modelData.hint); color: card.mutedFg; font.family: card.fontFamily; font.pixelSize: Style.font.caption }
        }
      }
    }
  }
}
