#!/usr/bin/env python3
"""Conservative PR scope, Swift 6 body-boundary proof, and actual Xcode inventory."""
import hashlib
import importlib.util
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('classification', ROOT / 'Scripts/classify-ci-changes.py')
CLASSIFY = importlib.util.module_from_spec(spec)
spec.loader.exec_module(CLASSIFY)
# Explicit consumers verified from HomeContentView/HomeEntryView and the test
# suites. Prefixes denote whole classes/targets, never hand-picked methods.
HOME = 'CoolMalliOSUITests/HomeLoadTests'
NAVIGATION = 'CoolMalliOSUITests/NavigationSmokeTests'
CATALOG = 'CatalogFeatureTests'
PATH_TARGETS = {
    'CoolMalliOSUITests/HomeLoadTests.swift': [HOME],
    'CoolMalliOSUITests/NavigationSmokeTests.swift': [NAVIGATION],
    'Packages/MallKit/Tests/CatalogFeatureTests/CatalogFixtureTests.swift': [CATALOG],
    'Packages/MallKit/Tests/CatalogFeatureTests/HomeBannerSelectionTests.swift': [CATALOG],
    'Packages/MallKit/Tests/CatalogFeatureTests/Home/HomeBannerProductionTimingTests.swift': [CATALOG],
    'Packages/MallKit/Tests/CatalogFeatureTests/Home/HomeViewModelTests.swift': [CATALOG],
    'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeBannerCarouselView.swift': [CATALOG, HOME],
    'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeBannerTiming.swift': [CATALOG, HOME],
    'Packages/MallKit/Sources/CatalogFeature/Pages/Home/HomeViewModel.swift': [CATALOG, HOME, NAVIGATION],
    'Packages/MallKit/Sources/CatalogFeature/Entry/HomeEntryView.swift': [CATALOG, HOME, NAVIGATION],
    'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeContentView.swift': [CATALOG, HOME, NAVIGATION],
    'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeProductSectionsView.swift': [CATALOG, HOME],
    'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeProductCardView.swift': [CATALOG, HOME],
    'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeSectionView.swift': [CATALOG, HOME],
    'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeCategorySectionView.swift': [CATALOG, HOME],
    'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeCouponSectionView.swift': [CATALOG, HOME],
}
CATEGORY = 'CoolMalliOSUITests/CategoryLoadTests'
PATH_TARGETS['CoolMalliOSUITests/CategoryLoadTests.swift'] = [CATEGORY]
PR_SMOKE = [NAVIGATION + '/' + name + '()' for name in [
    'testColdStartDefaultsToHomeWithFourTabs', 'testCartRouteHidesTabBarAndBackRestoresIt',
]]
LIFECYCLE = [HOME + '/' + name + '()' for name in [
    'testBannerAutoplayCyclesAndRestartsAfterUnchangedDrag',
    'testBannerAutoplayPausesWhileAwayAndResumesFullInterval',
    'testBannerAutoplayPausesWhileBannerIsOffscreen',
    'testBannerAutoplayArmsAfterPushedRoutePopsBack', 'testBannerFastPageRoundTripsAreBounded',
]]
for path in list(PATH_TARGETS):
    if path.endswith(('HomeBannerCarouselView.swift', 'HomeBannerTiming.swift')):
        PATH_TARGETS[path] = [CATALOG, *LIFECYCLE]
# CI-only changes are verified by the complete governance suite and PR baseline;
# changing product/test discovery/shared code still triggers conservative coverage.
VERIFICATION_PATHS = {'.github/workflows/ios.yml', '.github/workflows/ios-full-advisory.yml',
                         '.github/workflows/ios-isolation-experiment.yml',
                         '.github/workflows/ios-device-isolation.yml',
                         'Scripts/create-simulator.py', 'Scripts/check-governance.py', 'Scripts/ci-job-outcome.py',
                         'ENGINEERING.md', 'AGENTS.md'} | {
    'Scripts/' + name for name in [
        'SourceBoundaries.swift', 'check-boundaries.py', 'check-boundary-negative.sh',
        'check-source-boundaries.sh', 'check-compiler-boundary.py', 'check-project-boundaries.py',
        'check-format.sh', 'check-toolchain.sh', 'format.sh', 'check-ci-results.py',
        'check-test-results.py', 'check-banner-lifecycle.py', 'ci-deferred-checks.json',
        'ci-deferred-policy.py', 'finalize-verification.py', 'prepare-ui-test-runner.py',
        'select-test-scope.py', 'select-simulator.py', 'verification-timing.py',
        'verify-local.sh', 'with-banner-trace.py', 'classify-ci-changes.py',
        'test-duration-summary.py', 'check-test-support.py',
        'check-test-support-scope.py', 'check-test-support-execution.py',
        'split-test-shards.py', 'prepare-isolation-experiment.sh',
        'run-isolation-shard.sh', 'report-isolation-experiment.py',
    ]}
TEST_SUPPORT_MANIFEST = 'Tests/Governance/test-support-impact.json'


def advisory_methods(root):
    manifest = Path(root) / 'Tests/Governance/host-sensitive-advisory.json'
    if not manifest.is_file():
        return set()
    try:
        data = json.loads(manifest.read_text())
        return {entry['method'] for entry in data.get('entries', [])
                if isinstance(entry, dict) and isinstance(entry.get('method'), str)}
    except (ValueError, TypeError, KeyError, json.JSONDecodeError, OSError):
        return set()


def test_support_methods(root, path):
    """File-level test-support entry: owner, expiry, and affected methods."""
    manifest = Path(root) / TEST_SUPPORT_MANIFEST
    if not manifest.is_file():
        return None
    try:
        data = json.loads(manifest.read_text())
        entry = data.get('files', {}).get(path)
        if not entry:
            return None
        require(entry.get('owner', '').strip(), 'test-support owner missing')
        expires = datetime.date.fromisoformat(entry.get('expires', ''))
        require(expires >= datetime.date.today(), 'test-support entry expired')
        methods = entry.get('methods') or []
        require(methods
                and all(isinstance(m, str) and ID.fullmatch(m) for m in methods),
                'test-support methods invalid')
        return set(methods)
    except (ValueError, KeyError, TypeError, json.JSONDecodeError, OSError):
        return None


PRODUCTION_TIMING = [CATALOG + '/HomeBannerProductionTimingTests/' + name + '()' for name in [
    'P01DeadlineBeforeAndAtAdvanceActualSelection', 'P02PauseCancelsProductionWaitAndRejectsLateWake',
    'P03ReturnArmsNewFullPeriodWithoutCatchup', 'P04RapidPauseReturnHasOneCurrentTaskAndNoDuplicateCommit',
    'P05RealHostRemovalCancelsAutoplayWait', 'P06HiddenFullCycleStillFailsAudit',
]]
TEST_SUPPORT_MANIFEST_BYTES = ((ROOT / TEST_SUPPORT_MANIFEST).read_text()
                                if (ROOT / TEST_SUPPORT_MANIFEST).is_file() else '')
MAPPING_HASH = hashlib.sha256(json.dumps([PATH_TARGETS, PR_SMOKE, sorted(VERIFICATION_PATHS), CATEGORY,
                                          PRODUCTION_TIMING, TEST_SUPPORT_MANIFEST_BYTES,
                                          (ROOT / 'Tests/Governance/host-sensitive-advisory.json').read_text()
                                          if (ROOT / 'Tests/Governance/host-sensitive-advisory.json').is_file() else ''],
                                         sort_keys=True).encode()).hexdigest()

ID = re.compile(r'[A-Za-z_][A-Za-z_0-9]*(?:/[A-Za-z_][A-Za-z_0-9]*)+/[A-Za-z_][A-Za-z_0-9]*\([A-Za-z_0-9:]*\)|[A-Za-z_][A-Za-z_0-9]*/[A-Za-z_][A-Za-z_0-9]*\([A-Za-z_0-9:]*\)')


def require(ok, message):
    if not ok:
        raise ValueError('TEST-SCOPE: ' + message)


def identifier(value):
    require(isinstance(value, str) and ID.fullmatch(value), 'invalid stable identifier')
    return value


def git(root, *args):
    return CLASSIFY.git(root, *args).decode().strip()


def source(root):
    # Includes staged/unstaged tracked changes and new, nonignored files.
    head = git(root, 'rev-parse', 'HEAD')
    dirty = git(root, 'status', '--porcelain', '--untracked-files=all')
    digest = hashlib.sha256(CLASSIFY.git(root, 'diff', 'HEAD', '--binary'))
    for path in CLASSIFY.git(root, 'ls-files', '--others', '--exclude-standard', '-z').split(b'\0'):
        if path:
            digest.update(path)
            digest.update((root / os.fsdecode(path)).read_bytes())
    return {'head': head, 'tree': git(root, 'rev-parse', 'HEAD^{tree}'),
            'dirty': bool(dirty), 'worktreeSHA256': digest.hexdigest()}


FUNC_ATTRIBUTES = r'(?:@\w+(?:\([^)]*\))?\s+)*'
FUNC_MODIFIERS = r'(?:(?:public|private|fileprivate|internal|open|static|class|final|override|mutating|nonisolated|convenience|required)\s+)*'
FUNC_DECL = re.compile(r'^\s*' + FUNC_ATTRIBUTES + FUNC_MODIFIERS + r'func\s+')
TEST_FUNC = re.compile(r'^\s*' + FUNC_ATTRIBUTES + FUNC_MODIFIERS + r'func\s+(test[A-Za-z0-9_]+)\s*\(\s*\)')


def _test_body_ranges(source, class_name):
    """Use the pinned Swift grammar, never infer lexical nesting from source regex."""
    try:
        with tempfile.TemporaryDirectory(prefix='mall-scope-parse-') as tmp:
            parsed = subprocess.run(
                ['xcrun', 'swiftc', '-frontend', '-swift-version', '6',
                 '-module-cache-path', tmp, '-dump-parse', '-'],
                input=source, capture_output=True, text=True, check=True)
    except (OSError, subprocess.SubprocessError):
        return None
    stack, bodies = [], {}
    node = re.compile(r'^( *)(\(\w+)')
    location = re.compile(r'range=\[.*?:(\d+):(\d+) - line:(\d+):(\d+)\]')
    for line in parsed.stdout.splitlines():
        match = node.match(line)
        if not match:
            continue
        indent, kind = len(match[1]), match[2][1:]
        while stack and stack[-1]['indent'] >= indent:
            stack.pop()
        span = location.search(line)
        names = re.findall(r'"([^"\n]*)"', line)
        item = dict(indent=indent, kind=kind, name=names[0] if names else '', span=span)
        if kind == 'brace_stmt' and span and stack and stack[-1]['kind'] == 'func_decl':
            function = stack[-1]
            if len(stack) >= 2:
                owner = stack[-2]
                if (owner['kind'] in {'class_decl', 'extension_decl'}
                        and owner['indent'] == 2 and owner['name'] == class_name
                        and function['indent'] == 4
                        and re.fullmatch(r'test[A-Za-z0-9_]+\(\)', function['name'])):
                    name = function['name']
                    if name in bodies:
                        return None
                    bodies[name] = (int(span[1]), int(span[3]))
        stack.append(item)
    return bodies or None


def _ui_test_methods(root, path, patch, before):
    """Narrow only replacements proved inside matching old/new test bodies."""
    if not (path.startswith('CoolMalliOSUITests/') and path.endswith('.swift')):
        return None
    stem = Path(path).stem
    after = (Path(root) / path).read_text(encoding='utf-8')
    old_bodies = _test_body_ranges(before.decode('utf-8'), stem)
    new_bodies = _test_body_ranges(after, stem)
    if old_bodies is None or new_bodies is None:
        return None
    old_methods, new_methods = set(), set()
    hunks = list(re.finditer(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', patch, re.M))
    if not hunks:
        return None
    for hunk in hunks:
        for start, count, bodies, methods in [
            (int(hunk[1]), int(hunk[2] or '1'), old_bodies, old_methods),
            (int(hunk[3]), int(hunk[4] or '1'), new_bodies, new_methods),
        ]:
            # Pure insertion/deletion anchors and method delimiters are ambiguous.
            if count == 0:
                return None
            for row in range(start, start + count):
                owners = [name for name, (begin, end) in bodies.items() if begin < row < end]
                if len(owners) != 1:
                    return None
                methods.add(owners[0])
    if old_methods != new_methods:
        return None
    return {f'CoolMalliOSUITests/{stem}/{method}' for method in sorted(new_methods)}


def plan(root, env, history=None):
    """Current cumulative impact owns scope; prior red/deferred runs never do."""
    identity = source(root)
    event = env.get('GITHUB_EVENT_NAME', 'local')
    tier = env.get('MALL_VERIFICATION_TIER', 'required' if event == 'pull_request' else 'full')
    require(tier in {'required', 'full'}, 'unknown verification tier')
    if event in {'schedule', 'workflow_dispatch'}:
        require(tier == 'full', 'scheduled/manual verification must be full')
    if event == 'push':
        require(tier in {'required', 'full'}, 'unknown push verification tier')
    blocked = advisory_methods(root) if tier == 'required' else set()
    result = dict(source=identity, mode='full', tier=tier, reason='complete-regression', targets=[],
                  mappingSHA256=MAPPING_HASH, paths=[], testPlan='CoolMalliOS', configuration='Debug',
                  advisoryMethods=sorted(blocked))
    head = env.get('MALL_DIFF_HEAD', identity['head'])
    if event == 'pull_request':
        require(re.fullmatch(r'[0-9a-f]{40}', head or '') and identity['head'] == head
                and not identity['dirty'], 'PR checkout must be clean exact head')
    if tier == 'full':
        return result
    try:
        base = env.get('MALL_DIFF_BASE', identity['head'] if event == 'local' else '')
        require(re.fullmatch(r'[0-9a-f]{40}', base or ''), 'missing base')
        base = git(root, 'merge-base', base, head)
        result.update(mergeBase=base, head=head)
        # Local validation includes tracked disk changes and new source files;
        # PR runs require the exact clean head above.
        refs = [base, head] if event == 'pull_request' else [base]
        tokens = CLASSIFY.git(root, 'diff', '--no-renames', '--name-status', '-z', *refs).decode().rstrip('\0').split('\0')
        changes = [] if tokens == [''] else list(zip(tokens[::2], tokens[1::2]))
        require(tokens == [''] or len(tokens) % 2 == 0, 'invalid diff')
        if event != 'pull_request':
            changes += [('A', os.fsdecode(path)) for path in
                        CLASSIFY.git(root, 'ls-files', '--others', '--exclude-standard', '-z').split(b'\0') if path]
        result['paths'] = [dict(status=status, path=path) for status, path in changes]
        selected = set(PR_SMOKE)
        method_only = False
        test_support = False
        test_support_only = True
        for status, path in changes:
            if CLASSIFY.is_document(path) or path in VERIFICATION_PATHS or path.startswith('Tests/Governance/'):
                continue
            if path not in PATH_TARGETS or status != 'M':
                result['reason'] = 'unknown-shared-or-structural-impact'
                return result
            before_mode, before = CLASSIFY.snapshot(root, base, path)
            after_mode = CLASSIFY.snapshot(root, head, path)[0] if event == 'pull_request' else ('100755' if (root/path).stat().st_mode & 0o111 else '100644')
            if before_mode != '100644' or after_mode != '100644':
                result['reason'] = 'file-type-or-mode-impact'
                return result
            patch = git(root, 'diff', '--unified=0', *refs, '--', path)
            changed = '\n'.join(line[1:] for line in patch.splitlines() if line[:1] in ('+', '-') and not line.startswith(('+++', '---')))
            method_scope = _ui_test_methods(root, path, patch, before)
            if method_scope and not re.search(
                r'\b(public|open|func|struct|class|extension|typealias|import)\b|@(?:Test|Suite)\b', changed
            ):
                selected.update(method_scope)
                result.setdefault('testMethods', []).extend(sorted(method_scope))
                method_only = True
                continue
            supported = test_support_methods(root, path) if method_scope is None else None
            if supported is not None:
                selected.update(supported)
                result.setdefault('testSupportMethods', []).extend(sorted(supported))
                test_support = True
                continue
            test_support_only = False
            if re.search(r'\b(public|open|func|struct|class|extension|typealias|import)\b|@(?:Test|Suite)\b', changed):
                result['reason'] = 'declaration-api-or-test-discovery-change'
                return result
            selected.update(PATH_TARGETS[path])
            method_only = False
        result.update(mode='selected', targets=sorted(selected))
        if test_support and test_support_only:
            result['reason'] = 'test-support-targeted'
        else:
            result['reason'] = ('test-method-impact' if method_only and result.get('testMethods')
                                else 'required-baseline-plus-current-impact')
    except (ValueError, OSError, UnicodeError, subprocess.SubprocessError):
        result['reason'] = 'diff-unavailable-full'
    return result


def excluded_advisory(scope):
    # Direct consumer coverage wins over an unrelated-regression exclusion.
    if scope.get('tier') != 'required' or scope['mode'] == 'full':
        return set()
    return {method for method in scope.get('advisoryMethods', [])
            if not any(method == prefix or method.startswith(prefix + '/')
                       for prefix in scope['targets'])}


def selected_methods(scope, methods):
    if scope['mode'] == 'full':
        selected = list(methods)
    else:
        selected = [m for m in methods if m.split('/')[0] != 'CoolMalliOSUITests'
                    or any(m == prefix or m.startswith(prefix + '/') for prefix in scope['targets'])]
    blocked = excluded_advisory(scope)
    if blocked:
        selected = [m for m in selected if m not in blocked]
    targets = [prefix for prefix in scope['targets'] if prefix not in blocked]
    require(all(any(m == prefix or m.startswith(prefix + '/') for m in selected)
                for prefix in targets), 'expected target/method missing')
    return selected


def inventory(data, targets):
    require(data.get('errors') == [] and len(data.get('values', [])) == 1, 'enumeration errors or ambiguous plan')
    value = data['values'][0]
    require(value.get('testPlan') == 'CoolMalliOS' and value.get('disabledTests') == [], 'wrong plan or disabled methods')
    methods = [identifier(item['identifier']) for item in value['enabledTests']]
    require(methods and len(methods) == len(set(methods)), 'empty or duplicate discovery')
    require({method.split('/')[0] for method in methods} == set(targets), 'discovery target mismatch')
    return sorted(methods)


def resolve(scope, raw, targets):
    methods = inventory(raw, targets)
    require(set(PRODUCTION_TIMING) <= set(methods), 'required production timing method missing')
    selected = selected_methods(scope, methods)
    require(selected, 'empty selected inventory')
    return dict(scope, tier=scope.get('tier', 'full' if scope['mode'] == 'full' else 'required'), discovered=methods, expected=selected,
                omitted=[{'identifier': method, 'reason': 'complete regression; outside current required impact'} for method in methods if method not in selected],
                expectedSHA256=hashlib.sha256(('\n'.join(selected) + '\n').encode()).hexdigest(),
                inventorySHA256=hashlib.sha256(('\n'.join(methods) + '\n').encode()).hexdigest())


def validate_manifest(data):
    require(data.get('tier') in {'required', 'full'}, 'missing/unknown verification tier')
    require(data['mappingSHA256'] == MAPPING_HASH and data['mode'] in ('full', 'selected'), 'scope mapping/mode changed')
    require(data['testPlan'] == 'CoolMalliOS' and data['configuration'] == 'Debug', 'manifest configuration mismatch')
    methods = data['discovered']
    require(set(PRODUCTION_TIMING) <= set(methods), 'required production timing method missing')
    if data['mode'] == 'selected':
        require(set(PR_SMOKE) <= set(data['targets']), 'required UI baseline removed')
    require(methods and methods == sorted(set(methods)), 'invalid discovery manifest')
    for method in methods:
        identifier(method)
    for key, values in [('inventorySHA256', methods), ('expectedSHA256', data['expected'])]:
        require(data[key] == hashlib.sha256(('\n'.join(values) + '\n').encode()).hexdigest(), 'inventory hash mismatch')
    expected = selected_methods(data, methods)
    require(expected and data['expected'] == expected, 'selected manifest differs from consumer union')


def main(argv):
    command, filename, *args = argv
    path = Path(filename)
    if command == 'plan':
        data = plan(ROOT, os.environ)
    elif command == 'resolve':
        spec = importlib.util.spec_from_file_location('policy', ROOT / 'Scripts/check-boundaries.py')
        policy = importlib.util.module_from_spec(spec); spec.loader.exec_module(policy)
        targets = set(policy.read_policy(ROOT / 'ENGINEERING.md')['tests']) | {'CoolMalliOSUITests'}
        data = resolve(json.loads(path.read_text()), json.loads(Path(args[0]).read_text()), targets)
        Path(args[1]).write_text('\n'.join(data['expected']) + '\n')
    elif command == 'check-source':
        data = json.loads(path.read_text())
        require(data['source'] == source(ROOT), 'source changed since selection')
        validate_manifest(data)
        require(Path(args[0]).read_text().splitlines() == data['expected'], 'response file differs from expected methods')
        return
    else:
        raise ValueError('unknown command')
    path.write_text(json.dumps(data, indent=2) + '\n')
    print('Test scope: ' + data.get('tier', 'legacy') + '/' + data['mode'] + ' (' + data['reason'] + ')')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
