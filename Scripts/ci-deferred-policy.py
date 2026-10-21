#!/usr/bin/env python3
"""Exact, dated CI-only deferrals. No module/import or test-selection exemption."""
import json
from datetime import date
from pathlib import Path

TIMEOUT_METHOD = 'CoolMalliOSUITests/HomeLoadTests/testSelectedBannerAndBottomPositionRetainedAcrossTabs()'
CYCLE_METHOD = 'CoolMalliOSUITests/HomeLoadTests/testBannerAutoplayCyclesAndRestartsAfterUnchangedDrag()'
TIMEOUT_TEXT = 'Test exceeded execution time allowance of 1 minute'
IDS = {'CI-DEFER-HOME-TIMEOUT-01': (TIMEOUT_METHOD, 'whole-method-execution-allowance-60s'),
       'CI-DEFER-CYCLE-EVIDENCE-01': (CYCLE_METHOD, 'cycle-sequence-gap-and-unproven-tail')}


def load(path=None, today=None, active=True):
    path = path or Path(__file__).with_name('ci-deferred-checks.json')
    data = json.loads(Path(path).read_text())
    if data.get('schemaVersion') != 1 or data.get('decision') != 'DEC-016' or data.get('state') != 'deferred-unresolved':
        raise ValueError('CI-DEFER: unknown policy/schema/state')
    if data.get('created') != '2026-10-21' or data.get('expires') != '2026-11-04':
        raise ValueError('CI-DEFER: dates differ from explicit approval; no automatic renewal')
    created, expires = date.fromisoformat(data['created']), date.fromisoformat(data['expires'])
    if (expires-created).days > 14 or expires <= created or (active and not (created <= (today or date.today()) < expires)):
        raise ValueError('CI-DEFER: policy not active/expired; maintainer review required')
    if data.get('reviewRequired') != ['before-home-logic-change', 'before-external-release',
                                    'on-reproducible-user-stall-state-loss-or-crash', 'by-expiry']:
        raise ValueError('CI-DEFER: missing review triggers')
    issues = data['issues']
    if len(issues) != 2 or {v['id']: (v['method'], v['kind']) for v in issues} != IDS:
        raise ValueError('CI-DEFER: unsupported scope')
    if not data.get('evidence') or any(not v.get('impact') or not v.get('closeWhen') for v in issues):
        raise ValueError('CI-DEFER: missing tracking evidence/impact/closure')
    return data


def warning(identifier, reason, **fields):
    return dict(id=identifier, state='deferred-unresolved', reason=reason, **fields)
