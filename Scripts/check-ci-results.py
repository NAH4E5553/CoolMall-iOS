#!/usr/bin/env python3
"""Fail closed when any required workflow job is absent, failed, skipped or cancelled."""
import json
import os
import sys


def validate(needs):
    if set(needs) != {'verify'}:
        raise ValueError(f'Unexpected required job set: {sorted(needs)}')
    if needs['verify']['result'] != 'success':
        raise ValueError(f"verify result is {needs['verify']['result']}")


def main():
    try:
        validate(json.loads(os.environ['MALL_CI_NEEDS']))
    except (KeyError, ValueError, TypeError) as error:
        print(f'FAIL: required-checks: {error}', file=sys.stderr)
        return 1
    print('PASS: all required F0 workflow jobs succeeded; iOS 17 device coverage remains pending.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
