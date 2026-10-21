#!/usr/bin/env python3
"""Skip heavy verification only for proven documentation/placeholder-copy changes."""
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


DOC_NAMES = {'README.md', 'CHANGELOG.md', 'PRODUCT_SPEC.md', 'IMPLEMENTATION_PLAN.md'}
PLACEHOLDER_FILES = {
    'CoolMalliOS/Navigation/RootView.swift',
    'Packages/MallKit/Sources/CatalogFeature/Entry/CatalogEntryView.swift',
    'Packages/MallKit/Sources/CartFeature/Entry/CartEntryView.swift',
}
# Only existing literal display-copy slots, never callbacks, IDs, timing or layout.
# No escapes/interpolation; the rest of both files must remain byte-identical.
COPY = re.compile(r'(?P<prefix>Text\(|detail: )"(?P<text>[^"\\\r\n]*)"')
MARKERS = ('暂未开放', '待接入', '导航占位')


def static_placeholder(source):
    """Recognize a complete, inert internal SwiftUI placeholder, not arbitrary Swift."""
    if source is None:
        return None
    text = source.decode('utf-8')
    pattern = (
        r'\s*import SwiftUI\s+'
        r'(?P<access>private\s+)?struct (?P<name>[A-Za-z_][A-Za-z_0-9]*)\s*:\s*View\s*\{'
        r'\s*var body\s*:\s*some View\s*\{\s*Text\("(?P<copy>[^"\\\r\n]*)"\)'
        r'\s*\}\s*\}\s*'
    )
    match = re.fullmatch(pattern, text)
    if match and any(marker in match['copy'] for marker in MARKERS):
        return match['access'], match['name']
    return None


def inert_placeholder_only(path, before, after):
    prefixes = ('CoolMalliOS/', 'Packages/MallKit/Sources/CatalogFeature/',
                'Packages/MallKit/Sources/CartFeature/')
    if not path.startswith(prefixes) or not path.endswith('.swift'):
        return False
    new = static_placeholder(after)
    # New module-visible names can shadow an imported/implemented type. A new
    # file-private placeholder cannot affect other files; the suffix also
    # excludes self-shadowing of SwiftUI Text/View used in this exact shape.
    if before is None:
        return new is not None and new[0] is not None and new[1].endswith('PlaceholderView')
    # Removing/renaming a type can break consumers and must still be compiled.
    return new is not None and static_placeholder(before) == new


def is_document(path):
    p = PurePosixPath(path)
    if p.name in {'AGENTS.md', 'ENGINEERING.md', 'SKILL.md'}:
        return False
    return path in DOC_NAMES or (
        p.parts[0] in {'docs', 'Docs'} and p.suffix.lower() in {'.md', '.txt', '.png', '.jpg', '.jpeg'}
    )


def placeholder_copy_only(path, before, after):
    if path not in PLACEHOLDER_FILES or before is None or after is None:
        return False
    def normalize(source):
        def replace(match):
            if any(marker in match['text'] for marker in MARKERS):
                return match['prefix'] + '"<pending-copy>"'
            return match[0]
        return COPY.sub(replace, source.decode('utf-8'))
    return before != after and normalize(before) == normalize(after)


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE)


def snapshot(root, ref, path):
    entry = git(root, 'ls-tree', '-z', ref, '--', path)
    if not entry:
        return None, None
    metadata, name = entry.rstrip(b'\0').split(b'\t', 1)
    mode, kind, oid = metadata.split()
    if kind != b'blob':
        return mode.decode(), None
    return mode.decode(), git(root, 'cat-file', 'blob', oid.decode())


def classify(root, event, base, head):
    # Scheduled/manual runs deliberately verify implemented capabilities.
    if event != 'pull_request':
        return True, 'non-pr-full', []
    if not re.fullmatch(r'[0-9a-f]{40}', base or '') or set(base) == {'0'}:
        return True, 'missing-base', []
    if not re.fullmatch(r'[0-9a-f]{40}', head or ''):
        raise ValueError('Invalid diff head')
    if event == 'pull_request':
        base = git(root, 'merge-base', base, head).decode().strip()
    raw = git(root, 'diff', '--no-renames', '--name-only', '-z', base, head)
    paths = [path.decode('utf-8') for path in raw.split(b'\0') if path]
    if not paths:
        return True, 'empty-diff-needs-verification', []
    for path in paths:
        old_mode, before = snapshot(root, base, path)
        new_mode, after = snapshot(root, head, path)
        if any(mode not in {None, '100644'} for mode in (old_mode, new_mode)):
            return True, 'file-mode-or-type', paths
        if is_document(path):
            continue
        if inert_placeholder_only(path, before, after) or placeholder_copy_only(path, before, after):
            continue
        return True, 'implementation-rules-or-unknown', paths
    return False, 'docs-or-placeholder-only', paths


def main():
    try:
        run, reason, paths = classify(
            Path.cwd(), os.environ['GITHUB_EVENT_NAME'],
            os.environ.get('MALL_DIFF_BASE', ''), os.environ.get('MALL_DIFF_HEAD', ''))
        result = {'run_verification': str(run).lower(), 'reason': reason, 'changed_paths': paths}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'run_verification={str(run).lower()}\nreason={reason}\n')
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
                summary.write('Build/tests: ' + ('required' if run else 'not required') + f' ({reason}).\n')
        return 0
    except (KeyError, ValueError, OSError, UnicodeError, subprocess.SubprocessError) as error:
        print(f'FAIL: CI change classification: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
