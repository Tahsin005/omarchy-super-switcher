#!/usr/bin/env python3
"""Test workspace quick-release activation on an unlocked Hyprland desktop."""
import json
import re
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def current_workspace():
    monitors = json.loads(run('hyprctl', '-j', 'monitors'))
    return next(monitor['activeWorkspace']['id'] for monitor in monitors if monitor['focused'])


def switcher_visible():
    layers = json.loads(run('hyprctl', '-j', 'layers'))
    return any(layer.get('namespace') == 'harryxu-super-switcher'
               for monitor in layers.values()
               for level in monitor.get('levels', {}).values()
               for layer in level)


def wait_for(predicate, message):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.025)
    raise AssertionError(message)


def main():
    workspaces = json.loads(run('hyprctl', '-j', 'workspaces'))
    numbered = sorted(workspace['id'] for workspace in workspaces if workspace['id'] > 0)
    named = sorted((workspace for workspace in workspaces
                    if workspace['id'] < 0 and not workspace['name'].startswith('special:')),
                   key=lambda workspace: workspace['name'])
    ids = numbered + [workspace['id'] for workspace in named]
    assert len(ids) >= 2, 'Need at least two existing regular workspaces'
    original_workspace = current_workspace()
    original_window = json.loads(run('hyprctl', '-j', 'activewindow')).get('address', '')
    original_cursor = run('hyprctl', 'cursorpos')
    try:
        for method, step in [('workspaceNext', 1), ('workspacePrev', -1)] * 3:
            before = current_workspace()
            expected = ids[(ids.index(before) + step) % len(ids)]
            run('omarchy-shell', 'harryxu.super-switcher', method)
            wait_for(lambda: current_workspace() == expected and not switcher_visible(),
                     f'{method}: did not activate workspace {expected}')
            wait_for(lambda: run('hyprctl', 'submap') == 'default'
                     and run('hyprctl', 'cursorpos') == original_cursor,
                     'Switcher left its input mode active or moved the pointer')
            time.sleep(0.15)
            assert current_workspace() == expected, 'Workspace focus did not settle on the selection'
            print(f'PASS {method}: {before} -> {expected}, quick release and pointer preserved', flush=True)
    finally:
        run('omarchy-shell', 'harryxu.super-switcher', 'altTabCancel')
        original_name = next(workspace['name'] for workspace in workspaces if workspace['id'] == original_workspace)
        # JSON quoting covers normal Unicode workspace names used by this live
        # test; production dispatching also escapes arbitrary control bytes.
        selector = str(original_workspace) if original_workspace > 0 else 'name:' + original_name
        run('hyprctl', 'dispatch', 'hl.dsp.focus({ workspace = ' + json.dumps(selector, ensure_ascii=False) + ' })')
        if re.fullmatch(r'0x[0-9a-f]+', original_window):
            run('hyprctl', 'dispatch', f'hl.dsp.focus({{ window = "address:{original_window}" }})')
        position = re.fullmatch(r'(-?\d+),\s*(-?\d+)', original_cursor)
        if position:
            run('hyprctl', 'dispatch', f'hl.dsp.cursor.move({{ x = {position[1]}, y = {position[2]} }})')


if __name__ == '__main__':
    main()
