"""Synthetic parser controls; these do not replace real hosted production tests."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('banner_lifecycle', ROOT / 'Scripts/check-banner-lifecycle.py')
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)
STATUS = {'state': 'stream-stopped-by-owner', 'diagnosticErrors': [], 'pid': 123, 'command': ['test'],
          'collectorOrderedBeforeTest': True, 'clockDomain': 'unavailable'}


class Transcript:
    def __init__(self, kind):
        self.method = next(m for m, k in AUDIT.METHODS.items() if k == kind)
        self.run = 'run-' + kind
        self.t, self.seq, self.revision, self.generation = 100., {'app': 0, 'carousel': 0}, 1, 0
        self.selected, self.selection, self.advance = 910001, 0, 0
        self.events, self.markers = [], []
        self.gate = dict(homeActive=kind != 'push', sceneActive=True, drag=False, visible=True,
                         allowed=True, reduceMotion=False, voiceOver=False, count=3,
                         frame=[0, 0, 100, 100], viewport=[0, 0, 100, 100])
        self.mark('begin')
        self.t += .1
        self.app('initial')
        self.t += .1
        self.car('initial')
        self.task()

    def mark(self, event, **extra):
        if event == 'observation': extra.setdefault('finishedMonotonic', self.t)
        self.markers.append(dict(runID=self.run, method=self.method, event=event, monotonicTime=self.t, **extra))

    def app(self, event):
        self.seq['app'] += 1
        self.events.append(dict(schemaVersion=1, runID=self.run, origin='app', processID=123,
                                instanceID='app', eventSequence=self.seq['app'], monotonicTime=self.t,
                                event=event, homeActive=self.gate['homeActive'], sceneActive=self.gate['sceneActive']))

    def car(self, event, **extra):
        self.seq['carousel'] += 1
        record = dict(schemaVersion=1, runID=self.run, origin='carousel', processID=123,
                      instanceID='carousel', eventSequence=self.seq['carousel'], monotonicTime=self.t,
                      inputRevision=self.revision, generation=self.generation, event=event,
                      selectedID=self.selected, selectionRevision=self.selection, advanceSequence=self.advance,
                      gate=copy.deepcopy(self.gate))
        record.update(extra)
        self.events.append(record)

    def task(self):
        self.task_id = 'task-' + str(self.generation)
        self.car('taskEntry', taskID=self.task_id)
        self.generation += 1
        self.deadline = self.t + 5 if AUDIT.eligible(self.gate) else None
        self.car('arm', taskID=self.task_id, deadline=self.deadline, deadlineUpper=self.deadline)

    def input(self, field, value):
        previous = copy.deepcopy(self.gate)
        self.gate[field] = value
        self.revision += 1
        if field in ['homeActive', 'sceneActive']:
            self.app('routeInput' if field == 'homeActive' else 'sceneInput')
        self.car('rawInput', previousGate=previous)
        self.task()

    def commit(self):
        self.t = max(self.t + .01, self.deadline)
        self.car('advanceAttempt', taskID=self.task_id)
        old = self.selected
        self.selected = 910001 + (old - 910000) % 3
        self.selection += 1
        self.advance += 1
        self.car('advanceCommit', taskID=self.task_id, oldSelectedID=old, cause='autoplay')
        self.task()

    def operation(self, leave, restore, field):
        self.t += .1
        if leave:
            self.mark(leave + '-begin')
            self.t += .1
            self.input(field, False)
            self.t += .1
            self.mark(leave + '-end')
        self.t += 6
        self.mark(restore + '-begin')
        self.t += .1
        self.input(field, True)
        self.t += .1
        self.mark(restore + '-end')
        self.t += .01
        self.observe()
        self.commit()

    def drag(self, expects=True):
        self.t += .1
        self.mark('drag-begin')
        self.t += .1
        self.input('drag', True)
        self.t += .2
        self.input('drag', False)
        self.t += .1
        self.mark('drag-end')
        self.mark('drag-release', expectsAdvance=expects)

    def observe(self):
        self.mark('observation', startedMonotonic=self.t - .01,
                  leafID='home.banner.current.' + str(self.selected),
                  page='第' + str(self.selected - 910000) + '页，共3页')

    def cycle_checkpoint(self, event):
        fields = dict(leafID='home.banner.current.' + str(self.selected),
                      page='第' + str(self.selected - 910000) + '页，共3页')
        self.mark('observation', startedMonotonic=self.t - .01, **fields)
        self.mark(event, selectedID=self.selected, observationStarted=self.t - .01,
                  observationEnded=self.t, **fields)

    def finish(self, kind):
        if kind == 'cycle':
            self.commit()
        for leave, restore, field, _ in AUDIT.OPERATIONS[kind]:
            self.operation(leave, restore, field)
        if kind != 'push':
            self.drag()
        if kind == 'cycle':
            self.cycle_checkpoint('cycle-baseline')
        for _ in range(3 if kind == 'cycle' else 1):
            self.commit()
        self.t += .1
        if kind == 'cycle':
            self.cycle_checkpoint('cycle-wrap')
        else:
            self.observe()
        self.mark('end', outcome='passed')
        return self

    def audit(self, test_exit=0, status=None, native_passed=None):
        return AUDIT.audit([AUDIT.PREFIX + self.method + '()'],
                           '\n'.join('2026-10-21 17:49:16.867 Df CoolMalliOS[86305:24887a] (Foundation) BANNERAUDIT '
                                     + json.dumps(e) for e in self.events),
                           '\n'.join('BANNERTEST ' + json.dumps(m) for m in self.markers),
                           STATUS if status is None else status, test_exit, native_passed=native_passed)


class BannerLifecycleTests(unittest.TestCase):
    def test_four_complete_parser_controls(self):
        for kind in ['cycle', 'away', 'offscreen', 'push']:
            with self.subTest(kind=kind):
                self.assertEqual(Transcript(kind).finish(kind).audit()['status'], 'passed')

    def test_normal_post_end_autoplay_is_diagnostic_only(self):
        for kind in ['push', 'offscreen']:
            fixture = Transcript(kind).finish(kind)
            fixture.commit()
            result = fixture.audit(native_passed={fixture.method})
            method = result['methods'][fixture.method]
            self.assertEqual(method['status'], 'passed')
            self.assertGreater(method['outsideWindowEventCount'], 0)
            self.assertTrue(all(e['monotonicTime'] > method['observationWindow']['end']
                                for e in method['outsideWindowEvents']))

    def test_window_exclusion_does_not_excuse_unknown_or_malformed_records(self):
        for field, value in [('event', 'unknownProductionEvent'), ('schemaVersion', 99),
                             ('monotonicTime', float('nan')), ('processID', 'invalid')]:
            fixture = Transcript('push').finish('push')
            fixture.commit()
            fixture.events[-1][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                fixture.audit(native_passed={fixture.method})

    def test_pre_begin_initial_cannot_supply_missing_window_initial(self):
        fixture = Transcript('push').finish('push')
        fixture.markers[0]['monotonicTime'] = fixture.events[1]['monotonicTime'] + .001
        with self.assertRaisesRegex(ValueError, 'initial snapshot missing'):
            fixture.audit(native_passed={fixture.method})

    def test_no_end_failed_prefix_still_checks_events_after_last_marker(self):
        fixture = Transcript('push').finish('push')
        fixture.markers.pop()
        fixture.commit()
        next(e for e in reversed(fixture.events) if e['event'] == 'advanceCommit')['generation'] += 1
        with self.assertRaisesRegex(ValueError, 'current arm'):
            fixture.audit(test_exit=65, native_passed=set())

    def test_post_end_commit_cannot_supply_missing_in_window_commit(self):
        fixture = Transcript('push').finish('push')
        first = next(e for e in fixture.events if e['event'] == 'advanceCommit')
        boundary = first['monotonicTime'] - .001
        fixture.markers = [m for m in fixture.markers if m['monotonicTime'] <= boundary]
        fixture.t = boundary
        fixture.mark('end', outcome='passed')
        with self.assertRaisesRegex(ValueError, 'no subsequent|no actual'):
            fixture.audit(native_passed={fixture.method})

    def test_failed_native_result_ignores_advisory_passed_end(self):
        fixture = Transcript('push')
        fixture.mark('end', outcome='passed')
        result = fixture.audit(test_exit=65, native_passed=set())
        self.assertEqual(result['methods'][fixture.method]['status'], 'recorded-prefix')
        self.assertIn('pop', result['methods'][fixture.method]['notReached'])

    def test_native_passing_method_still_requires_full_checks_when_other_test_failed(self):
        fixture = Transcript('push')
        fixture.mark('end', outcome='passed')
        with self.assertRaisesRegex(ValueError, 'missing pop'):
            fixture.audit(test_exit=65, native_passed={fixture.method})

    def test_native_pass_not_overridden_by_advisory_failed_marker(self):
        fixture = Transcript('push').finish('push')
        fixture.markers[-1]['outcome'] = 'failed'
        self.assertEqual(fixture.audit(native_passed={fixture.method})['status'], 'passed')

    def test_end_window_cannot_hide_in_window_wrong_generation(self):
        fixture = Transcript('offscreen').finish('offscreen')
        next(e for e in fixture.events if e['event'] == 'advanceCommit')['generation'] += 1
        fixture.commit()
        with self.assertRaisesRegex(ValueError, 'current arm'):
            fixture.audit(native_passed={fixture.method})

    def test_none_selected_is_explicitly_not_required(self):
        result = AUDIT.audit(['CatalogFeatureTests/Other/test()'], '', '', {})
        self.assertEqual(result['status'], 'not-required')

    def test_multiple_marked_drags_and_poll_observations_bind_by_run(self):
        fixture = Transcript('away').finish('away')
        fixture.markers.pop()
        fixture.drag()
        fixture.commit()
        fixture.t += .1
        fixture.observe()
        fixture.observe()
        fixture.observe()
        fixture.mark('end', outcome='passed')
        for marker in fixture.markers:
            if marker['event'] != 'begin': del marker['method']
        result = fixture.audit()
        self.assertEqual(sum(c['operation'] == 'drag-release' for c in result['methods'][fixture.method]['checks']), 2)

    def test_expected_post_drag_advance_requires_commit_and_visible_tail(self):
        for fault in ['missing-commit', 'wrong-page', 'preparatory-drag']:
            with self.subTest(fault=fault):
                fixture = Transcript('offscreen').finish('offscreen')
                release = next(m for m in fixture.markers if m['event'] == 'drag-release')
                if fault in ['missing-commit', 'preparatory-drag']:
                    fixture.events = [e for e in fixture.events if e['monotonicTime'] <= release['monotonicTime']]
                    fixture.markers = [m for m in fixture.markers if m['monotonicTime'] <= release['monotonicTime']]
                    fixture.mark('end', outcome='passed')
                    if fault == 'preparatory-drag': release['expectsAdvance'] = False
                else:
                    next(m for m in reversed(fixture.markers) if m['event'] == 'observation')['page'] = '第99页，共3页'
                if fault == 'preparatory-drag':
                    self.assertEqual(fixture.audit()['status'], 'passed')
                else:
                    with self.assertRaisesRegex(ValueError, 'post-drag'): fixture.audit()

    def test_hidden_full_wrap_cannot_pass_equal_final_id(self):
        fixture = Transcript('away')
        fixture.mark('tab-leave-begin')
        fixture.t += .1
        fixture.input('homeActive', False)
        fixture.mark('tab-leave-end')
        # Parser-only fault transcript. Actual production N03 is a separate
        # source-copy hosted mutant, never claimed by this fixture.
        original = fixture.selected
        for _ in range(3):
            fixture.t += 5
            old = fixture.selected
            fixture.selected = 910001 + (old - 910000) % 3
            fixture.selection += 1
            fixture.advance += 1
            fixture.car('advanceCommit', oldSelectedID=old, cause='autoplay')
        self.assertEqual(original, fixture.selected)
        fixture.mark('tab-return-begin')
        fixture.input('homeActive', True)
        fixture.mark('tab-return-end')
        hidden = [e for e in fixture.events if e['origin'] == 'carousel']
        with self.assertRaisesRegex(ValueError, 'hidden selected ID/counter changed'):
            AUDIT.check_hidden_ledger(hidden, hidden[3]['monotonicTime'], fixture.t)
        with self.assertRaisesRegex(ValueError, 'advance missing current arm|hidden'):
            fixture.audit(test_exit=65)

    def test_dropped_duplicate_and_counter_gap_fail_closed(self):
        for fault in ['drop', 'duplicate', 'counter', 'instance', 'process', 'clock']:
            with self.subTest(fault=fault):
                fixture = Transcript('cycle').finish('cycle')
                event = next(e for e in fixture.events if e['event'] == 'advanceCommit')
                if fault == 'drop': fixture.events.remove(event)
                if fault == 'duplicate': fixture.events.insert(fixture.events.index(event), copy.deepcopy(event))
                if fault == 'counter': event['advanceSequence'] += 3
                if fault == 'instance': event['instanceID'] = 'replacement'
                if fault == 'process': event['processID'] += 1
                if fault == 'clock': event['monotonicTime'] = 0
                with self.assertRaises(ValueError): fixture.audit()

    def test_missing_resume_checkpoint_and_app_edge_fail(self):
        for fault in ['receipt', 'app']:
            with self.subTest(fault=fault):
                fixture = Transcript('away').finish('away')
                target = next(e for e in fixture.events if e['event'] == ('taskEntry' if fault == 'receipt' else 'routeInput')
                              and e.get('gate', e).get('homeActive') is True)
                target['event'] = 'wake' if fault == 'receipt' else 'sceneInput'
                with self.assertRaises(ValueError): fixture.audit()

    def test_shortened_resume_deadline_fails(self):
        fixture = Transcript('push').finish('push')
        arm = next(e for e in fixture.events if e['event'] == 'arm' and e.get('deadline'))
        arm['deadline'] -= 4.9
        with self.assertRaisesRegex(ValueError, 'fresh full five-second'): fixture.audit()

    def test_push_allows_only_first_nil_to_fixture_initialization(self):
        for fault in ['', 'second', 'wrong-first', 'advance']:
            with self.subTest(fault=fault):
                fixture = Transcript('push')
                fixture.t += .01
                fixture.selection = 1
                fixture.car('selectionCommit', oldSelectedID=None, cause='reconcile')
                if fault == 'second':
                    fixture.t += .01
                    fixture.selection += 1
                    fixture.car('selectionCommit', oldSelectedID=None, cause='reconcile')
                elif fault == 'wrong-first':
                    fixture.events[-1]['selectedID'] = 910002
                    fixture.selected = 910002
                elif fault == 'advance':
                    fixture.t += .01
                    fixture.advance += 1
                    fixture.car('advanceCommit', oldSelectedID=910001, cause='autoplay')
                fixture.finish('push')
                if fault:
                    with self.assertRaises(ValueError): fixture.audit()
                else:
                    self.assertEqual(fixture.audit()['status'], 'passed')

    def test_identical_raw_observation_may_repeat_revision_but_edges_may_not(self):
        for fault in ['', 'new-gate', 'not-duplicate-observation', 'regression']:
            with self.subTest(fault=fault):
                fixture = Transcript('away').finish('away')
                event = next(e for e in fixture.events if e['event'] == 'rawInput')
                duplicate = copy.deepcopy(event)
                duplicate['previousGate'] = copy.deepcopy(duplicate['gate'])
                if fault == 'new-gate': duplicate['gate']['visible'] = not duplicate['gate']['visible']
                if fault == 'not-duplicate-observation': duplicate['previousGate']['drag'] = True
                if fault == 'regression': duplicate['inputRevision'] -= 1
                fixture.events.insert(fixture.events.index(event) + 1, duplicate)
                sequence = {'app': 0, 'carousel': 0}
                for e in fixture.events:
                    sequence[e['origin']] += 1; e['eventSequence'] = sequence[e['origin']]
                if fault:
                    with self.assertRaisesRegex(ValueError, 'raw input revision'): fixture.audit()
                else:
                    self.assertEqual(fixture.audit()['status'], 'passed')

    def test_unmounted_seeded_push_requires_controlled_first_instance(self):
        for fault in ['', 'collector', 'later-selected', 'old-instance', 'already-active']:
            with self.subTest(fault=fault):
                fixture = Transcript('push')
                fixture.events = [e for e in fixture.events if e['origin'] == 'app']
                fixture.seq['carousel'] = fixture.generation = 0
                fixture.t += .1; fixture.mark('pop-begin')
                fixture.t += .1; fixture.gate['homeActive'] = True; fixture.app('routeInput')
                fixture.t += .1; fixture.selection = 1
                fixture.car('selectionCommit', oldSelectedID=None, cause='reconcile')
                fixture.car('initial'); fixture.task()
                fixture.t += .1; fixture.mark('pop-end')
                fixture.t += .1; fixture.observe(); fixture.commit()
                fixture.t += .1; fixture.observe(); fixture.mark('end', outcome='passed')
                status = copy.deepcopy(STATUS)
                if fault == 'collector': status.pop('collectorOrderedBeforeTest')
                if fault == 'later-selected': fixture.events[2]['selectedID'] = 910003
                if fault == 'old-instance': fixture.events[2]['instanceID'] = 'old-instance'
                if fault == 'already-active': fixture.events[0]['homeActive'] = True
                if fault:
                    with self.assertRaises(ValueError): fixture.audit(status=status)
                else:
                    result = fixture.audit(status=status)
                    self.assertEqual(result['methods'][fixture.method]['checks'][0]['branch'], 'initially-unmounted')

    def test_restore_delivery_uses_only_first_existing_consistent_snapshot_within_budget(self):
        for fault in ['', 'after-first', 'inconsistent-first', 'late-first', 'pick-later']:
            with self.subTest(fault=fault):
                fixture = Transcript('away').finish('away')
                native_end = next(m for m in fixture.markers if m['event'] == 'activate-end')
                first = next(m for m in fixture.markers if m['event'] == 'observation'
                             and m['monotonicTime'] > native_end['monotonicTime'])
                # Real callback occurs after native return, inside the existing
                # first snapshot. Do not add any new query or waiting window.
                native_end['monotonicTime'] -= .15
                callback = next(e for e in fixture.events if e['event'] == 'sceneInput' and e['sceneActive'])
                if fault == 'after-first':
                    first['startedMonotonic'] = callback['monotonicTime'] - .01
                    first['finishedMonotonic'] = callback['monotonicTime'] - .001
                if fault in {'inconsistent-first', 'pick-later'}: first['page'] = '第99页，共3页'
                if fault == 'late-first':
                    for marker in fixture.markers[fixture.markers.index(first):]:
                        for key in ['monotonicTime', 'startedMonotonic', 'finishedMonotonic']:
                            if key in marker: marker[key] += 10
                if fault:
                    expected = ('actual input edge' if fault == 'after-first' else
                                'nine-second budget' if fault == 'late-first' else 'leaf/dots inconsistent')
                    with self.assertRaisesRegex(ValueError, expected): fixture.audit()
                else:
                    self.assertEqual(fixture.audit()['status'], 'passed')

    def test_host_prefix_ignored_but_unknown_actual_ui_run_rejected(self):
        fixture = Transcript('push').finish('push')
        expected = [AUDIT.PREFIX + fixture.method]
        trace = '\n'.join('BANNERAUDIT ' + json.dumps(e) for e in fixture.events)
        tests = '\n'.join('BANNERTEST ' + json.dumps(m) for m in fixture.markers)
        self.assertEqual(AUDIT.audit(expected, trace + '\nBANNERHOST {not-ui}\n',
                                     tests + '\nBANNERHOST {not-ui}\n', STATUS)['status'], 'passed')
        unknown = copy.deepcopy(fixture.events[0]); unknown['runID'] = 'unknown-real-ui-run'
        with self.assertRaisesRegex(ValueError, 'source runID'):
            AUDIT.audit(expected, trace + '\nBANNERAUDIT ' + json.dumps(unknown), tests, STATUS)

    def test_source_or_collector_error_is_not_no_advance(self):
        fixture = Transcript('push').finish('push')
        with self.assertRaisesRegex(ValueError, 'collector'):
            fixture.audit(status={'state': 'diagnostic-missing', 'diagnosticErrors': ['dropped']})
        with self.assertRaisesRegex(ValueError, 'malformed'):
            AUDIT.audit([AUDIT.PREFIX + fixture.method], 'BANNERAUDIT {bad',
                        'BANNERTEST ' + json.dumps(fixture.markers[0]), STATUS)

    def test_compact_header_is_ignored_but_real_malformed_or_error_payload_fails(self):
        header = ('Filtering the log data using "composedMessage BEGINSWITH "BANNERAUDIT " '
                  'OR composedMessage BEGINSWITH "BANNERAUDIT_ERROR""\n')
        self.assertEqual(AUDIT.records(header, 'BANNERAUDIT '), [])
        prefix = '2026-10-21 17:49:16.867 Df CoolMalliOS[86305:24887a] (Foundation) '
        with self.assertRaisesRegex(ValueError, 'malformed'):
            AUDIT.records(header + prefix + 'BANNERAUDIT {broken\n', 'BANNERAUDIT ')
        fixture = Transcript('push').finish('push')
        source = '\n'.join(prefix + 'BANNERAUDIT ' + json.dumps(e) for e in fixture.events)
        tests = '\n'.join('BANNERTEST ' + json.dumps(m) for m in fixture.markers)
        self.assertEqual(AUDIT.audit([AUDIT.PREFIX + fixture.method], header + source, tests, STATUS)['status'], 'passed')
        with self.assertRaisesRegex(ValueError, 'source event encoding'):
            AUDIT.audit([AUDIT.PREFIX + fixture.method], header + source + '\n' + prefix + 'BANNERAUDIT_ERROR broken', tests, STATUS)

    def test_failed_ui_audits_prefix_and_records_unreached_chains(self):
        fixture = Transcript('away')
        fixture.t += .1
        fixture.mark('tab-leave-begin')
        fixture.t += .1
        fixture.input('homeActive', False)
        fixture.mark('tab-leave-end')
        fixture.mark('end', outcome='failed')
        result = fixture.audit(test_exit=65)
        self.assertEqual(result['status'], 'recorded-prefix')
        method = result['methods'][fixture.method]
        self.assertEqual(method['notReached'], ['tab-return', 'activate', 'drag-release'])
        self.assertEqual(method['checks'][0]['status'], 'recorded-prefix')

    def test_success_cannot_omit_method_end(self):
        fixture = Transcript('push').finish('push')
        fixture.markers.pop()
        with self.assertRaisesRegex(ValueError, 'passing end'): fixture.audit()

    def test_drag_actual_gate_window_rejects_changed_selection(self):
        fixture = Transcript('cycle').finish('cycle')
        start = next(e for e in fixture.events if e['event'] == 'rawInput' and e['gate']['drag'])
        # An event-only fault is enough to ensure parser cannot infer safety
        # from the unchanged final AX marker.
        start['advanceSequence'] += 3
        with self.assertRaisesRegex(ValueError, 'counter|unrecorded'): fixture.audit()

    def test_cycle_needs_exact_adjacent_commits_and_unambiguous_ax(self):
        for fault in ['ax', 'order', 'extra']:
            with self.subTest(fault=fault):
                fixture = Transcript('cycle').finish('cycle')
                if fault == 'ax':
                    next(m for m in fixture.markers if m['event'] == 'cycle-baseline')['selectedID'] = 910003
                elif fault == 'order':
                    # Preserve the ledger and all counters but permute the
                    # fixture IDs consistently, so only adjacency detects it.
                    swap = {910001: 910001, 910002: 910003, 910003: 910002}
                    for e in fixture.events:
                        for key in ['selectedID', 'oldSelectedID']:
                            if key in e: e[key] = swap[e[key]]
                    for m in fixture.markers:
                        if 'selectedID' in m: m['selectedID'] = swap[m['selectedID']]
                else:
                    fixture.markers = fixture.markers[:-3]
                    for _ in range(3): fixture.commit()
                    fixture.t += .1
                    fixture.cycle_checkpoint('cycle-wrap')
                    fixture.mark('end', outcome='passed')
                with self.assertRaises(ValueError): fixture.audit()

    def test_cycle_snapshot_commit_overlap_is_ambiguous_even_if_final_id_matches(self):
        for checkpoint in ['cycle-baseline', 'cycle-wrap']:
            with self.subTest(checkpoint=checkpoint):
                fixture = Transcript('cycle').finish('cycle')
                mark = next(m for m in fixture.markers if m['event'] == checkpoint)
                observation = next(m for m in fixture.markers if m['event'] == 'observation'
                                   and m['startedMonotonic'] == mark['observationStarted'])
                commit = next(e for e in fixture.events if e['event'] == 'advanceCommit')
                mark['observationStarted'] = commit['monotonicTime'] - .01
                observation['startedMonotonic'] = mark['observationStarted']
                with self.assertRaisesRegex(ValueError, 'observation spans selection/advance'):
                    fixture.audit()

    def test_cli_writes_independent_failure_without_rewriting_raw_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = Transcript('push')
            scope = root / 'scope.json'; scope.write_text(json.dumps({'expected': [AUDIT.PREFIX + fixture.method]}))
            trace = root / 'trace.log'; trace.write_text('unavailable raw stream\n')
            tests = root / 'tests.log'; tests.write_text('original assertion failure\n')
            status = root / 'status.json'; status.write_text(json.dumps(STATUS))
            output = root / 'audit.json'
            result = subprocess.run([sys.executable, str(ROOT / 'Scripts/check-banner-lifecycle.py'),
                                     '--scope', str(scope), '--trace', str(trace), '--tests-log', str(tests),
                                     '--collector-status', str(status), '--output', str(output), '--test-exit', '42'],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(output.read_text())['status'], 'failed')
            self.assertEqual(tests.read_text(), 'original assertion failure\n')


if __name__ == '__main__':
    unittest.main()
