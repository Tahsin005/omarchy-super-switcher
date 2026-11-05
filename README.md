# macOS App Switcher

A macOS-style application switcher for Omarchy and Hyprland. It shows one icon
per running application, ordered by recent use, on the currently focused output.

The plugin ID is `harryxu.super-switcher`.
The plugin now contains only application switching: no dock bar, pinned apps,
auto-hide, drag-and-drop, window previews, or icon-management tools.

## Keyboard and mouse

- `Super + Tab`: next application.
- `Super + Shift + Tab`: previous application.
- Hold Super and press Tab repeatedly to move through running applications.
- Release Super to activate the selected application's most recently used window.
- A quick press and release also works if Super was released before the switcher
  acquired keyboard focus.
- Arrow keys move the selection, Enter activates, and Escape cancels.
- Hover selects an application; clicking activates it.

The switcher uses native desktop-entry icons with a bundled fallback for unknown
applications. It does not write dock settings or download icons.
Visible icon artwork is centered and fitted to an 84px maximum dimension,
matching the smaller native icons. Transparent padding and faint shadows do not
determine the size; source geometry is measured once and cached for later switches.

## Requirements

Omarchy with Quickshell and Hyprland's Lua configuration API, including
`hl.is_key_down`, `o.rebind`, and the `omarchy-shell` IPC command.

## Development installation

Link the checkout into the user plugin directory, using its manifest ID:

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s /absolute/path/to/omarchy-dock ~/.config/omarchy/plugins/harryxu.super-switcher
omarchy-shell shell rescanPlugins
omarchy plugin enable harryxu.super-switcher
```

If the destination is already occupied, remove the previous plugin installation
before creating the link. Source changes are used directly from the checkout.
After editing QML, restart the shell to clear its component cache:

```bash
omarchy restart shell
```

The runtime bindings reserve `Super + Tab` and `Super + Shift + Tab` without
editing Hyprland configuration files or changing Alt-based shortcuts.

## IPC

The existing command names remain available:

```bash
omarchy-shell harryxu.super-switcher altTabNext
omarchy-shell harryxu.super-switcher altTabPrev
omarchy-shell harryxu.super-switcher altTabCancel
```

A next/previous call made with Super already released completes the switch
automatically after the panel acquires focus. Dock visibility, placement,
auto-hide, pinning, and custom-icon commands have been removed.

## Tests

Run the application grouping, icon lookup, MRU ordering, and navigation tests:

```bash
./tests/run.sh
/usr/lib/qt6/bin/qmllint --ignore-settings --only-explicit-categories --syntax error Switcher.qml SwitcherPanel.qml
omarchy plugin validate .
```

On an unlocked Hyprland desktop with this plugin enabled and at least two
applications running, test quick-release switching through the live IPC path:

```bash
python3 tests/switcher-live.test.py
```

This switches applications temporarily and restores the original window focus.

## Removal

```bash
omarchy plugin remove harryxu.super-switcher --yes
```

For a development installation, removal unlinks the plugin and keeps the checkout.
