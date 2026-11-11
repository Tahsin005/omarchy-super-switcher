const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const { execFileSync } = require("node:child_process")

const context = { module: { exports: {} } }
vm.runInNewContext(fs.readFileSync("SwitcherKeys.js", "utf8").replace(/^\.pragma library\s*/, ""), context)
const keys = context.module.exports
const plain = value => JSON.parse(JSON.stringify(value))
const holdThresholdMs = 60

function lua(command, down = [], invokeBinding) {
  const prelude = `
local down = {${down.map(code => `[${JSON.stringify(code)}] = true`).join(",")}}
local bindings = {}
local definingSubmap = ""
local currentSubmap = ""
local now = 0
local holdThreshold = ${holdThresholdMs}
local timer
local listeners = {}
local keyQueries = 0
hl = {
  is_key_down = function(code)
    assert(type(code) == "number" or code == "a" or code == "A",
      "Modifier keys must use physical codes to preserve per-device mappings")
    keyQueries = keyQueries + 1
    return down[code] == true
  end,
  exec_cmd = function(command) print(command) end,
  on = function(event, callback)
    assert(event == "input.keyboard.key")
    listeners[callback] = true
    return { remove = function() listeners[callback] = nil end }
  end,
  timer = function(callback, options)
    assert(timer == nil, "The hold check should reuse its timer")
    assert(options.timeout == holdThreshold and options.type == "repeat")
    timer = { callback = callback, deadline = now + options.timeout,
      set_enabled = function(self, enabled)
        self.deadline = enabled and now + options.timeout or nil
      end,
      set_timeout = function(self, timeout) self.deadline = now + timeout end }
    return timer
  end,
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
local function keyEvent(code, event)
  -- Hyprland emits this event before updating hl.is_key_down or calling bindings.
  for callback in pairs(listeners) do callback(code, now, event) end
  down[code] = event == 1 or nil
end
local function invoke(chord, submap, code)
  for _, binding in ipairs(bindings) do
    if binding.chord == chord and binding.submap == (submap or "") then
      keyEvent(code or (chord:find("grave") and 49 or 23), 1)
      binding.callback()
      return
    end
  end
  error("Missing binding: " .. chord)
end
local function release(code)
  keyEvent(code, 0)
end
local function advance(ms)
  local endTime = now + ms
  while timer and timer.deadline and timer.deadline <= endTime do
    now = timer.deadline
    timer.deadline = now + holdThreshold
    timer.callback()
  end
  now = endTime
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
    assert.equal(dispatch, `omarchy-shell -q harryxu.super-switcher shortcutPressed 1 ${code} apps 1`)
    const held = keys.parseHeldKeys(dispatch.split(" ").at(-3))
    assert.equal(lua(keys.releaseCommand(held, 9), [code]), "")
    assert.equal(lua(keys.releaseCommand(held, 9), []),
      "omarchy-shell -q harryxu.super-switcher.switcher acceptRelease 9")
  })
}

test("reverse switching ignores Shift, and unrelated Alt cannot prolong the session", () => {
  const dispatch = lua(keys.bindingCommand(), [64, 50, 23], "SUPER + SHIFT + TAB")
  assert.equal(dispatch, "omarchy-shell -q harryxu.super-switcher shortcutPressed -1 64 apps 1")
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

test("holding A scopes application shortcuts in both directions and submaps", () => {
  for (const a of ["a", "A"]) {
    for (const modifier of [64, 108, 133, 134]) {
      for (const [chord, step] of [["SUPER + TAB", 1], ["SUPER + SHIFT + TAB", -1]]) {
        for (const submap of ["", keys.submapName]) {
          assert.equal(lua(`${keys.bindingCommand()} invoke("${chord}", "${submap}")`, [modifier, a, 23]),
            `omarchy-shell -q harryxu.super-switcher shortcutPressed ${step} ${modifier} localApps 1`)
        }
      }
    }
  }
})

test("A does not change Alt+Tab workspace switching", () => {
  assert.equal(lua(keys.cycleCommand(1, "workspaces"), [64, "a"]),
    "omarchy-shell -q harryxu.super-switcher workspaceCycleHeld 1 64")
})

test("releasing A restores the app scope only while Super remains held", () => {
  const command = keys.releaseCommand([133], 17, true, 3)
  assert.equal(lua(command, [133, "a"]),
    "omarchy-shell -q harryxu.super-switcher.switcher acceptAppScope 17 3 true")
  assert.equal(lua(command, [133]),
    "omarchy-shell -q harryxu.super-switcher.switcher acceptAppScope 17 3 false")
  for (const down of [[], ["a"]]) {
    assert.equal(lua(command, down),
      "omarchy-shell -q harryxu.super-switcher.switcher acceptRelease 17")
  }
})

test("a local quick tap keeps its captured scope when A and Super were released before focus", () => {
  assert.equal(lua(keys.cycleCommand(1), ["a", 133]),
    "omarchy-shell -q harryxu.super-switcher localCycleHeld 1 133")
  assert.equal(lua(keys.releaseCommand([133], 18, true, 4)),
    "omarchy-shell -q harryxu.super-switcher.switcher acceptRelease 18")
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

test("a short tap commits before the hold threshold, including release before IPC", () => {
  for (const code of [64, 133]) {
    const command = keys.pendingCommand([code], 19)
    const release = "omarchy-shell -q harryxu.super-switcher.switcher acceptRelease 19"
    assert.equal(lua(command + "\nassert(not timer and not next(listeners))"), release)
    assert.equal(lua(`${command}
      advance(holdThreshold - 20)
      release(23)
      assert(timer.deadline == holdThreshold and next(listeners) and keyQueries == 1)
      release(${code})
      assert(not timer.deadline and not next(listeners))
      advance(holdThreshold)
    `, [code, 23]), release)
  }
})

test("a held modifier requests the panel only at the threshold", () => {
  assert.equal(lua(`${keys.pendingCommand([133, 134], 20)}
    release(133)
    advance(holdThreshold - 1)
    assert(timer.deadline == holdThreshold and next(listeners))
    advance(1)
    assert(not timer.deadline and not next(listeners))
    advance(holdThreshold)
  `, [133, 134]), "omarchy-shell -q harryxu.super-switcher.switcher acceptHold 20")
})

test("the deadline checks the current modifier state if a release was missed", () => {
  assert.equal(lua(`${keys.pendingCommand([108], 23)}
    down[108] = nil
    advance(holdThreshold)
    assert(not timer.deadline and not next(listeners))
  `, [108]), "omarchy-shell -q harryxu.super-switcher.switcher acceptRelease 23")
})

test("a new pending session replaces the old modifier check and deadline", () => {
  assert.equal(lua(`
    do ${keys.pendingCommand([133], 21)} end
    advance(holdThreshold - 10)
    do ${keys.pendingCommand([64], 22)} end
    release(133)
    advance(holdThreshold - 1)
    assert(timer.deadline == 2 * holdThreshold - 10 and next(listeners))
    advance(1)
    assert(not timer.deadline and not next(listeners))
  `, [64, 133]), "omarchy-shell -q harryxu.super-switcher.switcher acceptHold 22")
})

test("startup retries keep switcher bindings without duplicating Escape or removing user binds", () => {
  lua(`
    hl.bind("Escape", function() end)
    hl.bind("SUPER + mouse:272", function() end, {mouse = true})
    hl.bind("SUPER + mouse:273", function() end, {mouse = true})
    hl.define_submap("user-mode", function() hl.bind("Escape", function() end) end)
    ${keys.bindingCommand()}
    ${keys.bindingCommand()}
    ${keys.bindingCommand()}
    assert(next(listeners) and not next(listeners, next(listeners)))
    assert(#bindings == 17, "Expected 4 user bindings and 13 switcher bindings")
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
      assert(counts[map .. ":SUPER + grave"] == 1)
      assert(counts[map .. ":SUPER + SHIFT + grave"] == 1)
      assert(counts[map .. ":ALT + TAB"] == 1)
      assert(counts[map .. ":ALT + SHIFT + TAB"] == 1)
    end
    assert(counts[":Escape"] == 1 and counts["user-mode:Escape"] == 1)
    assert(counts["${keys.submapName}:Escape"] == 1)
  `)
})

test("window shortcuts cycle in both submaps and ignore the app scope key", () => {
  for (const [chord, step] of [["SUPER + grave", 1], ["SUPER + SHIFT + grave", -1]]) {
    for (const submap of ["", keys.submapName]) {
      assert.equal(lua(`${keys.bindingCommand()} invoke("${chord}", "${submap}")`, [64, "a", 49]),
        `omarchy-shell -q harryxu.super-switcher shortcutPressed ${step} 64 windows 1`)
    }
  }
})

test("workspace shortcuts track Option and remapped Win positions through release in both submaps", () => {
  for (const code of [64, 108, 133, 134]) {
    for (const [chord, step] of [["ALT + TAB", 1], ["ALT + SHIFT + TAB", -1]]) {
      for (const submap of ["", keys.submapName]) {
        const dispatch = lua(`${keys.bindingCommand()} invoke("${chord}", "${submap}")`, [code, 23, 50])
        assert.equal(dispatch, `omarchy-shell -q harryxu.super-switcher shortcutPressed ${step} ${code} workspaces 1`)
        const held = keys.parseHeldKeys(dispatch.split(" ").at(-3))
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
    `omarchy-shell -q harryxu.super-switcher shortcutPressed ${step} 64 apps 1`)
  }
})

test("shortcut repeat tracks the physical press through submap entry and stops on release", () => {
  lua(`${keys.bindingCommand()}
    local function firstHeld() ${keys.shortcutHeldCommand(1)} end
    local function secondHeld() ${keys.shortcutHeldCommand(2)} end
    invoke("SUPER + grave", "", 94)
    assert(not firstHeld())
    ${keys.submapCommand(true)}
    assert(firstHeld())
    release(64)
    assert(firstHeld(), "The other captured modifier is still held")
    release(94)
    keyEvent(94, 1)
    assert(not firstHeld(), "A released press must stay invalid even if the key is down again")
    invoke("SUPER + SHIFT + grave", currentSubmap, 94)
    assert(not firstHeld() and secondHeld())
    release(134)
    keyEvent(134, 1)
    assert(not secondHeld(), "Re-pressing a modifier cannot revive the old shortcut")
  `, [64, 134])
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
