# macOS App Switcher

A macOS-style app and workspace switcher for Omarchy and Hyprland. Press
`Super + Tab` to choose an app, or `Alt/Option + Tab` to preview workspaces.
Release the modifier key to switch. Both panels open on the focused display.

The plugin ID is `harryxu.super-switcher`. It handles switching without a dock,
pinned apps, auto-hide, drag-and-drop, or icon-management tools.

## Screenshots

### Application switcher

One icon per running app, ordered by recent use.

![Application switcher with native app icons and the selected app's name](assets/screenshots/app-switcher.png)

### Workspace switcher

Window previews and workspace names, with a theme-colored border around the
selection.

![Workspace switcher showing Browse, Code, and Files in a demo session](assets/screenshots/workspace-switcher.png)

## Keyboard and mouse

| Shortcut | Action |
| --- | --- |
| `Super + Tab` | Next application |
| `Super + Shift + Tab` | Previous application |
| `Alt/Option + Tab` | Next workspace |
| `Alt/Option + Shift + Tab` | Previous workspace |

Hold Super or Alt/Option and press Tab repeatedly to move through the list.
Release the modifier to activate the selection. Quick taps work even if you
release the key before the panel gets keyboard focus.

Arrow keys move the selection, Enter activates it, and Escape cancels. Moving
the pointer over an item selects it; clicking activates it. Long names are
shortened to fit. The app switcher shows the selected app's name below its icon.

Per-device `altwin:swap_alt_win` mappings work with a swapped external PC
keyboard and an unchanged internal Apple keyboard. The switcher captures the
held Alt/Win physical keys when the shortcut fires and tracks them until
release, so logical Super does not have to be physical Win.

## Applications

Each running application appears once. Apps are ordered by recent use, and
selecting one focuses its most recently used window.

Icons come from native desktop entries, with a bundled fallback for unknown
apps. The switcher does not download icons or write dock settings. Visible
artwork is centered and fitted to an 84px maximum dimension, matching smaller
native icons. Transparent padding and faint shadows do not affect the size;
source geometry is measured once and cached.

The panel is 160px high, with 96px selection tiles, 12px gaps, 24px horizontal
padding, and 32px above and below the icons. The app name sits in the lower
padding. Long lists scroll horizontally to keep the selection within the
display margins.

## Workspaces

The workspace switcher lists all existing regular workspaces across monitors,
including empty and named workspaces. Numbered workspaces come first in
numerical order, followed by named workspaces in alphabetical order. Special
scratchpad workspaces are excluded.

Each preview shows the wallpaper and window layout inside a rounded border.
The selected preview has a stronger outline in the theme's accent color.
Window contents use Hyprland's toplevel capture protocol. If a client cannot
be captured, its application icon appears in the same position. Video
wallpapers use the theme background color. Long lists scroll horizontally to
keep the selection visible.

Hold Alt/Option while choosing a workspace. The desktop changes when you
release it; Escape cancels the selection.

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

Clone the repository and link it into the user plugin directory under its
manifest ID, `harryxu.super-switcher`:

```bash
git clone https://github.com/harryxu/omarchy-super-switcher.git
cd omarchy-super-switcher
mkdir -p ~/.config/omarchy/plugins
ln -s "$PWD" ~/.config/omarchy/plugins/harryxu.super-switcher
omarchy-shell shell rescanPlugins
omarchy plugin enable harryxu.super-switcher
```

If the destination already exists, remove the previous plugin installation
before creating the link. The plugin uses source files directly from the
checkout. After editing QML, restart the shell to clear its component cache:

```bash
omarchy restart shell
```

The plugin registers `Super + Tab`, `Super + Shift + Tab`, `Alt + Tab`, and
`Alt + Shift + Tab` at runtime without editing Hyprland configuration files.
The Alt shortcuts replace Omarchy's immediate next/previous workspace actions
with preview selection and activation on release.

Bindings are restored after Hyprland configuration reloads, including theme
changes. A reload cancels any open switching session. Plugin unload and shell
startup also reset the switcher's input mode.

While a panel is open, a dedicated Hyprland submap prevents held Super from
turning clicks into window drags. Closing the panel restores normal bindings.
If the shell crashes with a panel open, Escape restores normal shortcuts
directly in Hyprland, with or without Super held.

## IPC

```bash
omarchy-shell harryxu.super-switcher altTabNext
omarchy-shell harryxu.super-switcher altTabPrev
omarchy-shell harryxu.super-switcher altTabCancel
omarchy-shell harryxu.super-switcher workspaceNext
omarchy-shell harryxu.super-switcher workspacePrev
```

A next/previous call made after its modifier has been released completes the
switch once the panel gets focus. `altTabCancel` cancels either mode.

## Tests

Run the logic tests, QML syntax check, and plugin validation. The logic tests
cover application grouping, icon lookup, MRU ordering, navigation, and remapped
modifiers, and require Node.js and a standalone Lua interpreter.

```bash
./tests/run.sh
/usr/lib/qt6/bin/qmllint --ignore-settings --only-explicit-categories --syntax error Switcher.qml SwitcherPanel.qml WorkspacePreview.qml
omarchy plugin validate .
```

Run the Qt rendering tests at 100%, 160%, and 200% scale (requires Qt Test):

```bash
./tests/render.sh
```

These check visible artwork size and centering for opaque and asymmetrically
padded icons, including reopening from the geometry cache.

With the plugin enabled on an unlocked Hyprland desktop, run the live
quick-release tests:

```bash
python3 tests/switcher-live.test.py
python3 tests/workspace-live.test.py
```

The application test needs at least two running apps and restores the original
window focus afterward. The workspace test needs two existing workspaces. It
checks forward, reverse, and consecutive quick releases, then restores the
original workspace and focus.

To check that shortcuts survive the compositor reload used by theme changes:

```bash
python3 tests/bindings-live.test.py
```

This waits for startup retries to finish and checks two configuration reloads
without changing the selected theme.

## Removal

```bash
omarchy plugin remove harryxu.super-switcher --yes
```

For a development installation, removal unlinks the plugin and keeps the
checkout.
