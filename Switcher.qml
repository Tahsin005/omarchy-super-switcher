import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "SwitcherModel.js" as SwitcherModel

Item {
  id: root

  property var recentWindows: []
  property string pendingFocusTarget: ""
  property string pendingCursorPosition: ""

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

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (monitor && screens[i].name === monitor.name) return screens[i]
    }
    return screens.length ? screens[0] : null
  }

  function cycle(step) {
    if (panel.active) {
      if (step > 0) panel.next(); else panel.prev()
      return
    }
    root.rememberFocus()
    var apps = root.runningApps()
    if (!apps.length) return
    var current = SwitcherModel.appForWindow(Hyprland.activeToplevel, root.appEntries())
    panel.open(apps, SwitcherModel.initialIndex(apps, current ? current.id : "", step))
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
      root.recentWindows = SwitcherModel.touchWindow(root.recentWindows, apps[i].addresses[0])
      restoreCursorWarps.stop()
      if (!cursorCapture.running) cursorCapture.running = true
      return
    }
  }

  IpcHandler {
    target: "harryxu.super-switcher"
    function altTabNext(): void { root.cycle(1) }
    function altTabPrev(): void { root.cycle(-1) }
    function altTabCancel(): void { panel.cancel() }
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { root.rememberFocus() }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      var windows = Hyprland.toplevels.values || []
      root.recentWindows = root.recentWindows.filter(function(address) {
        for (var i = 0; i < windows.length; i++) if (windows[i].address === address) return true
        return false
      })
      if (panel.active && !root.runningApps().length) panel.cancel()
    }
  }

  SwitcherPanel {
    id: panel
    screen: root.focusedScreen()
    iconSourceFor: function(app) { return root.iconSource(app) }
    onActivated: function(appId) { root.activateApp(appId) }
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
      Hyprland.dispatch("hl.dsp.focus({ window = \"" + target + "\" })")
      Qt.callLater(function() { Hyprland.dispatch("hl.dsp.window.bring_to_top()") })
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
    command: ["hyprctl", "eval", "o.rebind(\"SUPER + TAB\", \"App switcher next\", \"omarchy-shell -q harryxu.super-switcher altTabNext\") o.rebind(\"SUPER + SHIFT + TAB\", \"App switcher prev\", \"omarchy-shell -q harryxu.super-switcher altTabPrev\")"]
  }

  // Shell startup can reapply config bindings after this plugin is loaded.
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
    layerRule.running = true
    registerBindings.running = true
    bindRetry.start()
  }
}
