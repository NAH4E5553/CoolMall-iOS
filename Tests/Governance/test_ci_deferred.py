"""Exact CI-only deferral controls; offline fixtures, never simulator/App runs."""
import copy
from datetime import date
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


NATIVE = load('deferred_native', ROOT/'Scripts/check-test-results.py')
POLICY = load('deferred_policy', ROOT/'Scripts/ci-deferred-policy.py')
AUDIT = load('deferred_audit', ROOT/'Scripts/check-banner-lifecycle.py')
FINAL = load('deferred_final', ROOT/'Scripts/finalize-verification.py')
FIXTURES = load('deferred_transcripts', ROOT/'Tests/Governance/test_banner_lifecycle.py')


class NativeDeferralTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT/'Tests/Governance/Fixtures/deferred-home-timeout.json').read_text())

    def check(self):
        return NATIVE.native_result(**{key:self.data[key] for key in
                                     ['summary','tree','scope','execution','details','issues','log']})

    def test_native_exact_timeout_retained_without_mutating_failure(self):
        before = copy.deepcopy(self.data)
        result = self.check()
        self.assertEqual(result['status'], 'core-passed-with-deferred')
        self.assertEqual(result['nativeCounts']['failedTests'],1)
        self.assertEqual(result['nativeExitCode'],65)
        self.assertEqual(self.data,before)

    def test_standard_xcode_timeout_restart_is_not_a_crash_proof(self):
        self.data['log'] += '\nRestarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.'
        self.assertEqual(self.check()['status'],'core-passed-with-deferred')

    def test_same_case_timeout_plus_assertion_crash_or_second_issue_blocks(self):
        for kind in ['assertion','crash','second-summary','second-legacy','detail']:
            with self.subTest(kind=kind):
                self.setUp()
                case=self.data['tree']['testNodes'][0]['children'][0]
                if kind=='assertion': case['children'].append({'nodeType':'Failure Message','name':'XCTAssertEqual failed 1 != 2'})
                if kind=='crash': self.data['log'] += '\nApp crashed: signal 11'
                if kind=='second-summary': self.data['summary']['testFailures'].append(copy.deepcopy(self.data['summary']['testFailures'][0]))
                if kind=='second-legacy': self.data['issues']['issues']['testFailureSummaries']['_values'].append({'message':{'_value':'App crashed'}})
                if kind=='detail': self.data['details']['testRuns'].append({'nodeType':'Test Case Run','result':'Failed','name':'App crashed'})
                with self.assertRaises(ValueError): self.check()

    def test_other_method_timeout_unknown_exit_and_incomplete_sources_block(self):
        for kind in ['other','command','wrapper-only','missing-details','missing-issues','missing-log','skipped','count','missing-method','duplicate','bad-arguments']:
            with self.subTest(kind=kind):
                self.setUp()
                case=self.data['tree']['testNodes'][0]['children'][0]
                if kind=='other': case['nodeIdentifier']='HomeLoadTests/Other()'
                if kind=='command': self.data['execution']['commandExitCode']=42
                if kind=='wrapper-only': self.data['execution']['commandExitCode']=0
                if kind=='missing-details': self.data['details']=None
                if kind=='missing-issues': self.data['issues']=None
                if kind=='missing-log': self.data['log']=''
                if kind=='skipped': self.data['summary']['skippedTests']=1
                if kind=='count': self.data['summary']['totalTestCount']=2
                if kind=='missing-method': self.data['scope']['expected'].append('CoolMalliOSUITests/HomeLoadTests/Missing()')
                if kind=='duplicate': self.data['tree']['testNodes'][0]['children'].append(copy.deepcopy(case))
                if kind=='bad-arguments': case['children'].append({'nodeType':'Arguments','result':'Skipped'})
                with self.assertRaises(ValueError): self.check()

    def test_passing_summary_or_case_cannot_hide_structured_crash(self):
        for kind in ['summary','node']:
            self.setUp()
            self.data['execution'].update(commandExitCode=0,exitCode=0)
            self.data['summary'].update(result='Passed',passedTests=1,failedTests=0)
            case=self.data['tree']['testNodes'][0]['children'][0]
            case['result']='Passed'; case['children']=[]
            if kind=='summary': self.data['summary']['testFailures'][0]['failureText']='App crashed: SIGABRT'
            else:
                self.data['summary']['testFailures']=[]
                case['children']=[{'nodeType':'Crash','name':'App crashed'}]
            with self.subTest(kind=kind), self.assertRaises(ValueError): self.check()

    def test_assertion_in_log_blocks_even_with_timeout_only_native_summary(self):
        for line in ['XCTAssertEqual failed: 2 != 1','error: app failed','Test runner unexpectedly exited','Crash: SIGABRT']:
            with self.subTest(line=line):
                self.setUp(); self.data['log'] += '\n'+line
                with self.assertRaises(ValueError): self.check()


class LifecycleDeferralTests(unittest.TestCase):
    def run_audit(self, fixtures, extra_trace=''):
        methods=[AUDIT.PREFIX+f.method+'()' for f in fixtures]
        trace='\n'.join('BANNERAUDIT '+json.dumps(e) for f in fixtures for e in f.events)+extra_trace
        marks='\n'.join('BANNERTEST '+json.dumps(m) for f in fixtures for m in f.markers)
        return AUDIT.audit(methods,trace,marks,FIXTURES.STATUS,defer_cycle=True)

    def fixture(self,kind):
        return FIXTURES.Transcript(kind).finish(kind)

    def test_cycle_gap_is_deferred_other_methods_still_audited(self):
        cycle,away=self.fixture('cycle'),self.fixture('away')
        cycle.events.remove(next(e for e in cycle.events if e['event']=='advanceCommit'))
        result=self.run_audit([cycle,away])
        self.assertEqual(result['status'],'core-passed-with-deferred')
        self.assertEqual(result['methods'][cycle.method]['status'],'deferred-unresolved')
        self.assertEqual(result['methods'][away.method]['status'],'passed')

    def test_cycle_gap_cannot_hide_other_method_semantic_violation(self):
        cycle,away=self.fixture('cycle'),self.fixture('away')
        cycle.events.remove(next(e for e in cycle.events if e['event']=='advanceCommit'))
        next(e for e in away.events if e['event']=='arm' and e.get('deadline'))['deadline']-=4.9
        result=self.run_audit([cycle,away])
        self.assertEqual(result['status'],'failed')
        self.assertEqual(result['methods'][away.method]['status'],'failed')

    def test_unrelated_native_timeout_cannot_excuse_missing_audit_for_passed_method(self):
        away=self.fixture('away')
        for fault in ['begin','end']:
            marks=copy.deepcopy(away.markers)
            if fault=='begin': marks=[]
            else: marks=[m for m in marks if m['event']!='end']
            trace='\n'.join('BANNERAUDIT '+json.dumps(e) for e in away.events)
            test='\n'.join('BANNERTEST '+json.dumps(m) for m in marks)
            if fault=='begin':
                # Keep another selected method's markers so the global begin
                # requirement does not mask the method-level check.
                cycle=self.fixture('cycle')
                test='\n'.join('BANNERTEST '+json.dumps(m) for m in cycle.markers)
                trace+='\n'+'\n'.join('BANNERAUDIT '+json.dumps(e) for e in cycle.events)
                expected=[AUDIT.PREFIX+f.method+'()' for f in [away,cycle]]
            else: expected=[AUDIT.PREFIX+away.method+'()']
            if fault=='begin':
                with self.assertRaises(ValueError): AUDIT.audit(expected,trace,test,FIXTURES.STATUS,65,True,{away.method})
            else:
                result=AUDIT.audit(expected,trace,test,FIXTURES.STATUS,65,True,{away.method})
                self.assertEqual(result['status'],'failed')

    def test_app_gap_cannot_hide_malformed_or_complete_carousel_violation(self):
        for fault in ['event','shape','early-arm','duplicate']:
            with self.subTest(fault=fault):
                f=self.fixture('cycle')
                next(e for e in f.events if e['origin']=='app')['eventSequence']=2
                if fault=='event': f.events[-1]['event']='unknown'
                if fault=='shape': f.events[-1]['gate']['count']='invalid'
                if fault=='early-arm':
                    next(e for e in f.events if e['event']=='arm' and e.get('deadline'))['deadline']-=4.9
                if fault=='duplicate': f.events.insert(4,copy.deepcopy(f.events[4]))
                self.assertEqual(self.run_audit([f])['status'],'failed')

    def test_complete_cycle_semantic_violation_blocks(self):
        cycle=self.fixture('cycle')
        next(e for e in cycle.events if e['event']=='arm' and e.get('deadline'))['deadline']-=4.9
        self.assertEqual(self.run_audit([cycle])['status'],'failed')

    def test_tail_not_certified_even_when_current_parser_passes(self):
        cycle=self.fixture('cycle')
        # A recorded trailing wake with no further state change currently has
        # no producer terminal watermark. Its absence is genuinely unprovable.
        last=copy.deepcopy(cycle.events[-1])
        last.update(event='wake',eventSequence=last['eventSequence']+1)
        cycle.events.append(last)
        for drop_tail in [False,True]:
            with self.subTest(drop_tail=drop_tail):
                candidate=copy.deepcopy(cycle)
                if drop_tail: candidate.events.pop()
                result=self.run_audit([candidate])
                self.assertEqual(result['status'],'core-passed-with-deferred')
                self.assertEqual(result['methods'][cycle.method]['tailCompleteness'],'unproven')
                self.assertTrue(any('Terminal source' in w['reason'] for w in result['deferred']))

    def test_other_gap_schema_duplicate_encoding_and_unknown_do_not_defer(self):
        for kind in ['away-gap','schema','duplicate','encoding','unknown']:
            with self.subTest(kind=kind):
                f=self.fixture('away' if kind=='away-gap' else 'cycle')
                if kind=='away-gap': f.events.pop(4)
                if kind=='schema': f.events[-1]['schemaVersion']=99
                if kind=='duplicate': f.events.insert(4,copy.deepcopy(f.events[4]))
                if kind=='unknown': f.events[-1]['event']='unknown'
                if kind=='encoding':
                    with self.assertRaises(ValueError): self.run_audit([f],'\nBANNERAUDIT_ERROR broken')
                else: self.assertEqual(self.run_audit([f])['status'],'failed')


class VerdictPolicyTests(unittest.TestCase):
    def test_dated_scope_exact_and_expiry_blocks(self):
        self.assertEqual(POLICY.load(today=date(2026,10,21))['decision'],'DEC-016')
        self.assertEqual(POLICY.load(today=date(2026,11,5),active=False)['decision'],'DEC-016')
        for day in [date(2026,10,20),date(2026,11,4),date(2026,11,5)]:
            with self.assertRaisesRegex(ValueError,'expired'): POLICY.load(today=day)
        data=POLICY.load(today=date(2026,10,21))
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'policy.json'
            for kind in ['method','review','extra','renewal']:
                bad=copy.deepcopy(data)
                if kind=='method': bad['issues'][0]['method']='all'
                if kind=='review': bad['reviewRequired']=[]
                if kind=='extra': bad['issues'].append(copy.deepcopy(bad['issues'][0]))
                if kind=='renewal': bad.update(created='2026-10-22',expires='2026-11-05')
                p.write_text(json.dumps(bad))
                with self.assertRaises(ValueError): POLICY.load(p,today=date(2026,10,21))

    def test_core_warning_is_explicit_and_unknowns_block(self):
        native={'status':'core-passed-with-deferred','nativeExitCode':65,'wrapperExitCode':65,
                'deferred':[POLICY.warning('CI-DEFER-HOME-TIMEOUT-01','original timeout',method=POLICY.TIMEOUT_METHOD)]}
        result=FINAL.verdict(native,{'status':'not-required'},0)
        self.assertEqual(result['status'],'core-passed-with-deferred')
        self.assertIn('核心检查通过，但存在延期问题',FINAL.markdown(result))
        self.assertEqual(result['deferredIssueCount'],1)
        repeated={'status':'core-passed-with-deferred','deferred':[POLICY.warning(
            'CI-DEFER-CYCLE-EVIDENCE-01',reason,method=POLICY.CYCLE_METHOD) for reason in ['gap','tail unproven']]}
        self.assertEqual(FINAL.verdict(native,repeated,0)['deferredIssueCount'],2)
        self.assertEqual(FINAL.verdict(native,{'status':'not-required'},23)['status'],'failed')
        for audit in [{'status':'failed'},{},{'status':'passed','methods':{'away':{'status':'failed'}}}]:
            with self.assertRaises(ValueError): FINAL.verdict(native,audit,0)
        native['deferred'][0]['id']='arbitrary-waiver'
        with self.assertRaises(ValueError): FINAL.verdict(native,{'status':'passed'},0)


class SummaryDisclosureTests(unittest.TestCase):
    def reports(self):
        return {
            'native-results.json': {'status': 'failed', 'error': 'TEST-RESULT: not an isolated native test failure', 'deferred': []},
            'banner-audit.json': {'status': 'failed', 'methods': {'away': {'status': 'failed', 'error': 'source event after method end'}},
                'deferred': [POLICY.warning('CI-DEFER-CYCLE-EVIDENCE-01', 'Terminal source completeness is unproven', method=POLICY.CYCLE_METHOD)]},
            'banner-trace.status.log': {'commandExitCode': 65, 'exitCode': 65},
        }

    def publish(self, reports, prior=65):
        with tempfile.TemporaryDirectory() as td:
            directory = Path(td)
            for name, value in reports.items():
                (directory/name).write_text(value if isinstance(value, str) else json.dumps(value))
            originals = {name: (directory/name).read_bytes() for name in reports}
            output = directory/'github-output.txt'
            result = subprocess.run([sys.executable, str(ROOT/'Scripts/finalize-verification.py'), str(directory),
                                     '--prior-exit', str(prior)], capture_output=True, text=True,
                                    env=dict(os.environ, GITHUB_OUTPUT=str(output), PYTHONDONTWRITEBYTECODE='1'))
            self.assertEqual({name: (directory/name).read_bytes() for name in reports}, originals)
            data = json.loads((directory/'verification-verdict.json').read_text())
            markdown = (directory/'verification-verdict.md').read_text()
            return result, data, markdown, output.read_text()

    def test_blocking_summary_keeps_recognized_cycle_warning_and_raw_exits(self):
        result, data, markdown, output = self.publish(self.reports())
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertEqual((data['status'], data['deferredIssueCount']), ('failed', 1))
        self.assertEqual(data['deferred'][0]['id'], 'CI-DEFER-CYCLE-EVIDENCE-01')
        self.assertEqual((data['nativeExitCode'], data['wrapperExitCode'], data['priorExitCode']), (65, 65, 65))
        self.assertIn('banner-trace.status.log', data['nativeExitCodeSource'])
        self.assertIn('Blocking verification failure', markdown)
        self.assertIn('已识别的延期项（阻塞失败保持不变）', markdown)
        self.assertIn('CI-DEFER-CYCLE-EVIDENCE-01', markdown)
        self.assertIn('Original native/wrapper exits: 65/65', markdown)
        self.assertNotIn('核心检查通过', markdown)
        self.assertEqual(output, 'verification_status=failed\ndeferred_count=1\n')

    def test_unknown_mismatched_or_malformed_warning_never_becomes_an_allowed_issue(self):
        for kind in ['id', 'method', 'state', 'reason', 'not-object', 'list', 'report-status']:
            with self.subTest(kind=kind):
                reports = self.reports()
                warning = copy.deepcopy(reports['banner-audit.json']['deferred'][0])
                if kind == 'id': warning['id'] = 'allow-all-timeouts'
                if kind == 'method': warning['method'] = POLICY.TIMEOUT_METHOD
                if kind == 'state': warning['state'] = 'closed'
                if kind == 'reason': warning['reason'] = ''
                if kind == 'not-object': warning = 'not-a-warning'
                if kind == 'report-status': reports['banner-audit.json']['status'] = 'unknown-source'
                if kind == 'list': reports['banner-audit.json']['deferred'] = 'not-a-list'
                else: reports['banner-audit.json']['deferred'].append(warning)
                result, data, _, _ = self.publish(reports)
                self.assertEqual((result.returncode, data['status']), (65, 'failed'))
                self.assertEqual(data['deferredIssueCount'], 0 if kind in ['list', 'report-status'] else 1)
                self.assertTrue(data['disclosureErrors'])
                self.assertTrue(all(item['id'] in POLICY.IDS for item in data['deferred']))

    def test_duplicate_reasons_count_unique_ids_without_changing_blocking_exit(self):
        reports = self.reports()
        reports['banner-audit.json']['deferred'].append(copy.deepcopy(reports['banner-audit.json']['deferred'][0]))
        reports['native-results.json']['deferred'] = [POLICY.warning('CI-DEFER-HOME-TIMEOUT-01', 'recognized timeout', method=POLICY.TIMEOUT_METHOD)]
        result, data, _, output = self.publish(reports, prior=23)
        self.assertEqual((result.returncode, data['status'], data['deferredIssueCount']), (23, 'failed', 2))
        self.assertIn('deferred_count=2', output)

    def test_missing_or_damaged_report_keeps_other_valid_disclosure_and_failure(self):
        for kind in ['missing', 'malformed', 'non-object']:
            with self.subTest(kind=kind):
                reports = self.reports()
                if kind == 'missing': del reports['native-results.json']
                if kind == 'malformed': reports['native-results.json'] = '{broken'
                if kind == 'non-object': reports['native-results.json'] = []
                result, data, _, _ = self.publish(reports, prior=42)
                self.assertEqual((result.returncode, data['status'], data['deferredIssueCount']), (42, 'failed', 1))
                self.assertEqual((data['nativeExitCode'], data['wrapperExitCode']), (65, 65))
                self.assertTrue(data['disclosureErrors'])

    def test_original_command_wrapper_and_prior_codes_are_not_collapsed(self):
        reports = self.reports()
        reports['banner-trace.status.log'] = {'commandExitCode': 0, 'exitCode': 65}
        reports['native-results.json'].update(nativeExitCode=65, wrapperExitCode=65)
        result, data, markdown, _ = self.publish(reports, prior=42)
        self.assertEqual(result.returncode, 42)
        self.assertEqual((data['nativeExitCode'], data['wrapperExitCode'], data['priorExitCode']), (0, 65, 42))
        self.assertIn('records disagree', ' '.join(data['disclosureErrors']))
        self.assertIn('Original native/wrapper exits: 0/65', markdown)

    def test_unavailable_original_codes_are_explicit_not_inferred_from_prior(self):
        reports = self.reports(); del reports['banner-trace.status.log']
        result, data, markdown, _ = self.publish(reports, prior=42)
        self.assertEqual(result.returncode, 42)
        self.assertEqual((data['nativeExitCode'], data['wrapperExitCode']), (None, None))
        self.assertIn('Original native/wrapper exits: unavailable/unavailable', markdown)
        self.assertIn('Prior gate/entry exit: 42', markdown)

    def test_failed_result_with_disclosures_still_blocks_required_checks(self):
        result, data, _, output = self.publish(self.reports())
        checks = load('disclosure_required', ROOT/'Scripts/check-ci-results.py')
        for job_result in ['failure', 'success']:
            with self.subTest(job_result=job_result), self.assertRaises(ValueError):
                checks.validate({'classify': {'result': 'success', 'outputs': {'run_verification': 'true'}},
                                 'verify': {'result': job_result, 'outputs': dict(line.split('=',1) for line in output.splitlines())}})
        self.assertEqual(result.returncode, 65)
        self.assertEqual(data['status'], 'failed')

    def test_business_or_crash_failure_never_turns_green_with_a_known_warning(self):
        for error in ['XCTAssertEqual failed: 1 != 2', 'App crashed: signal 11']:
            with self.subTest(error=error):
                reports = self.reports(); reports['native-results.json']['error'] = error
                result, data, markdown, _ = self.publish(reports, prior=0)
                self.assertEqual((result.returncode, data['status'], data['deferredIssueCount']), (65, 'failed', 1))
                self.assertNotIn('核心检查通过', markdown)

    def test_summary_error_preserves_original_zero_prior_while_returning_failure(self):
        reports = self.reports(); del reports['native-results.json']
        reports['banner-trace.status.log'] = {'commandExitCode': 0, 'exitCode': 0}
        result, data, markdown, output = self.publish(reports, prior=0)
        self.assertEqual((result.returncode, data['status']), (65, 'failed'))
        self.assertEqual((data['priorExitCode'], data['nativeExitCode'], data['wrapperExitCode']), (0, 0, 0))
        self.assertIn('Prior gate/entry exit: 0', markdown)
        self.assertEqual(output, 'verification_status=failed\ndeferred_count=1\n')
        self.assertTrue(data['disclosureErrors'])

    def test_existing_passing_verdicts_and_warning_labels_remain(self):
        for deferred in [False, True]:
            with self.subTest(deferred=deferred):
                reports = self.reports()
                reports['native-results.json'] = {'status': 'passed', 'nativeExitCode': 0, 'wrapperExitCode': 0, 'deferred': []}
                reports['banner-trace.status.log'] = {'commandExitCode': 0, 'exitCode': 0}
                reports['banner-audit.json'].update(status='core-passed-with-deferred' if deferred else 'not-required', methods={})
                if not deferred: reports['banner-audit.json']['deferred'] = []
                result, data, markdown, _ = self.publish(reports, prior=0)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(data['status'], 'core-passed-with-deferred' if deferred else 'core-passed')
                self.assertEqual('核心检查通过，但存在延期问题' in markdown, deferred)


if __name__=='__main__': unittest.main()
