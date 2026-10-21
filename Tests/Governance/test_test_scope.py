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
        self.assertEqual(result['targets'], sorted([S.HOME,S.NAVIGATION]))
        self.assertEqual(len(result['paths']), 2)
        self.write('Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeBannerCarouselView.swift','changedBody\n'); self.commit()
        self.assertEqual(self.plan()['targets'], sorted([S.CATALOG,S.HOME,S.NAVIGATION]))

    def test_unknown_api_structural_and_missing_history_full(self):
        self.write('CoolMalliOSUITests/HomeLoadTests.swift','changedBody\n'); self.commit()
        self.assertEqual(self.plan(good=False)['mode'], 'full')
        self.write('CoolMalliOSUITests/HomeLoadTests.swift','func renamed() {}\n'); self.commit()
        self.assertEqual(self.plan()['mode'], 'full')
        self.write('Unknown.swift','changedBody\n'); self.commit()
        self.assertEqual(self.plan()['mode'], 'full')

    def test_banner_timing_map_unions_real_consumers(self):
        timing = 'Packages/MallKit/Sources/CatalogFeature/Pages/Home/Components/HomeBannerTiming.swift'
        hosted = 'Packages/MallKit/Tests/CatalogFeatureTests/Home/HomeBannerProductionTimingTests.swift'
        self.assertEqual(S.PATH_TARGETS[timing], [S.CATALOG, S.HOME])
        self.assertEqual(S.PATH_TARGETS[hosted], [S.CATALOG])
        self.write(hosted, 'changedBody\n'); self.commit()
        self.assertEqual(self.plan()['targets'], [S.CATALOG])
        self.write(timing, 'changedBody\n'); self.commit()
        self.assertEqual(self.plan()['targets'], sorted([S.CATALOG, S.HOME]))

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

    def test_history_latest_success_closes_older_failure(self):
        run = dict(id=2, workflow_id=10, head_branch='feature')
        prior = dict(id=1, created_at='2026-01-01', status='completed',conclusion='success',head_sha=self.base,
                     head_branch='feature',pull_requests=[{'number':13}])
        data = {'total_count':2,'workflow_runs':[dict(prior,id=0,created_at='2025-01-01',conclusion='failure'),prior]}
        jobs = {'total_count':2,'jobs':[{'name':name,'status':'completed','conclusion':'success'} for name in ['F0 verification','required-checks']]}
        env = dict(GITHUB_RUN_ID='2', MALL_PR_NUMBER='13', MALL_DIFF_HEAD=self.base)
        def fetch(path, env):
            if '/jobs?' in path: return jobs
            if '/workflows/' in path: return data
            return run
        self.assertTrue(S.prior_verification(self.root,env,fetch)[0])
        for status, allowed in [('core-passed',True),('core-passed-with-deferred',False),
                                ('unknown',False),('',False)]:
            jobs['jobs'][0]['steps']=[{'name':'Verification verdict: '+status,'conclusion':'success'}]
            self.assertEqual(S.prior_verification(self.root,env,fetch)[0],allowed)
        jobs['jobs'][0]['steps']=[]
        for state in ['failure','cancelled',None]:
            prior['conclusion']=state
            self.assertFalse(S.prior_verification(self.root,env,fetch)[0])
        prior['conclusion']='success'; jobs['jobs'][0]['conclusion']='skipped'
        self.assertFalse(S.prior_verification(self.root,env,fetch)[0])
        run['run_attempt']=2
        self.assertFalse(S.prior_verification(self.root,env,fetch)[0])
        run['run_attempt']=1
        data['total_count']=999
        self.assertFalse(S.prior_verification(self.root,env,fetch)[0])


if __name__ == '__main__': unittest.main()
