import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import "Core.js" as Core

// Comprueba la clave del sistema con PAM (omarchy-lock-password, que trae
// faillock). La clave solo vive en `pending` hasta que PAM la pide, y se borra
// en cuanto se entrega o falla. Nunca se escribe en ningún log.
Item {
  id: auth

  // Los de /etc/pam.d/omarchy-lock-password (deny=10 unlock_time=120).
  readonly property int faillockDeny: 10
  readonly property int faillockUnlockSec: 120
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")

  property bool busy: false
  property string pending: ""

  signal succeeded()
  // waitSeconds > 0: faillock activo, hay que esperar.
  signal failed(int waitSeconds)

  function submit(password) {
    if (busy || !password || password.length === 0) return
    pending = password
    busy = true
    if (!pam.start()) finishFailure()
    else Qt.callLater(respond)
  }

  function respond() {
    if (!busy || !pam.active || !pam.responseRequired) return
    pam.respond(pending)
    pending = ""
  }

  function finishFailure() {
    pending = ""
    faillockProc.exec(["faillock", "--user", userName])
  }

  PamContext {
    id: pam
    config: "omarchy-lock-password"
    user: auth.userName

    onResponseRequiredChanged: auth.respond()
    onPamMessage: auth.respond()
    onCompleted: function(result) {
      auth.pending = ""
      if (result === PamResult.Success) {
        auth.busy = false
        auth.succeeded()
      } else auth.finishFailure()
    }
    onError: function(error) { auth.finishFailure() }
  }

  // Tras un fallo: ¿ya saltó faillock? (el registro del propio usuario se lee sin root)
  Process {
    id: faillockProc
    stdout: StdioCollector {
      onStreamFinished: {
        auth.busy = false
        auth.failed(Core.faillockWait(text, Date.now(), auth.faillockDeny, auth.faillockUnlockSec))
      }
    }
  }
}
