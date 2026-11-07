import QtQuick
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons as Commons
import "WorkspaceModel.js" as WorkspaceModel

Item {
  id: root

  property var workspace: null
  property var iconSourceFor: function(window) { return "" }
  property bool selected: false
  property bool live: false
  property real cornerRadius: 12
  readonly property var windows: workspace && workspace.toplevels ? workspace.toplevels.values : []
  readonly property var geometry: WorkspaceModel.monitorGeometry(workspace ? workspace.monitor : null)
  readonly property real previewScale: Math.min(width / geometry.width, height / geometry.height)

  // Letterbox outputs with different aspect ratios, preserving window layout.
  ClippingRectangle {
    id: desktop
    anchors.centerIn: parent
    width: root.geometry.width * root.previewScale
    height: root.geometry.height * root.previewScale
    color: Commons.Color.background
    radius: root.cornerRadius
    border.width: root.selected ? 3 : 1
    border.color: root.selected
      ? Qt.tint(Commons.Color.accent, Commons.Util.alpha(Commons.Color.foreground, 0.18))
      : Qt.tint(Commons.Color.background, Commons.Util.alpha(Commons.Color.foreground, 0.32))
    border.pixelAligned: true
    // Keep the layout fixed as the focus border changes thickness. Content
    // clips to the rounded frame, including windows touching an output edge.
    contentInsideBorder: false

    Repeater {
      model: root.windows

      Rectangle {
        id: windowTile
        required property var modelData
        required property int index
        readonly property var ipc: modelData ? modelData.lastIpcObject || {} : {}
        readonly property var bounds: WorkspaceModel.windowGeometry(modelData, root.geometry, index, root.windows.length)
        x: bounds.x * root.previewScale
        y: bounds.y * root.previewScale
        width: Math.max(1, bounds.width * root.previewScale)
        height: Math.max(1, bounds.height * root.previewScale)
        // Floating and focused windows sit above tiled content.
        z: (ipc.floating ? 1 : 0) + (modelData && modelData.activated ? 2 : 0)
        visible: !!modelData && ipc.mapped !== false && ipc.hidden !== true
        color: Qt.tint(Commons.Color.background, Commons.Util.alpha(Commons.Color.foreground, 0.12))
        border.color: Commons.Util.alpha(Commons.Color.foreground, 0.32)
        border.width: 1
        clip: true

        ScreencopyView {
          id: capture
          anchors.fill: parent
          anchors.margins: 1
          captureSource: windowTile.modelData ? windowTile.modelData.wayland : null
          live: root.live
          paintCursor: false
        }

        // Some clients do not export a surface. Keep their actual position
        // recognizable while the first frame arrives or capture is unavailable.
        Image {
          anchors.centerIn: parent
          width: Math.min(32, parent.width * 0.6, parent.height * 0.6)
          height: width
          source: root.iconSourceFor(windowTile.modelData)
          fillMode: Image.PreserveAspectFit
          visible: !capture.hasContent
        }
      }
    }
  }
}
