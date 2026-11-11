.pragma library

var submapName = "harryxu-super-switcher"
// A quick release commits the selection. Holding through this delay opens the panel.
var holdThresholdMs = 60

// Capture physical Alt/Win positions before the IPC handoff. Hyprland's keysym
// query can use the global keymap and miss a per-device altwin:swap_alt_win mapping.
function cycleCommand(step, mode, fromBinding) {
  var localScope = '(hl.is_key_down("a") or hl.is_key_down("A"))'
  var capture = "local held = {} "
    + "for _, code in ipairs({64, 108, 133, 134}) do "
    + "if hl.is_key_down(code) then table.insert(held, code) end end "
    + "local keycodes = #held > 0 and table.concat(held, \",\") or \"none\" "
  var direction = step < 0 ? "-1" : "1"
  if (fromBinding) {
    var shortcutMode = mode === "apps" ? localScope + ' and "localApps" or "apps"' : '"' + mode + '"'
    return capture
      + "shortcut.id = shortcut.id + 1 shortcut.key = shortcut.last_key shortcut.modifiers = held "
      + "local mode = " + shortcutMode + " "
      + 'hl.exec_cmd("omarchy-shell -q harryxu.super-switcher shortcutPressed ' + direction
      + ' " .. keycodes .. " " .. mode .. " " .. shortcut.id)'
  }
  var method = mode === "workspaces" ? '"workspaceCycleHeld"'
    : mode === "windows" ? '"windowCycleHeld"'
    : localScope + ' and "localCycleHeld" or "cycleHeld"'
  return capture
    + "local method = " + method + " "
    + 'hl.exec_cmd("omarchy-shell -q harryxu.super-switcher " .. method .. " ' + direction + ' " .. keycodes)'
}

function trackShortcutCommand() {
  // The keyboard event precedes the binding callback. Capture the actual XKB
  // code so repeat survives a layout or modifier mapping different from the default.
  return "local shortcut = _G.harryxu_super_switcher_shortcut "
    + "if not shortcut then shortcut = { id = 0 } _G.harryxu_super_switcher_shortcut = shortcut "
    + "shortcut.is_held = function(released) "
    + "if not shortcut.key or shortcut.key == released or not hl.is_key_down(shortcut.key) then return false end "
    + "for _, code in ipairs(shortcut.modifiers) do "
    + "if code ~= released and hl.is_key_down(code) then return true end end return false end "
    + 'shortcut.listener = hl.on("input.keyboard.key", function(code, _, event) '
    + "if event == 1 then shortcut.last_key = code "
    + "elseif event == 0 and shortcut.key and not shortcut.is_held(code) then shortcut.key = nil end "
    + "end) end "
}

function shortcutHeldCommand(press) {
  return "local shortcut = _G.harryxu_super_switcher_shortcut "
    + "return shortcut ~= nil and shortcut.id == " + press
    + ' and hl.get_current_submap() == "' + submapName + '" and shortcut.is_held()'
}

function bindingCommand() {
  // hl.unbind (used by o.rebind) removes a chord across ALL submaps in
  // Hyprland 0.56. Register all global chords before their submap copies.
  // Escape is registered once per compositor Lua state: unbinding it would
  // also remove unrelated Escape shortcuts belonging to the user.
  var shortcuts = [
    ["SUPER + TAB", "App switcher next", 1, "apps"],
    ["SUPER + SHIFT + TAB", "App switcher prev", -1, "apps"],
    ["SUPER + grave", "Window switcher next", 1, "windows"],
    ["SUPER + SHIFT + grave", "Window switcher prev", -1, "windows"],
    ["ALT + TAB", "Workspace switcher next", 1, "workspaces"],
    ["ALT + SHIFT + TAB", "Workspace switcher prev", -1, "workspaces"]
  ]
  var globals = shortcuts.map(function(shortcut) {
    return "o.rebind(\"" + shortcut[0] + "\", \"" + shortcut[1] + "\", function() "
      + cycleCommand(shortcut[2], shortcut[3], true) + " end) "
  }).join("")
  var submap = shortcuts.map(function(shortcut) {
    return "hl.bind(\"" + shortcut[0] + "\", function() " + cycleCommand(shortcut[2], shortcut[3], true)
      + " end, { description = \"" + shortcut[1] + "\" }) "
  }).join("")
  // The submap suppresses Super+click window drags while the panel is open.
  // Escape resets it before calling IPC, even if the shell has crashed.
  return trackShortcutCommand() + globals + "hl.define_submap(\"" + submapName + "\", function() " + submap
    + "if not _G.harryxu_super_switcher_escape then "
    + "hl.bind(\"Escape\", function() "
    + "hl.dispatch(hl.dsp.submap(\"reset\")) "
    + "hl.exec_cmd(\"omarchy-shell -q harryxu.super-switcher altTabCancel\") "
    + "end, { ignore_mods = true, description = \"Cancel switcher\" }) "
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

function pendingCommand(codes, generation) {
  var keys = codes.map(function(code) { return "[" + code + "] = true" }).join(", ")
  // Hyprland emits the release event before clearing that key's pressed state.
  // Ignore the released code when checking the other captured modifiers.
  return "local state = _G.harryxu_super_switcher_pending or {} "
    + "_G.harryxu_super_switcher_pending = state "
    + "local keys = {" + keys + "} "
    + "local function any_held(released) "
    + "for code in pairs(keys) do if code ~= released and hl.is_key_down(code) then return true end end "
    + "return false end "
    + "local function stop() "
    + "if state.release then state.release:remove() state.release = nil end "
    + "if state.timer then state.timer:set_enabled(false) end "
    + "state.deadline = nil end "
    + "local function finish(held) stop() "
    + "local method = held and \"acceptHold\" or \"acceptRelease\" "
    + "hl.exec_cmd(\"omarchy-shell -q harryxu.super-switcher.switcher \" .. method .. \" " + generation + "\") end "
    + "if not any_held() then finish(false) return end "
    + "stop() "
    + "state.release = hl.on(\"input.keyboard.key\", function(code, _, event) "
    + "if event == 0 and keys[code] and not any_held(code) then finish(false) end end) "
    + "state.deadline = function() finish(any_held()) end "
    // Hyprland reclaims a oneshot timer only after it fires. Keep one reusable
    // timer and stop it on release or on its first callback.
    + "if state.timer then state.timer:set_timeout(" + holdThresholdMs + ") "
    + "else state.timer = hl.timer(function() state.deadline() end, "
    + "{ timeout = " + holdThresholdMs + ", type = \"repeat\" }) end"
}

function releaseCommand(codes, generation, trackAppScope, revision) {
  var checks = codes.map(function(code) { return "hl.is_key_down(" + code + ")" })
  return "if not (" + (checks.length ? checks.join(" or ") : "false") + ") then "
    + "hl.exec_cmd(\"omarchy-shell -q harryxu.super-switcher.switcher acceptRelease "
    + generation + "\") "
    + (trackAppScope ? "else hl.exec_cmd(\"omarchy-shell -q harryxu.super-switcher.switcher acceptAppScope "
      + generation + " " + revision + " \" .. tostring(hl.is_key_down(\"a\") or hl.is_key_down(\"A\"))) " : "")
    + "end"
}

if (typeof module !== "undefined") module.exports = {
  cycleCommand: cycleCommand, bindingCommand: bindingCommand, shortcutHeldCommand: shortcutHeldCommand,
  parseHeldKeys: parseHeldKeys, pendingCommand: pendingCommand, releaseCommand: releaseCommand,
  submapName: submapName, submapCommand: submapCommand
}
