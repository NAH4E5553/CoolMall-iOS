import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('test_results', ROOT / 'Scripts/check-test-results.py')
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)

class TestResultsTests(unittest.TestCase):
    def setUp(self):
        self.summary = {'result':'Passed', 'failedTests':0, 'skippedTests':0, 'expectedFailures':0, 'totalTestCount':2, 'passedTests':2}
        self.tree = {'testNodes':[{'name':name,'nodeType':'Unit test bundle','children':[{'name':'contract()', 'nodeType':'Test Case','result':'Passed'}]} for name in ['CoreTests','UITests']]}

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
