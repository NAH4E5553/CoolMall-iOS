#!/usr/bin/env python3
"""Remove only the enumerated UI runner before Xcode installs it for execution."""
import hashlib
import json
import plistlib
import subprocess
import sys
from pathlib import Path


RUNNER = 'CoolMalliOSUITests-Runner.app'
BUNDLE_ID = 'com.coolmall.CoolMallIOSUITests.xctrunner'


def prepare(expected_file, products, simulator):
    methods = Path(expected_file).read_text().splitlines()
    if not methods or any(not method.strip() for method in methods):
        raise ValueError('missing selected test inventory')
    if not any(method.startswith('CoolMalliOSUITests/') for method in methods):
        print(json.dumps({'status': 'not-required', 'reason': 'no selected UI tests'}), flush=True)
        return 0
    products = Path(products).resolve(strict=True)
    runner = products / RUNNER
    info = runner / 'Info.plist'
    if runner.resolve(strict=True) != runner or info.resolve(strict=True) != info:
        raise ValueError('UI runner must be the current built product, without redirected paths')
    raw = info.read_bytes()
    metadata = plistlib.loads(raw)
    if metadata.get('CFBundleIdentifier') != BUNDLE_ID or metadata.get('CFBundlePackageType') != 'APPL':
        raise ValueError('built UI runner identity mismatch; refusing device cleanup')
    command = ['xcrun', 'simctl', 'uninstall', simulator, BUNDLE_ID]
    print(json.dumps({'status': 'starting', 'runner': str(runner), 'bundleID': BUNDLE_ID,
                      'infoSHA256': hashlib.sha256(raw).hexdigest(), 'command': command}), flush=True)
    result = subprocess.run(command, check=False)
    code = result.returncode if result.returncode >= 0 else 128 - result.returncode
    print(json.dumps({'status': 'passed' if code == 0 else 'failed', 'exitCode': code}), flush=True)
    return code


def main(argv):
    if len(argv) != 3:
        print('UI-RUNNER-PREPARE: expected inventory, built products, simulator', file=sys.stderr)
        return 64
    try:
        return prepare(*argv)
    except (OSError, ValueError, TypeError, AttributeError, plistlib.InvalidFileException) as error:
        print('UI-RUNNER-PREPARE: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
