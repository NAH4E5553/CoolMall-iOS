#!/usr/bin/env python3
"""Require successful verification or an explicit, successful scope exclusion."""
import importlib.util
import json
from pathlib import Path
import os
import sys


SPEC = importlib.util.spec_from_file_location('ci_defer', Path(__file__).with_name('ci-deferred-policy.py'))
POLICY = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(POLICY)


def validate(needs):
    if set(needs) != {'classify', 'verify'}:
        raise ValueError(f'Unexpected required job set: {sorted(needs)}')
    classification = needs['classify']
    if classification['result'] != 'success':
        raise ValueError(f"classify result is {classification['result']}")
    outputs = classification['outputs']
    required = outputs['run_verification']
    actual = needs['verify']['result']
    if required == 'true':
        if actual != 'success':
            raise ValueError(f"verify result is {actual}; category={needs['verify'].get('outputs', {}).get('failure_category', 'unclassified')}; no product success inferred")
        POLICY.load(active=False)
        verdict = needs['verify'].get('outputs', {})
        status, count = verdict.get('verification_status'), verdict.get('deferred_count')
        if not isinstance(count, str) or not count.isdecimal():
            raise ValueError('Missing/invalid structured verification verdict')
        ids = json.loads(verdict.get('deferred_ids', 'null'))
        if (not isinstance(ids, list) or not all(isinstance(v, str) for v in ids)
                or len(ids) != len(set(ids)) or set(ids) - POLICY.IDS.keys()
                or str(len(ids)) != count):
            raise ValueError('Invalid deferred ID inventory/count')
        if status == 'core-passed' and int(count) == 0:
            return 'PASS: required implementation verification succeeded for its scope; iOS 17 remains pending.'
        if status == 'core-passed-with-deferred' and ids:
            POLICY.load()
            return 'WARNING: 核心检查通过，但存在延期问题 / Core checks passed with deferred issues; not complete acceptance.'
        raise ValueError('Missing/invalid structured verification verdict')
    if required == 'false' and outputs['reason'] == 'docs-or-placeholder-only':
        if actual != 'skipped':
            raise ValueError(f'Excluded verification unexpectedly returned {actual}')
        return 'PASS: documentation/placeholder-only change; build/tests not run or claimed passed.'
    raise ValueError('Missing or invalid classification decision')


def main():
    try:
        print(validate(json.loads(os.environ['MALL_CI_NEEDS'])))
    except (KeyError, ValueError, TypeError) as error:
        print(f'FAIL: required-checks: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
