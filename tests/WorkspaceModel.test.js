const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const { execFileSync } = require("node:child_process")

const context = { module: { exports: {} } }
vm.runInNewContext(fs.readFileSync("WorkspaceModel.js", "utf8").replace(/^\.pragma library\s*/, ""), context)
const model = context.module.exports
const plain = value => JSON.parse(JSON.stringify(value))

test("includes empty, numbered and named workspaces on every monitor, excluding scratchpads", () => {
  const workspaces = [
    { id: 11, name: "11", monitor: { name: "HDMI-A-1" } },
    { id: -1337, name: "Design" }, { id: 3, name: "Writing" },
    { id: 1, name: "1", windows: 0 }, { id: -1338, name: "Chat" },
    { id: -99, name: "special:console" }, null, { id: 0 }, { id: "2" }
  ]
  const entries = model.buildWorkspaces(workspaces)
  assert.deepEqual(plain(entries.map(entry => [entry.id, entry.name])),
    [["1", "1"], ["3", "Writing"], ["11", "11"], ["-1338", "Chat"], ["-1337", "Design"]])
  assert.equal(entries[2].workspace, workspaces[0], "Retain the live workspace for preview updates")
  assert.equal(workspaces[0].id, 11, "Do not reorder the compositor model")
})

test("preserves workspace names verbatim for plain-text rendering", () => {
  const name = '<img src="https://example.invalid/tracker"> 工作区'
  assert.equal(model.buildWorkspaces([{ id: 1, name }])[0].name, name)
  assert.equal(model.buildWorkspaces([{ id: 2 }])[0].name, "2")
  assert.deepEqual(plain(model.buildWorkspaces([])), [])
})

test("focuses numbered and named workspaces without treating a negative ID as a relative offset", () => {
  for (const [workspace, expected] of [
    [{ id: 3, name: "Writing" }, "3"],
    [{ id: -1337, name: "工作区" }, "name:工作区"],
    [{ id: -1338, name: 'name"; os.exit(); --\\\n\u00001' }, 'name:name"; os.exit(); --\\\n\u00001']
  ]) {
    const actual = execFileSync("lua", ["-"], {
      input: 'hl = { dsp = { focus = function(args) io.write(args.workspace) end } }\n' + model.focusCommand(workspace),
      encoding: "utf8"
    })
    assert.equal(actual, expected)
  }
  assert.equal(model.focusCommand({ id: -99, name: "special:console" }), "")
  assert.equal(model.focusCommand(null), "")
})

test("converts scaled and rotated monitor pixels into logical coordinates", () => {
  const monitor = { lastIpcObject: { x: -1600, y: 120, width: 2560, height: 1600, scale: 1.6 } }
  assert.deepEqual(plain(model.monitorGeometry(monitor)), { x: -1600, y: 120, width: 1600, height: 1000 })
  monitor.lastIpcObject.transform = 1
  assert.deepEqual(plain(model.monitorGeometry(monitor)), { x: -1600, y: 120, width: 1000, height: 1600 })
})

test("window layouts are relative to their own monitor, including offscreen and floating windows", () => {
  const monitor = { x: -1600, y: 120, width: 1600, height: 1000 }
  assert.deepEqual(plain(model.windowGeometry({ lastIpcObject: { at: [-1550, 160], size: [900, 600] } }, monitor, 0, 2)),
    { x: 50, y: 40, width: 900, height: 600 })
  assert.deepEqual(plain(model.windowGeometry({ lastIpcObject: { at: [-1700, 100], size: [1000, 700] } }, monitor, 0, 1)),
    { x: -100, y: -20, width: 1000, height: 700 })
})

test("new clients without geometry get a placeholder until IPC refreshes", () => {
  const monitor = model.monitorGeometry(null)
  assert.deepEqual(plain(model.windowGeometry({}, monitor, 2, 3)),
    { x: 0, y: 500, width: 800, height: 500 })
})
