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
- Per-device `altwin:swap_alt_win` mappings are supported, including a swapped
  external PC keyboard alongside an unchanged internal Apple keyboard. The
  shortcut captures the held Alt/Win physical keys and tracks those keys until
  release; it does not assume that logical Super is physical Win.
- A quick press and release also works if Super was released before the switcher
  acquired keyboard focus.
- Arrow keys move the selection, Enter activates, and Escape cancels.
- Hover selects an application; clicking activates it.
- While visible, the switcher uses a dedicated Hyprland submap so holding Super
  does not turn icon clicks into window drags. Closing returns to normal bindings.
- The selected application's name appears below its icon, following keyboard
  and pointer selection. Long names are shortened to fit the panel.

The switcher uses native desktop-entry icons with a bundled fallback for unknown
applications. It does not write dock settings or download icons.
Visible icon artwork is centered and fitted to an 84px maximum dimension,
matching the smaller native icons. Transparent padding and faint shadows do not
determine the size; source geometry is measured once and cached for later switches.
The compact layout uses 96px selection tiles with 12px between tiles, 24px
horizontal padding, and equal 32px vertical padding around the icons, for a
160px panel height. The selected application's name is centered in the bottom
padding. Longer lists scroll horizontally to keep the selected application
visible within the display margins.

## Requirements

Omarchy with Quickshell and Hyprland's Lua configuration API, including
`hl.is_key_down`, `hl.define_submap`, `hl.get_current_submap`, `o.rebind`, and the
`omarchy-shell` IPC command.

## Installation

Install and enable the plugin from
[harryxu/omarchy-super-switcher](https://github.com/harryxu/omarchy-super-switcher):

```bash
omarchy plugin add https://github.com/harryxu/omarchy-super-switcher.git --enable
```

## Development installation

For development, clone the repository and link the checkout into the user plugin
directory using its manifest ID, `harryxu.super-switcher`:

```bash
git clone https://github.com/harryxu/omarchy-super-switcher.git
cd omarchy-super-switcher
mkdir -p ~/.config/omarchy/plugins
ln -s "$PWD" ~/.config/omarchy/plugins/harryxu.super-switcher
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
Bindings are restored after Hyprland configuration reloads, including those
triggered by Omarchy theme changes.
An active switching session is canceled when Hyprland configuration reloads.
Plugin unload and shell startup reset the switcher's input mode. If the shell
crashes while the switcher is open, Escape (with or without Super held) restores
normal shortcuts directly in Hyprland, without needing the shell to respond.

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

Run the application grouping, icon lookup, MRU ordering, navigation, and
remapped-modifier tests (requires Node.js and a standalone Lua interpreter):

```bash
./tests/run.sh
/usr/lib/qt6/bin/qmllint --ignore-settings --only-explicit-categories --syntax error Switcher.qml SwitcherPanel.qml
omarchy plugin validate .
```

Run the Qt rendering regressions at 100%, 160%, and 200% scale (requires Qt Test):

```bash
./tests/render.sh
```

These verify the visible artwork size and centering for opaque and
asymmetrically padded icons, including reopening from the geometry cache.

On an unlocked Hyprland desktop with this plugin enabled and at least two
applications running, test quick-release switching through the live IPC path:

```bash
python3 tests/switcher-live.test.py
```

This switches applications temporarily and restores the original window focus.

To verify shortcuts survive the compositor reload used by theme changes:

```bash
python3 tests/bindings-live.test.py
```

This waits for startup retries to finish, then checks two configuration reloads
without changing the selected theme.

## Removal

```bash
omarchy plugin remove harryxu.super-switcher --yes
```

For a development installation, removal unlinks the plugin and keeps the checkout.
