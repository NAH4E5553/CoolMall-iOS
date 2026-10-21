#!/usr/bin/env python3
"""Stream opt-in DEBUG carousel events; retain test failure/cancellation codes."""
import argparse
import json
import re
import signal
import subprocess
import sys
import time
from pathlib import Path


class Cancelled(Exception):
    pass


MESSAGE = re.compile(
    r'^\s*(?:\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{4})?\s+'
    r'[^\[\]\r\n]+\[\d+:[^\]\r\n]+\]\s*(?:\([^\)\r\n]*\)\s*)?)?'
    r'(?P<payload>(?:AUTOTRACE |BANNERAUDIT |BANNERAUDIT_ERROR(?:\s|$)|BANNERTEST ).*)$')


def payloads(text):
    """Read only raw messages or messages after a real compact/NSLog prefix.

    log stream prints its predicate in a header. Prefixes quoted in that
    header (or another message's body) are not audit records or source errors.
    Malformed JSON after a real audit prefix remains a record for rejection.
    """
    for line in text.splitlines():
        match = MESSAGE.match(line)
        if match:
            yield match['payload']


def run(simulator, output, command):
    output = Path(output)
    status = {'command': command, 'state': 'starting', 'startedMonotonic': time.monotonic()}
    code = 65
    diagnostic_errors = []
    collector = test = None
    command_code = None
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
            # ProcessInfo.systemUptime and macOS CLOCK_UPTIME_RAW exclude
            # sleep. time.monotonic() here has a process-relative origin.
            uptime_clock = getattr(time, 'CLOCK_UPTIME_RAW', None)
            status['clockDomain'] = 'system-uptime-raw' if uptime_clock is not None else 'unavailable'
            if uptime_clock is not None:
                status['collectorStartRequestedUptime'] = time.clock_gettime(uptime_clock)
            collector = subprocess.Popen([
                'xcrun', 'simctl', 'spawn', simulator, 'log', 'stream',
                '--level', 'debug', '--style', 'compact', '--predicate',
                '(eventMessage BEGINSWITH "AUTOTRACE ") OR (eventMessage BEGINSWITH "BANNERAUDIT ") OR (eventMessage BEGINSWITH "BANNERAUDIT_ERROR")'], stdout=stream, stderr=subprocess.STDOUT)
            status.update(state='stream-started', pid=collector.pid)
            save()
            if uptime_clock is not None:
                status['testStartRequestedUptime'] = time.clock_gettime(uptime_clock)
            test = subprocess.Popen(command)
            status['collectorOrderedBeforeTest'] = True
            code = test.wait()
            code = code if code >= 0 else 128 - code
            command_code = code
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
        trace = output.read_text(errors='replace')
        messages = list(payloads(trace))
        status['eventsObserved'] = any(m.startswith(('AUTOTRACE ', 'BANNERAUDIT ')) for m in messages)
        status['auditEventsObserved'] = any(m.startswith('BANNERAUDIT ') for m in messages)
        if any(m.startswith('BANNERAUDIT_ERROR') for m in messages):
            error('source audit encoding/recording error')
    except OSError as exc:
        error('trace read: ' + str(exc))
    status.update(exitCode=code, commandExitCode=command_code,
                  finishedMonotonic=time.monotonic(), diagnosticErrors=diagnostic_errors)
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
