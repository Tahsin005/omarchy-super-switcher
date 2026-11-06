const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const { execFileSync } = require("node:child_process")

const context = { module: { exports: {} } }
vm.runInNewContext(fs.readFileSync("SwitcherKeys.js", "utf8").replace(/^\.pragma library\s*/, ""), context)
const keys = context.module.exports
const plain = value => JSON.parse(JSON.stringify(value))

function lua(command, down = [], invokeBinding) {
  const prelude = `
local down = {${down.map(code => `[${code}] = true`).join(",")}}
local bindings = {}
local definingSubmap = ""
local currentSubmap = ""
hl = {
  is_key_down = function(code)
    assert(type(code) == "number", "keysym lookup ignores per-device mappings")
    return down[code] == true
  end,
  exec_cmd = function(command) print(command) end,
  bind = function(chord, callback, options)
    table.insert(bindings, {chord = chord, callback = callback,
      options = options or {}, submap = definingSubmap})
  end,
  define_submap = function(name, callback)
    local previous = definingSubmap
    definingSubmap = name
    callback()
    definingSubmap = previous
  end,
  get_current_submap = function() return currentSubmap end,
  dsp = { submap = function(name) return name end },
  dispatch = function(name) currentSubmap = name == "reset" and "" or name end,
}
o = { rebind = function(chord, description, callback)
  -- Match 0.56: chord removal is NOT limited to the defining submap.
  for i = #bindings, 1, -1 do
    if bindings[i].chord == chord then table.remove(bindings, i) end
  end
  hl.bind(chord, callback, {description = description})
end }
local function invoke(chord, submap)
  for _, binding in ipairs(bindings) do
    if binding.chord == chord and binding.submap == (submap or "") then
      binding.callback()
      return
    end
  end
  error("Missing binding: " .. chord)
end
`
  return execFileSync("lua", ["-"], {
    input: prelude + command + (invokeBinding ? `\ninvoke(${JSON.stringify(invokeBinding)})` : ""),
    encoding: "utf8",
  }).trim()
}

for (const [label, code] of [["left Super", 133], ["right Super", 134], ["swapped left Alt", 64], ["swapped right Alt", 108]]) {
  test(`${label}: shortcut stays open while held and accepts after release`, () => {
    const dispatch = lua(keys.bindingCommand(), [code, 23], "SUPER + TAB")
    assert.equal(dispatch, `omarchy-shell -q harryxu.super-switcher cycleHeld 1 ${code}`)
    const held = keys.parseHeldKeys(dispatch.split(" ").at(-1))
    assert.equal(lua(keys.releaseCommand(held, 9), [code]), "")
    assert.equal(lua(keys.releaseCommand(held, 9), []),
      "omarchy-shell -q harryxu.super-switcher.switcher acceptRelease 9")
  })
}

test("reverse switching ignores Shift, and unrelated Alt cannot prolong the session", () => {
  const dispatch = lua(keys.bindingCommand(), [64, 50, 23], "SUPER + SHIFT + TAB")
  assert.equal(dispatch, "omarchy-shell -q harryxu.super-switcher cycleHeld -1 64")
  const held = keys.parseHeldKeys("64")
  assert.equal(lua(keys.releaseCommand(held, 10), [64, 50, 133]), "")
  assert.equal(lua(keys.releaseCommand(held, 10), [50, 133]),
    "omarchy-shell -q harryxu.super-switcher.switcher acceptRelease 10")
})

test("both held Super positions must be released", () => {
  assert.equal(lua(keys.cycleCommand(1), [64, 134]),
    "omarchy-shell -q harryxu.super-switcher cycleHeld 1 64,134")
  assert.equal(lua(keys.releaseCommand([64, 134], 11), [134]), "")
})

test("release before IPC/focus still accepts, and untrusted code lists are rejected", () => {
  assert.equal(lua(keys.cycleCommand(1), []),
    "omarchy-shell -q harryxu.super-switcher cycleHeld 1 none")
  assert.deepEqual(plain(keys.parseHeldKeys("none")), [])
  assert.equal(lua(keys.releaseCommand([], 12), []),
    "omarchy-shell -q harryxu.super-switcher.switcher acceptRelease 12")
  assert.deepEqual(plain(keys.parseHeldKeys("64,64,134")), [64, 134])
  for (const value of ["", "23", "64,", "64); os.exit()", "1e2", "-1"])
    assert.equal(keys.parseHeldKeys(value), null)
})

test("startup retries keep app/workspace bindings without duplicating Escape or removing user binds", () => {
  lua(`
    hl.bind("Escape", function() end)
    hl.bind("SUPER + mouse:272", function() end, {mouse = true})
    hl.bind("SUPER + mouse:273", function() end, {mouse = true})
    hl.define_submap("user-mode", function() hl.bind("Escape", function() end) end)
    ${keys.bindingCommand()}
    ${keys.bindingCommand()}
    ${keys.bindingCommand()}
    assert(#bindings == 13, "Expected 4 user bindings and 9 switcher bindings")
    local counts = {}
    for _, binding in ipairs(bindings) do
      local key = binding.submap .. ":" .. binding.chord
      counts[key] = (counts[key] or 0) + 1
      if binding.submap == "${keys.submapName}" then
        assert(not binding.options.mouse, "Drag/resize must remain outside the switcher mode")
        assert(not binding.chord:find("mouse"), "Clicks and wheel events must reach QML")
      end
    end
    for _, map in ipairs({"", "${keys.submapName}"}) do
      assert(counts[map .. ":SUPER + TAB"] == 1)
      assert(counts[map .. ":SUPER + SHIFT + TAB"] == 1)
      assert(counts[map .. ":ALT + TAB"] == 1)
      assert(counts[map .. ":ALT + SHIFT + TAB"] == 1)
    end
    assert(counts[":Escape"] == 1 and counts["user-mode:Escape"] == 1)
    assert(counts["${keys.submapName}:Escape"] == 1)
  `)
})

test("workspace shortcuts track Option and remapped Win positions through release in both submaps", () => {
  for (const code of [64, 108, 133, 134]) {
    for (const [chord, step] of [["ALT + TAB", 1], ["ALT + SHIFT + TAB", -1]]) {
      for (const submap of ["", keys.submapName]) {
        const dispatch = lua(`${keys.bindingCommand()} invoke("${chord}", "${submap}")`, [code, 23, 50])
        assert.equal(dispatch, `omarchy-shell -q harryxu.super-switcher workspaceCycleHeld ${step} ${code}`)
        const held = keys.parseHeldKeys(dispatch.split(" ").at(-1))
        assert.equal(lua(keys.releaseCommand(held, 15), [code]), "")
        assert.equal(lua(keys.releaseCommand(held, 15), [23, 50]),
          "omarchy-shell -q harryxu.super-switcher.switcher acceptRelease 15")
      }
    }
  }
})

test("workspace quick release follows the same release-before-focus path", () => {
  assert.equal(lua(keys.cycleCommand(-1, "workspaces")),
    "omarchy-shell -q harryxu.super-switcher workspaceCycleHeld -1 none")
})

test("submap navigation preserves per-device modifier tracking in both directions", () => {
  for (const [chord, step] of [["SUPER + TAB", 1], ["SUPER + SHIFT + TAB", -1]]) {
    assert.equal(lua(`${keys.submapCommand(true)}
      assert(currentSubmap == "${keys.submapName}")
      invoke("${chord}", currentSubmap)`, [64]),
    `omarchy-shell -q harryxu.super-switcher cycleHeld ${step} 64`)
  }
})

test("Escape restores global bindings before contacting the shell, even with Super held", () => {
  assert.equal(lua(`${keys.submapCommand(true)}
    for _, binding in ipairs(bindings) do
      if binding.submap == currentSubmap and binding.chord == "Escape" then
        assert(binding.options.ignore_mods)
      end
    end
    local exec = hl.exec_cmd
    hl.exec_cmd = function(command)
      assert(currentSubmap == "", "Recovery must not depend on a live shell")
      exec(command)
    end
    invoke("Escape", currentSubmap)`), "omarchy-shell -q harryxu.super-switcher altTabCancel")
})

test("cleanup leaves the switcher mode and does not reset someone else's mode", () => {
  lua(`${keys.submapCommand(true)}
    ${keys.submapCommand(false)}
    assert(currentSubmap == "")
    currentSubmap = "user-mode"
    ${keys.submapCommand(false)}
    assert(currentSubmap == "user-mode")`)
})
