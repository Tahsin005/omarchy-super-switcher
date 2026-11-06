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
  property var pendingAppWorkspaceId: null
  property string pendingCursorPosition: ""
  property bool currentWorkspaceAppsOnly: false
  property int appSessionWorkspaceId: 0

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

  function runningApps(workspaceId) {
    return SwitcherModel.buildApps(Hyprland.toplevels.values || [], root.appEntries(), root.recentWindows, workspaceId)
  }

  function sessionApps() {
    return root.runningApps(root.currentWorkspaceAppsOnly ? root.appSessionWorkspaceId : null)
  }

  function refreshApps() {
    if (!panel.active || panel.workspaceMode) return
    var selected = panel.apps[panel.selectedIndex]
    var apps = root.sessionApps()
    if (!apps.length) { panel.cancel(); return }
    var selectedIndex = 0
    for (var i = 0; i < apps.length; i++) {
      if (selected && apps[i].id === selected.id) { selectedIndex = i; break }
    }
    panel.apps = apps
    panel.selectedIndex = selectedIndex
  }

  function setAppScope(currentWorkspaceOnly) {
    if (!panel.active || panel.workspaceMode || root.currentWorkspaceAppsOnly === currentWorkspaceOnly) return
    if (currentWorkspaceOnly)
      root.appSessionWorkspaceId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
    root.currentWorkspaceAppsOnly = currentWorkspaceOnly
    root.refreshApps()
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

  function cycle(step, heldKeys, currentWorkspaceOnly) {
    if (panel.active && !panel.workspaceMode) {
      root.setAppScope(!!currentWorkspaceOnly)
      if (!panel.active) return
      if (step > 0) panel.next(); else panel.prev()
      return
    }
    root.rememberFocus()
    root.currentWorkspaceAppsOnly = !!currentWorkspaceOnly
    root.appSessionWorkspaceId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
    var apps = root.sessionApps()
    if (!apps.length) { panel.cancel(); return }
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
    var apps = root.sessionApps()
    for (var i = 0; i < apps.length; i++) {
      if (apps[i].id !== id) continue
      var address = String(apps[i].addresses[0])
      if (address.indexOf("0x") !== 0) address = "0x" + address
      if (!/^0x[0-9a-f]+$/i.test(address)) return
      root.pendingFocusTarget = "address:" + address
      root.pendingWorkspaceFocus = false
      root.pendingAppWorkspaceId = root.currentWorkspaceAppsOnly ? root.appSessionWorkspaceId : null
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
      if (heldKeys !== null) root.cycle(step, heldKeys, false)
    }
    function localCycleHeld(step: int, keycodes: string): void {
      var heldKeys = SwitcherKeys.parseHeldKeys(keycodes)
      if (heldKeys !== null) root.cycle(step, heldKeys, true)
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
    function onFocusedWorkspaceChanged() {
      if (panel.active && !panel.workspaceMode && root.currentWorkspaceAppsOnly
          && (!Hyprland.focusedWorkspace || Hyprland.focusedWorkspace.id !== root.appSessionWorkspaceId))
        panel.cancel()
    }
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
      } else if (String(event.name) === "movewindowv2") {
        Qt.callLater(root.refreshApps)
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
      root.refreshApps()
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
    onAppScopeChanged: function(currentWorkspaceOnly) { root.setAppScope(currentWorkspaceOnly) }
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
        if (root.pendingAppWorkspaceId !== null) {
          // Recheck after the asynchronous cursor capture. An app can have a
          // newer window elsewhere, or its selected window can move away.
          var windows = Hyprland.toplevels.values || []
          var allowed = Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === root.pendingAppWorkspaceId
          var found = false
          for (var j = 0; allowed && j < windows.length; j++) {
            var address = "address:0x" + String(windows[j].address).replace(/^0x/i, "")
            if (address === target && SwitcherModel.windowInWorkspace(windows[j], root.pendingAppWorkspaceId)) {
              found = true
              break
            }
          }
          if (!found) { restoreCursorWarps.restart(); return }
        }
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
