#!/usr/bin/env python3
"""Select an available iPhone on the exact requested runtime; never silently substitute OS."""
import argparse
import json
import subprocess
import sys
from uuid import UUID


def select(runtimes, devices, version):
    matching = [runtime for runtime in runtimes['runtimes']
                if runtime.get('version') == version
                and runtime.get('isAvailable') is True
                and runtime.get('identifier', '').startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
    if len(matching) != 1:
        raise ValueError(f'Expected one available iOS {version} runtime; found {len(matching)}')
    identifier = matching[0]['identifier']
    phones = sorted((device for device in devices['devices'].get(identifier, [])
                     if device.get('isAvailable') is True
                     and device.get('name', '').startswith('iPhone ')), key=lambda device: device['name'])
    if not phones:
        raise ValueError(f'No available iPhone for iOS {version}')
    udid = phones[0]['udid']
    if str(UUID(udid)).upper() != udid.upper():
        raise ValueError('Invalid simulator UDID')
    return udid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-version', required=True)
    args = parser.parse_args()
    try:
        values = [json.loads(subprocess.run(
            ['xcrun', 'simctl', 'list', kind, '--json'], check=True, capture_output=True, text=True).stdout)
            for kind in ('runtimes', 'devices')]
        print(select(*values, args.runtime_version))
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
