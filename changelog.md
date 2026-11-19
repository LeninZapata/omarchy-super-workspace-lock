# Changelog — Super Workspace Lock

> What changed, by version (newest first; the last 10 are kept).

## 0.3.7 - 2026-11-19 17:21
---
- [fix] The lock shortcut's ownership check now looks at every Hyprland submap, not just the main key map: hl.unbind removes a key from all submaps, so a key that something else uses in any submap is treated as taken (never set, never released). Only the plugin's own lock-layer submap is ignored, since the plugin rebuilds it. Reported in the marketplace review

## 0.3.6 - 2026-11-19 15:06
---
- [fix] Releasing the lock shortcut never removes anything else on that key: if Hyprland's bind list can't be read, nothing is released or set (it retries), and on unload the new binds.py releases a key only when every bind on it is the plugin's. Reported in the marketplace review
- [fix] If the window list can't be read, vis.py leaves the saved opacities alone instead of treating it as "no windows" and forgetting them; the watcher retries, so open windows can no longer stay invisible because of a failed query. Reported in the marketplace review
- [new] binds.py, the ownership-checked release of the lock shortcut

## 0.3.5 - 2026-11-19 13:40
---
- [fix] The lock shortcut never takes over a key that something else already uses: before setting it, the plugin reads Hyprland's binds and only sets or releases its own (recognized by its description). A taken key is left alone and the settings window says so under "Lock shortcut". Reported in the marketplace review
- [fix] A window's saved opacity is only forgotten once Hyprland has actually restored it (checked with getprop, up to 3 tries). If Hyprland rejects it, the value stays in hidden.json and the watcher retries while the plugin runs, so a window can no longer stay invisible after unlocking. Reported in the marketplace review

## 0.3.4 - 2026-11-18 13:45
---
- [fix] A password unlocks only the workspace it was typed for: verification is asynchronous (scrypt or PAM), and switching workspaces while it ran opened whichever workspace was active when the result arrived, even one with a different password. Reported in the marketplace review

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
