import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import Quickshell.Hyprland
import qs.Ui
import "Settings.js" as Settings
import "Core.js" as Core

// Ventana flotante de ajustes (Rebanada B). No guarda nada por sí misma: cada
// cambio va a `service.saveSettings`, que normaliza y escribe settings.json.
// Ningún TextInput: los números se eligen con −/+ y el atajo se captura pulsándolo.
FloatingWindow {
  id: win

  property var service: null
  property var strings: null
  readonly property var settings: service ? service.settings : Settings.defaults()
  readonly property var defs: settings.defaults
  property bool capturing: false
  property int selectedWorkspace: 1
  readonly property var lockState: service ? service.lockState : null
  readonly property var workspaceIds: {
    var existing = []
    var list = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].id > 0) existing.push(list[i].id)
    return Core.panelIds(existing, lockState ? lockState.privateIds : [], 5)
  }
  readonly property var selectedEntry: settings.workspaces[String(selectedWorkspace)] || ({})
  readonly property var selectedEffective: Settings.effective(settings, selectedWorkspace)

  function modeLabel(mode) { return mode === "delay" ? t("settings.delay") : t("settings.immediate") }
  function passwordLabel(mode) { return mode === "own" ? t("settings.passwordOwn") : t("settings.passwordSystem") }

  // Resumen de la config efectiva de un workspace para la lista.
  function summary(id) {
    var e = Settings.effective(settings, id)
    var parts = [e.private ? t("settings.private") : t("settings.public")]
    if (e.private) {
      parts.push(e.lockMode === "delay" ? t("settings.delay") + " · " + formatDelay(e.delaySeconds) : t("settings.immediate"))
      parts.push(passwordLabel(e.passwordMode))
    }
    return parts.join(" · ")
  }

  // value null = «heredar»: se borra el campo y manda defaults.
  function saveWorkspace(field, value) {
    service.saveSettings(Settings.withWorkspaceField(settings, selectedWorkspace, field, value))
  }

  // Pasos del retardo (segundos), dentro de 5…3600.
  readonly property var delaySteps: [5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]

  title: strings ? strings.t("settings.title") : "Super Workspace Lock"
  color: Commons.Color.background
  implicitWidth: 560
  implicitHeight: 760

  function t(key) { return strings ? strings.t(key) : key }

  function formatDelay(sec) {
    return sec >= 60 && sec % 60 === 0 ? t("settings.minutes").arg(sec / 60) : t("settings.seconds").arg(sec)
  }

  function stepDelay(current, dir) {
    var i = delaySteps.indexOf(current)
    if (i === -1) { i = 0; while (i < delaySteps.length - 1 && delaySteps[i] < current) i++ }
    i = Math.max(0, Math.min(delaySteps.length - 1, i + dir))
    return delaySteps[i]
  }

  function saveDefault(field, value) {
    var next = Settings.normalize(settings)
    next.defaults[field] = value
    service.saveSettings(next)
  }

  function saveTop(field, value) {
    var next = Settings.normalize(settings)
    next[field] = value
    service.saveSettings(next)
  }

  // Atajo pulsado → "SUPER + CTRL + L". Solo teclas con nombre seguro (van a Lua).
  function chordFromEvent(event) {
    var names = { }
    names[Qt.Key_Tab] = "TAB"; names[Qt.Key_Space] = "SPACE"; names[Qt.Key_Return] = "RETURN"
    names[Qt.Key_Left] = "LEFT"; names[Qt.Key_Right] = "RIGHT"; names[Qt.Key_Up] = "UP"; names[Qt.Key_Down] = "DOWN"
    var key = names[event.key] || ""
    if (!key && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) key = "F" + (event.key - Qt.Key_F1 + 1)
    if (!key && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) key = String.fromCharCode(event.key)
    if (!key && event.key >= Qt.Key_0 && event.key <= Qt.Key_9) key = String.fromCharCode(event.key)
    if (!key) return ""
    var mods = []
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    if (mods.length === 0) return ""
    return mods.concat([key]).join(" + ")
  }

  onVisibleChanged: { capturing = false; if (visible) Qt.callLater(function() { keys.forceActiveFocus() }) }

  Item {
    id: keys
    anchors.fill: parent
    focus: true
    Keys.onPressed: function(event) {
      if (win.capturing) {
        if (event.key === Qt.Key_Escape) win.capturing = false
        else {
          var chord = win.chordFromEvent(event)
          if (chord) { win.capturing = false; win.saveTop("lockShortcut", chord) }
        }
        event.accepted = true
      } else if (event.key === Qt.Key_Escape) {
        win.service.closeSettings()
        event.accepted = true
      }
    }

    Flickable {
      anchors.fill: parent
      anchors.margins: 24
      contentHeight: column.implicitHeight
      clip: true

      Column {
        id: column
        width: parent.width
        spacing: 18

        Text {
          textFormat: Text.PlainText
          text: win.t("settings.general")
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        // --- modo de bloqueo
        Column {
          width: parent.width
          spacing: 8
          Text { textFormat: Text.PlainText; text: win.t("settings.lockMode"); color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          ButtonGroup {
            objectName: "lockModeGroup"
            options: [{ value: "immediate", label: win.t("settings.immediate") }, { value: "delay", label: win.t("settings.delay") }]
            value: win.defs.lockMode
            onChanged: function(v) { win.saveDefault("lockMode", v) }
          }
        }

        // --- retardo
        Row {
          spacing: 10
          visible: win.defs.lockMode === "delay"
          Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: win.t("settings.delaySeconds"); color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; width: 140 }
          Button { objectName: "delayMinus"; text: "−"; bordered: true; onClicked: win.saveDefault("delaySeconds", win.stepDelay(win.defs.delaySeconds, -1)) }
          Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: win.formatDelay(win.defs.delaySeconds); color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: 80; horizontalAlignment: Text.AlignHCenter }
          Button { objectName: "delayPlus"; text: "+"; bordered: true; onClicked: win.saveDefault("delaySeconds", win.stepDelay(win.defs.delaySeconds, 1)) }
        }

        // --- tipo de clave
        Column {
          width: parent.width
          spacing: 8
          Text { textFormat: Text.PlainText; text: win.t("settings.passwordMode"); color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          ButtonGroup {
            options: [{ value: "system", label: win.t("settings.passwordSystem") }, { value: "own", label: win.t("settings.passwordOwn") }]
            value: win.defs.passwordMode
            onChanged: function(v) { win.saveDefault("passwordMode", v) }
          }
        }

        // --- atajo de bloqueo (se captura pulsándolo)
        Row {
          spacing: 10
          Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: win.t("settings.shortcut"); color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; width: 180 }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: win.capturing ? win.t("settings.shortcutPress") : (win.settings.lockShortcut || win.t("settings.shortcutNone"))
            color: win.capturing ? Commons.Color.accent : Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Button {
            visible: !win.capturing
            text: win.t("settings.shortcutChange")
            bordered: true
            onClicked: { win.capturing = true; keys.forceActiveFocus() }
          }
        }

        PanelSeparator { foreground: Commons.Color.foreground }

        Text {
          textFormat: Text.PlainText
          text: win.t("settings.perWorkspace")
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        // --- lista: cada workspace con su config efectiva; clic = elegirlo
        Column {
          width: parent.width
          spacing: 2
          Repeater {
            model: win.workspaceIds
            Rectangle {
              id: wsRow
              required property int modelData
              width: column.width
              height: 34
              radius: 4
              color: win.selectedWorkspace === modelData ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
              Text {
                anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: win.strings ? win.strings.t("panel.workspace").arg(wsRow.modelData) : String(wsRow.modelData)
                color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body
              }
              Text {
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: win.summary(wsRow.modelData)
                color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
              }
              MouseArea { anchors.fill: parent; onClicked: win.selectedWorkspace = wsRow.modelData }
            }
          }
        }

        // --- formulario del workspace elegido («Por defecto» = heredar)
        Column {
          width: parent.width
          spacing: 10

          Row {
            spacing: 10
            Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: win.strings ? win.strings.t("panel.workspace").arg(win.selectedWorkspace) : ""; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; width: 140 }
            ButtonGroup {
              options: [{ value: "public", label: win.t("settings.public") }, { value: "private", label: win.t("settings.private") }]
              value: win.selectedEffective.private ? "private" : "public"
              onChanged: function(v) { win.service.requestPrivate(win.selectedWorkspace, v === "private") }
            }
          }
          Text {
            visible: win.lockState && win.lockState.lockedIds.indexOf(win.selectedWorkspace) !== -1
            textFormat: Text.PlainText; text: win.t("settings.lockedNote")
            color: Commons.Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
          }

          Row {
            spacing: 10
            Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: win.t("settings.lockMode"); color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; width: 140 }
            ButtonGroup {
              options: [{ value: "inherit", label: win.t("settings.inheritValue").arg(win.modeLabel(win.defs.lockMode)) },
                        { value: "immediate", label: win.t("settings.immediate") }, { value: "delay", label: win.t("settings.delay") }]
              value: win.selectedEntry.lockMode || "inherit"
              onChanged: function(v) { win.saveWorkspace("lockMode", v === "inherit" ? null : v) }
            }
          }

          Row {
            spacing: 10
            visible: win.selectedEffective.lockMode === "delay"
            Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: win.t("settings.delaySeconds"); color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; width: 140 }
            Button { text: "−"; bordered: true; onClicked: win.saveWorkspace("delaySeconds", win.stepDelay(win.selectedEffective.delaySeconds, -1)) }
            Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: win.formatDelay(win.selectedEffective.delaySeconds); color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; width: 80; horizontalAlignment: Text.AlignHCenter }
            Button { text: "+"; bordered: true; onClicked: win.saveWorkspace("delaySeconds", win.stepDelay(win.selectedEffective.delaySeconds, 1)) }
            Button { visible: win.selectedEntry.delaySeconds !== undefined; text: win.t("settings.inherit"); bordered: true; onClicked: win.saveWorkspace("delaySeconds", null) }
          }

          Row {
            spacing: 10
            Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: win.t("settings.passwordMode"); color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; width: 140 }
            ButtonGroup {
              options: [{ value: "inherit", label: win.t("settings.inheritValue").arg(win.passwordLabel(win.defs.passwordMode)) },
                        { value: "system", label: win.t("settings.passwordSystem") }, { value: "own", label: win.t("settings.passwordOwn") }]
              value: win.selectedEntry.passwordMode || "inherit"
              onChanged: function(v) { win.saveWorkspace("passwordMode", v === "inherit" ? null : v) }
            }
          }
        }

        PanelSeparator { foreground: Commons.Color.foreground }

        Button {
          text: win.t("settings.close")
          bordered: true
          onClicked: win.service.closeSettings()
        }
      }
    }
  }
}
