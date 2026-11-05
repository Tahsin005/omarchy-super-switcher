#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

runner="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"
for scale in 1 1.6 2; do
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_CONTROLS_STYLE=Basic \
    QSG_RHI_BACKEND=software QT_SCALE_FACTOR="$scale" \
    "$runner" -input tests/tst_SwitcherIcon.qml
done
