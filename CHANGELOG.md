# Changelog

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
