"""Exercise the real verification entry with isolated command stubs, not Xcode."""
import json
import os
import py_compile
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STUB = r'''#!/usr/bin/env python3
import json, os, plistlib, sys, time
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
event = name
if name == 'xcrun' and 'stream' in args:
    event = 'xcrun:trace'
if name == 'xcodebuild':
    event += ':' + args[0]
    if '-enumerate-tests' in args:
        event = 'xcodebuild:discovery'
    if args[0] == 'build':
        event += ':' + args[args.index('-configuration') + 1]
with open(os.environ['STUB_EVENTS'], 'a') as f:
    f.write(json.dumps({'event': event, 'args': args}) + '\n')
if event == 'xcodebuild:build:Debug':
    app = Path(args[args.index('-derivedDataPath') + 1]) / 'Build/Products/Debug-iphonesimulator/CoolMalliOS.app'
    app.mkdir(parents=True)
    (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'fixture.verification'}))
if event == 'xcodebuild:discovery':
    raw = json.loads(Path('fixture-enumeration.json').read_text())
    if os.environ.get('STUB_BAD_DISCOVERY'):
        raw['values'][0]['enabledTests'] = []
    Path(args[args.index('-test-enumeration-output-path') + 1]).write_text(json.dumps(raw))
    if os.environ.get('STUB_CREATE_BYTECODE'):
        import py_compile
        cache = Path('Scripts/__pycache__/check-boundaries.fixture.pyc')
        cache.parent.mkdir(exist_ok=True)
        py_compile.compile('Scripts/check-boundaries.py', cfile=str(cache), doraise=True)
    if os.environ.get('STUB_MUTATE_SOURCE') == 'tracked':
        with Path('Scripts/check-toolchain.sh').open('a') as source:
            source.write('\n# genuine tracked source change\n')
    elif os.environ.get('STUB_MUTATE_SOURCE') == 'untracked':
        Path('Scripts/unexpected.py').write_text('unexpected = True\n')
if event == 'xcodebuild:test-without-building':
    deadline = time.monotonic() + 5
    while not Path('.build/trace-ready').exists() and time.monotonic() < deadline:
        time.sleep(.01)
if event == 'xcodebuild:test-without-building' and os.environ.get('STUB_TAMPER'):
    response = Path(args[args.index('-only-testing') + 1][1:])
    if os.environ['STUB_TAMPER'] == 'response':
        response.write_text('CoolMalliOSUITests/HomeLoadTests/unknown()\n')
    else:
        manifest = response.parent / 'test-scope.json'
        data = json.loads(manifest.read_text()); data['expected'] = data['expected'][:-1]
        manifest.write_text(json.dumps(data))
if event == os.environ.get('STUB_BLOCK'):
    Path(os.environ['STUB_READY']).write_text('ready')
    time.sleep(30)
if event == 'xcodebuild:test-without-building' and os.environ.get('STUB_CORRUPT'):
    next(Path('.build/verification').glob('*/stage-timings.json')).write_text('{broken')
if event == os.environ.get('STUB_FAIL'):
    sys.exit(int(os.environ.get('STUB_RC', '42')))
if event == 'check-banner-lifecycle.py' and os.environ.get('STUB_AUDIT_RC'):
    sys.exit(int(os.environ['STUB_AUDIT_RC']))
if event == 'check-test-results.py':
    if os.environ.get('STUB_FAIL') == 'xcodebuild:test-without-building' and not os.environ.get('STUB_NATIVE_DEFER'):
        sys.exit(1)
    native = {'status':'passed', 'deferred':[], 'nativeExitCode':0, 'wrapperExitCode':0}
    if os.environ.get('STUB_NATIVE_DEFER'):
        native.update(status='core-passed-with-deferred', nativeExitCode=65, wrapperExitCode=65,
                      deferred=[{'id':'CI-DEFER-HOME-TIMEOUT-01','state':'deferred-unresolved',
                      'method':'CoolMalliOSUITests/HomeLoadTests/testSelectedBannerAndBottomPositionRetainedAcrossTabs()',
                      'reason':'fixture original timeout retained'}])
    Path(args[args.index('--output')+1]).write_text(json.dumps(native))
if event == 'check-banner-lifecycle.py':
    audit = {'status':'passed','methods':{},'deferred':[]}
    if os.environ.get('STUB_AUDIT_DEFER'):
        audit.update(status='core-passed-with-deferred', deferred=[{
            'id':'CI-DEFER-CYCLE-EVIDENCE-01','state':'deferred-unresolved',
            'method':'CoolMalliOSUITests/HomeLoadTests/testBannerAutoplayCyclesAndRestartsAfterUnchangedDrag()',
            'reason':'fixture unproven tail'}])
    Path(args[args.index('--output')+1]).write_text(json.dumps(audit))
if event == 'xcrun:trace':
    print('AUTOTRACE fixture stream', flush=True)
    Path('.build/trace-ready').write_text('ready')
    while True: time.sleep(1)
'''


class VerificationDriverTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'Scripts').mkdir()
        (self.root / 'bin').mkdir()
        (self.root / '.github/workflows').mkdir(parents=True)
        (self.root / '.github/workflows/ios.yml').write_text('name: legacy fixture\\n')
        for name in ['verify-local.sh', 'verification-timing.py', 'select-test-scope.py', 'classify-ci-changes.py', 'check-boundaries.py', 'with-banner-trace.py', 'finalize-verification.py', 'ci-deferred-policy.py', 'ci-deferred-checks.json']:
            shutil.copy2(ROOT / 'Scripts' / name, self.root / 'Scripts' / name)
        for name in ['check-toolchain.sh', 'check-format.sh', 'check-boundary-negative.sh',
                     'check-test-results.py', 'check-banner-lifecycle.py']:
            self.stub(self.root / 'Scripts' / name)
        for name in ['xcodebuild', 'xcrun']:
            self.stub(self.root / 'bin' / name)
        shutil.copy2(ROOT / 'ENGINEERING.md', self.root / 'ENGINEERING.md')
        shutil.copy2(ROOT / 'Tests/Governance/Fixtures/test-enumeration.json', self.root / 'fixture-enumeration.json')
        # Match the real repository: Python cache is generated output, not source.
        (self.root / '.gitignore').write_text('.build/\n__pycache__/\nevents.jsonl\nready\n')
        for args in [('init', '-q'), ('config', 'user.email', 'fixture@example.invalid'),
                     ('config', 'user.name', 'Fixture'), ('add', '.'), ('commit', '-qm', 'fixture')]:
            subprocess.run(['git', *args], cwd=self.root, check=True, capture_output=True)
        self.env = dict(os.environ, PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
                        MALL_SIMULATOR_ID='fixture-only-no-device',
                        STUB_EVENTS=str(self.root / 'events.jsonl'),
                        STUB_READY=str(self.root / 'ready'))
        for key in ['MALL_TEST_DIAGNOSTICS', 'STUB_FAIL', 'STUB_RC', 'STUB_CORRUPT', 'STUB_BLOCK', 'STUB_BAD_DISCOVERY', 'STUB_CREATE_BYTECODE', 'STUB_MUTATE_SOURCE', 'GITHUB_EVENT_NAME']:
            self.env.pop(key, None)

    def stub(self, path):
        path.write_text(STUB)
        path.chmod(0o755)

    def run_entry(self, **env):
        return subprocess.run(['bash', 'Scripts/verify-local.sh'], cwd=self.root,
                              env=dict(self.env, **env), capture_output=True, text=True, timeout=15)

    def ledger(self):
        path = next((self.root / '.build/verification').glob('*/stage-timings.json'))
        return path, json.loads(path.read_text())

    def events(self):
        path = self.root / 'events.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()
                if json.loads(line)['event'] not in {'xcrun:trace', 'check-banner-lifecycle.py'}] if path.exists() else []

    def test_default_keeps_complete_order_and_never_diagnostics(self):
        result = self.run_entry()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = self.events()
        self.assertEqual([e['event'] for e in events], [
            'check-toolchain.sh', 'xcrun', 'xcrun', 'check-format.sh',
            'check-boundary-negative.sh', 'xcodebuild:build:Debug', 'xcodebuild:build:Release',
            'xcrun', 'xcrun', 'xcrun', 'xcrun', 'xcodebuild:discovery', 'xcodebuild:test-without-building', 'check-test-results.py'])
        discovery = next(e['args'] for e in events if e['event'] == 'xcodebuild:discovery')
        self.assertEqual(discovery[discovery.index('-collect-test-diagnostics') + 1], 'never')
        args = next(e['args'] for e in events if e['event'] == 'xcodebuild:test-without-building')
        self.assertEqual(args[args.index('-collect-test-diagnostics') + 1], 'never')
        self.assertEqual(args[args.index('-testPlan') + 1], 'CoolMalliOS')
        self.assertEqual(args[args.index('-parallel-testing-enabled') + 1], 'NO')
        self.assertFalse(any(a.startswith(('-skip-testing', '-maximum-test')) for a in args))
        self.assertEqual(args.count('-only-testing'), 1)
        self.assertTrue(args[args.index('-only-testing') + 1].startswith('@'))
        manifest = json.loads(next((self.root / '.build/verification').glob('*/test-scope.json')).read_text())
        self.assertEqual(manifest['expected'], manifest['discovered'])
        path, data = self.ledger()
        self.assertEqual(data['verificationExitCode'], 0)
        self.assertTrue(all(p['status'] == 'passed' and p['durationSeconds'] >= 0 for p in data['phases']))
        self.assertTrue(path.with_suffix('.md').exists())

    def test_live_trace_is_retained_without_changing_business_checks(self):
        result = self.run_entry()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = [json.loads(line) for line in (self.root / 'events.jsonl').read_text().splitlines()]
        self.assertEqual(sum(event['event'] == 'xcrun:trace' for event in events), 1)
        trace = next((self.root / '.build/verification').glob('*/banner-trace.log'))
        self.assertIn('AUTOTRACE fixture stream', trace.read_text())
        status = json.loads(trace.with_suffix('.status.log').read_text())
        self.assertEqual(status['exitCode'], 0)
        self.assertTrue(status['eventsObserved'])
        self.assertEqual(status['diagnosticErrors'], [])
        self.assertEqual(self.events()[-1]['event'], 'check-test-results.py')

    def test_pr_selected_entry_uses_discovered_class_and_exact_head(self):
        # Replace only the remote transport in this isolated copy, retaining the
        # actual history decision, Git diff, resolver and shell entry.
        selector = self.root / 'Scripts/select-test-scope.py'
        text = selector.read_text().replace('def api(path, env):', 'def live_api(path, env):')
        fake = """def api(path, env):
    if '/jobs?' in path:
        return {'total_count':2, 'jobs':[{'name':name,'status':'completed','conclusion':'success'} for name in ['F0 verification','required-checks']]}
    if '/workflows/' in path:
        return {'total_count':1,'workflow_runs':[{'id':1,'created_at':'2026-01-01','status':'completed','conclusion':'success','head_sha':env['MALL_DIFF_BASE'],'head_branch':'fixture','pull_requests':[{'number':13}]}]}
    return {'id':2,'workflow_id':10,'head_branch':'fixture'}


"""
        selector.write_text(text.replace('def prior_verification(', fake + 'def prior_verification('))
        test = self.root / 'CoolMalliOSUITests/HomeLoadTests.swift'
        test.parent.mkdir(); test.write_text('oldBody\n')
        def git(*args):
            return subprocess.check_output(['git', *args], cwd=self.root).decode().strip()
        git('add','.'); git('commit','-qm','baseline transport fixture')
        base = git('rev-parse','HEAD')
        test.write_text('newBody\n')
        git('add','.'); git('commit','-qm','test body change')
        head = git('rev-parse','HEAD')
        # Real bytecode inside the repo must not make an exact-head PR dirty.
        cache = self.root / 'Scripts/__pycache__/select-test-scope.fixture.pyc'
        cache.parent.mkdir(exist_ok=True)
        py_compile.compile(str(selector), cfile=str(cache), doraise=True)
        self.assertTrue(cache.is_file())
        result = self.run_entry(STUB_CREATE_BYTECODE='1', GITHUB_EVENT_NAME='pull_request', GITHUB_RUN_ID='2',
                                MALL_PR_NUMBER='13', MALL_DIFF_BASE=base, MALL_DIFF_HEAD=head)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        scope = json.loads(next((self.root / '.build/verification').glob('*/test-scope.json')).read_text())
        self.assertEqual(scope['mode'], 'selected')
        self.assertTrue(scope['expected'])
        self.assertTrue(scope['omitted'])
        self.assertTrue(all(method.startswith('CoolMalliOSUITests/HomeLoadTests/') for method in scope['expected']))
        args = next(e['args'] for e in self.events() if e['event'] == 'xcodebuild:test-without-building')
        response = self.root / args[args.index('-only-testing') + 1][1:]
        self.assertEqual(response.read_text().splitlines(), scope['expected'])

    def test_bytecode_generated_after_selection_does_not_change_source_identity(self):
        result = self.run_entry(STUB_CREATE_BYTECODE='1')
        self.assertTrue((self.root / 'Scripts/__pycache__/check-boundaries.fixture.pyc').is_file())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.events()[-1]['event'], 'check-test-results.py')
        status = subprocess.check_output(['git', 'status', '--porcelain'], cwd=self.root, text=True)
        self.assertEqual(status, '')

    def assert_source_change_rejected(self, kind, path):
        result = self.run_entry(STUB_CREATE_BYTECODE='1', STUB_MUTATE_SOURCE=kind)
        self.assertTrue((self.root / 'Scripts/__pycache__/check-boundaries.fixture.pyc').is_file())
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('TEST-SCOPE: source changed since selection', result.stdout + result.stderr)
        self.assertNotIn('xcodebuild:test-without-building', [event['event'] for event in self.events()])
        status = subprocess.check_output(['git', 'status', '--porcelain'], cwd=self.root, text=True)
        self.assertIn(path, status)
        self.assertNotIn('__pycache__', status)

    def test_tracked_source_change_still_rejected_with_bytecode_cache(self):
        self.assert_source_change_rejected('tracked', 'Scripts/check-toolchain.sh')

    def test_untracked_source_change_still_rejected_with_bytecode_cache(self):
        self.assert_source_change_rejected('untracked', 'Scripts/unexpected.py')

    def test_changed_response_or_manifest_cannot_pass_entry(self):
        for value in ['response', 'manifest']:
            with self.subTest(value=value):
                result = self.run_entry(STUB_TAMPER=value)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('PASS: local F0 gates', result.stdout)

    def test_empty_discovery_stops_before_execution(self):
        result = self.run_entry(STUB_BAD_DISCOVERY='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('xcodebuild:test-without-building', [e['event'] for e in self.events()])

    def test_enumeration_failure_preserves_exit(self):
        result = self.run_entry(STUB_FAIL='xcodebuild:discovery', STUB_RC='71')
        self.assertEqual(result.returncode, 71)
        self.assertNotIn('xcodebuild:test-without-building', [e['event'] for e in self.events()])

    def test_explicit_failure_diagnostics(self):
        result = self.run_entry(MALL_TEST_DIAGNOSTICS='on-failure')
        self.assertEqual(result.returncode, 0)
        args = next(e['args'] for e in self.events() if e['event'] == 'xcodebuild:test-without-building')
        self.assertEqual(args[args.index('-collect-test-diagnostics') + 1], 'on-failure')

    def test_invalid_diagnostics_rejected_before_external_commands(self):
        # Each value is literal environment data, never evaluated as shell code.
        for value in ['', 'always', 'never -skip-testing:Anything', '$(touch injected)']:
            with self.subTest(value=value):
                result = self.run_entry(MALL_TEST_DIAGNOSTICS=value)
                self.assertEqual(result.returncode, 64)
                self.assertEqual(self.events(), [])
                self.assertFalse((self.root / 'injected').exists())

    def test_early_failure_preserves_exit_and_does_not_run_later_checks(self):
        result = self.run_entry(STUB_FAIL='check-format.sh', STUB_RC='23')
        self.assertEqual(result.returncode, 23)
        _, data = self.ledger()
        phases = {p['name']: p for p in data['phases']}
        self.assertEqual(phases['format']['exitCode'], 23)
        self.assertEqual(phases['format']['status'], 'failed')
        self.assertEqual(phases['policy-negative']['status'], 'not-run')
        self.assertNotIn('xcodebuild:test-without-building', [e['event'] for e in self.events()])

    def test_build_failure_stops_before_release_and_device(self):
        result = self.run_entry(STUB_FAIL='xcodebuild:build:Debug', STUB_RC='66')
        self.assertEqual(result.returncode, 66)
        self.assertEqual(self.events()[-1]['event'], 'xcodebuild:build:Debug')

    def test_test_failure_preserves_65_and_still_runs_result_validator(self):
        result = self.run_entry(STUB_FAIL='xcodebuild:test-without-building', STUB_RC='65', STUB_NATIVE_DEFER='')
        self.assertEqual(result.returncode, 65)
        path, data = self.ledger()
        self.assertEqual(data['verificationExitCode'], 65)
        self.assertEqual(data['phases'][-2]['status'], 'failed')
        self.assertEqual(data['phases'][-1]['status'], 'failed')
        self.assertTrue((path.parent / 'tests.log').exists())
        self.assertEqual(self.events()[-1]['event'], 'check-test-results.py')


    def test_exact_deferred_native_failure_continues_and_keeps_raw_code(self):
        result = self.run_entry(STUB_FAIL='xcodebuild:test-without-building', STUB_RC='65', STUB_NATIVE_DEFER='1', STUB_AUDIT_DEFER='1')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        path, ledger = self.ledger()
        phase = next(p for p in ledger['phases'] if p['name']=='test-execute-diagnostics')
        self.assertEqual((phase['status'],phase['exitCode']), ('deferred-unresolved',65))
        verdict = json.loads((path.parent/'verification-verdict.json').read_text())
        self.assertEqual(verdict['status'], 'core-passed-with-deferred')
        self.assertEqual(verdict['nativeExitCode'], 65)
        self.assertIn('核心检查通过，但存在延期问题', result.stdout)
        self.assertNotIn('PASS: local F0 gates', result.stdout)

    def test_deferred_native_cannot_hide_source_identity_failure(self):
        result = self.run_entry(STUB_FAIL='xcodebuild:test-without-building', STUB_RC='65', STUB_NATIVE_DEFER='1', STUB_TAMPER='response')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('TEST-SCOPE:',result.stdout)
        verdict = json.loads((self.ledger()[0].parent/'verification-verdict.json').read_text())
        self.assertEqual(verdict['status'],'failed')

    def test_deferred_native_cannot_hide_other_gate_failure(self):
        result = self.run_entry(STUB_FAIL='check-format.sh', STUB_RC='23', STUB_NATIVE_DEFER='1')
        self.assertEqual(result.returncode,23)
        self.assertNotIn('Core checks passed with deferred issues',result.stdout)

    def test_lifecycle_audit_runs_on_success_and_failed_prefix(self):
        for failure in ['', 'xcodebuild:test-without-building']:
            with self.subTest(failure=failure):
                (self.root / 'events.jsonl').unlink(missing_ok=True)
                result = self.run_entry(STUB_FAIL=failure, STUB_RC='42')
                self.assertEqual(result.returncode, 42 if failure else 0, result.stdout)
                events = [json.loads(line) for line in (self.root / 'events.jsonl').read_text().splitlines()]
                audit = next(e for e in events if e['event'] == 'check-banner-lifecycle.py')
                self.assertEqual(audit['args'][audit['args'].index('--test-exit') + 1], '42' if failure else '0')
                self.assertEqual(events[-1]['event'], 'check-banner-lifecycle.py')

    def test_lifecycle_audit_failure_cannot_report_pass(self):
        result = self.run_entry(STUB_FAIL='check-banner-lifecycle.py', STUB_RC='71')
        self.assertEqual(result.returncode, 71, result.stdout)
        self.assertNotIn('PASS: local F0 gates', result.stdout)

    def test_lifecycle_audit_failure_preserves_original_test_exit(self):
        result = self.run_entry(STUB_FAIL='xcodebuild:test-without-building', STUB_RC='42', STUB_AUDIT_RC='71')
        self.assertEqual(result.returncode, 42, result.stdout)
        self.assertNotIn('PASS: local F0 gates', result.stdout)

    def test_result_validator_failure_is_not_a_pass(self):
        result = self.run_entry(STUB_FAIL='check-test-results.py', STUB_RC='67')
        self.assertEqual(result.returncode, 67)
        self.assertEqual(self.ledger()[1]['phases'][-1]['status'], 'failed')

    def test_recording_error_does_not_mask_original_failure(self):
        result = self.run_entry(STUB_FAIL='xcodebuild:test-without-building', STUB_RC='42', STUB_CORRUPT='1')
        self.assertEqual(result.returncode, 42)
        self.assertIn('verification exit=42', result.stdout)

    def test_recording_error_cannot_produce_green(self):
        result = self.run_entry(STUB_CORRUPT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('PASS: local F0 gates', result.stdout)

    def interrupted(self, signum):
        process = subprocess.Popen(['bash', 'Scripts/verify-local.sh'], cwd=self.root,
                                   env=dict(self.env, STUB_BLOCK='xcodebuild:test-without-building'),
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   start_new_session=True)
        try:
            deadline = time.monotonic() + 10
            while not (self.root / 'ready').exists() and time.monotonic() < deadline:
                if process.poll() is not None:
                    self.fail('entry exited before cancellation checkpoint')
                time.sleep(0.02)
            self.assertTrue((self.root / 'ready').exists())
            os.killpg(process.pid, signum)
            return process.wait(timeout=5)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()

    def test_missing_device_is_rejected_before_external_commands(self):
        self.env.pop('MALL_SIMULATOR_ID')
        result = self.run_entry()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.events(), [])
        self.assertEqual(self.ledger()[1]['phases'][0]['status'], 'failed')

    def test_report_without_ledger_does_not_claim_pass(self):
        result = subprocess.run(['python3', 'Scripts/verification-timing.py', 'report-all',
                                 '.build/verification'], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('not started', result.stdout)

    def test_summary_failure_after_success_fails_closed(self):
        helper = self.root / 'Scripts/verification-timing.py'
        helper.write_text(helper.read_text().replace(
            "elif command == 'report':", "elif command == 'report':\n        raise OSError('fixture summary error')"))
        result = self.run_entry()
        self.assertEqual(result.returncode, 65)
        self.assertNotIn('PASS: local F0 gates', result.stdout)
        _, data = self.ledger()
        self.assertEqual(data['verificationExitCode'], 0)
        self.assertEqual(data['entryExitCode'], 65)
        self.assertTrue(data['recordingFailure'])
        report = subprocess.run(['python3', 'Scripts/verification-timing.py', 'report-all',
                                 '.build/verification'], cwd=self.root, capture_output=True, text=True)
        self.assertIn('Verification entry exit: 65', report.stdout)

    def test_int_records_cancellation_and_pending_stages(self):
        self.assertEqual(self.interrupted(signal.SIGINT), 130)
        _, data = self.ledger()
        self.assertEqual(data['phases'][-2]['status'], 'cancelled')
        self.assertEqual(data['phases'][-2]['exitCode'], 130)
        self.assertEqual(data['phases'][-1]['status'], 'not-run')

    def test_term_records_cancellation_and_pending_stages(self):
        self.assertEqual(self.interrupted(signal.SIGTERM), 143)
        _, data = self.ledger()
        self.assertEqual(data['phases'][-2]['status'], 'cancelled')
        self.assertEqual(data['phases'][-2]['exitCode'], 143)
        self.assertEqual(data['phases'][-1]['status'], 'not-run')

    def test_kill_leaves_durable_incomplete_stage_for_always_summary(self):
        self.assertEqual(self.interrupted(signal.SIGKILL), -signal.SIGKILL)
        _, data = self.ledger()
        self.assertEqual(data['phases'][-2]['status'], 'running')
        result = subprocess.run(['python3', 'Scripts/verification-timing.py', 'report-all',
                                 '.build/verification'], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('| test-execute-diagnostics | incomplete |', result.stdout)
        self.assertIn('| test-result-validation | not-run |', result.stdout)


if __name__ == '__main__':
    unittest.main()
