"""CI policy controls only: isolated git fixtures and existing report payloads."""
from datetime import date
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'Scripts' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


G = load('policy_governance', 'check-governance.py')
C = load('policy_gate', 'check-ci-results.py')
O = load('policy_outcome', 'ci-job-outcome.py')
S = load('policy_selector', 'select-test-scope.py')


class GovernanceScopeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.git('init', '-q'); self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        (self.root / 'CoolMalliOS').mkdir()
        (self.root / 'CoolMalliOS/AppDependencies.swift').write_text('old')
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.PIPE).decode().strip()

    def commit(self):
        self.git('add', '.'); self.git('commit', '-qm', 'fixture')
        return self.git('rev-parse', 'HEAD')

    def env(self):
        return dict(GITHUB_EVENT_NAME='pull_request', MALL_VERIFICATION_TIER='required',
                    MALL_DIFF_BASE=self.base, MALL_DIFF_HEAD=self.git('rev-parse', 'HEAD'))

    def test_feature_diff_does_not_run_driver(self):
        (self.root / 'CoolMalliOS/AppDependencies.swift').write_text('new'); self.commit()
        self.assertEqual(G.driver_required(self.root, self.env()), (False, 'known unrelated paths; driver inputs unchanged'))

    def test_every_driver_input_and_workflow_change_requires_driver(self):
        for path in sorted(G.DRIVER_INPUTS | {'.github/workflows/ios.yml', 'Scripts/new-shared-helper.py', 'Tests/Governance/test_new_contract.py'}):
            with self.subTest(path=path):
                p = self.root / path; p.parent.mkdir(parents=True, exist_ok=True); p.write_text('new')
                self.commit(); self.assertTrue(G.driver_required(self.root, self.env())[0])
                self.git('reset', '--hard', self.base)

    def test_unknown_identity_dirty_empty_and_full_fail_conservatively(self):
        for env in [self.env(), {}, dict(self.env(), MALL_DIFF_BASE='0' * 40),
                    dict(self.env(), GITHUB_EVENT_NAME='schedule')]:
            self.assertTrue(G.driver_required(self.root, env)[0])
        (self.root / 'CoolMalliOS/AppDependencies.swift').write_text('dirty')
        self.assertTrue(G.driver_required(self.root, self.env())[0])

    def test_only_exact_driver_module_is_omitted_and_zero_missing_duplicate_rejected(self):
        class Case(unittest.TestCase):
            def __init__(self, identifier): super().__init__(); self.identifier = identifier
            def id(self): return self.identifier
            def runTest(self): pass
        items = [Case('test_verification_driver.Case.test_one'), Case('test_other.Case.test_two')]
        _, ids, omitted = G.selection(unittest.TestSuite(items), False)
        self.assertEqual(ids, ['test_other.Case.test_two'])
        self.assertEqual(omitted, ['test_verification_driver.Case.test_one'])
        for items in [[], [Case('test_other.Case.test_two')],
                      [Case('test_verification_driver.Case.test_one')],
                      [Case('test_verification_driver.Case.test_one')] * 2]:
            with self.assertRaises(ValueError): G.selection(unittest.TestSuite(items), False)


class GateInventoryTests(unittest.TestCase):
    def needs(self, ids, count=None):
        return {'classify': {'result': 'success', 'outputs': {'run_verification': 'true'}},
                'verify': {'result': 'success', 'outputs': {
                    'verification_status': 'core-passed-with-deferred',
                    'deferred_ids': json.dumps(ids), 'deferred_count': str(len(ids) if count is None else count)}}}

    def test_one_through_all_approved_ids_accept_before_expiry(self):
        original = C.POLICY.load
        with mock.patch.object(C.POLICY, 'load', side_effect=lambda **kw: original(today=date(2026, 11, 3), **kw)):
            for count in range(1, len(C.POLICY.IDS) + 1):
                self.assertIn('延期', C.validate(self.needs(list(C.POLICY.IDS)[:count])))

    def test_unknown_duplicate_count_mismatch_missing_ids_and_expiry_rejected(self):
        first = next(iter(C.POLICY.IDS))
        for data in [self.needs(['UNKNOWN']), self.needs([first, first]), self.needs([first], 2),
                     self.needs([], 1)]:
            with self.assertRaises(ValueError): C.validate(data)
        data = self.needs([first]); del data['verify']['outputs']['deferred_ids']
        with self.assertRaises(ValueError): C.validate(data)
        original = C.POLICY.load
        with mock.patch.object(C.POLICY, 'load', side_effect=lambda **kw: original(today=date(2026, 11, 4), **kw)):
            with self.assertRaisesRegex(ValueError, 'expired'): C.validate(self.needs([first]))

    def test_failed_cancelled_or_missing_verify_never_passes_with_success_outputs(self):
        for result in ['failure', 'cancelled', 'skipped', None]:
            data = self.needs([]); data['verify']['result'] = result
            with self.assertRaisesRegex(ValueError, 'verify result'): C.validate(data)


class ImpactAndReportingTests(unittest.TestCase):
    def test_two_smokes_and_no_unconditional_category(self):
        self.assertEqual(len(S.PR_SMOKE), 2)
        methods = ['MallDataTests/Suite/testData()', S.PR_SMOKE[0], S.PR_SMOKE[1],
                   S.CATEGORY + '/testCategory()']
        selected = S.selected_methods({'mode': 'selected', 'tier': 'required',
                                       'targets': S.PR_SMOKE, 'advisoryMethods': []}, methods)
        self.assertNotIn(S.CATEGORY + '/testCategory()', selected)
        self.assertIn('MallDataTests/Suite/testData()', selected)

    def test_direct_method_target_class_and_unknown_full_override_exclusion(self):
        method = next(iter(S.advisory_methods(ROOT)))
        for mode, targets in [('selected', [method]), ('selected', [S.HOME]), ('full', [])]:
            scope = dict(mode=mode, targets=targets, tier='required', advisoryMethods=[method])
            self.assertIn(method, S.selected_methods(scope, [method]))
        scope = dict(mode='selected', targets=S.PR_SMOKE, tier='required', advisoryMethods=[method])
        self.assertIn(method, S.excluded_advisory(scope))

    def test_environment_governance_test_and_artifact_categories_do_not_imply_product_cause(self):
        self.assertEqual(O.category({'environment': {'conclusion': 'failure'}}), 'environment')
        self.assertEqual(O.category({'support': {'conclusion': 'failure'}}), 'governance')
        self.assertEqual(O.category({'gates': {'conclusion': 'failure'}}, {
            'phases': [{'name': 'policy-negative', 'status': 'failed'}]}), 'governance')
        self.assertEqual(O.category({'gates': {'conclusion': 'failure'}}, {
            'phases': [{'name': 'test-execute-diagnostics', 'status': 'failed'}]}), 'native-test-or-runner-failure')
        self.assertEqual(O.category({'gates': {'conclusion': 'success'},
                                     'artifacts': {'conclusion': 'failure'}}), 'evidence')
        self.assertEqual(O.category({}), 'unclassified')

    def test_workflow_keeps_mac_and_single_complete_gate(self):
        workflow = (ROOT / '.github/workflows/ios.yml').read_text()
        self.assertNotIn('governance-driver:', workflow)
        self.assertIn('needs: [classify, verify]', workflow)
        self.assertIn('failure_category: ${{ steps.outcome.outputs.failure_category }}', workflow)
        self.assertIn('deferred_ids: ${{ steps.gates.outputs.deferred_ids }}', workflow)
        self.assertNotIn('MALL_GOVERNANCE_EXCLUDE', workflow)
        self.assertIn('timeout-minutes: 120', workflow)


class SupportValidatorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'Tests/Governance').mkdir(parents=True)
        (self.root / 'Scripts').mkdir()
        for name in ['select-test-scope.py', 'classify-ci-changes.py']:
            shutil.copy2(ROOT / 'Scripts' / name, self.root / 'Scripts' / name)
        self.method = next(iter(S.advisory_methods(ROOT)))
        self.replacement = S.PRODUCTION_TIMING[0]
        (self.root / 'Tests/Governance/test-support-impact.json').write_text(json.dumps({'files': {}}))
        (self.root / 'Tests/Governance/host-sensitive-advisory.json').write_text(json.dumps({
            'entries': [{'method': self.method, 'replacement': [self.replacement]}]}))

    def run_validator(self, script, full):
        module = load('validator_' + script.replace('-', '_'), script)
        expected = [self.replacement] + ([self.method] if full else [])
        scope = dict(mode='full' if full else 'selected', tier='required',
                     targets=[] if full else S.PR_SMOKE, advisoryMethods=[self.method], expected=expected)
        (self.root / 'test-scope.json').write_text(json.dumps(scope))
        (self.root / 'enumeration.json').write_text(json.dumps({'values': [{'enabledTests': [
            {'identifier': x} for x in [self.method, self.replacement]]}]}))
        (self.root / 'native-results.json').write_text(json.dumps({'methodResults': {x: 'Passed' for x in expected}}))
        argv = [script, '--tier', 'required']
        if script == 'check-test-support-scope.py':
            argv += ['--scope', str(self.root / 'test-scope.json'), '--enumeration', str(self.root / 'enumeration.json')]
        else:
            argv += ['--native-results', str(self.root / 'native-results.json')]
        with mock.patch.object(module, 'ROOT', self.root), mock.patch.object(sys, 'argv', argv):
            return module.main()

    def test_required_full_fallback_allows_direct_affected_advisory_results(self):
        for script in ['check-test-support-scope.py', 'check-test-support-execution.py']:
            with self.subTest(script=script): self.assertEqual(self.run_validator(script, True), 0)

    def test_unrelated_scope_keeps_exclusion_and_replacements_required(self):
        for script in ['check-test-support-scope.py', 'check-test-support-execution.py']:
            self.assertEqual(self.run_validator(script, False), 0)
            manifest = self.root / 'Tests/Governance/host-sensitive-advisory.json'
            original = json.loads(manifest.read_text())
            invalid = json.loads(manifest.read_text())
            invalid['entries'][0]['replacement'] = ['CatalogFeatureTests/Missing/testMissing()']
            manifest.write_text(json.dumps(invalid))
            self.assertEqual(self.run_validator(script, False), 1)
            manifest.write_text(json.dumps(original))
