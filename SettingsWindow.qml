import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Settings.js" as Settings
import "Core.js" as Core

// Ventana flotante de ajustes, con la piel de super-clipboard: dos pestañas
// (Workspaces · General), tarjetas de ajuste y pie de teclas. No guarda nada por
// sí misma: cada cambio va a `service.saveSettings` (normaliza y escribe el JSON).
// Ningún TextInput: el retardo va con −/+ y los atajos se capturan pulsándolos.
FloatingWindow {
  id: win

  property var service: null
  property var strings: null

  // ------------------------------------------------------------------ tema
  readonly property color bg: Color.menu.background
  readonly property color fg: Color.menu.text
  readonly property color accent: Color.accent
  readonly property color mutedFg: Util.alpha(fg, 0.55)
  readonly property color lineColor: Util.alpha(fg, 0.14)
  readonly property color chipBg: Util.alpha(fg, 0.07)
  readonly property color lockedColor: "#e06c75"
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int margin: Style.spacing.panelPadding
  readonly property real tabUnderline: Math.max(2, Style.space(3))

  // ------------------------------------------------------------------ estado
  readonly property var settings: service ? service.settings : Settings.defaults()
  readonly property var defs: settings.defaults
  readonly property var lockState: service ? service.lockState : null
  property string tab: "workspaces"
  property bool capturing: false
  property string captureTarget: "lockShortcut"   // o "allowed": añadir a la lista
  property int selectedWorkspace: 1
  property string ownMessage: ""

  // ---- teclado en dos niveles: "list" (monitores / pestañas) y "options" (tarjetas)
  property string focusArea: "list"
  property int optCursor: 0
  readonly property var rows: tab === "workspaces"
    ? ["private", "lockMode", "delay", "idle", "idleTime", "idleAudio", "password", "own"].filter(function(r) {
        return (r !== "delay" || selectedEffective.lockMode === "delay") && (r !== "own" || selectedEffective.passwordMode === "own")
          && ((r !== "idleTime" && r !== "idleAudio") || selectedEffective.idleLock === "on")
      })
    : ["lockMode", "delay", "idle", "idleTime", "idleAudio", "password", "shortcut", "allowed"].filter(function(r) {
        return (r !== "delay" || defs.lockMode === "delay") && ((r !== "idleTime" && r !== "idleAudio") || defs.idleLock === "on")
      })
  readonly property string currentRow: focusArea === "options" ? (rows[Math.min(optCursor, rows.length - 1)] || "") : ""

  function cycle(list, current, dir) {
    var i = list.indexOf(current)
    return list[Math.max(0, Math.min(list.length - 1, (i === -1 ? 0 : i) + dir))]
  }

  // ←/→ sobre la tarjeta actual: cambia su valor con las mismas funciones que el ratón.
  function changeRow(dir) {
    var r = currentRow
    if (tab === "workspaces") {
      if (r === "private" && !selectedLocked) service.requestPrivate(selectedWorkspace, dir > 0)
      else if (r === "lockMode") {
        var m = cycle(["inherit", "immediate", "delay"], selectedEntry.lockMode || "inherit", dir)
        saveWorkspace("lockMode", m === "inherit" ? null : m)
      } else if (r === "delay") saveWorkspace("delaySeconds", stepDelay(selectedEffective.delaySeconds, dir))
      else if (r === "idle") {
        var il = cycle(["inherit", "off", "on"], selectedEntry.idleLock || "inherit", dir)
        saveWorkspace("idleLock", il === "inherit" ? null : il)
      } else if (r === "idleTime") saveWorkspace("idleSeconds", stepIdle(selectedEffective.idleSeconds, dir))
      else if (r === "idleAudio") {
        var ia = cycle(["inherit", "lock", "wait"], selectedEntry.idleAudio || "inherit", dir)
        saveWorkspace("idleAudio", ia === "inherit" ? null : ia)
      } else if (r === "password") {
        var p = cycle(["inherit", "system", "own"], selectedEntry.passwordMode || "inherit", dir)
        saveWorkspace("passwordMode", p === "inherit" ? null : p)
      }
    } else {
      if (r === "lockMode") saveDefault("lockMode", cycle(["immediate", "delay"], defs.lockMode, dir))
      else if (r === "delay") saveDefault("delaySeconds", stepDelay(defs.delaySeconds, dir))
      else if (r === "idle") saveDefault("idleLock", cycle(["off", "on"], defs.idleLock, dir))
      else if (r === "idleTime") saveDefault("idleSeconds", stepIdle(defs.idleSeconds, dir))
      else if (r === "idleAudio") saveDefault("idleAudio", cycle(["lock", "wait"], defs.idleAudio, dir))
      else if (r === "password") saveDefault("passwordMode", cycle(["system", "own"], defs.passwordMode, dir))
    }
  }

  // Enter sobre la tarjeta actual: lo que se edita (clave propia, capturar un atajo).
  function activateRow() {
    var r = currentRow
    if (r === "own") ownNew.forceActiveFocus()
    else if (r === "shortcut") startCapture("lockShortcut")
    else if (r === "allowed") startCapture("allowed")
  }

  function enterOptions() { focusArea = "options"; optCursor = 0 }
  function backToList() { focusArea = "list"; keys.forceActiveFocus() }

  readonly property var workspaceIds: {
    var existing = []
    var list = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].id > 0) existing.push(list[i].id)
    return Core.panelIds(existing, lockState ? lockState.privateIds : [], 5)
  }
  readonly property var selectedEntry: settings.workspaces[String(selectedWorkspace)] || ({})
  readonly property var selectedEffective: Settings.effective(settings, selectedWorkspace)
  readonly property bool selectedLocked: !!lockState && lockState.lockedIds.indexOf(selectedWorkspace) !== -1
  readonly property bool selectedHasOwn: service ? service.ownPasswordIds.indexOf(selectedWorkspace) !== -1 : false

  title: strings ? strings.t("settings.title") : "Super Workspace Lock"
  color: bg
  implicitWidth: 980
  implicitHeight: 660

  function t(key) { return strings ? strings.t(key) : key }

  function statusOf(id) {
    if (lockState && lockState.lockedIds.indexOf(id) !== -1) return "locked"
    return Settings.effective(settings, id).private ? "private" : "public"
  }

  function formatDelay(sec) {
    return sec >= 60 && sec % 60 === 0 ? t("settings.minutes").arg(sec / 60) : t("settings.seconds").arg(sec)
  }

  // Pasos del retardo (segundos), dentro de 5…3600.
  readonly property var delaySteps: [5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
  function stepDelay(current, dir) {
    var i = delaySteps.indexOf(current)
    if (i === -1) { i = 0; while (i < delaySteps.length - 1 && delaySteps[i] < current) i++ }
    return delaySteps[Math.max(0, Math.min(delaySteps.length - 1, i + dir))]
  }

  // Pasos del tiempo sin actividad (segundos), dentro de 60…7200.
  readonly property var idleSteps: [60, 120, 300, 600, 900, 1200, 1800, 2700, 3600, 5400, 7200]
  function stepIdle(current, dir) {
    var i = idleSteps.indexOf(current)
    if (i === -1) { i = 0; while (i < idleSteps.length - 1 && idleSteps[i] < current) i++ }
    return idleSteps[Math.max(0, Math.min(idleSteps.length - 1, i + dir))]
  }

  function modeLabel(mode) { return mode === "delay" ? t("settings.delay") : t("settings.immediate") }
  function passwordLabel(mode) { return mode === "own" ? t("settings.passwordOwn") : t("settings.passwordSystem") }

  // Resumen de la config efectiva de un workspace para la lista.
  function summary(id) {
    var e = Settings.effective(settings, id)
    if (!e.private) return t("settings.public")
    var parts = [e.lockMode === "delay" ? formatDelay(e.delaySeconds) : t("settings.immediate")]
    parts.push(passwordLabel(e.passwordMode))
    return parts.join(" · ")
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
  // value null = «heredar»: se borra el campo y manda defaults.
  function saveWorkspace(field, value) {
    service.saveSettings(Settings.withWorkspaceField(settings, selectedWorkspace, field, value))
  }

  function saveOwn() {
    if (ownNew.value.length === 0 || ownRepeat.value.length === 0) { ownMessage = t("settings.ownEmpty"); return }
    if (ownNew.value !== ownRepeat.value) {
      ownMessage = t("settings.ownMismatch")
      ownNew.clear(); ownRepeat.clear(); ownNew.forceActiveFocus()
      return
    }
    var pw = ownNew.value
    ownNew.clear(); ownRepeat.clear()
    ownMessage = ""
    service.setOwnPassword(selectedWorkspace, pw)
    keys.forceActiveFocus()
  }

  function ownStatusText() {
    if (ownMessage) return ownMessage
    var st = service ? service.ownStatus : ""
    if (st === "saved") return t("settings.ownSaved")
    if (st === "removed") return t("settings.ownRemoved")
    if (st === "error") return t("settings.ownError")
    return selectedHasOwn ? t("settings.ownHas") : t("settings.ownMissing")
  }

  function startCapture(target) { captureTarget = target; capturing = true; keys.forceActiveFocus() }

  // Atajo pulsado → "SUPER + CTRL + L". Solo teclas con nombre seguro (van a Lua).
  function chordFromEvent(event) {
    var names = {}
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

  function moveSelection(dy) {
    var i = workspaceIds.indexOf(selectedWorkspace)
    i = Math.max(0, Math.min(workspaceIds.length - 1, (i === -1 ? 0 : i) + dy))
    selectedWorkspace = workspaceIds[i]
  }

  onTabChanged: { focusArea = "list"; optCursor = 0 }
  onSelectedWorkspaceChanged: { if (service) service.ownStatus = ""; ownNew.clear(); ownRepeat.clear(); ownMessage = "" }
  // Cada vez que se abre: pestaña Workspaces, nivel lista y el workspace en el que
  // estás. Recordar la pestaña anterior hacía que las teclas cayeran donde no se veía.
  onVisibleChanged: {
    capturing = false
    if (!visible) return
    tab = "workspaces"
    focusArea = "list"
    optCursor = 0
    var active = service ? service.activeWorkspaceId : 1
    selectedWorkspace = workspaceIds.indexOf(active) !== -1 ? active : (workspaceIds[0] || 1)
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  // ------------------------------------------------------------------ vista
  Item {
    id: keys
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) {
      if (win.capturing) {
        if (event.key === Qt.Key_Escape) win.capturing = false
        else {
          var chord = win.chordFromEvent(event)
          if (chord) {
            win.capturing = false
            if (win.captureTarget === "allowed") win.service.saveSettings(Settings.withAllowed(win.settings, chord, true))
            else win.saveTop("lockShortcut", chord)
          }
        }
        event.accepted = true
        return
      }
      var up = event.key === Qt.Key_Up, down = event.key === Qt.Key_Down
      var left = event.key === Qt.Key_Left, right = event.key === Qt.Key_Right
      var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
      if (win.focusArea === "options") {
        // nivel opciones: ↑/↓ tarjeta · ←/→ valor · enter editar · esc volver
        if (event.key === Qt.Key_Escape) win.backToList()
        else if (up || down) win.optCursor = Math.max(0, Math.min(win.rows.length - 1, win.optCursor + (up ? -1 : 1)))
        else if (left || right) win.changeRow(left ? -1 : 1)
        else if (enter) win.activateRow()
        else return
      } else {
        // nivel lista: ↑/↓ workspace · ←/→ pestaña · enter opciones · esc cerrar
        if (event.key === Qt.Key_Escape) win.service.closeSettings()
        else if (left || right) win.tab = win.tab === "workspaces" ? "general" : "workspaces"
        else if ((up || down) && win.tab === "workspaces") win.moveSelection(up ? -1 : 1)
        else if (enter || ((up || down) && win.tab === "general")) win.enterOptions()
        else return
      }
      event.accepted = true
    }

    MouseArea { anchors.fill: parent; onClicked: keys.forceActiveFocus() }

    Column {
      anchors.fill: parent
      anchors.margins: win.margin
      spacing: Style.space(14)

      // ---- cabecera: pestañas con icono y subrayado de acento
      Item {
        id: tabBar
        width: parent.width
        height: Style.space(40)

        Row {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          spacing: Style.space(6)

          Repeater {
            model: [{ id: "workspaces", icon: "󰍹", label: "tab.workspaces" }, { id: "general", icon: "󰒓", label: "tab.general" }]
            Item {
              required property var modelData
              readonly property bool active: win.tab === modelData.id
              objectName: "tab-" + modelData.id
              width: tabLabel.implicitWidth + Style.space(24)
              height: parent.height
              Text {
                id: tabLabel
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Style.space(2)
                textFormat: Text.PlainText
                text: modelData.icon + "  " + win.t(modelData.label)
                color: parent.active || tabMouse.containsMouse ? win.accent : win.mutedFg
                font.family: win.fontFamily
                font.pixelSize: Style.font.body
                font.bold: parent.active
              }
              Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: win.tabUnderline; radius: height / 2
                color: win.accent
                visible: parent.active
              }
              MouseArea {
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { win.tab = modelData.id; keys.forceActiveFocus() }
              }
            }
          }
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "󰌾  " + win.t("plugin.name")
          color: win.mutedFg
          font.family: win.fontFamily
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
          height: Style.normalBorderWidth
          color: win.lineColor
        }
      }

      // ---- contenido
      Item {
        id: body
        width: parent.width
        height: parent.height - tabBar.height - footer.height - 2 * Style.space(14)

        // ================= pestaña Workspaces: lista + detalle
        Row {
          anchors.fill: parent
          spacing: Style.space(18)
          visible: win.tab === "workspaces"

          // lista
          ListView {
            id: wsList
            width: Style.space(290)
            height: parent.height
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds
            model: win.workspaceIds

            delegate: Rectangle {
              id: wsRow
              required property int modelData
              readonly property bool selected: win.selectedWorkspace === modelData
              readonly property bool focused: selected && win.focusArea === "list"
              objectName: "ws-" + modelData
              width: wsList.width
              height: Style.space(52)
              radius: Style.cornerRadius
              color: selected ? Color.menu.selectedBackground : (rowMouse.containsMouse ? win.chipBg : "transparent")

              WorkspaceIcon {
                id: wsIcon
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                number: wsRow.modelData
                status: win.statusOf(wsRow.modelData)
                foreground: win.fg
                accent: win.accent
                lockedColor: win.lockedColor
                fontFamily: win.fontFamily
              }

              Column {
                anchors.left: wsIcon.right
                anchors.leftMargin: Style.space(12)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: win.strings ? win.strings.t("panel.workspace").arg(wsRow.modelData) : ""
                  color: wsRow.focused ? Color.menu.selectedText : win.fg
                  font.family: win.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: wsRow.selected
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: win.statusOf(wsRow.modelData) === "locked" ? win.t("state.locked") : win.summary(wsRow.modelData)
                  color: win.statusOf(wsRow.modelData) === "locked" ? win.lockedColor : win.mutedFg
                  font.family: win.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { win.selectedWorkspace = wsRow.modelData; win.backToList() }
              }
            }
          }

          Rectangle { width: Style.normalBorderWidth; height: parent.height; color: win.lineColor }

          // detalle del elegido
          Flickable {
            id: detail
            width: parent.width - wsList.width - 2 * Style.space(18) - Style.normalBorderWidth
            height: parent.height
            contentHeight: detailCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: detailCol
              width: detail.width
              spacing: Style.space(8)

              // cabecera del detalle: monitor grande + nombre + estado
              Row {
                spacing: Style.space(14)
                bottomPadding: Style.space(6)
                WorkspaceIcon {
                  anchors.verticalCenter: parent.verticalCenter
                  size: 1.6
                  number: win.selectedWorkspace
                  status: win.statusOf(win.selectedWorkspace)
                  foreground: win.fg; accent: win.accent; lockedColor: win.lockedColor; fontFamily: win.fontFamily
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)
                  Text {
                    textFormat: Text.PlainText
                    text: win.strings ? win.strings.t("panel.workspace").arg(win.selectedWorkspace) : ""
                    color: win.fg
                    font.family: win.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }
                  Rectangle {
                    readonly property string st: win.statusOf(win.selectedWorkspace)
                    readonly property color tone: st === "locked" ? win.lockedColor : st === "private" ? win.accent : win.mutedFg
                    radius: Style.space(3)
                    color: Util.alpha(tone, 0.14)
                    width: stateText.implicitWidth + Style.space(14)
                    height: Style.space(20)
                    Text {
                      id: stateText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: win.t(parent.st === "locked" ? "state.locked" : parent.st === "private" ? "state.private" : "state.public")
                      color: parent.tone
                      font.family: win.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }
              }

              SettingCard {
                width: parent.width
                title: win.t("settings.private")
                hasCursor: win.currentRow === "private"
                description: win.selectedLocked ? win.t("detail.locked") : win.t("card.private.desc")
                fontFamily: win.fontFamily
                ButtonGroup {
                  objectName: "privateGroup"
                  focusable: false
                  enabled: !win.selectedLocked
                  opacity: enabled ? 1 : 0.5
                  options: [{ value: "public", label: win.t("settings.public") }, { value: "private", label: win.t("settings.private") }]
                  value: win.selectedEffective.private ? "private" : "public"
                  foreground: win.fg; background: win.bg; accent: win.accent; fontFamily: win.fontFamily; fontSize: Style.font.caption
                  onChanged: function(v) { win.service.requestPrivate(win.selectedWorkspace, v === "private") }
                }
              }

              SettingCard {
                width: parent.width
                title: win.t("card.lockMode")
                description: win.t("card.lockMode.desc")
                hasCursor: win.currentRow === "lockMode"
                fontFamily: win.fontFamily
                ButtonGroup {
                  objectName: "wsLockMode"
                  focusable: false
                  options: [{ value: "inherit", label: win.t("settings.inherit") },
                            { value: "immediate", label: win.t("settings.immediate") }, { value: "delay", label: win.t("settings.delay") }]
                  value: win.selectedEntry.lockMode || "inherit"
                  foreground: win.fg; background: win.bg; accent: win.accent; fontFamily: win.fontFamily; fontSize: Style.font.caption
                  onChanged: function(v) { win.saveWorkspace("lockMode", v === "inherit" ? null : v) }
                }
              }

              SettingCard {
                width: parent.width
                visible: win.selectedEffective.lockMode === "delay"
                hasCursor: win.currentRow === "delay"
                title: win.t("card.delay")
                description: win.t("card.delay.desc")
                fontFamily: win.fontFamily
                Button { text: "−"; bordered: true; fontFamily: win.fontFamily; onClicked: win.saveWorkspace("delaySeconds", win.stepDelay(win.selectedEffective.delaySeconds, -1)) }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(70)
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: win.formatDelay(win.selectedEffective.delaySeconds)
                  color: win.fg; font.family: win.fontFamily; font.pixelSize: Style.font.body; font.bold: true
                }
                Button { text: "+"; bordered: true; fontFamily: win.fontFamily; onClicked: win.saveWorkspace("delaySeconds", win.stepDelay(win.selectedEffective.delaySeconds, 1)) }
                Button { visible: win.selectedEntry.delaySeconds !== undefined; text: win.t("settings.inherit"); bordered: true; fontFamily: win.fontFamily; onClicked: win.saveWorkspace("delaySeconds", null) }
              }

              SettingCard {
                width: parent.width
                title: win.t("card.idle")
                description: win.t("card.idle.desc")
                hasCursor: win.currentRow === "idle"
                fontFamily: win.fontFamily
                ButtonGroup {
                  objectName: "wsIdleLock"
                  focusable: false
                  options: [{ value: "inherit", label: win.t("settings.inherit") },
                            { value: "off", label: win.t("settings.off") }, { value: "on", label: win.t("settings.on") }]
                  value: win.selectedEntry.idleLock || "inherit"
                  foreground: win.fg; background: win.bg; accent: win.accent; fontFamily: win.fontFamily; fontSize: Style.font.caption
                  onChanged: function(v) { win.saveWorkspace("idleLock", v === "inherit" ? null : v) }
                }
              }

              SettingGroup {
                width: parent.width
                visible: win.selectedEffective.idleLock === "on"
                lineColor: win.lineColor

                SettingCard {
                  width: parent.width
                  hasCursor: win.currentRow === "idleTime"
                  title: win.t("card.idleTime")
                  description: win.t("card.idleTime.desc")
                  fontFamily: win.fontFamily
                  Button { text: "−"; bordered: true; fontFamily: win.fontFamily; onClicked: win.saveWorkspace("idleSeconds", win.stepIdle(win.selectedEffective.idleSeconds, -1)) }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(70)
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: win.formatDelay(win.selectedEffective.idleSeconds)
                    color: win.fg; font.family: win.fontFamily; font.pixelSize: Style.font.body; font.bold: true
                  }
                  Button { text: "+"; bordered: true; fontFamily: win.fontFamily; onClicked: win.saveWorkspace("idleSeconds", win.stepIdle(win.selectedEffective.idleSeconds, 1)) }
                  Button { visible: win.selectedEntry.idleSeconds !== undefined; text: win.t("settings.inherit"); bordered: true; fontFamily: win.fontFamily; onClicked: win.saveWorkspace("idleSeconds", null) }
                }

                SettingCard {
                  width: parent.width
                  hasCursor: win.currentRow === "idleAudio"
                  title: win.t("card.idleAudio")
                  description: win.t("card.idleAudio.desc")
                  fontFamily: win.fontFamily
                  ButtonGroup {
                    objectName: "wsIdleAudio"
                    focusable: false
                    options: [{ value: "inherit", label: win.t("settings.inherit") },
                              { value: "lock", label: win.t("settings.idleAudioLock") }, { value: "wait", label: win.t("settings.idleAudioWait") }]
                    value: win.selectedEntry.idleAudio || "inherit"
                    foreground: win.fg; background: win.bg; accent: win.accent; fontFamily: win.fontFamily; fontSize: Style.font.caption
                    onChanged: function(v) { win.saveWorkspace("idleAudio", v === "inherit" ? null : v) }
                  }
                }
              }

              SettingCard {
                width: parent.width
                title: win.t("card.password")
                hasCursor: win.currentRow === "password"
                description: win.t("card.password.desc")
                fontFamily: win.fontFamily
                ButtonGroup {
                  objectName: "wsPasswordMode"
                  focusable: false
                  options: [{ value: "inherit", label: win.t("settings.inherit") },
                            { value: "system", label: win.t("settings.passwordSystem") }, { value: "own", label: win.t("settings.passwordOwn") }]
                  value: win.selectedEntry.passwordMode || "inherit"
                  foreground: win.fg; background: win.bg; accent: win.accent; fontFamily: win.fontFamily; fontSize: Style.font.caption
                  onChanged: function(v) { win.saveWorkspace("passwordMode", v === "inherit" ? null : v) }
                }
              }

              SettingCard {
                width: parent.width
                visible: win.selectedEffective.passwordMode === "own"
                hasCursor: win.currentRow === "own"
                below: true
                title: win.t("card.ownPassword")
                description: win.ownStatusText()
                fontFamily: win.fontFamily
                PasswordField {
                  id: ownNew
                  objectName: "ownNew"
                  implicitWidth: Style.space(190)
                  implicitHeight: Style.space(34)
                  placeholder: win.t("settings.ownNew")
                  onSubmitted: function(pw) { ownNew.value = pw; ownRepeat.forceActiveFocus() }
                  onEscaped: keys.forceActiveFocus()
                }
                PasswordField {
                  id: ownRepeat
                  objectName: "ownRepeat"
                  implicitWidth: Style.space(190)
                  implicitHeight: Style.space(34)
                  placeholder: win.t("settings.ownRepeat")
                  onSubmitted: function(pw) { ownRepeat.value = pw; win.saveOwn() }
                  onEscaped: keys.forceActiveFocus()
                }
                Button { anchors.verticalCenter: parent.verticalCenter; text: win.t("settings.ownSave"); bordered: true; fontFamily: win.fontFamily; onClicked: win.saveOwn() }
                Button { anchors.verticalCenter: parent.verticalCenter; visible: win.selectedHasOwn; text: win.t("settings.ownRemove"); bordered: true; fontFamily: win.fontFamily; onClicked: win.service.removeOwnPassword(win.selectedWorkspace) }
              }
            }
          }
        }

        // ================= pestaña General
        Flickable {
          anchors.fill: parent
          visible: win.tab === "general"
          contentHeight: generalCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: generalCol
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: win.t("general.intro")
              color: win.mutedFg
              font.family: win.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              bottomPadding: Style.space(4)
            }

            PanelSectionHeader { text: win.t("section.lock").toUpperCase(); foreground: win.fg; fontFamily: win.fontFamily; topPadding: Style.space(6) }

            SettingCard {
              width: parent.width
              title: win.t("card.lockMode")
              description: win.t("card.generalLock.desc")
              hasCursor: win.currentRow === "lockMode"
              fontFamily: win.fontFamily
              ButtonGroup {
                objectName: "lockModeGroup"
                focusable: false
                options: [{ value: "immediate", label: win.t("settings.immediate") }, { value: "delay", label: win.t("settings.delay") }]
                value: win.defs.lockMode
                foreground: win.fg; background: win.bg; accent: win.accent; fontFamily: win.fontFamily; fontSize: Style.font.caption
                onChanged: function(v) { win.saveDefault("lockMode", v) }
              }
            }

            SettingCard {
              width: parent.width
              visible: win.defs.lockMode === "delay"
              hasCursor: win.currentRow === "delay"
              title: win.t("card.delay")
              description: win.t("card.delay.desc")
              fontFamily: win.fontFamily
              Button { objectName: "delayMinus"; text: "−"; bordered: true; fontFamily: win.fontFamily; onClicked: win.saveDefault("delaySeconds", win.stepDelay(win.defs.delaySeconds, -1)) }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(70)
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: win.formatDelay(win.defs.delaySeconds)
                color: win.fg; font.family: win.fontFamily; font.pixelSize: Style.font.body; font.bold: true
              }
              Button { objectName: "delayPlus"; text: "+"; bordered: true; fontFamily: win.fontFamily; onClicked: win.saveDefault("delaySeconds", win.stepDelay(win.defs.delaySeconds, 1)) }
            }

            PanelSectionHeader { text: win.t("section.idle").toUpperCase(); foreground: win.fg; fontFamily: win.fontFamily; topPadding: Style.space(10) }

            SettingCard {
              width: parent.width
              title: win.t("card.idle")
              description: win.t("card.idle.desc")
              hasCursor: win.currentRow === "idle"
              fontFamily: win.fontFamily
              ButtonGroup {
                objectName: "idleLockGroup"
                focusable: false
                options: [{ value: "off", label: win.t("settings.off") }, { value: "on", label: win.t("settings.on") }]
                value: win.defs.idleLock
                foreground: win.fg; background: win.bg; accent: win.accent; fontFamily: win.fontFamily; fontSize: Style.font.caption
                onChanged: function(v) { win.saveDefault("idleLock", v) }
              }
            }

            SettingGroup {
              width: parent.width
              visible: win.defs.idleLock === "on"
              lineColor: win.lineColor

              SettingCard {
                width: parent.width
                hasCursor: win.currentRow === "idleTime"
                title: win.t("card.idleTime")
                description: win.t("card.idleTime.desc")
                fontFamily: win.fontFamily
                Button { objectName: "idleMinus"; text: "−"; bordered: true; fontFamily: win.fontFamily; onClicked: win.saveDefault("idleSeconds", win.stepIdle(win.defs.idleSeconds, -1)) }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(70)
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: win.formatDelay(win.defs.idleSeconds)
                  color: win.fg; font.family: win.fontFamily; font.pixelSize: Style.font.body; font.bold: true
                }
                Button { objectName: "idlePlus"; text: "+"; bordered: true; fontFamily: win.fontFamily; onClicked: win.saveDefault("idleSeconds", win.stepIdle(win.defs.idleSeconds, 1)) }
              }

              SettingCard {
                width: parent.width
                hasCursor: win.currentRow === "idleAudio"
                title: win.t("card.idleAudio")
                description: win.t("card.idleAudio.desc")
                fontFamily: win.fontFamily
                ButtonGroup {
                  objectName: "idleAudioGroup"
                  focusable: false
                  options: [{ value: "lock", label: win.t("settings.idleAudioLock") }, { value: "wait", label: win.t("settings.idleAudioWait") }]
                  value: win.defs.idleAudio
                  foreground: win.fg; background: win.bg; accent: win.accent; fontFamily: win.fontFamily; fontSize: Style.font.caption
                  onChanged: function(v) { win.saveDefault("idleAudio", v) }
                }
              }
            }

            PanelSectionHeader { text: win.t("section.password").toUpperCase(); foreground: win.fg; fontFamily: win.fontFamily; topPadding: Style.space(10) }

            SettingCard {
              width: parent.width
              title: win.t("card.password")
              description: win.t("card.password.desc")
              fontFamily: win.fontFamily
              hasCursor: win.currentRow === "password"
              ButtonGroup {
                focusable: false
                options: [{ value: "system", label: win.t("settings.passwordSystem") }, { value: "own", label: win.t("settings.passwordOwn") }]
                value: win.defs.passwordMode
                foreground: win.fg; background: win.bg; accent: win.accent; fontFamily: win.fontFamily; fontSize: Style.font.caption
                onChanged: function(v) { win.saveDefault("passwordMode", v) }
              }
            }

            PanelSectionHeader { text: win.t("section.shortcuts").toUpperCase(); foreground: win.fg; fontFamily: win.fontFamily; topPadding: Style.space(10) }

            SettingCard {
              width: parent.width
              title: win.t("card.shortcut")
              hasCursor: win.currentRow === "shortcut"
              description: win.service && win.service.shortcutConflict
                ? win.t("card.shortcut.inUse").arg(win.service.shortcutConflict)
                : win.t("card.shortcut.desc")
              fontFamily: win.fontFamily
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                radius: Style.space(3)
                color: win.capturing && win.captureTarget === "lockShortcut" ? Util.alpha(win.accent, 0.16) : win.chipBg
                width: chordText.implicitWidth + Style.space(16)
                height: Style.space(26)
                Text {
                  id: chordText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: win.capturing && win.captureTarget === "lockShortcut" ? win.t("settings.shortcutPress")
                    : (win.settings.lockShortcut || win.t("settings.shortcutNone"))
                  color: win.capturing && win.captureTarget === "lockShortcut" ? win.accent : win.fg
                  font.family: win.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
              Button {
                visible: !(win.capturing && win.captureTarget === "lockShortcut")
                text: win.t("settings.shortcutChange")
                bordered: true
                fontFamily: win.fontFamily
                onClicked: win.startCapture("lockShortcut")
              }
            }

            SettingCard {
              width: parent.width
              below: true
              title: win.t("card.allowed")
              hasCursor: win.currentRow === "allowed"
              description: win.t("card.allowed.desc")
              fontFamily: win.fontFamily
              Flow {
                width: generalCol.width - 2 * Style.spacing.rowPaddingX
                spacing: Style.space(6)
                Repeater {
                  model: win.settings.lockedAllowedShortcuts
                  Rectangle {
                    id: chip
                    required property string modelData
                    readonly property bool missing: !!win.service && win.service.missingAllowed.indexOf(modelData) !== -1
                    radius: Style.space(3)
                    color: chipMouse.containsMouse ? Util.alpha(win.lockedColor, 0.14) : win.chipBg
                    width: chipText.implicitWidth + Style.space(16)
                    height: Style.space(26)
                    Text {
                      id: chipText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: chip.modelData + (chipMouse.containsMouse ? "  ×" : "")
                      color: chip.missing || chipMouse.containsMouse ? win.lockedColor : win.fg
                      font.family: win.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      id: chipMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: win.service.saveSettings(Settings.withAllowed(win.settings, chip.modelData, false))
                    }
                  }
                }
                Rectangle {
                  radius: Style.space(3)
                  color: win.capturing && win.captureTarget === "allowed" ? Util.alpha(win.accent, 0.16) : "transparent"
                  border.width: Style.normalBorderWidth
                  border.color: Util.alpha(win.accent, 0.6)
                  width: addText.implicitWidth + Style.space(16)
                  height: Style.space(26)
                  Text {
                    id: addText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: win.capturing && win.captureTarget === "allowed" ? win.t("settings.shortcutPress") : "+  " + win.t("settings.allowedAdd")
                    color: win.accent
                    font.family: win.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.startCapture("allowed") }
                }
              }
            }
          }
        }
      }

      // ---- pie: teclas en chips
      Flow {
        id: footer
        width: parent.width
        spacing: Style.space(10)
        Repeater {
          model: win.capturing ? [{ keys: "esc", hint: "hint.cancel" }]
            : win.focusArea === "options" ? [{ keys: "↑/↓", hint: "hint.move" }, { keys: "←/→", hint: "hint.change" },
                                            { keys: "enter", hint: "hint.edit" }, { keys: "esc", hint: "hint.back" }]
            : win.tab === "workspaces" ? [{ keys: "↑/↓", hint: "hint.move" }, { keys: "enter", hint: "hint.options" },
                                          { keys: "←/→", hint: "hint.switchTab" }, { keys: "esc", hint: "hint.close" }]
            : [{ keys: "enter", hint: "hint.options" }, { keys: "←/→", hint: "hint.switchTab" }, { keys: "esc", hint: "hint.close" }]
          delegate: Row {
            required property var modelData
            spacing: Style.space(4)
            Rectangle {
              radius: Style.space(3)
              color: win.chipBg
              width: keyText.implicitWidth + Style.space(10)
              height: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              Text { id: keyText; anchors.centerIn: parent; textFormat: Text.PlainText; text: modelData.keys; color: win.mutedFg; font.family: win.fontFamily; font.pixelSize: Style.font.caption }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: win.t(modelData.hint); color: win.mutedFg; font.family: win.fontFamily; font.pixelSize: Style.font.caption }
          }
        }
      }
    }
  }
}
