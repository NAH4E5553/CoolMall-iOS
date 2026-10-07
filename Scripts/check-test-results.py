#!/usr/bin/env python3
"""Require actual passing cases from every registered target; reject zero/skipped/missing tests."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('boundary_policy', ROOT / 'Scripts/check-boundaries.py')
POLICY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(POLICY)


def validate(summary, tree, expected):
    POLICY.require(summary['result'] == 'Passed' and summary['failedTests'] == summary['skippedTests'] == summary['expectedFailures'] == 0, 'TEST-RESULT: failures/skips/unexpected result')
    counts = {}
    def visit(node, bundle=None):
        name = node.get('name')
        if name in expected:
            bundle = name
            counts.setdefault(bundle, 0)
        if node.get('nodeType') == 'Test Case':
            POLICY.require(bundle in expected and node.get('result') == 'Passed', 'TEST-RESULT: unregistered or nonpassing case')
            counts[bundle] += 1
        for child in node.get('children', []): visit(child, bundle)
    for node in tree['testNodes']: visit(node)
    POLICY.require(set(counts) == set(expected) and all(counts.values()), f'TEST-RESULT: missing/empty test target; actual={counts}, expected={sorted(expected)}')
    POLICY.require(sum(counts.values()) == summary['totalTestCount'] == summary['passedTests'], 'TEST-RESULT: count mismatch')
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xcresult', type=Path)
    args = parser.parse_args()
    expected = set(POLICY.read_policy(ROOT / 'ENGINEERING.md')['tests']) | {'CoolMalliOSUITests'}
    try:
        values = []
        for command in ['summary', 'tests']:
            result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', command, '--path', str(args.xcresult)], capture_output=True, text=True, check=True)
            data = json.loads(result.stdout)
            args.xcresult.with_suffix('.' + command + '.json').write_text(result.stdout)
            values.append(data)
        counts = validate(*values, expected)
        print('PASS: actual passing test counts: ' + json.dumps(counts, sort_keys=True))
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__': sys.exit(main())
