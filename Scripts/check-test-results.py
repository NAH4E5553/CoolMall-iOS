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


def validate_inventory(summary, tree, scope):
    """Compare stable method IDs, not display labels or parameterized row counts."""
    expected = scope['expected']
    POLICY.require(expected and len(expected) == len(set(expected)), 'TEST-RESULT: empty/duplicate expected inventory')
    targets = {method.split('/')[0] for method in expected}
    counts = validate(summary, tree, targets)
    actual, arguments = set(), set()
    def visit(node, bundle=None):
        if node.get('nodeType') in ('Unit test bundle', 'UI test bundle'):
            POLICY.require(node.get('name') in targets, 'TEST-RESULT: unregistered test bundle')
            bundle = node['name']
        if node.get('nodeType') == 'Test Case':
            POLICY.require(bundle in targets, 'TEST-RESULT: missing or unsupported test bundle')
            method = bundle + '/' + node['nodeIdentifier']
            POLICY.require(method in expected and method not in actual, 'TEST-RESULT: unexpected/duplicate method: ' + method)
            actual.add(method)
        if node.get('nodeType') == 'Arguments':
            key = node['nodeIdentifierURL']
            POLICY.require(node.get('result') == 'Passed' and key not in arguments, 'TEST-RESULT: failed/skipped/duplicate arguments')
            arguments.add(key)
        for child in node.get('children', []):
            visit(child, bundle)
    for node in tree['testNodes']:
        visit(node)
    POLICY.require(actual == set(expected), 'TEST-RESULT: missing executed methods: ' + str(sorted(set(expected) - actual)))
    return {'methodCounts': counts, 'parameterArgumentRecordCount': len(arguments)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xcresult', type=Path)
    parser.add_argument('--scope', type=Path, required=True)
    args = parser.parse_args()
    expected = set(POLICY.read_policy(ROOT / 'ENGINEERING.md')['tests']) | {'CoolMalliOSUITests'}
    try:
        values = []
        for command in ['summary', 'tests']:
            result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', command, '--path', str(args.xcresult)], capture_output=True, text=True, check=True)
            data = json.loads(result.stdout)
            args.xcresult.with_suffix('.' + command + '.json').write_text(result.stdout)
            values.append(data)
        scope = json.loads(args.scope.read_text())
        spec = importlib.util.spec_from_file_location('scope', ROOT / 'Scripts/select-test-scope.py')
        selector = importlib.util.module_from_spec(spec); spec.loader.exec_module(selector)
        selector.validate_manifest(scope)
        POLICY.require(set(scope['expected']) <= set(scope['discovered']), 'TEST-RESULT: invalid selected inventory')
        POLICY.require({method.split('/')[0] for method in scope['discovered']} == expected, 'TEST-RESULT: unregistered discovery target')
        counts = validate_inventory(*values, scope)
        print('PASS: exact passing test inventory: ' + json.dumps(counts, sort_keys=True))
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__': sys.exit(main())
