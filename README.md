# Omarchy Super Switcher

A macOS-style app, window, and workspace switcher for Omarchy.

https://github.com/user-attachments/assets/e7e3ffde-b8e6-4135-ad40-71d9cadf977b

## Installation

Requires Omarchy with the Quickshell-based Omarchy shell and Hyprland 0.56 or
later with its Lua configuration API. The plugin uses `omarchy-shell`, `hyprctl`,
and the `timeout` command from GNU coreutils.

```bash
omarchy plugin add https://github.com/harryxu/omarchy-super-switcher.git --enable
```

Enabling the plugin automatically takes over `Super + Tab`, `` Super + ` ``,
`Alt + Tab`, and their Shift variants for the current Hyprland session.
Installation requires no additional setup or edits to your Hyprland configuration files.

## Keyboard and mouse

| Shortcut | Action |
| --- | --- |
| `Super + Tab` | Next app |
| `Super + Shift + Tab` | Previous app |
| `` Super + ` `` | Next window of the focused app |
| `` Super + Shift + ` `` | Previous window of the focused app |
| Hold `A` with `Super + Tab` or `Super + Shift + Tab` | Show only apps with windows on the current workspace |
| `Alt/Option + Tab` | Next workspace |
| `Alt/Option + Shift + Tab` | Previous workspace |
| `Left`/`Right` or hover | Move the selection |
| `Enter` or click | Activate the selection |
| `Escape` | Cancel |
| `Q` in the app switcher | Ask the selected app to close all its windows across workspaces |

Keep Super or Alt/Option held after pressing the shortcut to browse. Release the
modifier to activate your selection. A quick tap switches without opening the panel.

You can also hold `A` after the app switcher opens. Keep it held to switch to a
window on the current workspace. Release `A` to see all apps again.

If `Q` brings up a save dialog, the switcher closes and focuses it.

## Screenshots

### Application switcher

![Application switcher with native app icons and the selected app's name](assets/screenshots/app-switcher.png)

### Workspace switcher

![Workspace switcher showing Browse, Code, and Files in a demo session](assets/screenshots/workspace-switcher.png)

## Applications

The switcher lists each running app once, most recently used first. Switching
to an app focuses its most recently used window.

## Windows

The window switcher cycles through the focused app's windows across workspaces.
Keep holding Super to see still previews with the selected window's title below
its thumbnail. The panel only opens when the app has at least two windows.

## Workspaces

The switcher shows regular workspaces across all monitors, including empty
ones. It lists numbered workspaces in order, then named workspaces alphabetically.

## Workspace preview settings

Previews show still images by default. Live previews update as you browse.
Changes apply the next time you open the workspace switcher.

```bash
omarchy-shell harryxu.super-switcher workspacePreviewMode
omarchy-shell harryxu.super-switcher setWorkspacePreviewMode live
omarchy-shell harryxu.super-switcher setWorkspacePreviewMode static
```

## Removal

```bash
omarchy plugin remove harryxu.super-switcher --yes
hyprctl reload
```

Reloading Hyprland restores the bindings from your configuration.

## License

[MIT](LICENSE)
