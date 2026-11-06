import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "SwitcherModel.js" as SwitcherModel
import "SwitcherKeys.js" as SwitcherKeys
import "WorkspaceModel.js" as WorkspaceModel

Item {
  id: root

  property var recentWindows: []
  property string pendingFocusTarget: ""
  property bool pendingWorkspaceFocus: false
  property string pendingCursorPosition: ""

  function syncSubmap() {
    // Serialize enter/leave commands. A rapid close/reopen must not let an
    // older leave command reset the new session's input mode.
    if (!panel.active) panel.inputReady = false
    if (submapControl.running) return
    submapControl.entering = panel.active
    submapControl.command = ["hyprctl", "eval", SwitcherKeys.submapCommand(panel.active)]
    submapControl.running = true
  }

  function appEntries() {
    return DesktopEntries.applications.values || []
  }

  function runningApps() {
    return SwitcherModel.buildApps(Hyprland.toplevels.values || [], root.appEntries(), root.recentWindows)
  }

  function rememberFocus() {
    var window = Hyprland.activeToplevel
    if (window && window.address)
      root.recentWindows = SwitcherModel.touchWindow(root.recentWindows, window.address)
  }

  function restoreRuntimeConfig() {
    // Theme changes reload Hyprland without recreating this plugin. The
    // compositor discards runtime bindings and layer rules during that reload.
    if (!layerRule.running) layerRule.running = true
    if (!registerBindings.running) registerBindings.running = true
    bindRetry.attempts = 0
    bindRetry.restart()
  }

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (monitor && screens[i].name === monitor.name) return screens[i]
    }
    return screens.length ? screens[0] : null
  }

  function cycle(step, heldKeys) {
    if (panel.active && !panel.workspaceMode) {
      if (step > 0) panel.next(); else panel.prev()
      return
    }
    root.rememberFocus()
    var apps = root.runningApps()
    if (!apps.length) return
    var current = SwitcherModel.appForWindow(Hyprland.activeToplevel, root.appEntries())
    panel.open(apps, SwitcherModel.initialIndex(apps, current ? current.id : "", step), heldKeys, "apps")
  }

  function workspaceEntries() {
    return WorkspaceModel.buildWorkspaces(Hyprland.workspaces.values || [])
  }

  function cycleWorkspaces(step, heldKeys) {
    if (panel.active && panel.workspaceMode) {
      if (step > 0) panel.next(); else panel.prev()
      return
    }
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    if (!wallpaperPath.running) wallpaperPath.running = true
    var workspaces = root.workspaceEntries()
    if (!workspaces.length) return
    var current = Hyprland.focusedWorkspace
    panel.open(workspaces, SwitcherModel.initialIndex(workspaces, current ? String(current.id) : "", step), heldKeys, "workspaces")
  }

  function updateWorkspaces() {
    if (!panel.active || !panel.workspaceMode) return
    var selected = panel.apps[panel.selectedIndex]
    var workspaces = root.workspaceEntries()
    if (!workspaces.length) { panel.cancel(); return }
    var index = Math.min(panel.selectedIndex, workspaces.length - 1)
    for (var i = 0; i < workspaces.length; i++) {
      if (selected && workspaces[i].id === selected.id) { index = i; break }
    }
    panel.apps = workspaces
    panel.selectedIndex = Math.max(0, index)
  }

  function activateWorkspace(id) {
    // A workspace may disappear during selection; never recreate a stale one.
    var workspaces = root.workspaceEntries()
    for (var i = 0; i < workspaces.length; i++) {
      if (workspaces[i].id !== id) continue
      root.pendingFocusTarget = id
      root.pendingWorkspaceFocus = true
      restoreCursorWarps.stop()
      if (!cursorCapture.running) cursorCapture.running = true
      return
    }
  }

  function iconSource(app) {
    var name = SwitcherModel.iconName(app)
    if (name === "application-x-executable") return Qt.resolvedUrl("assets/default-app.svg")
    if (name.indexOf("/") === 0) return "file://" + name
    if (/^(file|image):/.test(name)) return name
    return Quickshell.iconPath(name, true)
  }

  function activateApp(id) {
    // Resolve against live windows: a program may close while the HUD is open.
    var apps = root.runningApps()
    for (var i = 0; i < apps.length; i++) {
      if (apps[i].id !== id) continue
      var address = String(apps[i].addresses[0])
      if (address.indexOf("0x") !== 0) address = "0x" + address
      if (!/^0x[0-9a-f]+$/i.test(address)) return
      root.pendingFocusTarget = "address:" + address
      root.pendingWorkspaceFocus = false
      root.recentWindows = SwitcherModel.touchWindow(root.recentWindows, apps[i].addresses[0])
      restoreCursorWarps.stop()
      if (!cursorCapture.running) cursorCapture.running = true
      return
    }
  }

  IpcHandler {
    target: "harryxu.super-switcher"
    function altTabNext(): void { Quickshell.execDetached(["hyprctl", "eval", SwitcherKeys.cycleCommand(1)]) }
    function altTabPrev(): void { Quickshell.execDetached(["hyprctl", "eval", SwitcherKeys.cycleCommand(-1)]) }
    function cycleHeld(step: int, keycodes: string): void {
      var heldKeys = SwitcherKeys.parseHeldKeys(keycodes)
      if (heldKeys !== null) root.cycle(step, heldKeys)
    }
    function workspaceNext(): void { Quickshell.execDetached(["hyprctl", "eval", SwitcherKeys.cycleCommand(1, "workspaces")]) }
    function workspacePrev(): void { Quickshell.execDetached(["hyprctl", "eval", SwitcherKeys.cycleCommand(-1, "workspaces")]) }
    function workspaceCycleHeld(step: int, keycodes: string): void {
      var heldKeys = SwitcherKeys.parseHeldKeys(keycodes)
      if (heldKeys !== null) root.cycleWorkspaces(step, heldKeys)
    }
    function altTabCancel(): void { panel.cancel() }
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { root.rememberFocus() }
    function onRawEvent(event) {
      if (!event) return
      if (String(event.name) === "configreloaded") {
        // A reload removes the mode's bindings. End the current session before
        // restoring them, rather than leave a visible panel with drag enabled.
        panel.cancel()
        Qt.callLater(root.restoreRuntimeConfig)
      } else if (String(event.name) === "submap"
                 && String(event.data) !== SwitcherKeys.submapName
                 && panel.active && panel.inputReady) {
        // Includes the compositor-side Escape fallback and external mode changes.
        panel.cancel()
      } else if (String(event.name) === "renameworkspace") {
        Qt.callLater(root.updateWorkspaces)
      }
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      var windows = Hyprland.toplevels.values || []
      root.recentWindows = root.recentWindows.filter(function(address) {
        for (var i = 0; i < windows.length; i++) if (windows[i].address === address) return true
        return false
      })
      if (panel.active && !panel.workspaceMode && !root.runningApps().length) panel.cancel()
    }
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { root.updateWorkspaces() }
  }

  SwitcherPanel {
    id: panel
    screen: root.focusedScreen()
    iconSourceFor: function(app) { return root.iconSource(app) }
    windowIconSourceFor: function(window) {
      var app = SwitcherModel.appForWindow(window, root.appEntries())
      return root.iconSource(app || { id: "", icon: "" })
    }
    onActivated: function(appId) { root.activateApp(appId) }
    onWorkspaceActivated: function(workspaceId) { root.activateWorkspace(workspaceId) }
    onActiveChanged: root.syncSubmap()
  }

  Process {
    id: submapControl
    property bool entering: false
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 || exitStatus !== 0) {
        console.warn("Switcher: could not update Hyprland submap")
        if (panel.active) panel.cancel()
        return
      }
      if (submapControl.entering !== panel.active) root.syncSubmap()
      else if (panel.active) panel.inputReady = true
    }
  }

  // Preserve the pointer position when focusing another app or workspace.
  Process {
    id: cursorCapture
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.pendingCursorPosition = text.trim()
        if (!focusWithoutWarp.running) focusWithoutWarp.running = true
      }
    }
  }

  Process {
    id: focusWithoutWarp
    command: ["hyprctl", "eval", "hl.config({ cursor = { no_warps = true } })"]
    onExited: {
      if (!root.pendingFocusTarget) return
      var target = root.pendingFocusTarget
      root.pendingFocusTarget = ""
      if (root.pendingWorkspaceFocus) {
        // Resolve again after the asynchronous cursor capture.
        var workspaces = root.workspaceEntries()
        for (var i = 0; i < workspaces.length; i++) {
          if (workspaces[i].id !== target) continue
          Hyprland.dispatch(WorkspaceModel.focusCommand(workspaces[i].workspace))
          break
        }
      } else {
        Hyprland.dispatch("hl.dsp.focus({ window = \"" + target + "\" })")
        Qt.callLater(function() { Hyprland.dispatch("hl.dsp.window.bring_to_top()") })
      }
      restoreCursorWarps.restart()
    }
  }

  Timer {
    id: restoreCursorWarps
    interval: 80
    onTriggered: {
      var position = root.pendingCursorPosition.match(/(-?\d+)\s*,\s*(-?\d+)/)
      if (position)
        Hyprland.dispatch("hl.dsp.cursor.move({ x = " + position[1] + ", y = " + position[2] + " })")
      root.pendingCursorPosition = ""
      Quickshell.execDetached(["hyprctl", "eval", "hl.config({ cursor = { no_warps = false } })"])
    }
  }

  Process {
    id: wallpaperPath
    command: ["readlink", "-f", (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/current/background"]
    stdout: StdioCollector {
      onStreamFinished: {
        var path = text.trim()
        panel.wallpaperSource = path && !/\.(mp4|webm|mkv|mov|m4v|avi)$/i.test(path) ? "file://" + path : ""
      }
    }
  }

  Process {
    id: layerRule
    command: ["hyprctl", "eval", "hl.layer_rule({ match = { namespace = \"harryxu-super-switcher\" }, no_anim = true, animation = \"none\" })"]
  }

  Process {
    id: registerBindings
    command: ["hyprctl", "eval", SwitcherKeys.bindingCommand()]
  }

  // Shell startup or reload hooks can reapply config bindings after us.
  Timer {
    id: bindRetry
    interval: 1500
    repeat: true
    property int attempts: 0
    onTriggered: {
      bindRetry.attempts++
      if (bindRetry.attempts > 8) bindRetry.stop()
      else if (!registerBindings.running) registerBindings.running = true
    }
  }

  Component.onCompleted: {
    root.rememberFocus()
    root.syncSubmap()
    root.restoreRuntimeConfig()
  }

  Component.onDestruction: Quickshell.execDetached(["hyprctl", "eval", SwitcherKeys.submapCommand(false)])
}
