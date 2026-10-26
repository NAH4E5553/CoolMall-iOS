#!/usr/bin/env python3
"""Validate test-support manifest owner/expiry/method shape; never bypasses tests."""
import datetime
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / 'Tests/Governance/test-support-impact.json'
ID = re.compile(r'[A-Za-z_][A-Za-z_0-9]*(?:/[A-Za-z_][A-Za-z_0-9]*)+/[A-Za-z_][A-Za-z_0-9]*\([A-Za-z_0-9:]*\)')


def main():
    if not PATH.is_file():
        print('TEST-SUPPORT: manifest missing', file=sys.stderr)
        return 1
    try:
        data = json.loads(PATH.read_text())
        files = data.get('files')
        if not isinstance(files, dict) or not files:
            raise ValueError('files must be a non-empty object')
        for path, entry in files.items():
            if not isinstance(entry, dict):
                raise ValueError(f'{path}: entry must be an object')
            if not str(entry.get('owner', '')).strip():
                raise ValueError(f'{path}: owner missing')
            expires = datetime.date.fromisoformat(entry.get('expires', ''))
            if expires < datetime.date.today():
                raise ValueError(f'{path}: expired {expires}')
            methods = entry.get('methods')
            if not isinstance(methods, list) or not methods or not all(
                    isinstance(m, str) and ID.fullmatch(m) for m in methods):
                raise ValueError(f'{path}: methods invalid')
        print(f'TEST-SUPPORT: {len(files)} file(s), owners/expiry valid')
        return 0
    except (ValueError, TypeError, KeyError, json.JSONDecodeError, OSError) as error:
        print(f'TEST-SUPPORT: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
