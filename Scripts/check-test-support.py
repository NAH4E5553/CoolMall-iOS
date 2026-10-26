#!/usr/bin/env python3
"""Validate test-support manifest owner/expiry/method shape; never bypasses tests."""
import datetime
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / 'Tests/Governance/test-support-impact.json'
ADVISORY = ROOT / 'Tests/Governance/host-sensitive-advisory.json'
FIXTURE = ROOT / 'Tests/Governance/Fixtures/test-enumeration.json'
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
        fixture = json.loads(FIXTURE.read_text())
        enabled = {item['identifier'] for item in fixture['values'][0]['enabledTests']}
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
            missing = [m for m in methods if m not in enabled]
            if missing:
                raise ValueError(f'{path}: methods not in inventory: {missing[:3]}')
        advisory = json.loads(ADVISORY.read_text())
        entries = advisory.get('entries')
        if not isinstance(entries, list) or not entries:
            raise ValueError('advisory entries missing')
        for entry in entries:
            if not isinstance(entry, dict):
                raise ValueError('advisory entry must be an object')
            if not str(entry.get('owner', '')).strip():
                raise ValueError('advisory owner missing')
            expires = datetime.date.fromisoformat(entry.get('expires', ''))
            if expires < datetime.date.today():
                raise ValueError(f'advisory expired {expires}')
            if not ID.fullmatch(str(entry.get('method', ''))):
                raise ValueError('advisory method invalid')
            if entry['method'] not in enabled:
                raise ValueError(f"advisory method not in inventory: {entry['method']}")
            replacement = entry.get('replacement')
            if not isinstance(replacement, list) or not replacement or not all(
                    isinstance(m, str) and ID.fullmatch(m) for m in replacement):
                raise ValueError('advisory replacement invalid')
            missing = [m for m in replacement if m not in enabled]
            if missing:
                raise ValueError(f'advisory replacement not in inventory: {missing[:3]}')
        print(f'TEST-SUPPORT: {len(files)} file(s), {len(entries)} advisory method(s), owners/expiry valid')
        return 0
    except (ValueError, TypeError, KeyError, json.JSONDecodeError, OSError) as error:
        print(f'TEST-SUPPORT: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
