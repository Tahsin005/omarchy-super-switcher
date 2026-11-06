import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons
import qs.Ui as Ui
import "SwitcherKeys.js" as SwitcherKeys

// Shared application/workspace switcher. Both modes use the same input grab
// and physical-modifier release tracking.
//
// Keyboard contract: Hyprland consumes SUPER/ALT+TAB global/submap binds, so
// the bound key never reaches
// this window. While visible it grabs the keyboard exclusively and receives
// the unbound keys: modifier release activates, Escape cancels, Enter activates,
// arrows move the selection.
PanelWindow {
  id: root

  property bool active: false
  // Map only after the compositor has isolated its mouse/keyboard bindings.
  property bool inputReady: false
  property string mode: "apps"
  readonly property bool workspaceMode: root.mode === "workspaces"
  property var apps: []
  property int selectedIndex: -1
  property int releaseGeneration: 0
  property int modifierQueryRevision: 0
  property var heldModifierKeys: []
  readonly property bool keyboardReady: root.active && root.inputReady && keyCatcher.activeFocus && keyCatcher.Window.active
  readonly property real naturalWidth: root.apps.length ? root.apps.length * root.slotWidth + (root.apps.length - 1) * root.slotSpacing + 2 * root.sidePadding : 0
  readonly property real surfaceWidth: Math.min(root.naturalWidth, Math.max(0, root.width - 2 * root.screenMargin))
  property var iconSourceFor: function(app) { return "" }
  property var windowIconSourceFor: function(window) { return "" }

  // Application icons in a centered, fixed-spacing row.
  readonly property int iconSize: root.slotWidth
  property int artworkSize: 84
  property int slotWidth: root.workspaceMode ? Math.min(256, Math.max(1, root.width - 2 * (root.screenMargin + root.sidePadding))) : 96
  property int slotSpacing: root.workspaceMode ? 16 : 12
  property int sidePadding: 24
  readonly property real rowHeight: root.workspaceMode ? root.slotWidth * 10 / 16 + 40 : root.iconSize
  readonly property real surfaceHeight: root.rowHeight + 2 * root.verticalPadding
  property int surfaceRadius: root.workspaceMode ? 28 : 36
  property int selectionRadius: 20
  property int screenMargin: 32
  // Equal space above and below the icons; the name lives in the lower inset.
  property int verticalPadding: root.workspaceMode ? 24 : 32
  property int labelHeight: 24
  property int labelMargin: 12

  signal activated(string appId, string appName)
  signal workspaceActivated(string workspaceId)
  signal appScopeChanged(bool currentWorkspaceOnly)

  function iconSource(app) {
    var src = root.iconSourceFor(app)
    if (!src) return ""
    if (String(src).indexOf("/") === 0) return Commons.Util.fileUrl(src)
    if (String(src).indexOf("file:") === 0 || String(src).indexOf("image:") === 0) return src
    return Quickshell.iconPath(src, true)
  }

  onKeyboardReadyChanged: if (root.keyboardReady) root.checkModifierReleased()

  function checkModifierReleased() {
    if (!root.active) return
    // A quick tap can release the modifier before IPC opens the window. No release
    // event will reach us in that case. Once keyboard focus is established,
    // query the compositor's key state to cover that gap without a delay.
    // Later releases are handled by Keys.onReleased as usual.
    root.modifierQueryRevision++
    var command = SwitcherKeys.releaseCommand(root.heldModifierKeys, root.releaseGeneration,
      !root.workspaceMode, root.modifierQueryRevision)
    Quickshell.execDetached(["hyprctl", "eval", command])
  }

  IpcHandler {
    target: "harryxu.super-switcher.switcher"
    function acceptRelease(generation: int): void {
      // Ignore a reply from a session that was canceled or already committed.
      if (root.active && generation === root.releaseGeneration) root.activateSelected()
    }
    function acceptAppScope(generation: int, revision: int, currentWorkspaceOnly: bool): void {
      if (root.active && !root.workspaceMode && generation === root.releaseGeneration
          && revision === root.modifierQueryRevision)
        root.appScopeChanged(currentWorkspaceOnly)
    }
  }

  function open(list, initialIndex, heldKeys, mode) {
    pointerGate.reset()
    root.releaseGeneration++
    root.mode = mode || "apps"
    root.heldModifierKeys = heldKeys || []
    root.apps = list || []
    root.selectedIndex = initialIndex >= 0 && initialIndex < root.apps.length ? initialIndex : 0
    root.active = true
    Qt.callLater(function() {
      if (!root.active) return
      keyCatcher.forceActiveFocus()
      // A new session can begin before the previous window loses focus.
      if (root.keyboardReady) root.checkModifierReleased()
    })
  }

  function next() {
    if (root.apps.length === 0) return
    pointerGate.reset()
    root.selectedIndex = (root.selectedIndex + 1) % root.apps.length
  }

  function prev() {
    if (root.apps.length === 0) return
    pointerGate.reset()
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
    var workspace = root.workspaceMode
    root.cancel()
    if (workspace) root.workspaceActivated(id)
    else root.activated(id, name)
  }

  visible: root.active && root.inputReady
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "harryxu-super-switcher"
  WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  anchors { top: true; bottom: true; left: true; right: true }
  mask: Region { item: switcherSurface }

  Ui.PointerMoveGate {
    id: pointerGate
    // Filtering changes the centered surface's size and position. Compare
    // pointer motion in window coordinates so that resize is not a hover move.
    referenceItem: switcherSurface.parent
  }

  // Centered switcher surface.
  Rectangle {
    id: switcherSurface
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: root.surfaceWidth
    height: root.surfaceHeight
    radius: root.surfaceRadius
    color: Commons.Util.alpha(Commons.Color.background, root.workspaceMode ? 0.97 : 0.88)
    border.color: Commons.Util.alpha(Commons.Color.foreground, 0.20)
    border.width: 1
    opacity: root.active ? 1 : 0.96

    ListView {
      id: appRow
      anchors.horizontalCenter: parent.horizontalCenter
      y: root.verticalPadding
      width: Math.max(0, parent.width - 2 * root.sidePadding)
      height: root.rowHeight
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
        id: entryTile
        required property var modelData
        required property int index

        width: root.slotWidth
        height: root.rowHeight

        // Highlight the application selected by keyboard or pointer.
        Rectangle {
          anchors.centerIn: parent
          width: root.slotWidth
          height: root.rowHeight
          radius: root.workspaceMode ? 16 : root.selectionRadius
          color: Commons.Util.alpha(Commons.Color.accent, root.workspaceMode ? 0.08 : 0.28)
          border.color: Commons.Util.alpha(Commons.Color.accent, 0.40)
          border.width: root.workspaceMode ? 0 : 2
          visible: root.selectedIndex === index
        }

        SwitcherIcon {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          width: root.iconSize
          height: root.iconSize
          source: root.workspaceMode ? "" : root.iconSource(modelData)
          artworkSize: root.artworkSize
          visible: !root.workspaceMode
        }

        Loader {
          active: root.workspaceMode
          x: 8
          y: 8
          width: parent.width - 16
          height: parent.height - 44
          sourceComponent: WorkspacePreview {
            workspace: entryTile.modelData ? entryTile.modelData.workspace || null : null
            iconSourceFor: root.windowIconSourceFor
            selected: root.selectedIndex === entryTile.index
          }
        }

        Text {
          visible: root.workspaceMode
          x: 8
          y: parent.height - 32
          width: parent.width - 16
          height: 24
          text: entryTile.modelData ? String(entryTile.modelData.name || entryTile.modelData.id || "") : ""
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          maximumLineCount: 1
          color: Commons.Color.foreground
          font.family: Commons.Style.fontFamily
          font.pixelSize: 13
          font.weight: root.selectedIndex === entryTile.index ? Font.DemiBold : Font.Medium
        }

        MouseArea {
          id: pointerArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // Mapping the panel or scrolling the row can put a tile underneath
          // a stationary pointer. Only actual movement should replace the
          // keyboard selection, especially during a quick Alt+Tab release.
          onEntered: {
            if (pointerGate.moved(pointerArea, { x: mouseX, y: mouseY }))
              root.selectedIndex = index
          }
          onPositionChanged: function(mouse) {
            if (pointerGate.moved(pointerArea, mouse)) root.selectedIndex = index
          }
          onClicked: {
            root.selectedIndex = index
            root.activateSelected()
          }
        }
      }
    }

    Text {
      id: selectedAppLabel
      readonly property var app: root.selectedIndex >= 0 && root.selectedIndex < root.apps.length ? root.apps[root.selectedIndex] : null
      readonly property real iconCenter: appRow.x + (appRow.currentItem ? appRow.currentItem.x + root.slotWidth / 2 - appRow.contentX : appRow.width / 2)
      text: app ? String(app.name || app.id || "") : ""
      textFormat: Text.PlainText
      visible: !root.workspaceMode && !!app && !!appRow.currentItem
      // Keep the name centered under its icon, including while the row scrolls.
      // At either edge, shorten long names rather than spilling out of the panel.
      width: Math.max(0, Math.min(200, 2 * Math.min(iconCenter - root.labelMargin, switcherSurface.width - root.labelMargin - iconCenter)))
      height: root.labelHeight
      x: iconCenter - width / 2
      y: appRow.y + appRow.height + (root.verticalPadding - height) / 2
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
      maximumLineCount: 1
      color: Commons.Color.foreground
      font.family: Commons.Style.fontFamily
      font.pixelSize: 13
      font.weight: Font.Medium
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_A && !root.workspaceMode) {
          if (!event.isAutoRepeat) {
            root.modifierQueryRevision++
            root.appScopeChanged(true)
          }
          event.accepted = true; return
        }
        if (event.key === Qt.Key_Escape) {
          root.cancel(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          // Hyprland's submap bindings drive navigation; do not double-step.
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
        // A modifier held before focus can arrive as key 0. Its physical
        // position can also be Alt after a per-device Alt/Win swap. Check
        // the keys captured by the actual shortcut instead of guessing from
        // this event's symbol or scan code. Tab/Shift release must not accept.
        if (!event.isAutoRepeat) root.checkModifierReleased()
      }
    }
  }
}
