import QtQuick
import qs.Commons

// Monitor minimalista con el número del workspace. Gris si es público, color de
// acento si es privado, rojo con candado si está bloqueado.
Item {
  id: icon

  property int number: 1
  property string status: "public"        // public | private | locked
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color lockedColor: "#e06c75"    // rojo fijo: Color.urgent es gris en algunos temas
  property string fontFamily: Style.font.menuFamily
  property real size: 1.0

  readonly property color tone: status === "locked" ? lockedColor
    : status === "private" ? accent : Util.alpha(foreground, 0.5)

  implicitWidth: Math.round(34 * size)
  implicitHeight: Math.round(29 * size)

  Rectangle {
    id: screen
    width: Math.round(32 * size)
    height: Math.round(21 * size)
    x: Math.round((icon.width - width) / 2)
    radius: Math.round(3 * size)
    color: icon.status === "public" ? "transparent" : Util.alpha(icon.tone, 0.16)
    border.width: Math.max(1, Math.round(1.5 * size))
    border.color: icon.tone

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: icon.status === "locked" ? "󰌾" : String(icon.number)
      color: icon.tone
      font.family: icon.fontFamily
      font.pixelSize: Math.round(11 * icon.size)
      font.bold: true
    }
  }
  // pie y base del monitor
  Rectangle {
    width: Math.max(2, Math.round(2 * size)); height: Math.round(4 * size)
    x: Math.round((icon.width - width) / 2); y: screen.height
    color: icon.tone
  }
  Rectangle {
    width: Math.round(14 * size); height: Math.max(1, Math.round(1.5 * size)); radius: height / 2
    x: Math.round((icon.width - width) / 2); y: screen.height + Math.round(4 * size)
    color: icon.tone
  }
}
