# Changelog

## Unreleased

### Added

- Added configurable border styles (`squared` vs `rounded`) for the application,
  window, and workspace switchers.
- Added interactive `install.sh` installation script giving users the choice
  between squared and rounded borders during install or setup.
- Added IPC methods `borderStyle` and `setBorderStyle` to query and set the border
  style live via `omarchy-shell`.

### Changed

- Changed default border style to squared sharp borders across the switcher
  surface, selection highlights, and window/workspace previews.

## v0.3.1

### Fixed

- Prevented stalled Hyprland IPC from accumulating helper processes. Modifier
  checks coalesce repeated input, and app and workspace IPC calls use a bounded
  queue. A deadline stops unresponsive requests.

## v0.3.0

### Added

- Press `` Super + ` `` to cycle through the focused app's windows across
  workspaces, or hold Shift to cycle in reverse. Quick taps follow a stable
  order so you can reach every window.
- Hold Super to see still previews when the app has at least two windows.
  The panel shows the app's icon and name above the previews and the selected
  window's title below its thumbnail. Release Super to focus the selected window.

### Changed

- Reworked the marketplace preview so both the app and workspace switchers fit
  in list thumbnails.
- Documented the window switcher shortcuts and refreshed the README demo video.

### Maintenance

- Extended tests to cover window filtering, cycle order, and shortcut registration.
- Added the local `AGENTS.md` file to `.gitignore`.

Commit range `7756f4d..fb75540`.
