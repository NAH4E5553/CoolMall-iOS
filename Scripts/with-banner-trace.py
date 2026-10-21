#!/usr/bin/env python3
"""Stream opt-in DEBUG carousel events; retain test failure/cancellation codes."""
import argparse
import json
import signal
import subprocess
import sys
import time
from pathlib import Path


class Cancelled(Exception):
    pass


def run(simulator, output, command):
    output = Path(output)
    status = {'command': command, 'state': 'starting', 'startedMonotonic': time.monotonic()}
    code = 65
    diagnostic_errors = []
    collector = test = None
    interrupted = 0
    def error(message):
        diagnostic_errors.append(message)
        print('BANNER DIAGNOSTIC MISSING: ' + message, file=sys.stderr)
    def save():
        try:
            output.with_suffix('.status.log').write_text(json.dumps(status, indent=2) + '\n')
        except OSError as exc:
            error('status write: ' + str(exc))
    def stop(signum, _frame):
        nonlocal interrupted
        interrupted = signum
        raise Cancelled()
    def cleanup(process, label):
        if process is None:
            return
        try:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired) as exc:
            error(label + ' cleanup: ' + str(exc))
    previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        with output.open('w') as stream:
            collector = subprocess.Popen([
                'xcrun', 'simctl', 'spawn', simulator, 'log', 'stream',
                '--level', 'debug', '--style', 'compact', '--predicate',
                'eventMessage BEGINSWITH "AUTOTRACE "'], stdout=stream, stderr=subprocess.STDOUT)
            status.update(state='stream-started', pid=collector.pid)
            save()
            test = subprocess.Popen(command)
            code = test.wait()
            code = code if code >= 0 else 128 - code
            if collector.poll() is not None:
                error('stream exited before collection stopped: ' + str(collector.returncode))
            else:
                status['state'] = 'stream-stopped-by-owner'
    except Cancelled:
        code = 128 + interrupted
        status['state'] = 'cancelled'
    except OSError as exc:
        error(str(exc))
    finally:
        # Ignore repeated cancellation only during bounded cleanup of our own children.
        for sig in previous:
            signal.signal(sig, signal.SIG_IGN)
        cleanup(test, 'test')
        cleanup(collector, 'stream')
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    try:
        status['eventsObserved'] = 'AUTOTRACE ' in output.read_text(errors='replace')
    except OSError as exc:
        error('trace read: ' + str(exc))
    status.update(exitCode=code, finishedMonotonic=time.monotonic(), diagnosticErrors=diagnostic_errors)
    if diagnostic_errors and status['state'] != 'cancelled':
        status['state'] = 'diagnostic-missing'
    if code == 0 and diagnostic_errors:
        code = 65
    status['exitCode'] = code
    save()
    # Recording failures must not replace a prior business failure or cancellation.
    if code == 0 and diagnostic_errors:
        code = 65
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('simulator')
    parser.add_argument('output')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('test command required')
    return run(args.simulator, args.output, command)


if __name__ == '__main__':
    raise SystemExit(main())
