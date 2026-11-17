# Changelog — Super Workspace Lock

> What changed, by version (newest first; the last 10 are kept).

## 0.1.0 - 2026-11-17 14:42
---
- [feature] Mark a workspace as private: when you leave it, it locks and is covered with a heavy blur and a password box (system password, PAM)
- [feature] While a workspace is locked only the allowed shortcuts work (Super+1…0, Super+Tab, Super+Space, Super+Ctrl+L by default; editable in settings.json)
- [feature] Lock icon in the bar tray drawer with a panel listing workspaces and a private switch for each
- [feature] Super+Ctrl+Shift+L locks the current workspace; on a public one it is a one-off lock
- [feature] Private workspaces lock again when the whole session is locked (works with omarchy.lock and LockSigil)
- [feature] Wrong password and too-many-attempts (faillock) messages, in English and Spanish
- [new] Settings in ~/.config/omarchy/super-workspace-lock/settings.json (folder 700, file 600); private workspaces start locked after a restart
- [new] Watchdog that gives Hyprland back (reload + submap reset) if the shell dies while a workspace is locked
- [new] Logic tests (node) and helpers to test without hands: IPC state, layer screenshot, workspace switch
