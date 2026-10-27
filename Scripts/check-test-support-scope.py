#!/usr/bin/env python3
"""Validate test-support/advisory methods against the real selected inventory."""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ID = re.compile(r'[A-Za-z_][A-Za-z_0-9]*(?:/[A-Za-z_][A-Za-z_0-9]*)+/[A-Za-z_][A-Za-z_0-9]*\([A-Za-z_0-9:]*\)')


def load(path):
    return json.loads(Path(path).read_text())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--scope', required=True)
    parser.add_argument('--enumeration', required=True)
    parser.add_argument('--tier', required=True, choices=['required', 'full'])
    args = parser.parse_args()
    if not (ROOT / 'Tests/Governance/test-support-impact.json').is_file() or not (
            ROOT / 'Tests/Governance/host-sensitive-advisory.json').is_file():
        print('TEST-SUPPORT: manifest absent; fixture skip')
        return 0
    try:
        scope = load(args.scope)
        expected = set(scope['expected'])
        enumeration = load(args.enumeration)
        discovered = {item['identifier'] for item in enumeration['values'][0]['enabledTests']}
        manifest = load(ROOT / 'Tests/Governance/test-support-impact.json')['files']
        advisory = load(ROOT / 'Tests/Governance/host-sensitive-advisory.json')['entries']
        manifest_methods = {m for entry in manifest.values() for m in entry['methods']}
        advisory_methods = {entry['method'] for entry in advisory}
        replacements = {m for entry in advisory for m in entry['replacement']}
        missing = sorted((manifest_methods | replacements) - expected)
        if missing:
            raise ValueError(f'methods missing from selected inventory: {missing[:3]}')
        missing = sorted((manifest_methods | replacements) - discovered)
        if missing:
            raise ValueError(f'methods missing from real enumeration: {missing[:3]}')
        if args.tier == 'required':
            leaked = sorted(advisory_methods & expected)
            if leaked:
                raise ValueError(f'advisory methods leaked into required: {leaked[:3]}')
        else:
            missing = sorted((manifest_methods | advisory_methods | replacements) - expected)
            if missing:
                raise ValueError(f'full inventory missing methods: {missing[:3]}')
        print(f'TEST-SUPPORT-SCOPE: {args.tier} expected={len(expected)} '
              f'manifest={len(manifest_methods)} advisory={len(advisory_methods)} '
              f'replacements={len(replacements)}')
        return 0
    except (ValueError, KeyError, TypeError, json.JSONDecodeError, OSError) as error:
        print(f'TEST-SUPPORT-SCOPE: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
