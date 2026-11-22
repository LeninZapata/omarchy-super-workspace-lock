# Changelog — Super Workspace Lock

> What changed, by version (newest first; the last 10 are kept).

## 0.4.1 - 2026-11-22 12:00
---
- [update] The workspace tab of the settings is split into the same sections as the General tab (Lock, Inactivity, Password), so "Lock when idle" no longer reads as part of "When to lock"
- [update] "Time away" sits in an indented frame under "When to lock", like the idle settings under "Lock when idle"

## 0.4.0 - 2026-11-22 11:48
---
- [feature] Lock when idle: an open private workspace also locks while you are still in it once the keyboard and mouse sit untouched for a while. Off by default; 15 minutes (1 min – 2 h) when turned on. It uses Wayland's idle notification on its own, so it works even with Omarchy's idle lock off
- [feature] "While audio plays" option for the idle lock: lock anyway (default) or wait while any audio output is playing (checked with pactl)
- [new] Inactivity section in the General tab, with the same three settings per workspace (Default inherits); the time and audio settings are grouped and indented under the switch
- [new] SettingGroup.qml, the indented frame for settings that depend on a switch

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

