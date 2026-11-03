#!/usr/bin/env python3
"""Report A/B experiment shard results; never combines passing subsets into green."""
import json
import subprocess
import sys
from pathlib import Path


def main(root):
    root = Path(root)
    parent = (root / 'shards' / 'expected-all.txt').read_text().splitlines()
    parent_set = set(parent)
    report = {}
    for group in ('A', 'B-nonui', 'B-ui'):
        out = root / group
        scope = root / 'shards' / f"scope-{ {'A':'all','B-nonui':'nonui','B-ui':'ui'}[group] }.json"
        result = out / 'Tests.xcresult'
        tests = out / 'tests.log'
        status = out / 'banner-trace.status.log'
        native = out / 'native-results.json'
        cmd = [sys.executable, str(Path(__file__).parents[1] / 'Scripts/check-test-results.py'),
               str(result), '--scope', str(scope), '--execution-status', str(status),
               '--tests-log', str(tests), '--output', str(native)]
        check = subprocess.run(cmd, capture_output=True, text=True)
        methods = {}
        if native.is_file():
            methods = json.loads(native.read_text()).get('methodResults', {})
        audit = None
        if group in ('A', 'B-ui'):
            audit_cmd = [sys.executable, str(Path(__file__).parents[1] / 'Scripts/check-banner-lifecycle.py'),
                         '--scope', str(scope), '--trace', str(out / 'banner-trace.log'),
                         '--tests-log', str(tests), '--collector-status', str(status),
                         '--output', str(out / 'banner-audit.json'),
                         '--native-results', str(native),
                         '--test-exit', (out / 'exit.txt').read_text().strip()]
            audit_run = subprocess.run(audit_cmd, capture_output=True, text=True)
            audit = audit_run.returncode
            print(f"{group}: banner-audit exit={audit}")
        report[group] = {
            'checkExit': check.returncode,
            'auditExit': audit,
            'expected': len(json.loads(scope.read_text())['expected']),
            'executed': len(methods),
            'failed': sorted(k for k, v in methods.items() if v != 'Passed'),
        }
    executed = {}
    expected = {}
    for group, data in report.items():
        out = root / group
        native = out / 'native-results.json'
        methods = json.loads(native.read_text()).get('methodResults', {}) if native.is_file() else {}
        executed[group] = set(methods)
        expected[group] = set(json.loads((root / 'shards' / f"scope-{ {'A':'all','B-nonui':'nonui','B-ui':'ui'}[group] }.json").read_text())['expected'])
        missing = sorted(expected[group] - executed[group])
        extra = sorted(executed[group] - expected[group])
        print(f"{group}: checkExit={data['checkExit']} expected={data['expected']} "
              f"executed={data['executed']} failed={data['failed'][:3]} "
              f"missing={missing[:3]} extra={extra[:3]}")
        if missing or extra:
            return 1
    if executed['A'] != parent_set:
        print('EXPERIMENT: A does not equal immutable parent inventory')
        return 1
    if executed['B-nonui'] & executed['B-ui']:
        print('EXPERIMENT: B shards overlap')
        return 1
    if executed['B-nonui'] | executed['B-ui'] != parent_set:
        print('EXPERIMENT: B union does not equal immutable parent inventory')
        return 1
    print('A/B are separate verdicts; passing subsets are not combined into one green.')
    return 0 if all(v['checkExit'] == 0 and (v['auditExit'] in (None, 0)) for v in report.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1]))
