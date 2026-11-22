import QtQuick
import qs.Commons

// Tarjetas hijas de un interruptor (p. ej. «Bloquear por inactividad»): van sangradas a la
// derecha y dentro de un marco, para que se lea que dependen de la tarjeta de arriba. La
// sangría es la misma que usan las opciones dependientes en super-clipboard.
Item {
  id: group

  property color lineColor: "transparent"
  property int indent: Style.space(28)
  readonly property int pad: Style.space(8)
  default property alias cards: col.data

  implicitHeight: frame.height

  Rectangle {
    id: frame
    x: group.indent
    width: group.width - group.indent
    height: col.implicitHeight + 2 * group.pad
    radius: Style.cornerRadius
    color: "transparent"
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: group.lineColor

    Column {
      id: col
      x: group.pad
      y: group.pad
      width: frame.width - 2 * group.pad
      spacing: Style.space(8)
    }
  }
}
