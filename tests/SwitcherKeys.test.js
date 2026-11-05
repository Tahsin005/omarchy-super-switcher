const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const { execFileSync } = require("node:child_process")

const context = { module: { exports: {} } }
vm.runInNewContext(fs.readFileSync("SwitcherKeys.js", "utf8").replace(/^\.pragma library\s*/, ""), context)
const keys = context.module.exports
const plain = value => JSON.parse(JSON.stringify(value))

function lua(command, down, invokeBinding) {
  const prelude = `
local down = {${down.map(code => `[${code}] = true`).join(",")}}
local bindings = {}
hl = {
  is_key_down = function(code)
    assert(type(code) == "number", "keysym lookup ignores per-device mappings")
    return down[code] == true
  end,
  exec_cmd = function(command) print(command) end,
}
o = { rebind = function(chord, description, callback) bindings[chord] = callback end }
`
  return execFileSync("lua", ["-"], {
    input: prelude + command + (invokeBinding ? `\nbindings[${JSON.stringify(invokeBinding)}]()` : ""),
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
