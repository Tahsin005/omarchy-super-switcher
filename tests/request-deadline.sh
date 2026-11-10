#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fixture=$(mktemp -d /tmp/switcher-deadline.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
mkdir -m 700 "$fixture/runtime"
ln -s "$PWD/HyprlandProcess.qml" "$fixture/HyprlandProcess.qml"

cat > "$fixture/shell.qml" <<'EOF'
import QtQuick
import Quickshell

ShellRoot {
  id: root
  property int completed: 0

  HyprlandProcess {
    command: ["sleep", "0.2"]
    running: true
    onExited: function(exitCode, exitStatus) {
      if (root.completed < 6) {
        if (exitCode !== 0 || exitStatus !== 0) {
          console.error("A queued request inherited the previous deadline")
          Qt.exit(1)
          return
        }
        root.completed++
        if (root.completed === 6) command = ["sleep", "10"]
        running = true
      } else if (exitStatus === 0) {
        console.error("The stalled request was allowed to finish")
        Qt.exit(1)
      } else {
        console.log("PASS: each request has a fresh deadline and a stalled child is killed")
        Qt.exit(0)
      }
    }
  }
}
EOF

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= XDG_RUNTIME_DIR="$fixture/runtime" \
  XDG_CONFIG_HOME="$fixture/config" XDG_CACHE_HOME="$fixture/cache" \
  timeout --kill-after=1s 6s qs --no-color -p "$fixture/shell.qml"
