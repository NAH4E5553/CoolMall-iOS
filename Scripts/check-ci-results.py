#!/usr/bin/env python3
"""Require successful verification or an explicit, successful scope exclusion."""
import json
import os
import sys


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
            raise ValueError(f'verify result is {actual}')
        return 'PASS: required implementation verification succeeded; iOS 17 remains pending.'
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
