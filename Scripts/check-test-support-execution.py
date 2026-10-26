#!/usr/bin/env python3
"""Validate test-support/advisory methods in the actual native result set."""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(path):
    return json.loads(Path(path).read_text())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--native-results', required=True)
    parser.add_argument('--tier', required=True, choices=['required', 'full'])
    args = parser.parse_args()
    try:
        results = load(args.native_results).get('methodResults', {})
        manifest = load(ROOT / 'Tests/Governance/test-support-impact.json')['files']
        advisory = load(ROOT / 'Tests/Governance/host-sensitive-advisory.json')['entries']
        manifest_methods = {m for entry in manifest.values() for m in entry['methods']}
        advisory_methods = {entry['method'] for entry in advisory}
        replacements = {m for entry in advisory for m in entry['replacement']}
        required = manifest_methods | replacements
        missing = sorted(required - results.keys())
        if missing:
            raise ValueError(f'methods not executed: {missing[:3]}')
        failed = sorted(m for m in required if results.get(m) != 'Passed')
        if failed:
            raise ValueError(f'methods not passed: {failed[:3]}')
        if args.tier == 'required':
            leaked = sorted(advisory_methods & results.keys())
            if leaked:
                raise ValueError(f'advisory methods executed in required: {leaked[:3]}')
        else:
            missing = sorted(advisory_methods - results.keys())
            if missing:
                raise ValueError(f'advisory methods not executed in full: {missing[:3]}')
        print(f'TEST-SUPPORT-EXECUTION: {args.tier} required={len(required)} '
              f'advisory={len(advisory_methods)}')
        return 0
    except (ValueError, KeyError, TypeError, json.JSONDecodeError, OSError) as error:
        print(f'TEST-SUPPORT-EXECUTION: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
