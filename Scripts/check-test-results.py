#!/usr/bin/env python3
"""Require actual passing cases from every registered target; reject zero/skipped/missing tests."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('boundary_policy', ROOT / 'Scripts/check-boundaries.py')
DEFER_SPEC = importlib.util.spec_from_file_location('ci_defer', ROOT / 'Scripts/ci-deferred-policy.py')
DEFER = importlib.util.module_from_spec(DEFER_SPEC)
DEFER_SPEC.loader.exec_module(DEFER)
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


def _deferred_timeouts():
    return {method: identifier for identifier, (method, kind) in DEFER.IDS.items()
            if kind == 'whole-method-execution-allowance-60s'}


def _native_result(summary, tree, scope, execution, details=None, issues=None, log=''):
    """Classify only the approved whole-method timeouts; keep raw objects intact."""
    command, wrapper = execution.get('commandExitCode'), execution.get('exitCode')
    POLICY.require(type(command) is int and type(wrapper) is int, 'TEST-RESULT: missing original exits')
    POLICY.require(execution.get('state') == 'stream-stopped-by-owner'
                   and execution.get('diagnosticErrors') == [], 'TEST-RESULT: collector/command failure')
    if summary.get('result') == 'Passed':
        POLICY.require(not summary.get('testFailures', []), 'TEST-RESULT: passing summary has failure/crash records')

    def contradictions(node, passing=False):
        passing = passing or (node.get('nodeType') == 'Test Case' and node.get('result') == 'Passed')
        POLICY.require(not (passing and node.get('nodeType') in {'Failure Message', 'Crash', 'Error'}),
                       'TEST-RESULT: passing case contains failure/crash evidence')
        for child in node.get('children', []):
            contradictions(child, passing)

    for node in tree['testNodes']:
        contradictions(node)
    if command == wrapper == 0:
        counts = validate_inventory(summary, tree, scope)
        return dict(status='passed', counts=counts, deferred=[], nativeExitCode=command, wrapperExitCode=wrapper)
    DEFER.load()
    POLICY.require(command == wrapper == 65, 'TEST-RESULT: unknown nonzero execution failure')
    allowed = _deferred_timeouts()
    failed = summary.get('testFailures', [])
    POLICY.require(summary.get('result') == 'Failed'
                   and isinstance(failed, list) and 1 <= len(failed) <= len(allowed)
                   and summary.get('failedTests') == len(failed)
                   and summary.get('skippedTests') == summary.get('expectedFailures') == 0
                   and summary.get('runtimeWarnings', []) == [],
                   'TEST-RESULT: not an isolated native test failure')
    failures = {}
    for failure in failed:
        POLICY.require(isinstance(failure, dict) and failure.get('targetName') == 'CoolMalliOSUITests',
                       'TEST-RESULT: failure outside exact deferred timeout')
        short = failure.get('testIdentifierString')
        full = 'CoolMalliOSUITests/' + (short or '')
        POLICY.require(full in allowed and full not in failures
                       and failure.get('failureText') == DEFER.TIMEOUT_TEXT,
                       'TEST-RESULT: failure outside exact deferred timeout')
        failures[full] = allowed[full]

    normalized_tree = copy.deepcopy(tree)
    matching = []

    def visit(node, bundle=None):
        if node.get('nodeType') in ('Unit test bundle', 'UI test bundle'):
            bundle = node.get('name')
        if node.get('nodeType') == 'Test Case' and node.get('result') != 'Passed':
            matching.append((bundle, node))
        for child in node.get('children', []):
            visit(child, bundle)

    for node in normalized_tree['testNodes']:
        visit(node)
    POLICY.require(len(matching) == len(failures), 'TEST-RESULT: multiple/nonpassing native methods')
    seen = set()
    for bundle, case in matching:
        full = str(bundle) + '/' + str(case.get('nodeIdentifier', ''))
        POLICY.require(full in failures and full not in seen
                       and case.get('result') == 'Failed' and case.get('durationInSeconds') == 60
                       and case.get('children') == [{'name': DEFER.TIMEOUT_TEXT, 'nodeType': 'Failure Message'}],
                       'TEST-RESULT: timeout mixed with assertion/crash/unknown failure')
        seen.add(full)
    POLICY.require(seen == set(failures), 'TEST-RESULT: missing/mismatched native timeout method')

    detail_items = [details] if isinstance(details, dict) else details
    POLICY.require(isinstance(detail_items, list) and len(detail_items) == len(failures),
                   'TEST-RESULT: missing/mismatched native failure details')
    detail_methods = set()
    for detail in detail_items:
        POLICY.require(isinstance(detail, dict) and detail.get('testResult') == 'Failed'
                       and detail.get('durationInSeconds') == 60,
                       'TEST-RESULT: missing/mismatched native failure details')
        short = detail.get('testIdentifier')
        full = 'CoolMalliOSUITests/' + (short or '')
        POLICY.require(full in failures and full not in detail_methods,
                       'TEST-RESULT: missing/mismatched native failure details')
        detail_methods.add(full)
        runs = []

        def detail_walk(node):
            if node.get('nodeType') == 'Test Case Run':
                runs.append(node)
            for child in node.get('children', []):
                detail_walk(child)

        for node in detail.get('testRuns', []):
            detail_walk(node)
        POLICY.require(len(runs) == 1 and runs[0].get('result') == 'Failed'
                       and runs[0].get('name') == DEFER.TIMEOUT_TEXT
                       and all(n.get('nodeType') == 'Attachment' for n in runs[0].get('children', [])),
                       'TEST-RESULT: native run details contain other failures')
    POLICY.require(detail_methods == set(failures), 'TEST-RESULT: missing/mismatched native failure details')

    POLICY.require(isinstance(issues, dict), 'TEST-RESULT: missing original issue inventory')
    def issue_name(full):
        return full.split('/', 1)[1].replace('/', '.', 1)

    def check_issues(node):
        own = node.get('issues')
        if own is not None:
            POLICY.require(not own.get('errorSummaries', {}).get('_values', []),
                           'TEST-RESULT: native build/runtime error')
            for item in own.get('testFailureSummaries', {}).get('_values', []):
                POLICY.require(item.get('message', {}).get('_value') == DEFER.TIMEOUT_TEXT
                               and item.get('issueType', {}).get('_value') == 'Uncategorized',
                               'TEST-RESULT: native issues contain assertion/crash/unknown failure')
        for value in node.values():
            if isinstance(value, dict):
                check_issues(value)
            elif isinstance(value, list):
                for item in value:
                    if isinstance(item, dict):
                        check_issues(item)

    root_issues = issues.get('issues', {})
    root_failures = root_issues.get('testFailureSummaries', {}).get('_values', [])
    POLICY.require(len(root_failures) == len(failures),
                   'TEST-RESULT: incomplete native issue inventory')
    issue_methods = set()
    for item in root_failures:
        name = item.get('testCaseName', {}).get('_value')
        candidates = [method for method in failures if issue_name(method) == name]
        POLICY.require(len(candidates) == 1, 'TEST-RESULT: native issue method mismatch')
        issue_methods.add(candidates[0])
    POLICY.require(issue_methods == set(failures), 'TEST-RESULT: native issue method mismatch')
    action_failures = 0
    for action in issues.get('actions', {}).get('_values', []):
        action_failures += len(action.get('actionResult', {}).get('issues', {})
                               .get('testFailureSummaries', {}).get('_values', []))
    POLICY.require(action_failures == len(failures), 'TEST-RESULT: incomplete native issue inventory')
    check_issues(issues)

    # Check the original execution log too: a timeout summary never excuses an
    # App crash/assertion elsewhere that the summary or issue tree omitted.
    import re
    restart = 'Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.'
    other_log = '\n'.join(line for line in log.splitlines() if line != restart)
    POLICY.require(log and not re.search(r'(?im)(XCTAssert[^\n]*failed|Assertion Failure|'
                                         r'Crash:|Crashed:|crashed|unexpected exit|signal (?:6|9|11)|'
                                         r'Test runner[^\n]*(?:exited|failed)|^error:)', other_log),
                   'TEST-RESULT: missing log or additional assertion/crash/runner error')

    for _, case in matching:
        case['result'] = 'Passed'
    normalized = dict(summary, result='Passed', failedTests=0,
                      passedTests=summary['passedTests'] + len(failures))
    counts = validate_inventory(normalized, normalized_tree, scope)
    order = {method: index for index, method in enumerate(DEFER.TIMEOUT_METHODS)}
    deferred = [DEFER.warning(failures[method],
                              'Original whole-method 60-second timeout retained; final assertions not reached',
                              method=method)
                for method in sorted(failures, key=order.__getitem__)]
    return dict(status='core-passed-with-deferred', counts=counts,
                nativeExitCode=command, wrapperExitCode=wrapper,
                nativeCounts={key: summary[key] for key in
                              ['totalTestCount', 'passedTests', 'failedTests', 'skippedTests']},
                deferred=deferred)

def method_inventory(tree):
    methods = {}
    def visit(node, bundle=None):
        if node.get('nodeType') in ('Unit test bundle', 'UI test bundle'):
            bundle = node.get('name')
        if node.get('nodeType') == 'Test Case':
            POLICY.require(isinstance(bundle, str) and isinstance(node.get('nodeIdentifier'), str),
                           'TEST-RESULT: invalid native method identity')
            method = bundle + '/' + node['nodeIdentifier']
            POLICY.require(method not in methods, 'TEST-RESULT: duplicate native method')
            POLICY.require(node.get('result') in {'Passed', 'Failed', 'Skipped', 'Expected Failure'},
                           'TEST-RESULT: unknown native method result')
            methods[method] = node['result']
        for child in node.get('children', []): visit(child, bundle)
    for node in tree['testNodes']: visit(node)
    POLICY.require(methods, 'TEST-RESULT: empty native method inventory')
    return methods


def native_result(summary, tree, scope, execution, details=None, issues=None, log=''):
    report = _native_result(summary, tree, scope, execution, details, issues, log)
    report['methodResults'] = method_inventory(tree)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xcresult', type=Path)
    parser.add_argument('--scope', type=Path, required=True)
    parser.add_argument('--execution-status', type=Path, required=True)
    parser.add_argument('--tests-log', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    expected = set(POLICY.read_policy(ROOT / 'ENGINEERING.md')['tests']) | {'CoolMalliOSUITests'}
    retained = {}
    try:
        DEFER.load(active=False)
        values = []
        def native(command, *flags):
            result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', command,
                                     '--path', str(args.xcresult), *flags],
                                    capture_output=True, text=True, check=True)
            data = json.loads(result.stdout)
            (args.output.parent / args.xcresult.with_suffix('.' + command + '.json').name).write_text(result.stdout)
            return data
        for command in ['summary', 'tests']: values.append(native(command))
        retained['methodResults'] = method_inventory(values[1])
        retained['nativeCounts'] = {key: values[0].get(key) for key in ['totalTestCount', 'passedTests', 'failedTests', 'skippedTests']}
        scope = json.loads(args.scope.read_text())
        spec = importlib.util.spec_from_file_location('scope', ROOT / 'Scripts/select-test-scope.py')
        selector = importlib.util.module_from_spec(spec); spec.loader.exec_module(selector)
        selector.validate_manifest(scope)
        POLICY.require(set(scope['expected']) <= set(scope['discovered']), 'TEST-RESULT: invalid selected inventory')
        POLICY.require({method.split('/')[0] for method in scope['discovered']} == expected, 'TEST-RESULT: unregistered discovery target')
        details, issues = None, None
        if values[0].get('failedTests'):
            # Fetch every failed method detail, not only the allowed method.
            details_all = [native('test-details', '--test-id', v['testIdentifierString'])
                           for v in values[0].get('testFailures', [])]
            (args.output.parent / args.xcresult.with_suffix('.failure-details.json').name).write_text(json.dumps(details_all, indent=2) + '\n')
            details = details_all[0] if len(details_all) == 1 else details_all
            result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'object', '--legacy',
                                     '--format', 'json', '--path', str(args.xcresult)],
                                    capture_output=True, text=True, check=True)
            issues = json.loads(result.stdout)
            (args.output.parent / args.xcresult.with_suffix('.issues.json').name).write_text(result.stdout)
        report = native_result(*values, scope, json.loads(args.execution_status.read_text()),
                               details, issues, args.tests_log.read_text())
        code = 0
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        report, code = dict(retained, status='failed', error=str(error), deferred=[]), 1
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print('TEST-RESULT: ' + report['status'])
    return code

if __name__ == '__main__': sys.exit(main())
