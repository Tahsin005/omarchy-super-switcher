import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// macOS-style application switcher: one icon per running program.
//
// Keyboard contract: Hyprland consumes the SUPER+TAB global binds (exec
// omarchy-shell ... altTabNext/altTabPrev), so the bound key never reaches
// this window. While visible it grabs the keyboard exclusively and receives
// the unbound keys: Super release activates, Escape cancels, Enter activates,
// arrows move the selection.
PanelWindow {
  id: root

  property bool active: false
  property var apps: []
  property int selectedIndex: -1
  property int releaseGeneration: 0
  readonly property bool keyboardReady: root.active && keyCatcher.activeFocus && keyCatcher.Window.active
  readonly property real naturalWidth: root.apps.length ? root.apps.length * root.slotWidth + (root.apps.length - 1) * root.slotSpacing + 2 * root.sidePadding : 0
  readonly property real surfaceWidth: Math.min(root.naturalWidth, Math.max(0, root.width - 2 * root.screenMargin))
  property var iconSourceFor: function(app) { return "" }

  // Application icons in a centered, fixed-spacing row.
  property int iconSize: 105
  property int artworkSize: 84
  property int slotWidth: 96
  property int slotSpacing: 12
  property int sidePadding: 24
  property int surfaceHeight: 144
  property int surfaceRadius: 36
  property int selectionRadius: 20
  property int screenMargin: 32

  signal activated(string appId, string appName)

  function iconSource(app) {
    var src = root.iconSourceFor(app)
    if (!src) return ""
    if (String(src).indexOf("/") === 0) return Util.fileUrl(src)
    if (String(src).indexOf("file:") === 0 || String(src).indexOf("image:") === 0) return src
    return Quickshell.iconPath(src, true)
  }

  onKeyboardReadyChanged: if (root.keyboardReady) root.checkSuperReleased()

  function checkSuperReleased() {
    // A quick tap can release Super before IPC opens the window. No release
    // event will reach us in that case. Once keyboard focus is established,
    // query the compositor's key state to cover that gap without a delay.
    // Later releases are handled by Keys.onReleased as usual.
    var command = "if not (hl.is_key_down(\"Super_L\") or hl.is_key_down(\"Super_R\")) then "
      + "hl.exec_cmd(\"omarchy-shell -q harryxu.super-switcher.switcher acceptRelease " + root.releaseGeneration + "\") end"
    Quickshell.execDetached(["hyprctl", "eval", command])
  }

  IpcHandler {
    target: "harryxu.super-switcher.switcher"
    function acceptRelease(generation: int): void {
      // Ignore a reply from a session that was canceled or already committed.
      if (root.active && generation === root.releaseGeneration) root.activateSelected()
    }
  }

  function open(list, initialIndex) {
    root.releaseGeneration++
    root.apps = list || []
    root.selectedIndex = initialIndex >= 0 && initialIndex < root.apps.length ? initialIndex : 0
    root.active = true
    Qt.callLater(function() {
      if (!root.active) return
      keyCatcher.forceActiveFocus()
      // A new session can begin before the previous window loses focus.
      if (root.keyboardReady) root.checkSuperReleased()
    })
  }

  function next() {
    if (root.apps.length === 0) return
    root.selectedIndex = (root.selectedIndex + 1) % root.apps.length
  }

  function prev() {
    if (root.apps.length === 0) return
    root.selectedIndex = (root.selectedIndex - 1 + root.apps.length) % root.apps.length
  }

  function cancel() {
    root.releaseGeneration++
    root.active = false
    root.apps = []
    root.selectedIndex = -1
  }

  function activateSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.apps.length) {
      root.cancel()
      return
    }
    var app = root.apps[root.selectedIndex]
    var id = app.id
    var name = app.name
    root.cancel()
    root.activated(id, name)
  }

  visible: root.active
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "harryxu-super-switcher"
  WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  anchors { top: true; bottom: true; left: true; right: true }
  mask: Region { item: switcherSurface }

  // Centered switcher surface.
  Rectangle {
    id: switcherSurface
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: root.surfaceWidth
    height: root.surfaceHeight
    radius: root.surfaceRadius
    color: Util.alpha(Color.background, 0.88)
    border.color: Util.alpha(Color.foreground, 0.20)
    border.width: 1
    opacity: root.active ? 1 : 0.96

    ListView {
      id: appRow
      anchors.centerIn: parent
      width: Math.max(0, parent.width - 2 * root.sidePadding)
      height: root.iconSize
      orientation: ListView.Horizontal
      spacing: root.slotSpacing
      clip: root.naturalWidth > root.surfaceWidth
      boundsBehavior: Flickable.StopAtBounds
      keyNavigationEnabled: false
      currentIndex: root.selectedIndex
      model: root.apps

      function revealSelection() {
        if (currentIndex >= 0 && currentIndex < count)
          positionViewAtIndex(currentIndex, ListView.Contain)
      }
      onCurrentIndexChanged: Qt.callLater(appRow.revealSelection)
      onCountChanged: Qt.callLater(appRow.revealSelection)
      onWidthChanged: Qt.callLater(appRow.revealSelection)

      delegate: Item {
        id: item
        required property var modelData
        required property int index

        width: root.slotWidth
        height: root.iconSize

        // Highlight the application selected by keyboard or pointer.
        Rectangle {
          anchors.centerIn: parent
          width: root.slotWidth
          height: root.slotWidth
          radius: root.selectionRadius
          color: Util.alpha(Color.accent, 0.28)
          border.color: Util.alpha(Color.accent, 0.90)
          border.width: 2
          visible: root.selectedIndex === index
        }

        SwitcherIcon {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          width: root.iconSize
          height: root.iconSize
          source: root.iconSource(modelData)
          artworkSize: root.artworkSize
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.selectedIndex = index
          onClicked: {
            root.selectedIndex = index
            root.activateSelected()
          }
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.cancel(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          // Hyprland's global bindings drive navigation; do not double-step.
          event.accepted = true; return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateSelected(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Left) {
          root.prev(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Right) {
          root.next(); event.accepted = true; return
        }
      }
      Keys.onReleased: function(event) {
        // Hyprland delivers the Super release (pressed before this surface
        // gained keyboard focus) with an unmapped keysym: Qt reports key 0,
        // but the native scan code is intact (133 = Super_L, 134 = Super_R).
        // Match by scan code so "release Super to activate" works even for the
        // modifier that was held before the HUD appeared.
        var scan = event.nativeScanCode
        if (event.key === Qt.Key_Meta || scan === 133 || scan === 134) {
          root.activateSelected(); event.accepted = true
        }
      }
    }
  }
}
