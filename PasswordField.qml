import QtQuick
import qs.Commons as Commons

// Campo de clave dibujado por el plugin, SIN TextInput: un campo nativo editable
// lee el portapapeles ajeno (reparo del marketplace a super-clipboard). Aquí no
// hay pegar, ni seleccionar, ni deshacer: solo escribir, borrar y enviar.
Rectangle {
  id: root

  property string placeholder: ""
  property bool busy: false
  // La clave vive solo aquí hasta Enter; al enviarla se vacía.
  property string value: ""

  signal submitted(string password)
  // Esc con el campo ya vacío: quien lo contiene recupera el foco (ajustes).
  signal escaped()

  implicitWidth: 320
  implicitHeight: 44
  radius: 8
  color: Qt.rgba(1, 1, 1, 0.08)
  border.width: activeFocus ? 2 : 1
  border.color: activeFocus ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.25)

  function clear() { value = "" }

  // Clic = foco (en la ventana de ajustes hay dos campos).
  MouseArea { anchors.fill: parent; onClicked: root.forceActiveFocus() }

  Keys.onPressed: function(event) {
    if (busy) { event.accepted = true; return }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (value.length > 0) {
        var pw = value
        value = ""
        root.submitted(pw)
      }
    } else if (event.key === Qt.Key_Escape) {
      if (value.length === 0) root.escaped()
      value = ""
    } else if (event.key === Qt.Key_Backspace) {
      value = value.slice(0, -1)
    } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32
               && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
      value += event.text
    }
    event.accepted = true
  }

  Text {
    anchors.fill: parent
    anchors.leftMargin: 14
    anchors.rightMargin: 14
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    font.family: Commons.Style.fontFamily
    font.pixelSize: root.value.length > 0 ? 20 : 15
    color: root.value.length > 0 ? Commons.Color.foreground : Commons.Color.muted
    elide: Text.ElideLeft
    text: root.value.length > 0 ? "•".repeat(root.value.length) : root.placeholder
  }
}
