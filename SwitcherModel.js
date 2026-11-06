.pragma library

var ICON_ALIASES = {
    "org.kde.dolphin": "system-file-manager",
    "dolphin": "system-file-manager",
    "code": "vscode",
    "com.visualstudio.code": "vscode",
    "google-chrome": "google-chrome",
    "com.google.chrome": "google-chrome",
    "whatsapp": "WhatsApp",
    "discord": "Discord",
    "omarchy-discord": "Discord",
    "tui.tile": "kitty"
}

function normalizeId(value) {
    return String(value || "").trim().replace(/\.desktop$/i, "")
}

function entryFor(rawId, entries) {
    var lower = normalizeId(rawId).toLowerCase()
    if (!lower) return null
    for (var i = 0; i < entries.length; i++) {
        if (normalizeId(entries[i].id).toLowerCase() === lower) return entries[i]
    }
    for (var j = 0; j < entries.length; j++) {
        if (String(entries[j].startupClass || "").toLowerCase() === lower) return entries[j]
    }
    // Generated browser web-app classes can contain their desktop-entry name.
    // Gate fuzzy names so a short web-app name cannot capture normal apps.
    if (/^(chrome|chromium|google-chrome)[-_.]/.test(lower) || /__-default(-\d+)?$/.test(lower)) {
        for (var k = 0; k < entries.length; k++) {
            var name = String(entries[k].name || "").toLowerCase()
            if (name && lower.indexOf(name) !== -1) return entries[k]
        }
    }
    return null
}

function appForWindow(window, entries) {
    if (!window) return null
    var ipc = window.lastIpcObject || {}
    var ids = [window.wayland ? window.wayland.appId : "", ipc["class"], ipc.initialClass, ipc.appId]
    var fallback = ""
    for (var i = 0; i < ids.length; i++) {
        var id = normalizeId(ids[i])
        if (!id) continue
        if (!fallback) fallback = id
        var entry = entryFor(id, entries)
        if (entry) return { id: normalizeId(entry.id), name: entry.name || entry.id, icon: entry.icon || "" }
    }
    return fallback ? { id: fallback, name: fallback.replace(/[-_]+/g, " "), icon: "" } : null
}

function touchWindow(history, address) {
    if (!address) return history.slice()
    return [address].concat(history.filter(function(value) { return value !== address }))
}

function windowInWorkspace(window, workspaceId) {
    if (!window) return false
    var workspace = window.workspace || (window.lastIpcObject || {}).workspace
    return !!workspace && Number(workspace.id) === Number(workspaceId)
}

function buildApps(windows, entries, history, workspaceId) {
    var ordered = []
    for (var i = 0; i < windows.length; i++) {
        var window = windows[i]
        if (!window || !window.address || (window.lastIpcObject || {}).mapped === false) continue
        if (workspaceId !== undefined && workspaceId !== null && !windowInWorkspace(window, workspaceId)) continue
        var app = appForWindow(window, entries)
        if (app) ordered.push({ app: app, address: window.address })
    }
    ordered.sort(function(a, b) {
        var ai = history.indexOf(a.address)
        var bi = history.indexOf(b.address)
        return (ai < 0 ? history.length : ai) - (bi < 0 ? history.length : bi)
    })
    var apps = []
    for (var j = 0; j < ordered.length; j++) {
        var item = ordered[j]
        var existing = -1
        for (var k = 0; k < apps.length; k++) {
            if (apps[k].id.toLowerCase() === item.app.id.toLowerCase()) { existing = k; break }
        }
        if (existing >= 0) apps[existing].addresses.push(item.address)
        else apps.push({ id: item.app.id, name: item.app.name, icon: item.app.icon, addresses: [item.address] })
    }
    return apps
}

function initialIndex(apps, currentId, step) {
    if (!apps.length) return -1
    for (var i = 0; i < apps.length; i++) {
        if (apps[i].id === currentId) return (i + step + apps.length) % apps.length
    }
    return step > 0 ? 0 : apps.length - 1
}

function iconName(app) {
    var icon = String(app.icon || "").trim()
    if (icon && icon !== "application-x-executable") return icon
    var id = normalizeId(app.id).toLowerCase()
    return ICON_ALIASES[id] || "application-x-executable"
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        appForWindow: appForWindow,
        buildApps: buildApps,
        entryFor: entryFor,
        iconName: iconName,
        initialIndex: initialIndex,
        normalizeId: normalizeId,
        touchWindow: touchWindow,
        windowInWorkspace: windowInWorkspace
    }
}
