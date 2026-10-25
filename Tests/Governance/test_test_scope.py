"""Real enumeration protocol and conservative scope decisions in isolated Git repos."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('scope', ROOT / 'Scripts/select-test-scope.py')
S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)
spec = importlib.util.spec_from_file_location('results', ROOT / 'Scripts/check-test-results.py')
R = importlib.util.module_from_spec(spec); spec.loader.exec_module(R)
RAW = json.loads((ROOT / 'Tests/Governance/Fixtures/test-enumeration.json').read_text())
TARGETS = {item['identifier'].split('/')[0] for item in RAW['values'][0]['enabledTests']}


class InventoryTests(unittest.TestCase):
    def test_real_xcode_flat_protocol(self):
        methods = S.inventory(RAW, TARGETS)
        self.assertIn('CartFeatureTests/cancellationDoesNotPublishBufferedValues()', methods)
        self.assertIn('MallImagesTests/ImagePipelineTests/oldSuccessOrErrorAfterCancelCannotReplaceB(isError:)', methods)
        full = S.resolve({'mode': 'full', 'targets': []}, RAW, TARGETS)
        self.assertEqual(full['expected'], methods)
        selected = S.resolve({'mode': 'selected', 'targets': [S.CATALOG, S.HOME]}, RAW, TARGETS)
        self.assertTrue(any(x.startswith(S.CATALOG + '/') for x in selected['expected']))
        self.assertTrue(any(x.startswith(S.HOME + '/') for x in selected['expected']))
        self.assertFalse(any(x.startswith(S.NAVIGATION + '/') for x in selected['expected']))
        self.assertTrue(all(m in selected['expected'] for m in methods if not m.startswith('CoolMalliOSUITests/')))
        self.assertEqual(len(selected['expected']) + len(selected['omitted']), len(methods))

    def test_invalid_enumeration_never_becomes_full_success(self):
        for mutation in [lambda d: d.update(errors=['failure']), lambda d: d['values'].append(d['values'][0]),
                         lambda d: d['values'][0].update(enabledTests=[]),
                         lambda d: d['values'][0].update(disabledTests=[{'identifier':'x'}]),
                         lambda d: d['values'][0]['enabledTests'].append(d['values'][0]['enabledTests'][0]),
                         lambda d: d['values'][0]['enabledTests'].append({'identifier':'UnknownTests/test()'})]:
            data = copy.deepcopy(RAW); mutation(data)
            with self.assertRaises(ValueError): S.inventory(data, TARGETS)
        for value in ['-skip-testing:x', '@file', 'Target/method()\nOther/test()', 'warning: missing', 'A/B test()', 'A/B']:
            with self.assertRaises(ValueError): S.identifier(value)

    def test_exact_results_and_parameter_children(self):
        methods = ['CoreTests/Contract/test(value:)', 'UITests/Screen/testUI()']
        tree = {'testNodes': [{'name': 'CoreTests', 'nodeType': 'Unit test bundle', 'children': [
            {'nodeType':'Test Case','name':'display label', 'nodeIdentifier':'Contract/test(value:)', 'result':'Passed',
             'children':[{'nodeType':'Arguments','nodeIdentifierURL':'test://one?arg=1','result':'Passed'}]}]},
            {'name':'UITests','nodeType':'UI test bundle','children':[
                {'nodeType':'Test Case','nodeIdentifier':'Screen/testUI()','result':'Passed'}]}]}
        summary = dict(result='Passed', failedTests=0, skippedTests=0, expectedFailures=0, totalTestCount=2, passedTests=2)
        self.assertEqual(R.validate_inventory(summary, tree, {'expected':methods}), {'methodCounts':{'CoreTests':1,'UITests':1},'parameterArgumentRecordCount':1})
        for change in ['same-count-wrong-method', 'duplicate', 'missing', 'skip-argument']:
            bad = copy.deepcopy(tree)
            if change == 'same-count-wrong-method': bad['testNodes'][1]['children'][0]['nodeIdentifier']='Screen/different()'
            if change == 'duplicate': bad['testNodes'][1]['children'].append(bad['testNodes'][1]['children'][0])
            if change == 'missing': bad['testNodes'][1]['children']=[]
            if change == 'skip-argument': bad['testNodes'][0]['children'][0]['children'][0]['result']='Skipped'
            with self.subTest(change=change), self.assertRaises(ValueError):
                R.validate_inventory(summary, bad, {'expected':methods})


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.git('init','-q'); self.git('config','user.name','Fixture'); self.git('config','user.email','fixture@example.invalid')
        for path in S.PATH_TARGETS:
            self.write(path, 'existingBody\n')
        self.write('README.md','docs\n')
        self.write('.github/workflows/ios.yml','name: legacy\n')
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(['git','-C',str(self.root),*args], stderr=subprocess.PIPE).decode().strip()

    def write(self, path, text):
        file = self.root/path; file.parent.mkdir(parents=True,exist_ok=True); file.write_text(text)

    def commit(self):
        self.git('add','.'); self.git('commit','-qm','fixture'); return self.git('rev-parse','HEAD')

    def plan(self, event='pull_request', good=True):
        return S.plan(self.root, dict(GITHUB_EVENT_NAME=event, MALL_DIFF_BASE=self.base, MALL_DIFF_HEAD=self.git('rev-parse','HEAD')),
                      lambda root, env: (good, 'history-fixture'))

    def test_cumulative_union_and_shared_consumers(self):
        self.write('CoolMalliOSUITests/HomeLoadTests.swift','changedBody\n'); self.commit()
        self.write('CoolMalliOSUITests/NavigationSmokeTests.swift','changedBody\n'); self.commit()
        result = self.plan()
        self.assertEqual(result['targets'], sorted([S.HOME,S.NAVIGATION,*S.PR_SMOKE]))
        self.assertEqual(len(result['paths']), 2)
        self.write('Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeBannerCarouselView.swift','changedBody\n'); self.commit()
        self.assertEqual(self.plan()['targets'], sorted([S.CATALOG,S.HOME,S.NAVIGATION,*S.PR_SMOKE,*set(S.LIFECYCLE)-set(S.PR_SMOKE)]))

    def test_unknown_api_structural_full_but_history_is_irrelevant(self):
        self.write('CoolMalliOSUITests/HomeLoadTests.swift','changedBody\n'); self.commit()
        self.assertEqual(self.plan(good=False)['mode'], 'selected')
        self.write('CoolMalliOSUITests/HomeLoadTests.swift','func renamed() {}\n'); self.commit()
        self.assertEqual(self.plan()['mode'], 'full')
        self.write('Unknown.swift','changedBody\n'); self.commit()
        self.assertEqual(self.plan()['mode'], 'full')

    def test_banner_timing_map_unions_real_consumers(self):
        timing = 'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeBannerTiming.swift'
        hosted = 'Packages/MallKit/Tests/CatalogFeatureTests/Home/HomeBannerProductionTimingTests.swift'
        self.assertEqual(S.PATH_TARGETS[timing], [S.CATALOG, *S.LIFECYCLE])
        self.assertEqual(S.PATH_TARGETS[hosted], [S.CATALOG])
        self.write(hosted, 'changedBody\n'); self.commit()
        self.assertEqual(self.plan()['targets'], sorted([S.CATALOG,*S.PR_SMOKE]))
        self.write(timing, 'changedBody\n'); self.commit()
        self.assertEqual(self.plan()['targets'], sorted(set([S.CATALOG,*S.PR_SMOKE,*S.LIFECYCLE])))

    def test_new_mapped_timing_files_and_declarations_still_require_full(self):
        paths = [
            'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeBannerTiming.swift',
            'Packages/MallKit/Tests/CatalogFeatureTests/Home/HomeBannerProductionTimingTests.swift',
        ]
        for path in paths:
            with self.subTest(path=path):
                (self.root / path).unlink(); self.base = self.commit()
                self.write(path, 'newBody\n'); self.commit()
                self.assertEqual(self.plan()['mode'], 'full')
                self.base = self.git('rev-parse', 'HEAD')
                self.write(path, 'func newDiscovery() {}\n'); self.commit()
                self.assertEqual(self.plan()['mode'], 'full')
                self.assertEqual(self.plan()['reason'], 'declaration-api-or-test-discovery-change')

    def test_new_file_delete_and_non_pr_full(self):
        (self.root/'CoolMalliOSUITests/HomeLoadTests.swift').unlink(); self.commit()
        self.assertEqual(self.plan()['mode'], 'full')
        for event in ['push','schedule','workflow_dispatch','local']:
            self.assertEqual(self.plan(event)['mode'], 'full')

    def test_wrong_checkout_or_dirty_source_rejected(self):
        self.write('README.md','uncommitted\n')
        with self.assertRaisesRegex(ValueError,'clean exact head'): self.plan()
        self.commit()
        with self.assertRaisesRegex(ValueError,'clean exact head'):
            S.plan(self.root, dict(GITHUB_EVENT_NAME='pull_request',MALL_DIFF_HEAD=self.base))

    def test_prior_failure_deferred_or_missing_history_never_expands_scope(self):
        self.write('CoolMalliOSUITests/HomeLoadTests.swift','changedBody\n'); self.commit()
        def forbidden(*args):
            self.fail('history must not be queried')
        for prior in ['failure', 'deferred', 'missing']:
            env = dict(GITHUB_EVENT_NAME='pull_request', MALL_DIFF_BASE=self.base,
                       MALL_DIFF_HEAD=self.git('rev-parse','HEAD'), PRIOR_RUN=prior)
            result = S.plan(self.root, env, forbidden)
            self.assertEqual(result['mode'], 'selected')
            self.assertNotIn('history', result)

    def test_required_baseline_and_full_only_chains(self):
        self.write('Scripts/check-test-results.py', '# tooling change\n'); self.commit()
        scope = self.plan()
        self.assertEqual(scope['mode'], 'selected')
        required = S.resolve(scope, RAW, TARGETS)
        self.assertTrue(set(S.PR_SMOKE) <= set(required['expected']))
        self.assertIn(S.HOME + '/testBannerAutoplayArmsAfterPushedRoutePopsBack()', required['expected'])
        self.assertNotIn(S.HOME + '/testApprovedHomeDisplayAtAccessibilitySize()', required['expected'])
        self.assertNotIn(S.HOME + '/testBannerAutoplayCyclesAndRestartsAfterUnchangedDrag()', required['expected'])
        self.assertGreater(sum('HomeBannerProductionTimingTests/' in x for x in required['expected']), 0)
        S.validate_manifest(required)
        for event in ['push', 'schedule', 'workflow_dispatch']:
            full = S.resolve(self.plan(event), RAW, TARGETS)
            self.assertEqual(full['expected'], full['discovered'])

    def test_category_test_body_change_keeps_whole_category_without_unrelated_home_full(self):
        self.write('CoolMalliOSUITests/CategoryLoadTests.swift', 'changedAssertionBody\n'); self.commit()
        scope = self.plan()
        self.assertEqual(scope['mode'], 'selected')
        self.assertIn(S.CATEGORY, scope['targets'])
        raw = copy.deepcopy(RAW)
        method = S.CATEGORY + '/testTabReturnRetainsSelectionAndDoesNotReRead()'
        raw['values'][0]['enabledTests'].append({'identifier': method})
        resolved = S.resolve(scope, raw, TARGETS)
        self.assertIn(method, resolved['expected'])
        self.assertNotIn(S.HOME + '/testApprovedHomeDisplayAtAccessibilitySize()', resolved['expected'])

    def test_required_methods_missing_from_enumeration_block(self):
        scope = self.plan()
        raw = copy.deepcopy(RAW)
        raw['values'][0]['enabledTests'] = [x for x in raw['values'][0]['enabledTests'] if x['identifier'] != S.PR_SMOKE[0]]
        with self.assertRaisesRegex(ValueError, 'missing'):
            S.resolve(scope, raw, TARGETS)

    def test_push_required_tier_is_allowed_while_schedule_remains_full(self):
        self.write('CoolMalliOSUITests/HomeLoadTests.swift', 'changedBody\n')
        head = self.commit()
        push = S.plan(
            self.root,
            dict(GITHUB_EVENT_NAME='push', MALL_VERIFICATION_TIER='required',
                 MALL_DIFF_BASE=self.base, MALL_DIFF_HEAD=head))
        self.assertEqual((push['tier'], push['mode']), ('required', 'selected'))
        with self.assertRaisesRegex(ValueError, 'scheduled/manual'):
            S.plan(
                self.root,
                dict(GITHUB_EVENT_NAME='schedule', MALL_VERIFICATION_TIER='required',
                     MALL_DIFF_HEAD=head))

    def test_changed_ui_test_method_selects_only_that_method(self):
        path = 'CoolMalliOSUITests/HomeLoadTests.swift'
        source = (
            'import XCTest\n'
            'final class HomeLoadTests: XCTestCase {\n'
            '    func testA() {\n'
            '        let value = 1\n'
            '    }\n'
            '    func testB() {\n'
            '        let value = 2\n'
            '    }\n'
            '}\n'
        )
        self.write(path, source)
        base = self.commit()
        self.write(path, source.replace('let value = 1', 'let value = 3'))
        head = self.commit()
        result = S.plan(
            self.root,
            dict(GITHUB_EVENT_NAME='pull_request', MALL_VERIFICATION_TIER='required',
                 MALL_DIFF_BASE=base, MALL_DIFF_HEAD=head))
        self.assertEqual(result['reason'], 'test-method-impact')
        self.assertEqual(result['testMethods'], ['CoolMalliOSUITests/HomeLoadTests/testA()'])
        self.assertIn('CoolMalliOSUITests/HomeLoadTests/testA()', result['targets'])
        self.assertIn(S.PR_SMOKE[0], result['targets'])
        self.assertNotIn(S.HOME, result['targets'])

    def test_changed_ui_test_helper_falls_back_to_whole_target(self):
        path = 'CoolMalliOSUITests/HomeLoadTests.swift'
        source = (
            'import XCTest\n'
            'final class HomeLoadTests: XCTestCase {\n'
            '    @MainActor private func helper() -> Int {\n'
            '        return 1\n'
            '    }\n'
            '    func testA() {\n'
            '        _ = helper()\n'
            '    }\n'
            '}\n'
        )
        self.write(path, source)
        base = self.commit()
        self.write(path, source.replace('return 1', 'return 2'))
        head = self.commit()
        result = S.plan(
            self.root,
            dict(GITHUB_EVENT_NAME='pull_request', MALL_VERIFICATION_TIER='required',
                 MALL_DIFF_BASE=base, MALL_DIFF_HEAD=head))
        self.assertEqual(result['reason'], 'required-baseline-plus-current-impact')
        self.assertIn(S.HOME, result['targets'])
        self.assertNotIn('testMethods', result)

    def test_changed_comment_above_helper_falls_back_to_whole_target(self):
        path = 'CoolMalliOSUITests/HomeLoadTests.swift'
        source = (
            'import XCTest\n'
            'final class HomeLoadTests: XCTestCase {\n'
            '    func testA() {\n'
            '    }\n'
            '    // helper documentation\n'
            '    @MainActor private func helper() {\n'
            '    }\n'
            '}\n'
        )
        self.write(path, source)
        base = self.commit()
        self.write(path, source.replace('// helper documentation', '// helper documentation changed'))
        head = self.commit()
        result = S.plan(
            self.root,
            dict(GITHUB_EVENT_NAME='pull_request', MALL_VERIFICATION_TIER='required',
                 MALL_DIFF_BASE=base, MALL_DIFF_HEAD=head))
        self.assertEqual(result['reason'], 'required-baseline-plus-current-impact')
        self.assertIn(S.HOME, result['targets'])
        self.assertNotIn('testMethods', result)

    def test_local_dirty_required_captures_actual_source_and_unknown_falls_back(self):
        env = dict(MALL_VERIFICATION_TIER='required')
        self.write('Scripts/check-test-results.py', '# untracked tooling\n')
        required = S.plan(self.root, env)
        self.assertEqual(required['mode'], 'selected')
        self.assertTrue(required['source']['dirty'])
        self.write('UnknownProduction.swift', 'new product\n')
        self.assertEqual(S.plan(self.root, env)['mode'], 'full')



if __name__ == '__main__': unittest.main()
