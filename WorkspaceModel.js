.pragma library

function isRegular(workspace) {
  return !!workspace && Number.isInteger(workspace.id) && workspace.id !== 0
    && String(workspace.name || "").indexOf("special:") !== 0
}

function buildWorkspaces(workspaces) {
  return workspaces.filter(isRegular).map(function(workspace) {
    return { id: String(workspace.id), name: String(workspace.name || workspace.id), workspace: workspace }
  }).sort(function(a, b) {
    var ai = Number(a.id), bi = Number(b.id)
    if (ai > 0 && bi > 0) return ai - bi
    if (ai > 0) return -1
    if (bi > 0) return 1
    return a.name.localeCompare(b.name) || ai - bi
  })
}

function luaQuote(value) {
  return '"' + String(value).replace(/[\\"\x00-\x1f\x7f]/g, function(character) {
    if (character === '"' || character === "\\") return "\\" + character
    // Three decimal digits prevent a following digit from joining the escape.
    return "\\" + ("00" + character.charCodeAt(0)).slice(-3)
  }) + '"'
}

function focusCommand(workspace) {
  if (!isRegular(workspace)) return ""
  // Negative IDs are assigned to named workspaces. A numeric selector would
  // be interpreted as a relative workspace offset, so use its exact name.
  var selector = workspace.id > 0 ? String(workspace.id) : "name:" + workspace.name
  return "hl.dsp.focus({ workspace = " + luaQuote(selector) + " })"
}

// Hyprland reports window positions in logical, global coordinates, but
// monitor dimensions in physical pixels. Odd transforms rotate the output.
function monitorGeometry(monitor) {
  var ipc = monitor ? monitor.lastIpcObject || {} : {}
  var scale = Number(ipc.scale || (monitor && monitor.scale)) || 1
  var width = Number(ipc.width || (monitor && monitor.width)) || 1600
  var height = Number(ipc.height || (monitor && monitor.height)) || 1000
  if (Number(ipc.transform || 0) % 2) {
    var previous = width
    width = height
    height = previous
  }
  return {
    x: Number(ipc.x || (monitor && monitor.x)) || 0,
    y: Number(ipc.y || (monitor && monitor.y)) || 0,
    width: width / scale, height: height / scale
  }
}

function windowGeometry(window, monitor, index, count) {
  var ipc = window ? window.lastIpcObject || {} : {}
  if (ipc.at && ipc.size && ipc.size[0] > 0 && ipc.size[1] > 0) {
    return { x: ipc.at[0] - monitor.x, y: ipc.at[1] - monitor.y,
      width: ipc.size[0], height: ipc.size[1] }
  }
  // A new window can precede its IPC geometry. Give it a useful placeholder
  // until refreshToplevels supplies the real layout.
  var columns = Math.ceil(Math.sqrt(Math.max(1, count)))
  var rows = Math.ceil(Math.max(1, count) / columns)
  return { x: index % columns * monitor.width / columns,
    y: Math.floor(index / columns) * monitor.height / rows,
    width: monitor.width / columns, height: monitor.height / rows }
}

if (typeof module !== "undefined") module.exports = {
  isRegular: isRegular, buildWorkspaces: buildWorkspaces,
  monitorGeometry: monitorGeometry, windowGeometry: windowGeometry,
  focusCommand: focusCommand
}
