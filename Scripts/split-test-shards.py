#!/usr/bin/env python3
"""Split a real expected-method file into disjoint UI/non-UI shards."""
import argparse
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected', required=True, type=Path)
    parser.add_argument('--out-dir', required=True, type=Path)
    parser.add_argument('--ui-prefix', default='CoolMalliOSUITests/')
    args = parser.parse_args()
    methods = [line.strip() for line in args.expected.read_text().splitlines() if line.strip()]
    if not methods or len(set(methods)) != len(methods):
        print('SHARDS: expected list empty or duplicated', file=sys.stderr)
        return 1
    ui = [m for m in methods if m.startswith(args.ui_prefix)]
    nonui = [m for m in methods if not m.startswith(args.ui_prefix)]
    if not ui or not nonui or set(ui) & set(nonui) or set(ui) | set(nonui) != set(methods):
        print('SHARDS: shard partition invalid', file=sys.stderr)
        return 1
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / 'expected-all.txt').write_text('\n'.join(methods) + '\n')
    (args.out_dir / 'expected-ui.txt').write_text('\n'.join(ui) + '\n')
    (args.out_dir / 'expected-nonui.txt').write_text('\n'.join(nonui) + '\n')
    print(f'SHARDS: all={len(methods)} ui={len(ui)} nonui={len(nonui)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
