#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# The binding tests invoke standalone Lua to exercise the generated callbacks.
# Run QML syntax and plugin validation separately from the repository root.
# /usr/lib/qt6/bin/qmllint --ignore-settings --only-explicit-categories --syntax error Switcher.qml SwitcherPanel.qml WorkspacePreview.qml
# omarchy plugin validate .
node --test tests/*.test.js
./tests/install.test.sh
