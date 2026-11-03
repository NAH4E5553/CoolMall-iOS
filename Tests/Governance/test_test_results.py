import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import tempfile
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('test_results', ROOT / 'Scripts/check-test-results.py')
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)

class TestResultsTests(unittest.TestCase):
    def setUp(self):
        self.summary = {'result':'Passed', 'failedTests':0, 'skippedTests':0, 'expectedFailures':0, 'totalTestCount':2, 'passedTests':2}
        self.tree = {'testNodes':[{'name':name,'nodeType':'UI test bundle' if name == 'UITests' else 'Unit test bundle','children':[{'name':'contract()', 'nodeType':'Test Case','result':'Passed'}]} for name in ['CoreTests','UITests']]}

    def test_all_registered_targets(self):
        self.assertEqual(CHECK.validate(self.summary, self.tree, {'CoreTests','UITests'}), {'CoreTests':1,'UITests':1})

    def test_silent_missing_package_tests(self):
        with self.assertRaisesRegex(ValueError, 'missing/empty'):
            CHECK.validate(self.summary,self.tree,{'CoreTests','UITests','MissingTests'})

    def test_zero_cases(self):
        self.tree['testNodes'][0]['children']=[]
        with self.assertRaisesRegex(ValueError, 'missing/empty'): CHECK.validate(self.summary,self.tree,{'CoreTests','UITests'})

    def test_skip_is_failure(self):
        self.summary['skippedTests']=1
        with self.assertRaisesRegex(ValueError, 'failures/skips'): CHECK.validate(self.summary,self.tree,{'CoreTests','UITests'})

    def test_count_mismatch(self):
        self.summary['totalTestCount']=3
        with self.assertRaisesRegex(ValueError, 'count mismatch'): CHECK.validate(self.summary,self.tree,{'CoreTests','UITests'})


class NativeResultInventoryTests(unittest.TestCase):
    def setUp(self):
        # Pruned native xcresult nodes preserve real Unit/UI suite nesting,
        # stable identifiers and parameterized Arguments (not invented UI types).
        fixture = json.loads((ROOT / 'Tests/Governance/Fixtures/test-results-mixed-bundles.json').read_text())
        self.summary, self.tree = fixture['summary'], fixture['tree']
        self.scope = {'expected': fixture['expected']}
        self.unit, self.ui = self.tree['testNodes'][0]['children']
        self.ui_cases = self.ui['children'][0]['children']
        self.arguments = self.unit['children'][0]['children'][0]['children']

    def check(self):
        return CHECK.validate_inventory(self.summary, self.tree, self.scope)

    def test_native_mixed_bundles_and_parameter_records_pass(self):
        self.assertEqual(self.unit['nodeType'], 'Unit test bundle')
        self.assertEqual(self.ui['nodeType'], 'UI test bundle')
        self.assertEqual(self.check(), {
            'methodCounts': {'MallImagesTests': 1, 'CoolMalliOSUITests': 2},
            'parameterArgumentRecordCount': 2})

    def test_missing_extra_duplicate_and_wrong_ui_methods_rejected(self):
        original = copy.deepcopy(self.ui_cases)
        for change, error in [('missing', 'missing executed'), ('extra', 'unexpected/duplicate'),
                              ('duplicate', 'unexpected/duplicate'), ('same-count-wrong', 'unexpected/duplicate')]:
            with self.subTest(change=change):
                self.ui_cases[:] = copy.deepcopy(original)
                if change == 'missing': self.ui_cases.pop()
                if change in ('extra', 'duplicate'): self.ui_cases.append(copy.deepcopy(original[0]))
                if change in ('extra', 'same-count-wrong'):
                    self.ui_cases[-1]['nodeIdentifier'] = 'HomeLoadTests/unexpectedMethod()'
                # Keep counts internally consistent, so exact identity checks
                # must catch missing/replaced methods even when totals agree.
                self.summary['totalTestCount'] = self.summary['passedTests'] = 1 + len(self.ui_cases)
                with self.assertRaisesRegex(ValueError, error): self.check()

    def test_missing_or_unknown_bundle_type_rejected(self):
        for kind in [None, 'Unexpected test bundle']:
            with self.subTest(kind=kind):
                if kind is None: self.ui.pop('nodeType', None)
                else: self.ui['nodeType'] = kind
                with self.assertRaisesRegex(ValueError, 'missing or unsupported test bundle'):
                    self.check()

    def test_unregistered_ui_bundle_rejected(self):
        self.ui['name'] = 'UnregisteredUITests'
        with self.assertRaisesRegex(ValueError, 'unregistered'):
            self.check()

    def test_skipped_or_failed_ui_case_rejected(self):
        for state in ['Skipped', 'Failed']:
            with self.subTest(state=state):
                self.ui_cases[0]['result'] = state
                with self.assertRaisesRegex(ValueError, 'nonpassing case'):
                    self.check()

    def test_skipped_failed_or_duplicate_arguments_rejected(self):
        original = copy.deepcopy(self.arguments)
        for state in ['Skipped', 'Failed', 'duplicate']:
            with self.subTest(state=state):
                self.arguments[:] = copy.deepcopy(original)
                if state == 'duplicate': self.arguments.append(copy.deepcopy(original[0]))
                else: self.arguments[0]['result'] = state
                with self.assertRaisesRegex(ValueError, 'failed/skipped/duplicate arguments'):
                    self.check()


class FailedNativeDisclosureTests(unittest.TestCase):
    def test_cli_keeps_all_final_methods_when_five_native_failures_block(self):
        spec = importlib.util.spec_from_file_location('scope_fixture', ROOT / 'Scripts/select-test-scope.py')
        selector = importlib.util.module_from_spec(spec); spec.loader.exec_module(selector)
        raw = json.loads((ROOT/'Tests/Governance/Fixtures/test-enumeration.json').read_text())
        targets = {x['identifier'].split('/')[0] for x in raw['values'][0]['enabledTests']}
        scope = selector.resolve(dict(mode='full', targets=[], mappingSHA256=selector.MAPPING_HASH,
                                     testPlan='CoolMalliOS', configuration='Debug'), raw, targets)
        cases = {}
        for identifier in scope['expected']:
            bundle, case = identifier.split('/', 1)
            cases.setdefault(bundle, []).append(dict(nodeType='Test Case', nodeIdentifier=case, result='Passed'))
        failed = [x for x in cases['CoolMalliOSUITests'] if x['nodeIdentifier'].startswith('HomeLoadTests/')][:5]
        for node in failed: node['result'] = 'Failed'
        tree = {'testNodes': [dict(name=name, nodeType='UI test bundle' if name == 'CoolMalliOSUITests' else 'Unit test bundle',
                                  children=nodes) for name, nodes in cases.items()]}
        summary = dict(result='Failed', failedTests=5, passedTests=len(scope['expected'])-5,
                       skippedTests=0, expectedFailures=0, totalTestCount=len(scope['expected']),
                       testFailures=[dict(testIdentifierString=n['nodeIdentifier']) for n in failed])
        def native(command, **kwargs):
            value = summary if 'summary' in command else tree if 'tests' in command else {}
            return SimpleNamespace(stdout=json.dumps(value))
        with tempfile.TemporaryDirectory() as td:
            directory = Path(td)
            for name, data in [('scope.json',scope),('execution.json',dict(commandExitCode=65,exitCode=65,
                           state='stream-stopped-by-owner',diagnosticErrors=[]))]:
                (directory/name).write_text(json.dumps(data))
            (directory/'tests.log').write_text('original failing command')
            output=directory/'native.json'
            argv=['check-test-results.py', str(directory/'Tests.xcresult'), '--scope',str(directory/'scope.json'),
                  '--execution-status',str(directory/'execution.json'),'--tests-log',str(directory/'tests.log'),
                  '--output',str(output)]
            with patch('sys.argv',argv), patch.object(CHECK.subprocess,'run',side_effect=native):
                self.assertEqual(CHECK.main(),1)
            report=json.loads(output.read_text())
            self.assertEqual(report['status'],'failed')
            self.assertEqual(set(report['methodResults']),set(scope['expected']))
            self.assertEqual(sum(v=='Failed' for v in report['methodResults'].values()),5)
            self.assertEqual(report['deferred'],[])
            self.assertEqual(report['nativeCounts']['failedTests'],5)

    def test_duplicate_native_method_never_overwrites_a_failure(self):
        case=dict(nodeType='Test Case',nodeIdentifier='Suite/test()',result='Failed')
        tree={'testNodes':[dict(nodeType='UI test bundle',name='CoolMalliOSUITests',
                               children=[case,dict(case,result='Passed')])]}
        with self.assertRaisesRegex(ValueError,'duplicate native'):
            CHECK.method_inventory(tree)
