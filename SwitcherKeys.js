.pragma library

// At a SUPER+TAB binding, the held Alt/Win positions belong to the logical
// Super modifier. Capture physical codes there, before the IPC/focus handoff:
// Hyprland's keysym query may use the global keymap instead of a device map.
function cycleCommand(step) {
  return "local held = {} "
    + "for _, code in ipairs({64, 108, 133, 134}) do "
    + "if hl.is_key_down(code) then table.insert(held, code) end end "
    + "hl.exec_cmd(\"omarchy-shell -q harryxu.super-switcher cycleHeld "
    + (step < 0 ? "-1" : "1") + " \" .. (#held > 0 and table.concat(held, \",\") or \"none\"))"
}

function bindingCommand() {
  return "o.rebind(\"SUPER + TAB\", \"App switcher next\", function() "
    + cycleCommand(1) + " end) "
    + "o.rebind(\"SUPER + SHIFT + TAB\", \"App switcher prev\", function() "
    + cycleCommand(-1) + " end)"
}

function parseHeldKeys(value) {
  if (value === "none") return []
  var parts = String(value).split(",")
  var codes = []
  for (var i = 0; i < parts.length; i++) {
    if (!/^(64|108|133|134)$/.test(parts[i])) return null
    var code = Number(parts[i])
    if (codes.indexOf(code) < 0) codes.push(code)
  }
  return codes
}

function releaseCommand(codes, generation) {
  var checks = codes.map(function(code) { return "hl.is_key_down(" + code + ")" })
  return "if not (" + (checks.length ? checks.join(" or ") : "false") + ") then "
    + "hl.exec_cmd(\"omarchy-shell -q harryxu.super-switcher.switcher acceptRelease "
    + generation + "\") end"
}

if (typeof module !== "undefined") module.exports = {
  cycleCommand: cycleCommand, bindingCommand: bindingCommand,
  parseHeldKeys: parseHeldKeys, releaseCommand: releaseCommand
}
