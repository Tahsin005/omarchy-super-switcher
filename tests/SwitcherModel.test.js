const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

const context = { module: { exports: {} } }
vm.runInNewContext(fs.readFileSync("SwitcherModel.js", "utf8").replace(/^\.pragma library\s*/, ""), context)
const model = context.module.exports
const plain = value => JSON.parse(JSON.stringify(value))
const entries = [
  { id: "code.desktop", name: "Code", icon: "vscode", startupClass: "Code" },
  { id: "org.gnome.Nautilus", name: "Files", icon: "org.gnome.Nautilus", startupClass: "Nautilus" },
  { id: "WhatsApp", name: "WhatsApp", icon: "WhatsApp" },
  { id: "X", name: "X", icon: "X" },
]
const window = (address, appId, ipc = {}) => ({ address, wayland: { appId }, lastIpcObject: ipc })

test("groups multiple windows into one running application", () => {
  const apps = plain(model.buildApps([
    window("0x1", "code"), window("0x2", "CODE"), window("0x3", "Nautilus"),
  ], entries, []))
  assert.deepEqual(apps.map(app => app.id), ["code", "org.gnome.Nautilus"])
  assert.deepEqual(apps[0].addresses, ["0x1", "0x2"])
  assert.equal(apps[1].icon, "org.gnome.Nautilus")
  assert.equal(apps.some(app => app.id === "WhatsApp"), false)
})

test("orders applications and their windows by recent focus", () => {
  const apps = plain(model.buildApps([
    window("0x1", "code"), window("0x2", "Nautilus"), window("0x3", "code"),
  ], entries, ["0x2", "0x3", "0x1", "0xclosed"]))
  assert.deepEqual(apps.map(app => app.id), ["org.gnome.Nautilus", "code"])
  assert.deepEqual(apps[1].addresses, ["0x3", "0x1"])
})

test("workspace filtering runs before app grouping and MRU selection", () => {
  const windows = [
    window("0x1", "code", { workspace: { id: 1 } }),
    window("0x2", "code", { workspace: { id: 2 } }),
    window("0x3", "Nautilus", { workspace: { id: 1 } }),
    window("0x4", "browser", { workspace: { id: 2 } }),
    window("0x5", "code", { workspace: { id: 1 } }),
  ]
  const history = ["0x2", "0x4", "0x5", "0x3", "0x1"]
  const local = plain(model.buildApps(windows, entries, history, 1))
  assert.deepEqual(local.map(app => app.id), ["code", "org.gnome.Nautilus"])
  assert.deepEqual(local[0].addresses, ["0x5", "0x1"])
  const global = plain(model.buildApps(windows, entries, history))
  assert.deepEqual(global.map(app => app.id), ["code", "browser", "org.gnome.Nautilus"])
  assert.deepEqual(global[0].addresses, ["0x2", "0x5", "0x1"])
  assert.deepEqual(plain(model.buildApps(windows, entries, history, null)), global)
})

test("workspace membership uses the live object before stale IPC data and supports named workspaces", () => {
  const moved = window("0x1", "code", { workspace: { id: 1 } })
  moved.workspace = { id: -1337 }
  const unknown = window("0x2", "browser")
  assert.equal(model.windowInWorkspace(moved, 1), false)
  assert.equal(model.windowInWorkspace(moved, -1337), true)
  assert.deepEqual(plain(model.buildApps([moved, unknown], entries, [], -1337)).map(app => app.id), ["code"])
  assert.deepEqual(plain(model.buildApps([moved, unknown], entries, [], 1)), [])
  assert.deepEqual(plain(model.buildApps([moved, unknown], entries, [], 0)), [])
  assert.equal(model.windowInWorkspace(null, 1), false)
})

test("quit targets include every window of the selected app across workspaces", () => {
  const first = window("0x1", "code", { workspace: { id: 1 } })
  const second = window("0x2", "CODE", { workspace: { id: -1337 } })
  const other = window("0x3", "Nautilus", { workspace: { id: 1 } })
  const closed = window("0x4", "code", { mapped: false })
  const windows = [first, second, other, closed]
  const local = model.buildApps(windows, entries, [], 1)
  const plan = model.quitPlan(windows, entries, local[0].id)
  assert.deepEqual(plain(plan.windows.map(value => value.address)), ["0x1", "0x2"])
  assert.equal(plan.dialog, null)
  assert.deepEqual(plain(model.quitPlan(windows, entries, "missing")), { windows: [], dialog: null })
  assert.deepEqual(plain(model.quitPlan(windows, entries, "")), { windows: [], dialog: null })
})

test("quit yields to an existing modal without requesting more window closes", () => {
  const parent = window("0x1", "code")
  const dialog = window("0x2", "code")
  dialog.wayland.parent = parent.wayland
  const plan = model.quitPlan([parent, dialog], entries, "code")
  assert.equal(plan.dialog, dialog)
  assert.deepEqual(plain(plan.windows), [])
})

test("quit detects save dialogs with a different app ID by their native parent", () => {
  const parent = window("0x1", "code")
  const dialog = window("0x2", "org.example.Portal")
  dialog.wayland.parent = parent.wayland
  const unrelated = window("0x3", "Nautilus")
  const unrelatedDialog = window("0x4", "Nautilus")
  unrelatedDialog.wayland.parent = unrelated.wayland
  const plan = model.quitPlan([parent, unrelatedDialog, dialog, unrelated], entries, "code")
  assert.equal(plan.dialog, dialog)
  assert.deepEqual(plain(model.quitPlan([parent, unrelatedDialog, unrelated], entries, "code").windows.map(value => value.address)), ["0x1"])
})

test("quit yields to a new confirmation window when the client exports no parent", () => {
  const parent = window("0x1", "code")
  const dialog = window("0x2", "code")
  const other = window("0x3", "Nautilus")
  const plan = model.quitPlan([parent, other, dialog], entries, "code", ["0x1"])
  assert.equal(plan.dialog, dialog)
  assert.deepEqual(plain(plan.windows), [])
  assert.equal(model.quitPlan([parent, other], entries, "code", ["0x1"]).dialog, null)
})

test("removing the selected app selects its next neighbor and clamps at the end", () => {
  const apps = [{ id: "first" }, { id: "second" }, { id: "third" }]
  assert.equal(model.selectionIndex(apps, "second", 1), 1)
  assert.equal(model.selectionIndex([apps[0], apps[2]], "second", 1), 1)
  assert.equal(model.selectionIndex([apps[0], apps[1]], "third", 2), 1)
  assert.equal(model.selectionIndex([apps[1]], "first", 0), 0)
  assert.equal(model.selectionIndex([], "first", 0), -1)
})

test("normalizes X11 classes, StartupWMClass, and browser web apps", () => {
  assert.equal(model.appForWindow({ lastIpcObject: { class: "Nautilus" } }, entries).id, "org.gnome.Nautilus")
  assert.equal(model.appForWindow(window("0x1", "chrome-web.whatsapp.com__-Default"), entries).id, "WhatsApp")
  assert.equal(model.appForWindow(window("0x2", "firefox"), entries).id, "firefox")
  assert.equal(model.appForWindow(window("0x3", "org.example.Editor"), entries).id, "org.example.Editor")
})

test("skips closed or unidentified windows and tolerates missing desktop entries", () => {
  const apps = plain(model.buildApps([
    null, {}, window("0x1", "", {}), window("0x2", "code", { mapped: false }), window("0x3", "unknown-app"),
  ], entries, ["0x2"]))
  assert.deepEqual(apps, [{ id: "unknown-app", name: "unknown app", icon: "", addresses: ["0x3"] }])
})

test("recording focus moves only that window to the front without mutating history", () => {
  const history = ["0x1", "0x2", "0x3"]
  assert.deepEqual(plain(model.touchWindow(history, "0x2")), ["0x2", "0x1", "0x3"])
  assert.deepEqual(history, ["0x1", "0x2", "0x3"])
  assert.deepEqual(plain(model.touchWindow(history, "")), history)
})

test("forward and reverse switch past the focused app and wrap", () => {
  const apps = [{ id: "code" }, { id: "files" }, { id: "browser" }]
  assert.equal(model.initialIndex(apps, "code", 1), 1)
  assert.equal(model.initialIndex(apps, "code", -1), 2)
  assert.equal(model.initialIndex(apps, "browser", 1), 0)
  assert.equal(model.initialIndex(apps, "", 1), 0)
  assert.equal(model.initialIndex(apps, "", -1), 2)
  assert.equal(model.initialIndex([], "", 1), -1)
})

test("switching focus updates the next selection to the previous app", () => {
  const windows = [window("0x1", "code"), window("0x2", "Nautilus"), window("0x3", "browser")]
  let history = ["0x1", "0x2", "0x3"]
  let apps = model.buildApps(windows, entries, history)
  const next = apps[model.initialIndex(apps, "code", 1)]
  assert.equal(next.id, "org.gnome.Nautilus")
  history = model.touchWindow(history, next.addresses[0])
  apps = model.buildApps(windows, entries, history)
  assert.equal(apps[model.initialIndex(apps, next.id, 1)].id, "code")
})

test("uses native icons and known aliases with a neutral fallback", () => {
  assert.equal(model.iconName({ id: "code", icon: "custom-code" }), "custom-code")
  assert.equal(model.iconName({ id: "TUI.tile", icon: "application-x-executable" }), "kitty")
  assert.equal(model.iconName({ id: "code.desktop" }), "vscode")
  assert.equal(model.iconName({ id: "unrecognized" }), "application-x-executable")
})
