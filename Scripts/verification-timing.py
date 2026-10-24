#!/usr/bin/env python3
"""Durable timing for verify-local.sh; never interprets test results."""
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

PHASES = [
    'configuration', 'environment', 'format', 'policy-negative',
    'build-Debug', 'build-Release', 'simulator-prepare',
    'test-build-discovery', 'test-runner-prepare', 'test-execute-diagnostics', 'test-result-validation',
]


def utc():
    return datetime.now(timezone.utc).isoformat()


def save(path, data):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


# Python 3.9 on macOS gives time.monotonic() a process-local origin.
# Explicit CLOCK_MONOTONIC is system-wide across these short-lived invocations.
def complete(phase, code, outcome):
    phase.update(status=outcome, exitCode=code, finishedAtUTC=utc(),
                 durationSeconds=time.clock_gettime(time.CLOCK_MONOTONIC) - phase['startedMonotonic'])


def markdown(data):
    lines = ['### Verification stage timings', '',
             'Durations use a monotonic clock. Test discovery includes test compilation; execution includes requested diagnostics.',
             'An incomplete stage has no confirmed exit; not-run stages did not pass.', '',
             '| Stage | Status | Seconds | Exit |', '| --- | --- | ---: | ---: |']
    for phase in data['phases']:
        status = 'incomplete' if phase['status'] == 'running' else phase['status']
        duration = phase.get('durationSeconds')
        seconds = f"{duration:.3f}" if duration is not None else '—'
        code = phase.get('exitCode')
        lines.append(f"| {phase['name']} | {status} | {seconds} | {code if code is not None else '—'} |")
    lines += ['', f"Verification gates exit: {data.get('verificationExitCode', 'unconfirmed')}",
              f"Verification entry exit: {data.get('entryExitCode', 'unconfirmed')}",
              f"Recording failure: {data.get('recordingFailure', False)}", '']
    return '\n'.join(lines)


def main(argv):
    command, filename, *args = argv
    path = Path(filename)
    if command == 'report-all':
        reports = sorted(path.glob('*/stage-timings.json'))
        if not reports:
            print('Verification stages were not started; no stage is reported as passed.')
        for report in reports:
            text = markdown(json.loads(report.read_text()))
            report.with_suffix('.md').write_text(text)
            print(text)
        return
    if command == 'init':
        if path.exists():
            raise ValueError('refusing to overwrite a timing ledger')
        save(path, {'startedAtUTC': utc(), 'phases': [
            {'name': name, 'status': 'not-run'} for name in PHASES]})
        return
    data = json.loads(path.read_text())
    active = [phase for phase in data['phases'] if phase['status'] == 'running']
    if command == 'start':
        if active:
            raise ValueError('previous phase is still running')
        phase = next(phase for phase in data['phases'] if phase['name'] == args[0])
        if phase['status'] != 'not-run':
            raise ValueError('phase already executed')
        phase.update(status='running', startedAtUTC=utc(), startedMonotonic=time.clock_gettime(time.CLOCK_MONOTONIC))
    elif command == 'end':
        if len(active) != 1:
            raise ValueError('expected exactly one active phase')
        complete(active[0], 0, 'passed')
    elif command == 'finalize':
        code = int(args[0])
        outcome = args[1]
        if outcome not in ('failed', 'cancelled'):
            raise ValueError('invalid final outcome')
        if code == 0 and any(phase['status'] != 'passed' for phase in data['phases']):
            raise ValueError('successful exit with incomplete phases')
        for phase in active:
            complete(phase, code, outcome)
        data.update(verificationExitCode=code, entryExitCode=code, finishedAtUTC=utc())
    elif command == 'recording-failed':
        data.update(entryExitCode=int(args[0]), recordingFailure=True)
    elif command == 'report':
        print(markdown(data))
        return
    else:
        raise ValueError('unknown timing command')
    save(path, data)


if __name__ == '__main__':
    main(sys.argv[1:])
