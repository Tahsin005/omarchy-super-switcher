import QtQuick
import Quickshell.Io

Process {
  id: root

  // A successor started from onExited can keep running true across the handoff.
  onStarted: deadline.restart()
  onRunningChanged: if (!root.running) deadline.stop()

  readonly property Timer deadline: Timer {
    interval: 1000
    onTriggered: root.signal(9) // SIGKILL also works if SIGTERM is ignored.
  }
}
