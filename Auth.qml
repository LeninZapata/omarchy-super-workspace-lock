import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import "Core.js" as Core

// Comprueba la clave. Con clave propia (passwordMode "own"), primero hash.py por
// stdin; si no coincide, la del sistema con PAM (omarchy-lock-password + faillock),
// que SIEMPRE abre. La clave solo vive en `pending` hasta que se entrega, y se
// borra en cuanto se escribe o falla. Nunca va a un argumento ni a un log.
Item {
  id: auth

  // Los de /etc/pam.d/omarchy-lock-password (deny=10 unlock_time=120).
  readonly property int faillockDeny: 10
  readonly property int faillockUnlockSec: 120
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")

  property bool busy: false
  property string pending: ""
  // Ruta de hash.py (junto a este archivo) y workspace cuya clave propia se mira.
  readonly property string hashScript: String(Qt.resolvedUrl("hash.py")).replace(/^file:\/\//, "")

  signal succeeded()
  // waitSeconds > 0: faillock activo, hay que esperar.
  signal failed(int waitSeconds)

  function submit(password, workspaceId, useOwn) {
    if (busy || !password || password.length === 0) return
    pending = password
    busy = true
    if (useOwn && workspaceId > 0) {
      ownProc.secret = password
      ownProc.exec(["python3", "-I", hashScript, "verify", String(workspaceId)])
    } else startSystem()
  }

  function startSystem() {
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

  // Clave propia: hash.py verify, la clave por stdin. 0 = coincide; si no, PAM.
  Process {
    id: ownProc
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        auth.pending = ""
        auth.busy = false
        auth.succeeded()
      } else auth.startSystem()
    }
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
