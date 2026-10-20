import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'Scripts' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SIMULATOR = load('simulator_selection', 'select-simulator.py')
RESULTS = load('ci_results', 'check-ci-results.py')
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
UDID = 'A82A0761-D2D8-4A46-A517-98B945A52E15'


class CIRuntimeTests(unittest.TestCase):
    def inventories(self):
        return ({'runtimes': [{'identifier': RUNTIME, 'version': '27.0', 'isAvailable': True}]},
                {'devices': {RUNTIME: [{'name': 'iPhone 18 Pro', 'isAvailable': True, 'udid': UDID}]}})

    def test_exact_runtime(self):
        self.assertEqual(SIMULATOR.select(*self.inventories(), '27.0'), UDID)

    def test_other_runtime_cannot_replace_minimum(self):
        with self.assertRaisesRegex(ValueError, 'iOS 17.0 runtime'):
            SIMULATOR.select(*self.inventories(), '17.0')

    def test_unavailable_runtime(self):
        runtimes, devices = self.inventories()
        runtimes['runtimes'][0]['isAvailable'] = False
        with self.assertRaises(ValueError):
            SIMULATOR.select(runtimes, devices, '27.0')

    def test_unavailable_phone(self):
        runtimes, devices = self.inventories()
        devices['devices'][RUNTIME][0]['isAvailable'] = False
        with self.assertRaisesRegex(ValueError, 'No available iPhone'):
            SIMULATOR.select(runtimes, devices, '27.0')

    def test_invalid_udid(self):
        runtimes, devices = self.inventories()
        devices['devices'][RUNTIME][0]['udid'] = 'invalid'
        with self.assertRaises(ValueError):
            SIMULATOR.select(runtimes, devices, '27.0')


class CIResultTests(unittest.TestCase):
    def needs(self, required='true', result='success', reason='implementation-rules-or-unknown'):
        return {'classify': {'result': 'success', 'outputs': {'run_verification': required, 'reason': reason}},
                'verify': {'result': result}}

    def test_success(self):
        self.assertIn('verification succeeded', RESULTS.validate(self.needs()))

    def test_explicit_scope_exclusion(self):
        self.assertIn('not run', RESULTS.validate(self.needs('false', 'skipped', 'docs-or-placeholder-only')))

    def test_failure_skip_cancel_and_missing_result(self):
        for result in ('failure', 'skipped', 'cancelled', None):
            with self.subTest(result=result), self.assertRaisesRegex(ValueError, 'verify result'):
                RESULTS.validate(self.needs(result=result))

    def test_excluded_job_must_really_be_skipped(self):
        for result in ('failure', 'success', 'cancelled', None):
            with self.subTest(result=result), self.assertRaisesRegex(ValueError, 'unexpectedly'):
                RESULTS.validate(self.needs('false', result, 'docs-or-placeholder-only'))

    def test_classification_failure_never_passes(self):
        for result in ('failure', 'cancelled', 'skipped', None):
            data = self.needs('false', 'skipped', 'docs-or-placeholder-only')
            data['classify']['result'] = result
            with self.subTest(result=result), self.assertRaisesRegex(ValueError, 'classify result'):
                RESULTS.validate(data)

    def test_invalid_decision_or_reason(self):
        for required, reason in [('false', 'unknown'), ('', ''), ('TRUE', ''), (None, '')]:
            with self.subTest(required=required), self.assertRaisesRegex(ValueError, 'classification decision'):
                RESULTS.validate(self.needs(required, 'skipped', reason))

    def test_missing_job(self):
        with self.assertRaisesRegex(ValueError, 'job set'):
            RESULTS.validate({'verify': {'result': 'success'}})

    def test_unknown_job(self):
        data = self.needs()
        data['extra'] = {'result': 'success'}
        with self.assertRaisesRegex(ValueError, 'job set'):
            RESULTS.validate(data)

    def test_missing_outputs(self):
        data = self.needs()
        data['classify']['outputs'] = {}
        with self.assertRaises(KeyError):
            RESULTS.validate(data)


if __name__ == '__main__':
    unittest.main()
