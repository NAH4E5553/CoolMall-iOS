#!/usr/bin/env python3
"""Publish a truthful core/deferred/failed verdict; never changes raw native results."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('ci_defer', Path(__file__).with_name('ci-deferred-policy.py'))
POLICY = importlib.util.module_from_spec(spec); spec.loader.exec_module(POLICY)
STATUSES = {'core-passed', 'core-passed-with-deferred', 'failed'}


def verdict(native, audit, prior_exit):
    POLICY.load(active=False)
    if prior_exit != 0:
        return dict(status='failed', deferred=[], priorExitCode=prior_exit,
                    reason='An earlier gate/recording/audit failed')
    if native.get('status') not in {'passed', 'core-passed-with-deferred'}:
        raise ValueError('VERDICT: native result missing/failed')
    if audit.get('status') not in {'passed', 'recorded-prefix', 'not-required', 'core-passed-with-deferred'}:
        raise ValueError('VERDICT: lifecycle result missing/failed')
    if any(v.get('status') == 'failed' for v in audit.get('methods', {}).values()):
        raise ValueError('VERDICT: blocking method audit')
    command, wrapper = native.get('nativeExitCode'), native.get('wrapperExitCode')
    warnings = native.get('deferred', []) + audit.get('deferred', [])
    if (command, wrapper) not in {(0, 0), (65, 65)}:
        raise ValueError('VERDICT: unknown original exit code')
    if command == 65 and not any(v.get('id') == 'CI-DEFER-HOME-TIMEOUT-01' for v in native.get('deferred', [])):
        raise ValueError('VERDICT: native failure not classified')
    if warnings: POLICY.load()
    for warning in warnings:
        if (warning.get('id') not in POLICY.IDS or warning.get('state') != 'deferred-unresolved'
                or warning.get('method') != POLICY.IDS[warning['id']][0] or not warning.get('reason')):
            raise ValueError('VERDICT: unknown/invalid deferred result')
    if audit.get('status') == 'recorded-prefix' and command == 0:
        raise ValueError('VERDICT: successful command has incomplete lifecycle execution')
    return dict(status='core-passed-with-deferred' if warnings else 'core-passed', deferred=warnings,
                deferredIssueCount=len({v['id'] for v in warnings}),
                nativeExitCode=command, wrapperExitCode=wrapper,
                nativeResult=native['status'], lifecycleResult=audit['status'],
                scope='Only executed exact inventory; no release or complete acceptance claim')


def markdown(data):
    label = {'core-passed': 'Core checks passed for the executed scope',
             'core-passed-with-deferred': '核心检查通过，但存在延期问题 / Core checks passed with deferred issues',
             'failed': 'Blocking verification failure'}[data['status']]
    lines = ['### ' + label, '', 'This is not a claim that all acceptance issues are closed.']
    for warning in data.get('deferred', []):
        lines.append('- ' + warning['id'] + ': ' + warning['reason'])
    if data.get('reason'): lines.append('- ' + data['reason'])
    lines += ['', 'Original native/wrapper exits: ' + str(data.get('nativeExitCode', 'unavailable'))
              + '/' + str(data.get('wrapperExitCode', 'unavailable'))]
    return '\n'.join(lines) + '\n'


def main():
    p = argparse.ArgumentParser()
    p.add_argument('directory', type=Path)
    p.add_argument('--prior-exit', type=int, required=True)
    args = p.parse_args()
    code = args.prior_exit
    try:
        native = json.loads((args.directory/'native-results.json').read_text()) if code == 0 else {}
        audit = json.loads((args.directory/'banner-audit.json').read_text()) if code == 0 else {}
        data = verdict(native, audit, code)
    except (ValueError, OSError, KeyError, TypeError) as error:
        data = dict(status='failed', deferred=[], reason=str(error), priorExitCode=code)
        code = code or 65
    (args.directory/'verification-verdict.json').write_text(json.dumps(data, indent=2) + '\n')
    (args.directory/'verification-verdict.md').write_text(markdown(data))
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write('verification_status=' + data['status'] + '\n')
            output.write('deferred_count=' + str(data.get('deferredIssueCount', 0)) + '\n')
    print(markdown(data))
    return code


if __name__ == '__main__': sys.exit(main())
