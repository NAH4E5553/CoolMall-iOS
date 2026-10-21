#!/usr/bin/env python3
"""Audit the four selected carousel UI methods from their complete event ledger.

This validates lifecycle evidence, not visible UI assertions or latency. Synthetic
fixtures test this parser only; they are not hosted production-path evidence.
"""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import sys

_LOG_SPEC = importlib.util.spec_from_file_location('banner_trace_payload', Path(__file__).with_name('with-banner-trace.py'))
_LOG = importlib.util.module_from_spec(_LOG_SPEC)
_LOG_SPEC.loader.exec_module(_LOG)

PREFIX = 'CoolMalliOSUITests/HomeLoadTests/'
METHODS = {
    'testBannerAutoplayCyclesAndRestartsAfterUnchangedDrag': 'cycle',
    'testBannerAutoplayPausesWhileAwayAndResumesFullInterval': 'away',
    'testBannerAutoplayPausesWhileBannerIsOffscreen': 'offscreen',
    'testBannerAutoplayArmsAfterPushedRoutePopsBack': 'push',
}
OPERATIONS = {
    'cycle': [],
    'away': [('tab-leave', 'tab-return', 'homeActive', 5),
             ('background', 'activate', 'sceneActive', 5)],
    'offscreen': [('offscreen', 'reveal', 'visible', 5)],
    'push': [(None, 'pop', 'homeActive', 0)],
}
EVENTS = {'initial', 'rawInput', 'taskEntry', 'arm', 'wake', 'cancel', 'reject',
          'advanceAttempt', 'advanceCommit', 'selectionCommit'}
class EvidenceGap(ValueError):
    """Only a missing positive, ordered event sequence; other faults stay blocking."""


FLAGS = {'homeActive', 'sceneActive', 'drag', 'visible', 'allowed', 'reduceMotion', 'voiceOver'}


def require(condition, message):
    if not condition:
        raise ValueError('BANNER-AUDIT: ' + message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def method_name(value):
    require(isinstance(value, str), 'invalid method identifier')
    return value.removeprefix(PREFIX).removesuffix('()')


def records(text, prefix):
    result = []
    for line in _LOG.payloads(text):
        if not line.startswith(prefix):
            continue
        raw = line[len(prefix):]
        try:
            record = json.loads(raw)
        except (ValueError, TypeError) as error:
            raise ValueError('BANNER-AUDIT: malformed ' + prefix.strip() + ' record') from error
        require(isinstance(record, dict), 'record must be an object')
        result.append(record)
    return result


def validate_stream(events):
    require(events, 'missing source events')
    groups = {}
    for event in events:
        require(event.get('schemaVersion') == 1, 'unsupported schema')
        require(event.get('origin') in {'app', 'carousel'}, 'unknown origin')
        require(isinstance(event.get('runID'), str) and event['runID'], 'missing runID')
        require(type(event.get('processID')) is int and event['processID'] > 0, 'invalid processID')
        require(isinstance(event.get('instanceID'), str) and event['instanceID'], 'invalid instanceID')
        require(type(event.get('eventSequence')) is int, 'invalid eventSequence')
        require(number(event.get('monotonicTime')), 'invalid monotonicTime')
        key = (event['origin'], event['instanceID'])
        groups.setdefault(key, []).append(event)
    require(len({e['processID'] for e in events}) == 1, 'process replaced during method')
    for origin in ['app', 'carousel']:
        require(len({key[1] for key in groups if key[0] == origin}) == 1,
                origin + ' missing or instance replaced/reset')
    # Validate every group's schema and deterministic faults before allowing a
    # missing sequence anywhere to classify this method as incomplete evidence.
    # Otherwise an App gap could hide a malformed/invalid carousel record.
    gaps = []
    complete_carousels = []
    for (origin, _), group in groups.items():
        if origin == 'carousel':
            for e in group: validate_event_shape(e)
        else:
            for e in group:
                require(e.get('event') in {'initial', 'routeInput', 'sceneInput'}, 'unknown app event')
                require(all(type(e.get(k)) is bool for k in ['homeActive', 'sceneActive']), 'app activity missing')
        require(all(a['monotonicTime'] <= b['monotonicTime'] for a, b in zip(group, group[1:])),
                origin + ' time regressed')
        require(any(e['event'] == 'initial' for e in group), origin + ' initial snapshot missing')
        sequences = [e['eventSequence'] for e in group]
        contiguous = sequences == list(range(1, len(group) + 1))
        if not contiguous:
            require(all(v > 0 for v in sequences) and all(a < b for a, b in zip(sequences, sequences[1:])),
                    origin + ' sequence duplicate/reordering')
            gaps.append(origin)
        elif origin == 'carousel':
            complete_carousels.append(group)
    # A complete group's observed business violation stays blocking even when
    # a different group's evidence has a gap.
    for group in complete_carousels: validate_carousel(group)
    if gaps:
        raise EvidenceGap('BANNER-AUDIT: ' + ','.join(gaps) + ' sequence gap')
    return sorted(events, key=lambda e: (e['monotonicTime'], e['origin'], e['eventSequence']))


def eligible(gate):
    return (gate['homeActive'] and gate['sceneActive'] and gate['visible']
            and gate['allowed'] and not gate['drag'] and not gate['reduceMotion']
            and not gate['voiceOver'] and gate['count'] > 1)


def validate_event_shape(e):
    require(e.get('event') in EVENTS, 'unknown carousel event')
    for key in ['inputRevision', 'generation', 'selectionRevision', 'advanceSequence']:
        require(type(e.get(key)) is int and e[key] >= 0, 'invalid ' + key)
    gate = e.get('gate')
    require(isinstance(gate, dict) and all(type(gate.get(k)) is bool for k in FLAGS), 'incomplete gate')
    require(type(gate.get('count')) is int and gate['count'] >= 0, 'invalid gate count')
    for key in ['frame', 'viewport']:
        require(isinstance(gate.get(key), list) and len(gate[key]) == 4
            and all(number(v) for v in gate[key]), 'invalid gate ' + key)
    require(e.get('selectedID') is None or type(e['selectedID']) is int, 'invalid selectedID')

def validate_carousel(group):
    previous = None
    receipts = {}
    arms = {}
    latest_input = -1
    latest_raw = None
    current_arm = None
    committed_tasks = set()
    for e in group:
        validate_event_shape(e)
        gate = e['gate']
        if previous is None:
            require(e['advanceSequence'] == 0 and e['selectionRevision'] <= 1,
                    'initial snapshot has unrecorded commits')
        if previous is not None:
            ds = e['selectionRevision'] - previous['selectionRevision']
            da = e['advanceSequence'] - previous['advanceSequence']
            require(ds >= 0 and da >= 0, 'counter reset/regression')
            if e['event'] in {'advanceCommit', 'selectionCommit'}:
                initial_reconcile = (e['event'] == 'selectionCommit' and e.get('cause') == 'reconcile'
                                     and e.get('oldSelectedID') is None and previous['selectionRevision'] == 0
                                     and previous['advanceSequence'] == 0)
                require(initial_reconcile or e.get('oldSelectedID') == previous.get('selectedID'),
                        'commit old ID mismatches ledger')
                require((initial_reconcile or e.get('selectedID') != previous.get('selectedID')) and ds == 1,
                        'selection commit/counter mismatch')
                require(da == (1 if e['event'] == 'advanceCommit' else 0), 'advance commit/counter mismatch')
            else:
                require(ds == da == 0 and e.get('selectedID') == previous.get('selectedID'),
                        'unrecorded selection/advance or counter gap')
        if e['event'] == 'rawInput':
            repeated_observation = (e['inputRevision'] == latest_input and gate == latest_raw
                                    and e.get('previousGate') == gate)
            require(e['inputRevision'] > latest_input or repeated_observation,
                    'raw input revision regressed or changed gate without new revision')
            latest_input = e['inputRevision']
            latest_raw = gate
        if e['event'] == 'taskEntry':
            require(isinstance(e.get('taskID'), str) and e['taskID'], 'task receipt missing taskID')
            require(e['taskID'] not in receipts, 'duplicate task receipt')
            receipts[e['taskID']] = e
        if e['event'] == 'arm':
            receipt = receipts.get(e.get('taskID'))
            require(receipt is not None and receipt['inputRevision'] == e['inputRevision']
                    and receipt['gate'] == gate, 'arm missing same-input task receipt')
            if eligible(gate):
                # These stable system-uptime bounds surround the real restart.
                # Exact no-early business timing is proved by hosted virtual
                # clock tests, not a live cross-clock projection/tolerance.
                require(number(e.get('deadline')) and number(e.get('deadlineUpper'))
                        and receipt['monotonicTime'] + 5 <= e['deadline'] <= e['deadlineUpper']
                        and e['deadlineUpper'] <= e['monotonicTime'] + 5,
                        'arm does not start a fresh full five-second period')
            else:
                require(e.get('deadline') is None, 'ineligible timer arm')
            require(e['taskID'] not in arms, 'duplicate timer arm')
            require(e['generation'] > receipt['generation'], 'arm did not restart generation')
            arms[e['taskID']] = e
            current_arm = e
        if e['event'] in {'advanceAttempt', 'advanceCommit'}:
            arm = arms.get(e.get('taskID'))
            require(arm is not None and arm['generation'] == e['generation'], 'advance missing current arm')
            require(current_arm is arm and eligible(gate), 'stale/ineligible advance')
            require(e.get('taskID') not in committed_tasks, 'duplicate commit/wake for consumed timer')
            require(e['monotonicTime'] >= arm['deadline'], 'advance before deadline measurement lower bound')
            if e['event'] == 'advanceCommit':
                require(e.get('cause') == 'autoplay', 'autoplay commit cause missing')
                committed_tasks.add(e['taskID'])
        previous = e


def checkpoint(events, at):
    ledger = [e for e in events if e['origin'] == 'carousel' and e['monotonicTime'] <= at]
    if not ledger:
        # The App's launch snapshot precedes the view's creation. A complete
        # sequence beginning at one can reconstruct its initial selection;
        # no automatic commit may have preceded that first snapshot.
        first = next(e for e in events if e['origin'] == 'carousel')
        require(first['advanceSequence'] == 0 and first['selectionRevision'] <= 1,
                'no initial carousel checkpoint before lifecycle edge')
        ledger = [first]
    return tuple(ledger[-1].get(k) for k in ['selectedID', 'selectionRevision', 'advanceSequence'])


def check_hidden_ledger(carousel, paused, resumed):
    """The same bounded check can inspect a real host-only mutant transcript.

    Calling this helper alone proves only that transcript's hidden ledger;
    the UI entry additionally requires App edges and real operation markers.
    """
    require(carousel and [e['eventSequence'] for e in carousel] == list(range(1, len(carousel) + 1)),
            'hidden ledger sequence incomplete')
    require(paused <= resumed <= carousel[-1]['monotonicTime'], 'hidden ledger interval incomplete')
    baseline = checkpoint(carousel, paused)
    require(checkpoint(carousel, resumed) == baseline, 'hidden selected ID/counter changed (including full wrap)')
    require(all(e['event'] not in {'advanceAttempt', 'advanceCommit', 'selectionCommit'}
                for e in carousel if paused <= e['monotonicTime'] < resumed), 'hidden advance/selection event')
    return baseline


def push_initial_checkpoint(carousel, resumed):
    """Permit only the seeded first selection's nil-to-first initialization."""
    hidden = [e for e in carousel if e['monotonicTime'] < resumed]
    require(hidden, 'push initial carousel snapshot missing')
    require(all(e.get('selectedID') == 910001 and e['advanceSequence'] == 0 for e in hidden),
            'push initial selection/advance changed')
    require(not any(e['event'] in {'advanceAttempt', 'advanceCommit'} for e in hidden),
            'push initial hidden advance')
    initializers = [e for e in hidden if e['event'] == 'selectionCommit']
    require(len(initializers) <= 1, 'push repeated initialization selection')
    if initializers:
        initial = initializers[0]
        require(initial.get('oldSelectedID') is None and initial.get('cause') == 'reconcile'
                and initial['selectionRevision'] == 1, 'push invalid initial reconciliation')
        require(all(e['selectionRevision'] == (0 if e['eventSequence'] < initial['eventSequence'] else 1)
                    for e in hidden), 'push initial selection revision gap')
        require(not any(e['event'] == 'arm' and number(e.get('deadline')) for e in hidden),
                'push initialized after an eligible timer arm')
    else:
        require(all(e['selectionRevision'] == 0 for e in hidden), 'push missing initial selection commit')
    return checkpoint(carousel, resumed)


def audit_method(events, marks, kind, complete, collector=None):
    require(marks and marks[0]['event'] == 'begin', 'method begin missing')
    require(sum(m['event'] == 'begin' for m in marks) == 1, 'duplicate method begin')
    require(all(a['monotonicTime'] <= b['monotonicTime'] for a, b in zip(marks, marks[1:])), 'marker time regressed')
    index, drags, dragging = {}, [], None
    for mark in marks:
        event = mark['event']
        if event == 'observation':
            require(number(mark.get('startedMonotonic')) and number(mark.get('finishedMonotonic'))
                    and mark['startedMonotonic'] <= mark['finishedMonotonic'] <= mark['monotonicTime'],
                    'observation marker time missing/regressed')
            continue
        if event == 'drag-begin':
            require(dragging is None, 'overlapping marked drag')
            dragging = mark
            continue
        if event == 'drag-release':
            require(dragging is not None, 'drag release without begin')
            require(type(mark.get('expectsAdvance')) is bool, 'drag release advance intent missing')
            drags.append((dragging['monotonicTime'], mark['monotonicTime'], mark))
            dragging = None
            index[event] = mark
            continue
        if event == 'drag-end':
            continue  # release itself is the native API return anchor
        require(event not in index, 'duplicate operation marker: ' + event)
        index[event] = mark
    require(dragging is None or not complete, 'marked drag never released')
    require(all(e['monotonicTime'] >= marks[0]['monotonicTime'] for e in events), 'source event before method begin')
    events = validate_stream(events)
    car = [e for e in events if e['origin'] == 'carousel']
    app = [e for e in events if e['origin'] == 'app']
    checks, not_reached = [], []

    def window(operation):
        first, last = index.get(operation + '-begin'), index.get(operation + '-end')
        if not first or not last:
            return None
        require(first['monotonicTime'] <= last['monotonicTime'], operation + ' marker order')
        return first['monotonicTime'], last['monotonicTime']

    def edge(source, field, value, bounds, raw=False, initial=False):
        require(bounds is not None, 'missing operation window')
        candidates = []
        for position, e in enumerate(source):
            if not bounds[0] <= e['monotonicTime'] <= bounds[1]:
                continue
            if initial and e['event'] == 'initial':
                changed = True
            elif raw:
                changed = e['event'] == 'rawInput' and e.get('previousGate', {}).get(field) == (not value)
            else:
                changed = (e['event'] == ('routeInput' if field == 'homeActive' else 'sceneInput')
                           and position > 0 and source[position - 1][field] == (not value))
            if changed and (e['gate'][field] if raw else e[field]) == value:
                candidates.append(e)
        require(candidates, 'missing ' + field + '=' + str(value) + ' actual input edge')
        return candidates[0]

    def receipt_after(raw, before):
        candidates = [e for e in car if e['event'] == 'taskEntry'
                      and e['inputRevision'] == raw['inputRevision'] and e['gate'] == raw['gate']
                      and raw['monotonicTime'] <= e['monotonicTime'] <= before]
        # SwiftUI may deliver .task before onChange; pair by same actual snapshot.
        if not candidates:
            candidates = [e for e in car if e['event'] == 'taskEntry'
                          and e['inputRevision'] == raw['inputRevision'] and e['gate'] == raw['gate']
                          and e['monotonicTime'] <= before]
        require(candidates, 'missing matching task-entry checkpoint')
        return candidates[-1]

    def restored_window(operation, bounds):
        if operation not in {'tab-return', 'activate'} or bounds is None:
            return bounds
        snapshots = [m for m in marks if m['event'] == 'observation' and m['monotonicTime'] >= bounds[1]]
        require(snapshots, operation + ' first restore snapshot missing')
        first = snapshots[0]
        require(bounds[1] <= first['startedMonotonic'] <= first['finishedMonotonic'] <= bounds[1] + 9,
                operation + ' first restore snapshot exceeds original nine-second budget')
        leaf = first.get('leafID', '')
        require(leaf in {'home.banner.current.' + str(i) for i in [910001, 910002, 910003]},
                operation + ' first restore snapshot leaf invalid')
        selected = int(leaf.rsplit('.', 1)[1])
        require(first.get('page') == '第' + str(selected - 910000) + '页，共3页',
                operation + ' first restore snapshot leaf/dots inconsistent')
        return bounds[0], first['finishedMonotonic']

    for leave, restore, field, minimum in OPERATIONS[kind]:
        native_returned = window(restore)
        returned = restored_window(restore, native_returned)
        if returned is None:
            require(not complete, 'missing ' + restore + ' operation')
            departure = window(leave) if leave else (marks[0]['monotonicTime'], car[-1]['monotonicTime'])
            if departure:
                pause_car = edge(car, field, False, departure, raw=True, initial=leave is None)
                pause_edges = [pause_car]
                if field != 'visible':
                    pause_edges.append(edge(app, field, False, departure, initial=leave is None))
                paused = min(e['monotonicTime'] for e in pause_edges)
                if leave is None:
                    push_initial_checkpoint(car, math.nextafter(car[-1]['monotonicTime'], math.inf))
                else:
                    require(all(e['event'] not in {'advanceAttempt', 'advanceCommit', 'selectionCommit'}
                                for e in car if e['monotonicTime'] >= paused), 'hidden advance/selection in recorded prefix')
                    require(checkpoint(events, car[-1]['monotonicTime']) == checkpoint(events, paused),
                            'hidden prefix selected/counter changed')
                checks.append({'operation': leave or 'initial-push', 'status': 'recorded-prefix'})
            not_reached.append(restore)
            continue
        if leave is None:
            departed = (marks[0]['monotonicTime'], returned[0])
        else:
            departed = window(leave)
            require(departed is not None, 'return without departure window')
        if leave is None:
            app_pause = edge(app, field, False, departed, initial=True)
            app_resume = edge(app, field, True, returned)
            if car[0]['monotonicTime'] > app_resume['monotonicTime']:
                # With inactive HomeEntry no read starts, so no nonempty
                # HomeContent/Carousel exists until pop. Do not invent an
                # inactive component checkpoint for that legitimate branch.
                require(collector and collector.get('collectorOrderedBeforeTest') is True
                        and type(collector.get('pid')) is int and collector['pid'] > 0
                        and isinstance(collector.get('command'), list) and collector['command'],
                        'initially-unmounted push lacks collector-before-test proof')
                if collector.get('clockDomain') == 'system-uptime-raw':
                    require(number(collector.get('collectorStartRequestedUptime'))
                            and number(collector.get('testStartRequestedUptime'))
                            and collector['collectorStartRequestedUptime'] <= collector['testStartRequestedUptime']
                            <= marks[0]['monotonicTime'], 'collector did not start before method begin')
                first = car[0]
                require(first['eventSequence'] == 1 and first['generation'] == 0
                        and first['advanceSequence'] == 0 and first.get('selectedID') == 910001
                        and first['gate']['homeActive']
                        and first['monotonicTime'] <= returned[1],
                        'invalid first-created push carousel identity/selection')
                require(all(not e['homeActive'] for e in app if e['monotonicTime'] < app_resume['monotonicTime']),
                        'push home was active before pop')
                arms = [e for e in car if e['event'] == 'arm' and number(e.get('deadline'))]
                require(arms, 'new push carousel did not arm')
                initial = [e for e in car if e['eventSequence'] < arms[0]['eventSequence']]
                push_initial_checkpoint(initial, math.nextafter(initial[-1]['monotonicTime'], math.inf))
                require(all(e['eventSequence'] < arms[0]['eventSequence']
                            for e in car if e['event'] == 'selectionCommit'),
                        'new push carousel initialized/changed selection after first eligible arm')
                require(complete is False or any(e['event'] == 'advanceCommit' for e in car),
                        'new push carousel has no actual production advance')
                checks.append({'operation': restore, 'status': 'passed' if complete else 'recorded-prefix',
                               'branch': 'initially-unmounted', 'appInactiveAt': app_pause['monotonicTime'],
                               'appReturnedAt': app_resume['monotonicTime'], 'firstCarouselAt': first['monotonicTime'],
                               'collectorOrderingProof': collector.get('clockDomain', 'causal-order-only'),
                               'meaning': 'No mounted carousel task during pushed interval; new instance arms after pop'})
                continue
        pause_car = edge(car, field, False, departed, raw=True, initial=leave is None)
        resume_car = edge(car, field, True, returned, raw=True)
        pause_receipt = receipt_after(pause_car, departed[1])
        resume_receipt = receipt_after(resume_car, returned[1])
        require(departed[0] <= pause_receipt['monotonicTime'] and returned[0] <= resume_receipt['monotonicTime'],
                'task receipt outside real operation window')
        pause_edges, resume_edges = [pause_car, pause_receipt], [resume_car, resume_receipt]
        if field != 'visible':
            pause_edges.append(edge(app, field, False, departed, initial=leave is None))
            resume_edges.append(edge(app, field, True, returned))
        paused = min(e['monotonicTime'] for e in pause_edges)
        resumed = min(e['monotonicTime'] for e in resume_edges)
        require(resumed - paused > minimum, 'hidden interval did not span required product period')
        if leave is None:
            baseline = push_initial_checkpoint(car, resumed)
        else:
            baseline = check_hidden_ledger(car, paused, resumed)
        require(tuple(resume_receipt.get(k) for k in ['selectedID', 'selectionRevision', 'advanceSequence']) == baseline,
                'resume checkpoint changed before fresh arm')
        arms = [e for e in car if e['event'] == 'arm' and e.get('taskID') == resume_receipt.get('taskID')
                and number(e.get('deadline'))]
        require(arms, 'resume did not arm new full period')
        if complete:
            # Each successfully exercised restore needs an actual subsequent
            # production commit; another subchain's earlier commit is no proof.
            later_inputs = [e['monotonicTime'] for e in car if e['event'] == 'rawInput'
                            and e['monotonicTime'] > resume_receipt['monotonicTime']
                            and not eligible(e['gate'])]
            boundary = min(later_inputs, default=marks[-1]['monotonicTime'])
            require(any(e['event'] == 'advanceCommit'
                        and resume_receipt['monotonicTime'] < e['monotonicTime'] <= boundary for e in car),
                    restore + ' has no subsequent actual production commit')
        checks.append({'operation': restore, 'status': 'passed', 'pausedAt': paused,
                       'resumedAt': resumed, 'baseline': baseline,
                       'nativeReturnedAt': native_returned[1], 'deliveryWindowEnd': returned[1],
                       'latestReceiptAfterNativeReturn': max(0, max(e['monotonicTime'] for e in resume_edges)
                                                             - native_returned[1])})
    if kind in {'cycle', 'away', 'offscreen'}:
        if not drags:
            require(not complete, 'missing real drag release')
            not_reached.append('drag-release')
        for drag_start, drag_end, released in drags:
            # Gesture delivery can precede the native API return marker. Its
            # final false-drag raw input must still have a real task/arm receipt.
            raw = [e for e in car if e['event'] == 'rawInput' and not e['gate']['drag']
                   and e.get('previousGate', {}).get('drag') is True
                   and drag_start <= e['monotonicTime'] <= drag_end]
            require(raw, 'drag release input missing')
            require(len(raw) == 1, 'ambiguous repeated drag releases in one operation')
            began = edge(car, 'drag', True, (drag_start, drag_end), raw=True)
            require(checkpoint(events, began['monotonicTime']) == checkpoint(events, raw[-1]['monotonicTime']),
                    'unchanged drag selected/counter changed')
            require(all(e['event'] not in {'advanceAttempt', 'advanceCommit', 'selectionCommit'}
                        for e in car if began['monotonicTime'] <= e['monotonicTime'] <= raw[-1]['monotonicTime']),
                    'advance/selection during real drag')
            receipt = receipt_after(raw[-1], float('inf'))
            require(any(e['event'] == 'arm' and e.get('taskID') == receipt.get('taskID')
                        and number(e.get('deadline')) for e in car),
                    'drag release missing arm')
            if complete and released['expectsAdvance']:
                boundaries = [m['monotonicTime'] for m in marks if m['monotonicTime'] > drag_end
                              and m['event'] in {'drag-begin', 'tab-leave-begin', 'background-begin',
                                                'offscreen-begin', 'pop-begin', 'end'}]
                require(boundaries, 'post-drag observation chain has no end checkpoint')
                boundary = min(boundaries)
                require(any(e['event'] == 'advanceCommit' and drag_end < e['monotonicTime'] <= boundary for e in car),
                        'post-drag expected advance has no actual production commit')
                observations = [m for m in marks if m['event'] == 'observation'
                                and drag_end <= m['monotonicTime'] <= boundary]
                require(observations, 'post-drag advance missing visible end observation')
                visible = observations[-1]
                actual_ids = {checkpoint(car, visible['startedMonotonic'])[0],
                              checkpoint(car, visible['finishedMonotonic'])[0]}
                actual_ids.update(e.get('selectedID') for e in car
                                  if visible['startedMonotonic'] <= e['monotonicTime'] <= visible['finishedMonotonic'])
                require(visible.get('page') in {'第' + str(selected - 910000) + '页，共3页'
                                              for selected in actual_ids if type(selected) is int},
                        'post-drag visible page does not match actual production selection')
            checks.append({'operation': 'drag-release', 'status': 'passed', 'startedAt': drag_start, 'releasedAt': drag_end})
    if complete:
        require(marks[-1]['event'] == 'end', 'method end missing')
        require(all(e['monotonicTime'] <= marks[-1]['monotonicTime'] for e in events), 'source event after method end')
        require(any(e['event'] == 'advanceCommit' for e in car), 'method has no actual autoplay commit')
        if kind == 'cycle':
            require(sum(e['event'] == 'advanceCommit' for e in car) >= 4, 'cycle missing genuine advances/full wrap')
            baseline, wrapped = index.get('cycle-baseline'), index.get('cycle-wrap')
            require(baseline is not None and wrapped is not None, 'cycle AX baseline/wrap marker missing')
            require(index['drag-release']['monotonicTime'] <= baseline['monotonicTime'] < wrapped['monotonicTime'],
                    'cycle AX checkpoint order')
            for mark in [baseline, wrapped]:
                started, ended = mark.get('observationStarted'), mark.get('observationEnded')
                require(number(started) and number(ended) and started <= ended <= mark['monotonicTime'],
                        'cycle AX observation bounds missing/regressed')
                observations = [m for m in marks if m['event'] == 'observation'
                                and m.get('startedMonotonic') == started and m.get('finishedMonotonic') == ended
                                and m.get('leafID') == mark.get('leafID') and m.get('page') == mark.get('page')]
                require(len(observations) == 1, 'cycle AX checkpoint missing exact corresponding observation')
                require(mark.get('leafID') == 'home.banner.current.' + str(mark.get('selectedID')),
                        'cycle AX leaf/selected ID mismatch')
                require(mark.get('page') == '第' + str(mark.get('selectedID', 0) - 910000) + '页，共3页',
                        'cycle AX page/selected ID mismatch')
                require(not any(e['event'] in {'advanceAttempt', 'advanceCommit', 'selectionCommit'}
                                and started <= e['monotonicTime'] <= mark['monotonicTime'] for e in car),
                        'cycle AX observation spans selection/advance; evidence ambiguous')
                require(type(mark.get('selectedID')) is int and checkpoint(events, mark['monotonicTime'])[0] == mark['selectedID'],
                        'cycle AX checkpoint/production ledger ambiguous')
            commits = [e for e in car if e['event'] == 'advanceCommit'
                       and baseline['monotonicTime'] < e['monotonicTime'] <= wrapped['monotonicTime']]
            require(len(commits) == 3, 'cycle requires exactly three genuine commits from AX baseline to wrap')
            selected = baseline['selectedID']
            for commit in commits:
                require(commit['gate']['count'] == 3 and selected in [910001, 910002, 910003], 'unexpected cycle fixture')
                require(commit['oldSelectedID'] == selected and commit['selectedID'] == 910001 + (selected - 910000) % 3,
                        'cycle commit not adjacent in fixture order')
                selected = commit['selectedID']
            require(selected == baseline['selectedID'] == wrapped['selectedID'], 'cycle did not wrap to AX baseline')
    return {'status': 'passed' if complete else 'recorded-prefix', 'checks': checks,
            'notReached': not_reached, 'sourceEventCount': len(events)}


def audit(expected, trace_text, tests_text, collector, test_exit=0, defer_cycle=False, native_passed=None):
    selected = {method_name(m) for m in expected if m.startswith(PREFIX)} & METHODS.keys()
    if not selected:
        return {'status': 'not-required', 'reason': 'No selected carousel lifecycle UI methods', 'methods': {}}
    require(collector.get('diagnosticErrors') == [] and collector.get('state') == 'stream-stopped-by-owner',
            'collector incomplete/error')
    require(not any(m.startswith('BANNERAUDIT_ERROR')
                    for text in [trace_text, tests_text] for m in _LOG.payloads(text)),
            'source event encoding/recording error')
    source = records(trace_text, 'BANNERAUDIT ')
    markers = records(tests_text, 'BANNERTEST ')
    require(markers, 'selected methods have no execution markers')
    run_methods = {}
    for marker in markers:
        require(isinstance(marker.get('runID'), str) and marker['runID'] and number(marker.get('monotonicTime')),
                'invalid test marker identity/time')
        require(isinstance(marker.get('event'), str), 'invalid marker event')
        if marker['event'] == 'begin':
            require(marker['runID'] not in run_methods, 'duplicate run begin')
            run_methods[marker['runID']] = method_name(marker.get('method'))
    for marker in markers:
        require(marker['runID'] in run_methods, 'marker has no method begin')
        marker['method'] = method_name(marker.get('method', run_methods[marker['runID']]))
        require(marker['method'] == run_methods[marker['runID']], 'runID method changed')
        require(marker['method'] in selected, 'unexpected executed carousel method')
    result, used_runs, deferred = {}, set(), []
    for method in sorted(selected):
        marks = [m for m in markers if m['method'] == method]
        if not marks:
            if native_passed is not None and method in native_passed:
                result[method] = {'status': 'failed', 'error': 'Native passing method has no audit begin'}
                continue
            require(test_exit != 0, 'selected method was not executed: ' + method)
            result[method] = {'status': 'not-reached', 'notReached': ['begin']}
            continue
        runs = {m['runID'] for m in marks}
        require(len(runs) == 1 and not runs & used_runs, 'method runID missing/reused')
        used_runs |= runs
        end = next((m for m in marks if m['event'] == 'end'), None)
        if end:
            require(end.get('outcome') in {'passed', 'failed'}, 'end outcome missing')
        complete = bool(end and end['outcome'] == 'passed')
        if native_passed is not None and method in native_passed and not complete:
            result[method] = {'status': 'failed', 'error': 'Native passing method lacks passing audit end'}
            continue
        require(complete or test_exit != 0, 'successful UI run lacks passing end')
        events = [e for e in source if e.get('runID') in runs]
        try:
            result[method] = audit_method(events, marks, METHODS[method], complete, collector)
        except ValueError as error:
            if not defer_cycle:
                raise
            if METHODS[method] == 'cycle' and isinstance(error, EvidenceGap):
                result[method] = {'status': 'deferred-unresolved', 'error': str(error),
                                  'kind': 'sequence-gap', 'tailCompleteness': 'unproven'}
                deferred.append({'id': 'CI-DEFER-CYCLE-EVIDENCE-01', 'state': 'deferred-unresolved',
                                 'method': PREFIX + method + '()', 'reason': str(error)})
            else:
                result[method] = {'status': 'failed', 'error': str(error)}
        # No terminal source watermark exists. Do not certify an intact-looking
        # prefix as complete, and do not fabricate a production end event.
        if defer_cycle and METHODS[method] == 'cycle':
            result[method]['tailCompleteness'] = 'unproven'
            deferred.append({'id': 'CI-DEFER-CYCLE-EVIDENCE-01', 'state': 'deferred-unresolved',
                             'method': PREFIX + method + '()',
                             'reason': 'Terminal source completeness is unproven; lifecycle acceptance remains partial'})
    require(all(e.get('runID') in used_runs for e in source), 'source runID has no selected execution marker')
    status = 'passed' if test_exit == 0 else 'recorded-prefix'
    if any(v['status'] == 'failed' for v in result.values()): status = 'failed'
    elif deferred: status = 'core-passed-with-deferred'
    return {'status': status, 'methods': result, 'deferred': deferred}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ['scope', 'trace', 'tests-log', 'collector-status', 'output']:
        parser.add_argument('--' + flag, required=True, type=Path)
    parser.add_argument('--native-results', type=Path)
    parser.add_argument('--test-exit', type=int, required=True)
    args = parser.parse_args()
    try:
        spec = importlib.util.spec_from_file_location('ci_defer', Path(__file__).with_name('ci-deferred-policy.py'))
        policy = importlib.util.module_from_spec(spec); spec.loader.exec_module(policy)
        policy.load(active=False)
        scope = json.loads(args.scope.read_text())
        expected = scope['expected']
        selected = {method_name(m) for m in expected if m.startswith(PREFIX)} & METHODS.keys()
        if any(METHODS[m] == 'cycle' for m in selected): policy.load()
        native_passed = None
        if args.native_results and args.native_results.exists():
            native = json.loads(args.native_results.read_text())
            if native.get('status') in {'passed', 'core-passed-with-deferred'}:
                require(set(native['methodResults']) == set(expected), 'native method inventory mismatch')
                native_passed = {method_name(m) for m,v in native['methodResults'].items()
                                 if m.startswith(PREFIX) and v == 'Passed'}
        # None selected is a truthful exclusion and needs no collector files.
        if not ({method_name(m) for m in expected if m.startswith(PREFIX)} & METHODS.keys()):
            result = audit(expected, '', '', {}, args.test_exit)
        else:
            result = audit(expected, args.trace.read_text(), args.tests_log.read_text(),
                           json.loads(args.collector_status.read_text()), args.test_exit, defer_cycle=True, native_passed=native_passed)
        code = 1 if result['status'] == 'failed' else 0
    except (ValueError, OSError, KeyError, TypeError) as error:
        result, code = {'status': 'failed', 'error': str(error)}, 1
    try:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    except OSError as error:
        print('BANNER-AUDIT: output write failed: ' + str(error), file=sys.stderr)
        return 1
    print('BANNER-AUDIT: ' + result['status'])
    return code


if __name__ == '__main__':
    sys.exit(main())
