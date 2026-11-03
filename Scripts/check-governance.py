#!/usr/bin/env python3
"""Run the real governance inventory; scope only the macOS driver by its inputs."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
DRIVER = 'test_verification_driver'
DRIVER_INPUTS = {
    'ENGINEERING.md', 'Scripts/check-governance.py', 'Scripts/check-boundary-negative.sh',
    'Tests/Governance/test_verification_driver.py',
    'Tests/Governance/Fixtures/test-enumeration.json',
} | {'Scripts/' + name for name in [
    'verify-local.sh', 'verification-timing.py', 'select-test-scope.py',
    'classify-ci-changes.py', 'check-boundaries.py', 'with-banner-trace.py',
    'finalize-verification.py', 'ci-deferred-policy.py', 'ci-deferred-checks.json',
    'check-test-support-scope.py', 'check-test-support-execution.py',
]}


def known_unrelated(path):
    # This is a bounded allowlist, not "everything outside known CI directories".
    parts = Path(path).parts
    if path in {'README.md', 'CHANGELOG.md', 'PRODUCT_SPEC.md', 'IMPLEMENTATION_PLAN.md'}:
        return True
    if parts and parts[0] in {'docs', 'Docs'}:
        return Path(path).suffix.lower() in {'.md', '.txt', '.png', '.jpg', '.jpeg'} and Path(path).name not in {'ENGINEERING.md', 'AGENTS.md', 'SKILL.md'}
    if path in {'Packages/MallKit/Package.swift', 'CoolMalliOS.xctestplan'}:
        return True
    return (path.startswith(('CoolMalliOS/', 'CoolMalliOSUITests/',
                             'Packages/MallKit/Sources/', 'Packages/MallKit/Tests/',
                             'CoolMalliOS.xcodeproj/'))
            and (Path(path).suffix in {'.swift', '.plist', '.entitlements', '.pbxproj', '.xcscheme', '.xcsettings', '.xcworkspacedata'}
                 or '.xcassets/' in path))


def driver_required(root, env):
    if env.get('GITHUB_EVENT_NAME') not in {'pull_request', 'push'} or env.get('MALL_VERIFICATION_TIER') != 'required':
        return True, 'local/full verification'
    try:
        base, head = env['MALL_DIFF_BASE'], env['MALL_DIFF_HEAD']
        if not all(re.fullmatch(r'[0-9a-f]{40}', value) and set(value) != {'0'} for value in (base, head)):
            raise ValueError('invalid diff identity')
        def git(*args):
            return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE).decode().strip()
        if git('rev-parse', 'HEAD') != head or git('status', '--porcelain', '--untracked-files=all'):
            raise ValueError('not a clean exact checkout')
        base = git('merge-base', base, head)
        paths = git('diff', '--no-renames', '--name-only', '-z', base, head).strip('\0').split('\0')
        if not paths or paths == ['']:
            raise ValueError('empty diff')
        affected = sorted(path for path in paths if path in DRIVER_INPUTS or path.startswith(('.github/workflows/', 'Scripts/', 'Tests/Governance/')))
        if affected:
            return True, 'driver inputs: ' + ', '.join(affected)
        unknown = sorted(path for path in paths if not known_unrelated(path))
        if unknown:
            return True, 'unknown driver impact: ' + ', '.join(unknown)
        return False, 'known unrelated paths; driver inputs unchanged'
    except (KeyError, ValueError, OSError, subprocess.SubprocessError):
        return True, 'unavailable/ambiguous diff; conservative driver coverage'


def cases(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from cases(test)
        else:
            yield test


def selection(suite, include_driver):
    all_cases = list(cases(suite))
    selected = [test for test in all_cases if include_driver or test.id().split('.')[0] != DRIVER]
    ids = [test.id() for test in selected]
    if not ids or len(ids) != len(set(ids)):
        raise ValueError('empty/duplicate governance inventory')
    if not any(test.id().split('.')[0] == DRIVER for test in all_cases):
        raise ValueError('driver inventory missing; cannot prove scoped exclusion')
    if len(all_cases) != len({test.id() for test in all_cases}):
        raise ValueError('duplicate discovered governance inventory')
    return unittest.TestSuite(selected), ids, [test.id() for test in all_cases if test.id() not in set(ids)]


def main():
    include_driver, reason = driver_required(ROOT, os.environ)
    suite = unittest.defaultTestLoader.discover(str(ROOT / 'Tests/Governance'), pattern='test_*.py')
    selected, expected, omitted = selection(suite, include_driver)
    print('GOVERNANCE: ' + reason, flush=True)
    result = unittest.TextTestRunner(verbosity=2).run(selected)
    passed = result.wasSuccessful() and result.testsRun == len(expected) and not result.skipped
    report = dict(status='passed' if passed else 'failed', driverRequired=include_driver,
                  reason=reason, expected=expected, omitted=omitted, executed=result.testsRun,
                  failures=len(result.failures), errors=len(result.errors), skipped=len(result.skipped))
    path = ROOT / '.build/verification/governance-results.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + '\n')
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
