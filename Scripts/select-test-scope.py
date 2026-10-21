#!/usr/bin/env python3
"""Conservative PR scope and Xcode's actual flat JSON inventory; no source parsing."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request
import urllib.parse

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
MAPPING_HASH = hashlib.sha256(json.dumps(PATH_TARGETS, sort_keys=True).encode()).hexdigest()

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


def api(path, env):
    require(re.fullmatch(r'[A-Za-z_0-9.-]+/[A-Za-z_0-9.-]+', env['GITHUB_REPOSITORY']), 'invalid repository')
    request = urllib.request.Request('https://api.github.com/repos/' + env['GITHUB_REPOSITORY'] + path,
                                    headers={'Authorization': 'Bearer ' + env['GITHUB_TOKEN'],
                                             'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def prior_verification(root, env, fetch=api):
    """Only the latest related run may close earlier failures; uncertainty is full."""
    try:
        current = fetch('/actions/runs/' + str(int(env['GITHUB_RUN_ID'])), env)
        number = int(env['MALL_PR_NUMBER'])
        if current.get('run_attempt', 1) != 1:
            return False, 'rerun-requires-full'
        query = '/actions/workflows/' + str(int(current['workflow_id'])) + '/runs?event=pull_request&per_page=100&branch=' + urllib.parse.quote(current['head_branch'], safe='')
        runs = []
        for page in range(1, 4):
            data = fetch(query + '&page=' + str(page), env)
            runs.extend(data['workflow_runs'])
            if len(runs) >= data['total_count']:
                break
        else:
            return False, 'history-pagination-incomplete'
        related = []
        for run in runs:
            if run['id'] == current['id']:
                continue
            # A run on this branch with missing PR association is ambiguous.
            if not run['pull_requests'] and run['head_branch'] == current['head_branch']:
                return False, 'history-pr-unknown'
            if any(pr['number'] == number for pr in run['pull_requests']):
                related.append(run)
        if not related:
            return False, 'history-no-success-evidence'
        latest = max(related, key=lambda run: (run['created_at'], run['id']))
        if latest['status'] != 'completed' or latest['conclusion'] != 'success':
            return False, 'latest-verification-not-success'
        subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor', latest['head_sha'], env['MALL_DIFF_HEAD']], check=True, capture_output=True)
        jobs = fetch('/actions/runs/' + str(latest['id']) + '/jobs?per_page=100', env)
        require(jobs['total_count'] == len(jobs['jobs']), 'history jobs incomplete')
        named = {job['name']: job for job in jobs['jobs']}
        require(all(named[name]['conclusion'] == 'success' and named[name]['status'] == 'completed'
                    for name in ['F0 verification', 'required-checks']), 'previous full verification missing')
        verdicts = [step for step in named['F0 verification'].get('steps', [])
                    if step.get('name', '').startswith('Verification verdict:')]
        if verdicts:
            if len(verdicts) != 1 or verdicts[0].get('conclusion') != 'success':
                return False, 'previous-verdict-missing-or-invalid'
            if verdicts[0]['name'] == 'Verification verdict: core-passed-with-deferred':
                return False, 'previous-verification-has-deferred-issues'
            if verdicts[0]['name'] != 'Verification verdict: core-passed':
                return False, 'previous-verdict-missing-or-invalid'
        else:
            # Old commits predate structured verdicts. New configurations must
            # not omit their verdict and masquerade as an old complete run.
            try:
                workflow = git(root, 'show', latest['head_sha'] + ':.github/workflows/ios.yml')
            except subprocess.SubprocessError:
                return False, 'previous-workflow-unavailable'
            require('Verification verdict:' not in workflow, 'previous structured verdict missing')
        return True, 'previous-verification-success:' + str(latest['id'])
    except (KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError):
        return False, 'history-unavailable-or-untrusted'


def plan(root, env, history=prior_verification):
    identity = source(root)
    result = {'source': identity, 'mode': 'full', 'reason': 'non-pr', 'targets': [],
              'mappingSHA256': MAPPING_HASH, 'paths': [], 'testPlan': 'CoolMalliOS', 'configuration': 'Debug'}
    if env.get('GITHUB_EVENT_NAME') != 'pull_request':
        return result
    head, base = env.get('MALL_DIFF_HEAD', ''), env.get('MALL_DIFF_BASE', '')
    require(re.fullmatch(r'[0-9a-f]{40}', head or '') and identity['head'] == head and not identity['dirty'], 'PR checkout must be clean exact head')
    try:
        require(re.fullmatch(r'[0-9a-f]{40}', base or ''), 'missing base')
        base = git(root, 'merge-base', base, head)
        result.update(mergeBase=base, head=head)
        tokens = CLASSIFY.git(root, 'diff', '--no-renames', '--name-status', '-z', base, head).decode().rstrip('\0').split('\0')
        require(len(tokens) % 2 == 0, 'invalid diff')
        changes = list(zip(tokens[::2], tokens[1::2]))
        result['paths'] = [{'status': status, 'path': path} for status, path in changes]
        selected = set()
        for status, path in changes:
            if CLASSIFY.is_document(path):
                continue
            before_mode, _ = CLASSIFY.snapshot(root, base, path)
            after_mode, _ = CLASSIFY.snapshot(root, head, path)
            if status != 'M' or before_mode != '100644' or after_mode != '100644' or path not in PATH_TARGETS:
                result['reason'] = 'unknown-production-configuration-or-structural-change'
                return result
            # A conservative risk gate, NOT test discovery or a Swift parser:
            # declarations/API edits may add consumers outside this graph.
            patch = git(root, 'diff', '--unified=0', base, head, '--', path)
            changed = '\n'.join(line[1:] for line in patch.splitlines() if line[:1] in ('+', '-') and not line.startswith(('+++', '---')))
            if re.search(r'\b(public|open|func|struct|class|extension|typealias|import)\b|@(?:Test|Suite)\b', changed):
                result['reason'] = 'declaration-api-or-test-discovery-change'
                return result
            selected.update(PATH_TARGETS[path])
        if not selected:
            result['reason'] = 'empty-mapped-diff'
            return result
        good, reason = history(root, env)
        result['history'] = reason
        if good:
            result.update(mode='selected', reason='explicit-consumer-union', targets=sorted(selected))
        else:
            result['reason'] = reason
    except (ValueError, OSError, UnicodeError, subprocess.SubprocessError):
        result['reason'] = 'diff-unavailable-full'
    return result


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
    selected = [method for method in methods if scope['mode'] == 'full' or any(method.startswith(prefix + '/') for prefix in scope['targets'])]
    require(selected and (scope['mode'] == 'full' or all(any(m.startswith(prefix + '/') for m in selected) for prefix in scope['targets'])), 'expected target missing')
    return dict(scope, discovered=methods, expected=selected,
                omitted=[{'identifier': method, 'reason': 'outside explicit target consumers'} for method in methods if method not in selected],
                expectedSHA256=hashlib.sha256(('\n'.join(selected) + '\n').encode()).hexdigest(),
                inventorySHA256=hashlib.sha256(('\n'.join(methods) + '\n').encode()).hexdigest())


def validate_manifest(data):
    require(data['mappingSHA256'] == MAPPING_HASH and data['mode'] in ('full', 'selected'), 'scope mapping/mode changed')
    require(data['testPlan'] == 'CoolMalliOS' and data['configuration'] == 'Debug', 'manifest configuration mismatch')
    methods = data['discovered']
    require(methods and methods == sorted(set(methods)), 'invalid discovery manifest')
    for method in methods:
        identifier(method)
    for key, values in [('inventorySHA256', methods), ('expectedSHA256', data['expected'])]:
        require(data[key] == hashlib.sha256(('\n'.join(values) + '\n').encode()).hexdigest(), 'inventory hash mismatch')
    expected = [m for m in methods if data['mode'] == 'full' or any(m.startswith(p + '/') for p in data['targets'])]
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
    print('Test scope: ' + data['mode'] + ' (' + data['reason'] + ')')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
