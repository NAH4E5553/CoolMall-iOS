#!/usr/bin/env python3
"""Create a fresh iPhone simulator on the exact requested runtime."""
import argparse
import json
import subprocess
import sys
from uuid import UUID


def create(runtimes, devicetypes, version, name):
    matching = [runtime for runtime in runtimes['runtimes']
                if runtime.get('version') == version
                and runtime.get('isAvailable') is True
                and runtime.get('identifier', '').startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
    if len(matching) != 1:
        raise ValueError(f'Expected one available iOS {version} runtime; found {len(matching)}')
    runtime = matching[0]['identifier']
    phones = sorted((item for item in devicetypes['devicetypes']
                     if item.get('name', '').startswith('iPhone ')), key=lambda item: item['name'])
    if not phones:
        raise ValueError(f'No available iPhone device type for iOS {version}')
    preferred = next((item for item in phones if item['name'] == 'iPhone 17'), phones[0])
    result = subprocess.run(['xcrun', 'simctl', 'create', name, preferred['identifier'], runtime],
                            check=True, capture_output=True, text=True)
    udid = result.stdout.strip()
    if str(UUID(udid)).upper() != udid.upper():
        raise ValueError('Invalid simulator UDID')
    return udid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-version', required=True)
    parser.add_argument('--name', required=True)
    args = parser.parse_args()
    try:
        values = [json.loads(subprocess.run(
            ['xcrun', 'simctl', 'list', kind, '--json'], check=True, capture_output=True, text=True).stdout)
            for kind in ('runtimes', 'devicetypes')]
        print(create(*values, args.runtime_version, args.name))
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
