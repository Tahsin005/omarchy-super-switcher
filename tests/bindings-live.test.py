#!/usr/bin/env python3
"""Verify runtime shortcuts survive the Hyprland reload used by theme changes.

Run with this plugin enabled on an unlocked Hyprland desktop. The current
theme is preserved; this invokes only its compositor-reload step.
"""
import json
import os
import subprocess
import time

EXPECTED = {64: 'App switcher next', 65: 'App switcher prev'}


def bindings():
    result = subprocess.check_output(['hyprctl', '-j', 'binds'], text=True)
    return [binding for binding in json.loads(result)
            if binding['key'].upper() == 'TAB' and binding['modmask'] in EXPECTED]


def check_bindings():
    current = bindings()
    return all(len([binding for binding in current
                    if binding['modmask'] == mask and binding.get('description') == description]) == 1
               for mask, description in EXPECTED.items()) and len(current) == len(EXPECTED)


def main():
    env = dict(os.environ, OMARCHY_SHELL_IPC_TIMEOUT='10s')
    plugins = json.loads(subprocess.check_output(['omarchy', 'plugin', 'list', '--json'], env=env, text=True))
    assert any(plugin['id'] == 'harryxu.super-switcher' and plugin['enabled'] for plugin in plugins), 'Enable the switcher first'
    # Startup retries last about 13.5 seconds. Let them expire so they cannot
    # accidentally repair the bindings and hide a missing reload listener.
    print('Waiting for the startup binding-retry window to expire...', flush=True)
    time.sleep(14)
    for attempt in range(2):
        subprocess.run(['hyprctl', 'reload'], check=True, stdout=subprocess.DEVNULL)
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            if check_bindings():
                print(f'PASS reload {attempt + 1}: forward/reverse shortcuts restored without duplicates', flush=True)
                break
            time.sleep(0.1)
        else:
            descriptions = [(binding['modmask'], binding.get('description')) for binding in bindings()]
            raise AssertionError(f'Super+Tab stopped invoking the switcher after reload: {descriptions}')


if __name__ == '__main__':
    main()
