const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")

test("border style normalization logic", () => {
  function normalizeBorderStyle(style) {
    const normalized = String(style).trim().toLowerCase()
    if (normalized !== "squared" && normalized !== "square" && normalized !== "rounded") {
      return null
    }
    return normalized === "rounded" ? "rounded" : "squared"
  }

  assert.equal(normalizeBorderStyle("squared"), "squared")
  assert.equal(normalizeBorderStyle("square"), "squared")
  assert.equal(normalizeBorderStyle("SQUARED"), "squared")
  assert.equal(normalizeBorderStyle("rounded"), "rounded")
  assert.equal(normalizeBorderStyle("ROUNDED"), "rounded")
  assert.equal(normalizeBorderStyle("invalid"), null)
  assert.equal(normalizeBorderStyle(""), null)
})

test("Switcher.qml, SwitcherPanel.qml, WorkspacePreview.qml, and WindowPreview.qml contain borderStyle bindings", () => {
  const switcher = fs.readFileSync("Switcher.qml", "utf8")
  const panel = fs.readFileSync("SwitcherPanel.qml", "utf8")
  const ws = fs.readFileSync("WorkspacePreview.qml", "utf8")
  const win = fs.readFileSync("WindowPreview.qml", "utf8")

  assert.match(switcher, /property string borderStyle:\s*"rounded"/)
  assert.match(switcher, /readonly property bool roundedBorders:\s*borderStyle === "rounded"/)
  assert.match(switcher, /function borderStyle\(\):\s*string/)
  assert.match(switcher, /function setBorderStyle\(style:\s*string\):\s*string/)
  assert.match(switcher, /roundedBorders:\s*root\.roundedBorders/)

  assert.match(panel, /property bool roundedBorders:\s*true/)
  assert.match(panel, /property int surfaceRadius:\s*root\.roundedBorders \? \(root\.appMode \? 36 : 28\) : 0/)
  assert.match(panel, /property int selectionRadius:\s*root\.roundedBorders \? 20 : 0/)
  assert.match(panel, /radius:\s*root\.roundedBorders \? \(root\.appMode \? root\.selectionRadius : 16\) : 0/)

  assert.match(ws, /property bool roundedBorders:\s*true/)
  assert.match(ws, /property real cornerRadius:\s*root\.roundedBorders \? 12 : 0/)

  assert.match(win, /property bool roundedBorders:\s*true/)
  assert.match(win, /radius:\s*root\.roundedBorders \? 12 : 0/)
})

