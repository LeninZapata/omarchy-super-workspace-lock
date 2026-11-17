# Changelog — Super Workspace Lock

> What changed, by version (newest first; the last 10 are kept).

## 0.3.3 - 2026-11-17 18:45
---
- [update] A locked workspace now arrives already covered: it carries a cover window of its own (blurred wallpaper and the lock card) that slides in with Hyprland's switch animation, so nothing of it, not even the bare wallpaper, shows while switching
- [new] LockCard.qml, the lock card shared by the lock layer and the covers
- [fix] The lock layer's card appears once the switch animation ends, aligned over the cover's, instead of showing two cards while the workspace slides in

## 0.3.2 - 2026-11-17 18:35
---
- [fix] Switching to a locked workspace no longer flashes its windows for a moment: while a workspace is locked its windows are fully transparent, and they get their exact opacity back when it opens
- [new] vis.py helper that hides and restores those windows, keeping the original opacity in ~/.local/state/omarchy/super-workspace-lock/hidden.json, with a watcher that gives everything back if the plugin stops

## 0.3.1 - 2026-11-17 18:24
---
- [new] README with demo recordings
- [new] Marketplace preview image
- [fix] The settings window opens focused, centered and at its own size (on a scaled screen Omarchy's floating size cut it off), always on the Workspaces tab with the current workspace selected
- [fix] The bar panel's keyboard cursor starts at the top each time it opens

## 0.3.0 - 2026-11-17 15:35
---
- [update] Settings window redesigned: Workspaces tab (each workspace as a small monitor, its settings beside it) and General tab, with setting cards and key hints
- [update] Full keyboard control in settings: arrows move through the list, Enter goes into the options, left/right change a value, Esc goes back
- [update] Lock screen card: locked monitor, which password it asks for, key hints, and a shake on a wrong password
- [new] MIT license

## 0.2.0 - 2026-11-17 15:01
---
- [feature] Settings window (from the panel's Settings button): defaults and per-workspace overrides with "Default" to inherit
- [feature] Lock after a while away: a private workspace can stay open for a chosen time after you leave it (5 s to 1 h)
- [feature] Own password per workspace (scrypt, sent to the helper only through stdin); the system password always opens it too
- [feature] Lock-now button per private workspace in the bar panel
- [feature] Edit the shortcuts that work on a locked workspace, and the lock shortcut, by pressing them (no text fields)
- [new] hash.py helper for own passwords, with its tests

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
