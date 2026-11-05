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
