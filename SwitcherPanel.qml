import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons
import qs.Ui as Ui
import "SwitcherKeys.js" as SwitcherKeys

// All modes share the same input grab and physical-modifier release tracking.
//
// Hyprland consumes the global/submap cycle bindings. While visible, the panel
// grabs the keyboard for modifier release, Escape, Enter, and arrow keys.
PanelWindow {
  id: root

  property bool active: false
  // A pending selection can cycle and activate without mapping the window.
  property bool showRequested: false
  property bool inputReady: false
  property string mode: "apps"
  readonly property bool appMode: root.mode === "apps"
  readonly property bool windowMode: root.mode === "windows"
  readonly property bool workspaceMode: root.mode === "workspaces"
  property var windowApp: null
  property bool workspaceLivePreview: false
  property bool roundedBorders: false
  property var apps: []
  property int selectedIndex: -1
  property int releaseGeneration: 0
  property int modifierQueryRevision: 0
  property bool modifierQueryPending: false
  property var heldModifierKeys: []
  readonly property bool keyboardReady: root.active && root.inputReady && keyCatcher.activeFocus && keyCatcher.Window.active
  readonly property real naturalWidth: root.apps.length ? root.apps.length * root.slotWidth + (root.apps.length - 1) * root.slotSpacing + 2 * root.sidePadding : 0
  readonly property real surfaceWidth: Math.min(root.naturalWidth, Math.max(0, root.width - 2 * root.screenMargin))
  property var iconSourceFor: function(app) { return "" }
  property var windowIconSourceFor: function(window) { return "" }

  // Icons and previews use the same centered row, with wider slots for previews.
  readonly property int iconSize: root.slotWidth
  property int artworkSize: 84
  property int slotWidth: root.appMode ? 96 : Math.min(256, Math.max(1, root.width - 2 * (root.screenMargin + root.sidePadding)))
  property int slotSpacing: root.appMode ? 12 : 16
  property int sidePadding: 24
  readonly property real rowHeight: root.appMode ? root.iconSize : root.slotWidth * 10 / 16 + 40
  readonly property real surfaceHeight: root.rowHeight + 2 * root.verticalPadding + root.windowHeaderHeight
  property int surfaceRadius: root.roundedBorders ? (root.appMode ? 36 : 28) : 0
  property int selectionRadius: root.roundedBorders ? 20 : 0
  property int screenMargin: 32
  // Equal space above and below the icons; the name lives in the lower inset.
  property int verticalPadding: root.appMode ? 32 : 24
  property int labelHeight: 24
  property int labelMargin: 12
  readonly property int labelFontSize: 13
  readonly property int windowHeaderHeight: root.windowMode && root.windowApp ? root.labelHeight : 0

  signal activated(string appId, string appName)
  signal windowActivated(string address)
  signal workspaceActivated(string workspaceId)
  signal appScopeChanged(bool currentWorkspaceOnly)
  signal quitRequested(string appId)

  function iconSource(app) {
    var src = root.iconSourceFor(app)
    if (!src) return ""
    if (String(src).indexOf("/") === 0) return Commons.Util.fileUrl(src)
    if (String(src).indexOf("file:") === 0 || String(src).indexOf("image:") === 0) return src
    return Quickshell.iconPath(src, true)
  }

  onKeyboardReadyChanged: if (root.keyboardReady) root.checkModifierReleased()
  onReleaseGenerationChanged: root.modifierQueryPending = false

  function checkModifierReleased() {
    if (!root.keyboardReady) return
    // Recheck after the focus handoff, then on subsequent key releases.
    root.modifierQueryRevision++
    if (releaseCheck.running) root.modifierQueryPending = true
    else root.startModifierQuery()
  }

  function startModifierQuery() {
    root.modifierQueryPending = false
    if (!root.keyboardReady) return
    releaseCheck.generation = root.releaseGeneration
    releaseCheck.command = ["hyprctl", "eval", SwitcherKeys.releaseCommand(root.heldModifierKeys,
      releaseCheck.generation, root.appMode, root.modifierQueryRevision)]
    releaseCheck.running = true
  }

  HyprlandProcess {
    id: releaseCheck
    property int generation: 0
    onExited: function(exitCode, exitStatus) {
      if (generation === root.releaseGeneration && (exitCode !== 0 || exitStatus !== 0)) {
        root.cancel()
      } else if (root.modifierQueryPending) {
        root.startModifierQuery()
      }
    }
  }

  IpcHandler {
    target: "harryxu.super-switcher.switcher"
    function acceptRelease(generation: int): void {
      // Ignore a reply from a session that was canceled or already committed.
      if (root.active && generation === root.releaseGeneration) root.activateSelected()
    }
    function acceptHold(generation: int): void {
      if (root.active && generation === root.releaseGeneration) root.showRequested = true
    }
    function acceptAppScope(generation: int, revision: int, currentWorkspaceOnly: bool): void {
      if (root.active && root.appMode && generation === root.releaseGeneration
          && revision === root.modifierQueryRevision)
        root.appScopeChanged(currentWorkspaceOnly)
    }
  }

  function checkPendingHold() {
    if (!root.active || root.showRequested || !root.heldModifierKeys.length || holdCheck.running) return
    holdCheck.generation = root.releaseGeneration
    holdCheck.command = ["hyprctl", "eval", SwitcherKeys.pendingCommand(root.heldModifierKeys, holdCheck.generation)]
    holdCheck.running = true
  }

  HyprlandProcess {
    id: holdCheck
    property int generation: 0
    onExited: function(exitCode, exitStatus) {
      if (generation !== root.releaseGeneration) root.checkPendingHold()
      else if (exitCode !== 0 || exitStatus !== 0) root.cancel()
    }
  }

  function open(list, initialIndex, heldKeys, mode) {
    pointerGate.reset()
    root.releaseGeneration++
    root.showRequested = false
    root.mode = mode || "apps"
    root.heldModifierKeys = heldKeys || []
    root.apps = list || []
    root.selectedIndex = initialIndex >= 0 && initialIndex < root.apps.length ? initialIndex : 0
    root.active = true
    // Modifier release can beat the IPC handoff. Commit immediately if no
    // modifier is held.
    if (!root.heldModifierKeys.length) root.activateSelected()
    else root.checkPendingHold()
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
    root.showRequested = false
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
    var mode = root.mode
    root.cancel()
    if (mode === "workspaces") root.workspaceActivated(id)
    else if (mode === "windows") root.windowActivated(id)
    else root.activated(id, name)
  }

  function quitSelected() {
    if (!root.active || !root.appMode || root.selectedIndex < 0 || root.selectedIndex >= root.apps.length) return
    root.quitRequested(root.apps[root.selectedIndex].id)
  }

  visible: root.showRequested && root.inputReady
  onVisibleChanged: if (root.visible) keyCatcher.forceActiveFocus()
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "harryxu-super-switcher"
  WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
    color: Commons.Util.alpha(Commons.Color.background, root.appMode ? 0.88 : 0.97)
    border.color: Commons.Util.alpha(Commons.Color.foreground, 0.20)
    border.width: 1
    opacity: root.active ? 1 : 0.96

    Loader {
      active: root.visible && root.windowHeaderHeight > 0
      anchors.horizontalCenter: parent.horizontalCenter
      y: root.verticalPadding / 2
      height: root.windowHeaderHeight

      sourceComponent: Row {
        id: appHeader
        spacing: 6

        SwitcherIcon {
          id: headerIcon
          anchors.verticalCenter: parent.verticalCenter
          width: root.labelFontSize
          height: width
          artworkSize: width
          source: root.windowApp ? root.iconSource(root.windowApp) : ""
        }

        Text {
          width: Math.min(implicitWidth, Math.max(0, switcherSurface.width - 2 * root.sidePadding - headerIcon.width - appHeader.spacing))
          height: appHeader.height
          text: root.windowApp ? String(root.windowApp.name || root.windowApp.id || "") : ""
          textFormat: Text.PlainText
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          color: Commons.Color.foreground
          font.family: Commons.Style.fontFamily
          font.pixelSize: root.labelFontSize
          font.weight: Font.DemiBold
        }
      }
    }

    ListView {
      id: appRow
      anchors.horizontalCenter: parent.horizontalCenter
      y: root.verticalPadding + root.windowHeaderHeight
      width: Math.max(0, parent.width - 2 * root.sidePadding)
      height: root.rowHeight
      orientation: ListView.Horizontal
      spacing: root.slotSpacing
      clip: root.naturalWidth > root.surfaceWidth
      boundsBehavior: Flickable.StopAtBounds
      keyNavigationEnabled: false
      currentIndex: count > 0 ? root.selectedIndex : -1
      // Do not instantiate icons or start captures for a quick tap.
      model: root.visible ? root.apps : []

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
        readonly property bool selected: root.selectedIndex === entryTile.index
        readonly property var window: root.windowMode && entryTile.modelData ? entryTile.modelData.window : null

        width: root.slotWidth
        height: root.rowHeight

        // Highlight the entry selected by keyboard or pointer.
        Rectangle {
          anchors.centerIn: parent
          width: root.slotWidth
          height: root.rowHeight
          radius: root.roundedBorders ? (root.appMode ? root.selectionRadius : 16) : 0
          color: Commons.Util.alpha(Commons.Color.accent, root.appMode ? 0.28 : 0.08)
          border.color: Commons.Util.alpha(Commons.Color.accent, 0.40)
          border.width: root.appMode ? 2 : 0
          visible: entryTile.selected
        }

        SwitcherIcon {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          width: root.iconSize
          height: root.iconSize
          source: root.appMode ? root.iconSource(modelData) : ""
          artworkSize: root.artworkSize
          visible: root.appMode
        }

        Loader {
          active: !root.appMode
          x: 8
          y: 8
          width: parent.width - 16
          height: parent.height - 44
          sourceComponent: root.windowMode ? windowPreview : workspacePreview
        }

        Component {
          id: workspacePreview
          WorkspacePreview {
            workspace: entryTile.modelData ? entryTile.modelData.workspace || null : null
            iconSourceFor: root.windowIconSourceFor
            selected: entryTile.selected
            live: root.workspaceLivePreview
            roundedBorders: root.roundedBorders
          }
        }

        Component {
          id: windowPreview
          WindowPreview {
            window: entryTile.window
            selected: entryTile.selected
            roundedBorders: root.roundedBorders
          }
        }

        Text {
          readonly property var entry: entryTile.modelData
          visible: root.workspaceMode || (root.windowMode && entryTile.selected)
          x: 8
          y: parent.height - 32
          width: parent.width - 16
          height: 24
          text: (entryTile.window ? entryTile.window.title : "") || (entry ? String(entry.name || entry.id || "") : "")
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          maximumLineCount: 1
          color: Commons.Color.foreground
          font.family: Commons.Style.fontFamily
          font.pixelSize: root.labelFontSize
          font.weight: entryTile.selected ? Font.DemiBold : Font.Medium
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
      visible: root.appMode && !!app && !!appRow.currentItem
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
      font.pixelSize: root.labelFontSize
      font.weight: Font.Medium
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Q) {
          // Holding Q must not quit successive apps as the list shrinks.
          if (!event.isAutoRepeat) root.quitSelected()
          event.accepted = true; return
        }
        if (event.key === Qt.Key_A && root.appMode) {
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
