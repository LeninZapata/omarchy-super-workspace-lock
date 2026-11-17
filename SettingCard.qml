import QtQuick
import qs.Commons
import qs.Ui

// Una fila de ajuste con la piel de super-clipboard: tarjeta con borde, título y
// descripción a la izquierda y los controles a la derecha (o debajo, `below`).
BorderSurface {
  id: card

  property string title: ""
  property string description: ""
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  property bool below: false
  default property alias controls: controlsBox.data

  readonly property int pad: Style.spacing.rowPaddingX
  readonly property bool hot: hover.hovered

  implicitHeight: below
    ? textCol.implicitHeight + Style.space(10) + controlsBox.implicitHeight + Style.spacing.huge
    : Math.max(Style.space(58), Math.max(textCol.implicitHeight, controlsBox.implicitHeight) + Style.spacing.huge)
  radius: Style.cornerRadius
  color: Style.controlFill(false, hot, foreground, accent)
  borderSpec: Border.controlSpec(hot ? "hover-cursor" : "normal", foreground, accent)

  HoverHandler { id: hover }

  Column {
    id: textCol
    x: card.pad
    y: card.below ? Style.spacing.huge / 2 : (card.height - height) / 2
    width: card.below ? card.width - 2 * card.pad : Math.max(0, card.width - 3 * card.pad - controlsBox.width)
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: card.title
      color: card.foreground
      font.family: card.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: card.description !== ""
      textFormat: Text.PlainText
      text: card.description
      color: Qt.darker(card.foreground, 1.5)
      font.family: card.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Row {
    id: controlsBox
    x: card.below ? card.pad : card.width - card.pad - width
    y: card.below ? textCol.y + textCol.height + Style.space(10) : (card.height - height) / 2
    spacing: Style.space(6)
  }
}
