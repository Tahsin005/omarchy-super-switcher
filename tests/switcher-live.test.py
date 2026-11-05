#!/usr/bin/env python3
"""Live regression: Super is already released when its queued IPC arrives.

Run explicitly on an unlocked Hyprland desktop with at least two running apps.
The test switches focus temporarily and restores the original window on exit.
"""
import json
import os
import re
import subprocess
import time

ENV = dict(os.environ, OMARCHY_SHELL_IPC_TIMEOUT='10s')


def run(*command):
    return subprocess.check_output(command, env=ENV, text=True).strip()


def active_window():
    return json.loads(run('hyprctl', '-j', 'activewindow'))


def switcher_visible():
    layers = json.loads(run('hyprctl', '-j', 'layers'))
    return any(layer.get('namespace') == 'harryxu-super-switcher'
               for output in layers.values()
               for level in output.get('levels', {}).values()
               for layer in level)


def assert_no_dock_layers():
    layers = json.loads(run('hyprctl', '-j', 'layers'))
    removed = {'macos-dock', 'macos-dock-edge', 'macos-dock-spacer', 'macos-dock-material'}
    found = [layer.get('namespace')
             for output in layers.values()
             for level in output.get('levels', {}).values()
             for layer in level if layer.get('namespace') in removed]
    assert not found, f'Removed dock layers are still mapped: {found}'


def switch(method):
    before = active_window().get('class')
    # A fast tap can release Super before the command reaches the shell.
    # Invoke that exact late-arriving command with no modifier held; no
    # subsequent key release will be delivered to the newly mapped panel.
    run('omarchy-shell', 'harryxu.super-switcher', method)
    deadline = time.monotonic() + 2
    candidate = None
    stable_since = time.monotonic()
    while time.monotonic() < deadline:
        focused = active_window().get('class')
        if focused != candidate:
            candidate = focused
            stable_since = time.monotonic()
        if not switcher_visible() and focused and focused != before:
            # Activation also restores the cursor asynchronously after 80ms.
            # Wait for settled focus rather than sampling that transition.
            if time.monotonic() - stable_since >= 0.15:
                return focused
        time.sleep(0.025)
    raise AssertionError(f'{method}: switcher_stuck={switcher_visible()}, '
                         f'before={before}, after={active_window().get("class")}')


def main():
    clients = json.loads(run('hyprctl', '-j', 'clients'))
    assert len({client['class'] for client in clients}) >= 2, 'Need at least two running applications'
    original = active_window()
    address = original.get('address', '')
    assert re.fullmatch(r'0x[0-9a-f]+', address), 'Start with an application focused'
    try:
        assert_no_dock_layers()
        for method in ('altTabNext', 'altTabPrev'):
            for trial in range(3):
                run('omarchy-shell', 'harryxu.super-switcher', 'altTabCancel')
                run('hyprctl', 'dispatch', 'hl.dsp.focus({ window = "address:' + address + '" })')
                time.sleep(0.15)
                switch(method)
                print(f'PASS {method}: released-before-open, trial {trial + 1}', flush=True)
        # Reopen immediately after activation, without resetting the panel or
        # restoring focus between sessions. Each tap must close and switch.
        for trial in range(3):
            switch('altTabNext')
            print(f'PASS consecutive quick tap {trial + 1}', flush=True)
        assert_no_dock_layers()
        print('PASS no dock surfaces, edge triggers, or spacers', flush=True)
    finally:
        run('omarchy-shell', 'harryxu.super-switcher', 'altTabCancel')
        run('hyprctl', 'dispatch', 'hl.dsp.focus({ window = "address:' + address + '" })')


if __name__ == '__main__':
    main()
