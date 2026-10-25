#!/usr/bin/env python3
"""Print per-test durations and slow-test warnings from xcodebuild tests.log.

Telemetry only: this script never changes the verification verdict.
"""
import argparse
import re
import statistics
from pathlib import Path

XCTEST = re.compile(
    r"Test Case '-\[[^\]]+?\.([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]' "
    r"(passed|failed) \(([0-9.]+) seconds\)"
)
SWIFT_TESTING = re.compile(r'^✔ Test (.+?) (?:passed|failed) after ([0-9.]+) seconds\.$', re.M)


def durations(path):
    text = Path(path).read_text(encoding='utf-8', errors='replace')
    values = []
    for match in XCTEST.finditer(text):
        values.append((f'{match.group(1)}/{match.group(2)}()', match.group(3), float(match.group(4))))
    for match in SWIFT_TESTING.finditer(text):
        values.append((match.group(1).strip(), 'swift-testing', float(match.group(2))))
    return values


def markdown(values, top, slow):
    if not values:
        return '### Test durations\n\nNo XCTest/Swift Testing durations found.\n'
    ordered = sorted(values, key=lambda item: item[2], reverse=True)
    seconds = [item[2] for item in ordered]
    p50 = statistics.median(seconds)
    p95 = ordered[max(0, min(len(ordered) - 1, int(len(ordered) * 0.05) - 1))][2]
    lines = [
        '### Test durations',
        '',
        f'- tests recorded: {len(ordered)}',
        f'- slowest: {ordered[0][2]:.3f}s ({ordered[0][0]})',
        f'- p50/p95: {p50:.3f}s / {p95:.3f}s',
        f'- at/over {slow:g}s: {sum(1 for value in seconds if value >= slow)}',
        '',
        '| test | result | seconds |',
        '| --- | --- | ---: |',
    ]
    for name, result, value in ordered[:top]:
        lines.append(f'| {name} | {result} | {value:.3f} |')
    over = [item for item in ordered if item[2] >= slow]
    if over:
        lines += ['', f'#### At/over {slow:g}s', '']
        for name, result, value in over[:top]:
            lines.append(f'- {name}: {value:.3f}s ({result})')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tests_log', type=Path)
    parser.add_argument('--top', type=int, default=20)
    parser.add_argument('--slow', type=float, default=45)
    args = parser.parse_args()
    if not args.tests_log.is_file():
        print(f'test-duration-summary: missing {args.tests_log}', file=__import__('sys').stderr)
        return 2
    print(markdown(durations(args.tests_log), args.top, args.slow))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
