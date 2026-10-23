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


def failed_verdict(native, audit, prior_exit, execution=None, errors=()):
    # Disclosure is independent of acceptance. A known warning must survive an
    # unrelated blocking failure, but never authorize a successful verdict.
    warnings, problems = [], list(errors)
    try:
        POLICY.load(active=False)
        for source, report, allowed in [('native', native, 'CI-DEFER-HOME-TIMEOUT-01'),
                                         ('lifecycle', audit, 'CI-DEFER-CYCLE-EVIDENCE-01')]:
            if report.get('status') not in {'passed', 'core-passed-with-deferred', 'failed', 'recorded-prefix', 'not-required'}:
                problems.append(source + ': unknown report status')
                continue
            items = report.get('deferred', [])
            if not isinstance(items, list):
                problems.append(source + ': invalid deferred list')
                continue
            for warning in items:
                if (not isinstance(warning, dict) or warning.get('id') != allowed
                        or warning.get('state') != 'deferred-unresolved'
                        or warning.get('method') != POLICY.IDS[allowed][0]
                        or not isinstance(warning.get('reason'), str) or not warning['reason'].strip()):
                    problems.append(source + ': unknown/invalid deferred result')
                    continue
                warnings.append(warning)
    except (ValueError, OSError, KeyError, TypeError) as error:
        warnings = []
        problems.append(str(error))
    data = dict(status='failed', deferred=warnings,
                deferredIssueCount=len({warning['id'] for warning in warnings}),
                priorExitCode=prior_exit, nativeResult=native.get('status', 'unavailable'),
                lifecycleResult=audit.get('status', 'unavailable'),
                reason='An earlier gate/recording/audit failed')
    # The execution sidecar is the original command/wrapper record. A failed
    # native classifier may intentionally omit those fields; never infer them
    # from the prior gate code or replace distinct command and wrapper exits.
    for field, raw_field in [('nativeExitCode', 'commandExitCode'), ('wrapperExitCode', 'exitCode')]:
        original = (execution or {}).get(raw_field)
        classified = native.get(field)
        if type(original) is int:
            data[field] = original
            data[field + 'Source'] = 'banner-trace.status.log.' + raw_field
            if type(classified) is int and classified != original:
                problems.append(field + ': execution/native records disagree')
        elif type(classified) is int:
            data[field] = classified
            data[field + 'Source'] = 'native-results.json.' + field
        else:
            data[field] = None
    if problems:
        data['disclosureErrors'] = problems
    return data


def verdict(native, audit, prior_exit, execution=None, errors=()):
    if prior_exit != 0:
        return failed_verdict(native, audit, prior_exit, execution, errors)
    POLICY.load(active=False)
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
    if 'verificationTier' in data:
        lines += ['', 'Tier: ' + data['verificationTier'] + '; execution: ' + data.get('executionMode', 'unavailable'),
                  'Scope: ' + data.get('scopeReason', 'unavailable') + '; expected/omitted methods: '
                  + str(data.get('expectedMethodCount', 0)) + '/' + str(data.get('omittedMethodCount', 0))]
    if data['status'] == 'failed' and data.get('deferred'):
        lines += ['', '已识别的延期项（阻塞失败保持不变） / Reported deferred issues (failure unchanged):']
    for warning in data.get('deferred', []):
        lines.append('- ' + warning['id'] + ': ' + warning['reason'])
    if data.get('reason'): lines.append('- ' + data['reason'])
    for error in data.get('disclosureErrors', []):
        lines.append('- Disclosure error: ' + error)
    exits = [str(data[key]) if data.get(key) is not None else 'unavailable'
             for key in ['nativeExitCode', 'wrapperExitCode']]
    lines += ['', 'Original native/wrapper exits: ' + '/'.join(exits)]
    if 'priorExitCode' in data:
        lines.append('Prior gate/entry exit: ' + str(data['priorExitCode']))
    return '\n'.join(lines) + '\n'


def main():
    p = argparse.ArgumentParser()
    p.add_argument('directory', type=Path)
    p.add_argument('--prior-exit', type=int, required=True)
    args = p.parse_args()
    code = args.prior_exit
    reports, errors = {}, []
    for name in ['native-results.json', 'banner-audit.json', 'banner-trace.status.log']:
        path = args.directory/name
        reports[name] = {}
        if name == 'banner-trace.status.log' and not path.exists():
            continue
        try:
            value = json.loads(path.read_text())
            if not isinstance(value, dict):
                raise ValueError('expected a JSON object')
            reports[name] = value
        except (ValueError, OSError) as error:
            errors.append(name + ': ' + str(error))
    native, audit, execution = (reports[name] for name in
                               ['native-results.json', 'banner-audit.json', 'banner-trace.status.log'])
    try:
        if code == 0 and errors:
            raise ValueError('; '.join(errors))
        data = verdict(native, audit, code, execution, errors)
    except (ValueError, OSError, KeyError, TypeError) as error:
        data = failed_verdict(native, audit, code, execution, [*errors, str(error)])
        code = code or 65
    try:
        scope = json.loads((args.directory/'test-scope.json').read_text())
        data['verificationTier'] = scope['tier']
        data['executionMode'] = scope['mode']
        data['scopeReason'] = scope['reason']
        data['expectedMethodCount'] = len(scope.get('expected', []))
        data['omittedMethodCount'] = len(scope.get('omitted', []))
    except (ValueError, OSError, KeyError, TypeError):
        data['verificationTier'] = 'unavailable'
    (args.directory/'verification-verdict.json').write_text(json.dumps(data, indent=2) + '\n')
    (args.directory/'verification-verdict.md').write_text(markdown(data))
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write('verification_status=' + data['status'] + '\n')
            output.write('deferred_count=' + str(data.get('deferredIssueCount', 0)) + '\n')
    print(markdown(data))
    return code


if __name__ == '__main__': sys.exit(main())
