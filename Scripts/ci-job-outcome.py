#!/usr/bin/env python3
"""Describe existing CI step failures; never changes their conclusions or exits."""
import json
import os
from pathlib import Path

CATEGORIES = {
    'support': 'governance', 'environment': 'environment', 'gates': 'verification',
    'summary': 'evidence', 'verdict': 'evidence', 'artifacts': 'evidence',
}


def category(steps, ledger=None):
    for name, kind in CATEGORIES.items():
        result = steps.get(name, {}).get('conclusion')
        if result in {'failure', 'cancelled'}:
            if name == 'gates':
                phases = (ledger or {}).get('phases', [])
                failed = [p.get('name') for p in phases if p.get('status') in {'failed', 'cancelled'}]
                stage = failed[0] if failed else None
                if stage in {'configuration', 'environment', 'simulator-prepare'}:
                    kind = 'environment'
                elif stage in {'format', 'policy-negative'}:
                    kind = 'governance'
                elif stage in {'build-Debug', 'build-Release', 'test-build-discovery'}:
                    kind = 'build-or-discovery'
                elif stage == 'test-execute-diagnostics':
                    kind = 'native-test-or-runner-failure'
                elif stage == 'test-result-validation':
                    kind = 'result-validation'
            return kind
    return 'none' if steps.get('gates', {}).get('conclusion') == 'success' else 'unclassified'


def main():
    steps = json.loads(os.environ['MALL_CI_STEPS'])
    ledger = None
    paths = sorted(Path('.build/verification').glob('*/stage-timings.json'))
    if len(paths) == 1:
        try:
            ledger = json.loads(paths[0].read_text())
        except (OSError, ValueError):
            pass
    value = category(steps, ledger)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write('failure_category=' + value + '\n')
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
        summary.write('\nCI failure category: ' + value + '. Original job/command results remain authoritative.\n')
    print(value)


if __name__ == '__main__':
    main()
