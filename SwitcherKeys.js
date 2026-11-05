.pragma library

var submapName = "harryxu-super-switcher"

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
  // hl.unbind (used by o.rebind) removes a chord across ALL submaps in
  // Hyprland 0.56. Register both global chords before their submap copies.
  // Escape is registered once per compositor Lua state: unbinding it would
  // also remove unrelated Escape shortcuts belonging to the user.
  return "o.rebind(\"SUPER + TAB\", \"App switcher next\", function() "
    + cycleCommand(1) + " end) "
    + "o.rebind(\"SUPER + SHIFT + TAB\", \"App switcher prev\", function() "
    + cycleCommand(-1) + " end) "
    + "hl.define_submap(\"" + submapName + "\", function() "
    + "hl.bind(\"SUPER + TAB\", function() " + cycleCommand(1)
    + " end, { description = \"App switcher next\" }) "
    + "hl.bind(\"SUPER + SHIFT + TAB\", function() " + cycleCommand(-1)
    + " end, { description = \"App switcher prev\" }) "
    + "if not _G.harryxu_super_switcher_escape then "
    + "hl.bind(\"Escape\", function() "
    + "hl.dispatch(hl.dsp.submap(\"reset\")) "
    + "hl.exec_cmd(\"omarchy-shell -q harryxu.super-switcher altTabCancel\") "
    + "end, { ignore_mods = true, description = \"Cancel app switcher\" }) "
    + "_G.harryxu_super_switcher_escape = true end end)"
}

function submapCommand(active) {
  if (active) {
    // Also covers IPC opens that race the startup/reload registration process.
    return bindingCommand() + " hl.dispatch(hl.dsp.submap(\"" + submapName + "\"))"
  }
  // Never reset another application's submap during cleanup or shell startup.
  return "if hl.get_current_submap() == \"" + submapName + "\" then "
    + "hl.dispatch(hl.dsp.submap(\"reset\")) end"
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
  parseHeldKeys: parseHeldKeys, releaseCommand: releaseCommand,
  submapName: submapName, submapCommand: submapCommand
}
