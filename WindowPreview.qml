import QtQuick
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons as Commons

ClippingRectangle {
  id: root

  property var window: null
  property bool selected: false

  radius: 12
  color: Commons.Color.background
  border.width: root.selected ? 3 : 1
  border.color: root.selected
    ? Qt.tint(Commons.Color.accent, Commons.Util.alpha(Commons.Color.foreground, 0.18))
    : Qt.tint(Commons.Color.background, Commons.Util.alpha(Commons.Color.foreground, 0.32))
  border.pixelAligned: true
  contentInsideBorder: false

  ScreencopyView {
    anchors.centerIn: parent
    constraintSize: Qt.size(Math.max(1, root.width - 2), Math.max(1, root.height - 2))
    captureSource: root.window ? root.window.wayland : null
    live: false
    paintCursor: false
  }
}
