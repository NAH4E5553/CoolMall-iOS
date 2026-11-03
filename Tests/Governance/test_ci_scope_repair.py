"""P1/P2 controls: real Swift method boundaries and unknown governance inputs."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'Scripts' / filename)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


S = load('repair_scope', 'select-test-scope.py')
G = load('repair_governance', 'check-governance.py')


class RepairControls(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.git('init', '-q'); self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.path = 'CoolMalliOSUITests/HomeLoadTests.swift'
        self.raw = json.loads((ROOT / 'Tests/Governance/Fixtures/test-enumeration.json').read_text())
        self.methods = [x['identifier'] for x in self.raw['values'][0]['enabledTests']]
        for name in ['host-sensitive-advisory.json', 'test-support-impact.json']:
            self.write('Tests/Governance/' + name, (ROOT / 'Tests/Governance' / name).read_text())

    def write(self, path, value):
        file = self.root / path; file.parent.mkdir(parents=True, exist_ok=True); file.write_text(value)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.PIPE, text=True).strip()

    def commit(self):
        self.git('add', '.'); self.git('commit', '--allow-empty', '-qm', 'fixture'); return self.git('rev-parse', 'HEAD')

    def env(self, base):
        return dict(GITHUB_EVENT_NAME='pull_request', MALL_VERIFICATION_TIER='required',
                    MALL_DIFF_BASE=base, MALL_DIFF_HEAD=self.git('rev-parse', 'HEAD'))

    def change(self, before, after):
        self.write(self.path, before); base = self.commit()
        self.write(self.path, after); self.commit()
        return S.plan(self.root, self.env(base))

    def test_real_shared_budget_initializer_selects_budget_and_lifecycle_consumers(self):
        source = (ROOT / self.path).read_text()
        self.assertEqual(source.count('deadline = start + seconds'), 1)
        scope = self.change(source, source.replace('deadline = start + seconds', 'deadline = start + seconds + 1'))
        self.assertTrue(scope['mode'] == 'full' or S.HOME in scope['targets'])
        selected = S.selected_methods(scope, self.methods)
        budgets = {x for x in self.methods if 'ObservationBudget' in x}
        self.assertEqual(len(budgets), 3)
        self.assertTrue(budgets <= set(selected))
        self.assertTrue(set(S.LIFECYCLE) <= set(selected))

    def test_real_test_body_replacement_can_still_narrow(self):
        source = (ROOT / self.path).read_text()
        old = 'let budget = BannerObservationBudget(seconds: 9, start: 100)'
        self.assertGreaterEqual(source.count(old), 1)
        scope = self.change(source, source.replace(old, old.replace('seconds: 9', 'seconds: 8'), 1))
        self.assertEqual(scope['reason'], 'test-method-impact')
        self.assertEqual(scope['testMethods'], [S.HOME + '/testBannerObservationBudgetRetriesConsumeTheOriginalDeadline()'])
        self.assertNotIn(S.HOME, scope['targets'])

    def test_initializer_property_type_boundary_and_deletion_do_not_narrow(self):
        source = '''import XCTest
final class HomeLoadTests: XCTestCase {
    func testA() {
        XCTAssertTrue(true)
    }
    var shared: Int {
        return 1
    }
}
private struct Helper {
    init() {
        let value = 2
    }
}
'''
        for old, new in [('return 1', 'return 2'), ('let value = 2', 'let value = 3'),
                         ('    var shared: Int {\n', ''), ('        XCTAssertTrue(true)\n', '')]:
            with self.subTest(old=old):
                scope = self.change(source, source.replace(old, new))
                self.assertTrue(scope['mode'] == 'full' or S.HOME in scope['targets'])
                self.assertNotEqual(scope['reason'], 'test-method-impact')

    def test_parser_unavailable_or_bad_source_falls_back(self):
        source = 'import XCTest\nfinal class HomeLoadTests: XCTestCase {\n    func testA() {\n        let x = 1\n    }\n}\n'
        with mock.patch.object(S.subprocess, 'run', side_effect=OSError('parser unavailable')):
            self.assertIsNone(S._test_body_ranges(source, 'HomeLoadTests'))
        with mock.patch.object(S, '_test_body_ranges', return_value=None):
            scope = self.change(source, source.replace('let x = 1', 'let x = 2'))
        self.assertIn(S.HOME, scope['targets'])
        scope = self.change(source, source.replace('let x = 1', 'let x = {'))
        self.assertIn(S.HOME, scope['targets'])

    def test_known_feature_source_skips_driver_but_unknown_config_retains_it(self):
        self.write('CoolMalliOS/AppDependencies.swift', 'old'); base = self.commit()
        self.write('CoolMalliOS/AppDependencies.swift', 'new'); self.commit()
        self.assertFalse(G.driver_required(self.root, self.env(base))[0])
        for path in ['new-build-config.toml', '.github/new-control.json',
                     'CoolMalliOS/new-build-config.toml', 'Packages/MallKit/new-control.json',
                     'docs/ENGINEERING.md']:
            with self.subTest(path=path):
                base = self.commit(); self.write(path, 'unknown = true'); self.commit()
                self.assertTrue(G.driver_required(self.root, self.env(base))[0])

    def test_known_docs_skip_but_mixed_unknown_driver_inputs_do_not(self):
        self.write('README.md', 'old'); base = self.commit()
        self.write('README.md', 'new'); self.commit()
        self.assertFalse(G.driver_required(self.root, self.env(base))[0])
        self.write('Scripts/new-helper.py', 'x = 1'); self.commit()
        self.assertTrue(G.driver_required(self.root, self.env(base))[0])
